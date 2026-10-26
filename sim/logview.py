#!/usr/bin/env python3
"""
logview.py: debug-friendly views of a UVM run log.

The simulation log itself stays plain text (easy to grep, diff and archive).
This script only changes how it is *displayed*. Three views:

  stream  (default)  every message on one short line: cycle | time | tag | msg,
                     with a header whenever the kind of cycle changes
  --table            ONE ROW PER RISING EDGE: the inputs going into the edge,
                     the rd_data it consumes, the outputs after it, and the
                     scoreboard's verdict for that edge (errors listed below
                     their row; changed outputs highlighted)
  --summary          one line per log file: test, seed, check counts, PASS/FAIL

Usage:
  python3 logview.py run.log                         # stream view
  python3 logview.py --table run.log                 # edge table
  python3 logview.py --table --first-error run.log   # start here when a test fails
  python3 logview.py --table --errors-only run.log   # every error, with context
  python3 logview.py --table --around 1300 run.log   # edges near 1300 ns
  python3 logview.py --summary *.log                 # regression summary
  python3 logview.py --color ... | less -R           # page, keeping colours

  (make view / make table / make summary wrap these; see the makefile.)

Options:
  --color           force colours (needed when piping, e.g. into less -R)
  --no-color        plain text (the default when output isn't a terminal)
  --no-headers      no section headers (useful for random tests)
  --errors-only     table: only edges with errors, plus --context edges around
  --first-error     table: only the FIRST error, plus --context edges around it
  --around NS       table: only edges within --context edges of this time (ns)
  --context N       table: edges of context for --errors-only / --around (default 3)
  --period NS       clock period in ns          (default 20, see sync_fifo_tb.d)
  --first-edge NS   time of the first posedge   (default 10)
"""

import argparse
import os
import re
import sys

# --------------------------------------------------------------------------
# ANSI colours
# --------------------------------------------------------------------------
RESET_SGR = "\033[0m"
SGR = {
    "bold": "1", "dim": "2", "rev": "7",
    "red": "31", "green": "32", "yellow": "33", "blue": "34",
    "magenta": "35", "cyan": "36", "white": "37", "grey": "90",
}

USE_COLOR = True


def c(text, *styles):
    """Wrap text in ANSI colour codes (no-op when colour is off)."""
    if not USE_COLOR or not styles:
        return text
    return "\033[" + ";".join(SGR[s] for s in styles) + "m" + text + RESET_SGR


TAG_STYLE = {"SEQ": ("cyan",), "DRV": ("yellow",), "MON": ("green",),
             "SCB": ("magenta",)}
OP_STYLE = {"RESET": "magenta", "WRITE": "blue", "READ": "green",
            "R+W": "cyan", "IDLE": "grey"}
FLAG_KEYS = {"rst", "wr", "rd", "full", "empty"}
ERR_KEYS = {"werr", "rerr"}
DATA_KEYS = {"wdata", "rdata"}

# UVM_INFO ../testbench/fifo_driver.d(42) @ 190000: tb...agent.driver [DRV] msg
UVM_LINE = re.compile(
    r"^(UVM_(?:INFO|WARNING|ERROR|FATAL))\s+(\S+)\((\d+)\)\s+@\s+(\d+):\s+"
    r"(\S+)\s+\[([^\]]+)\]\s?(.*)$")
KV = re.compile(r"(\w+)=([0-9a-fA-F]+)")
COUNT_LINE = re.compile(r"^(UVM_(?:FATAL|ERROR|WARNING))\s*:\s*(\d+)")


def color_fields(msg):
    """Colour key=value pairs: data bytes bold, flags bright when 1, errors red."""
    def repl(m):
        key, val = m.group(1), m.group(2)
        if key in DATA_KEYS:
            return key + "=" + c(val, "bold", "white")
        if key in ERR_KEYS:
            return key + "=" + (c(val, "bold", "red") if val != "0" else c(val, "dim"))
        if key in FLAG_KEYS:
            return key + "=" + (c(val, "bold", "yellow") if val != "0" else c(val, "dim"))
        return key + "=" + val
    msg = KV.sub(repl, msg)
    return msg.replace(" | ", c(" | ", "grey"))


def operation(msg):
    """Kind of cycle, from the stimulus fields of a DRV/MON line (or None)."""
    kv = dict(KV.findall(msg.split("|")[0]))
    if not {"rst", "wr", "rd"} <= kv.keys():
        return None
    if kv["rst"] == "1":
        return "RESET"
    wr, rd = kv["wr"] == "1", kv["rd"] == "1"
    return {(True, True): "R+W", (True, False): "WRITE",
            (False, True): "READ", (False, False): "IDLE"}[(wr, rd)]


class Viewer:
    def __init__(self, period_ns, first_edge_ns, headers):
        self.period = period_ns
        self.first = first_edge_ns
        self.headers = headers
        self.last_op = None
        self.pending = []          # SEQ lines waiting for their cycle's DRV/MON line
        self.in_banner = False     # inside the UVM release-notes banner

    def cycle_of(self, t_ns):
        return int((t_ns - self.first) // self.period) if t_ns >= self.first else -1

    def fmt(self, sev, t_ns, tag, msg):
        cyc = self.cycle_of(t_ns) if tag in ("SEQ", "DRV", "MON") else -1
        cyc_s = c(f"c{cyc:03d}" if cyc >= 0 else "    ", "grey")
        if tag == "DRV":
            # The driver only fills the stimulus half of the item; its response
            # fields are always 0 and would be misleading next to MON lines.
            msg = msg.split(" | ")[0]
        time_s = c(f"{t_ns:7.0f} ns", "grey")
        tag_s = c(f"{tag:<4}", *TAG_STYLE.get(tag, ("white",)))
        line = f"{cyc_s} {time_s}  {tag_s} {color_fields(msg)}"
        if sev in ("UVM_ERROR", "UVM_FATAL"):
            line = c(f"{sev[4:]:<5}", "bold", "red") + " " + line
        elif sev == "UVM_WARNING":
            line = c("WARN ", "bold", "yellow") + " " + line
        return line

    def header(self, op, t_ns):
        label = f" {op} (from cycle c{self.cycle_of(t_ns):03d}) "
        return c(f"{label:─^78}", "bold", OP_STYLE.get(op, "white"))

    def flush_pending(self):
        for p in self.pending:
            print(self.fmt(*p))
        self.pending = []

    def feed(self, raw):
        line = raw.rstrip("\n")

        # The release-notes banner spans many lines: show it dimmed.
        if "[UVM/RELNOTES]" in line:
            self.in_banner = True
        if self.in_banner:
            print(c(line, "dim"))
            if line.startswith("Accellera:"):
                self.in_banner = False
            return

        m = UVM_LINE.match(line)
        if m:
            sev, _file, _lineno, t_ps, _path, tag, msg = m.groups()
            t_ns = int(t_ps) / 1000.0
            if tag == "SEQ":
                # Belongs to the cycle whose DRV line comes next: hold it, so a
                # section header can be printed *before* it.
                self.pending.append((sev, t_ns, tag, msg))
                return
            op = operation(msg) if tag in ("DRV", "MON") else None
            if op is not None and self.headers and op != self.last_op:
                print(self.header(op, t_ns))
            if op is not None:
                self.last_op = op
            self.flush_pending()
            print(self.fmt(sev, t_ns, tag, msg))
            return

        self.flush_pending()
        cm = COUNT_LINE.match(line)
        if cm:
            n = int(cm.group(2))
            bad = n > 0 and cm.group(1) in ("UVM_FATAL", "UVM_ERROR")
            style = ("bold", "red") if bad else (("bold", "yellow") if n else ("green",))
            print(c(line, *style))
        elif line.startswith("[ESDL") or line.startswith("stdbuf ") or line.startswith("make"):
            print(c(line, "dim"))
        else:
            print(line)

    def close(self):
        self.flush_pending()


# --------------------------------------------------------------------------
# Parsing (shared by --table and --summary)
# --------------------------------------------------------------------------
SCB_SUMMARY = re.compile(r"(\w+)=(\d+)")
MISMATCH = re.compile(r"(\w+) mismatch: expected=(\S+) got=(\S+)")
OUT_KEYS = ("wptr", "rptr", "full", "empty", "werr", "rerr")


def parse_log(lines):
    """Return (mons, events, meta) from the raw log lines.
    mons   : [(t_ns, {field: value})]  one per monitor sample
    events : [(t_ns, sev, tag, msg)]   errors/warnings and SCB messages
    meta   : test name, seed, scoreboard summary, UVM severity counts"""
    mons, events = [], []
    meta = {"test": None, "seed": None, "scb": None, "counts": {}}
    for raw in lines:
        line = raw.rstrip("\n")
        m = UVM_LINE.match(line)
        if m:
            sev, _f, _l, t_ps, _path, tag, msg = m.groups()
            t_ns = int(t_ps) / 1000.0
            if tag == "MON":
                mons.append((t_ns, dict(KV.findall(msg))))
            elif tag == "SCB" and "samples=" in msg:
                meta["scb"] = {k: int(v) for k, v in SCB_SUMMARY.findall(msg)}
            elif tag == "SCB" or sev != "UVM_INFO":
                events.append((t_ns, sev, tag, msg))
            continue
        tm = re.search(r"\+UVM_TESTNAME=(\S+)", line)
        if tm:
            meta["test"] = tm.group(1)
        sm = re.search(r"\+seed=(\d+)", line) or re.search(r"Using random seed:\s*(\d+)", line)
        if sm and meta["seed"] is None:
            meta["seed"] = sm.group(1)
        cm = COUNT_LINE.match(line)
        if cm:
            meta["counts"][cm.group(1)] = int(cm.group(2))
    return mons, events, meta


def verdict(meta):
    """(label, style) for one run."""
    cnt = meta["counts"]
    if not cnt and meta["test"] is None:
        return "NOT A RUN", ("grey",)                # e.g. a build log
    if "UVM_ERROR" not in cnt:
        return "INCOMPLETE", ("bold", "yellow")      # no report summary: crashed?
    if cnt.get("UVM_FATAL", 0) or cnt.get("UVM_ERROR", 0):
        return "FAIL", ("bold", "red")
    if meta["scb"] is None:
        return "NO SCB", ("yellow",)                 # run without a scoreboard
    if meta["scb"].get("edges_checked", 0) == 0:
        return "NO CHECKS", ("bold", "yellow")       # 0 errors, but nothing checked
    return "PASS", ("bold", "green")


def pad(text, width, align="<"):
    return f"{text:{align}{width}}"


# --------------------------------------------------------------------------
# --table: one row per rising edge
# --------------------------------------------------------------------------
# (group, title, width, align). Header and rows are both built from this list,
# so they can't drift out of alignment.
TABLE_COLS = [
    ("edge",   "cyc",     4, "<"), ("edge", "edge ns", 7, ">"),
    ("in",     "op",      5, "<"), ("in", "rst", 3, ">"), ("in", "wr", 2, ">"),
    ("in",     "rd",      2, ">"), ("in", "wdata", 5, ">"),
    ("in",     "wr#",     3, ">"), ("in", "rd#", 3, ">"),
    ("before", "rdata",   7, ">"),
    ("out",    "wptr",    4, ">"), ("out", "rptr", 4, ">"), ("out", "full", 4, ">"),
    ("out",    "empty",   5, ">"), ("out", "werr", 4, ">"), ("out", "rerr", 4, ">"),
    ("chk",    "scoreboard", 0, "<"),
]
GROUP_TITLE = {"edge": "", "in": "inputs into the edge", "before": "before",
               "out": "outputs after the edge", "chk": ""}


def table_view(lines, period, first_edge, headers, errors_only, first_only, around, context):
    mons, events, meta = parse_log(lines)
    if len(mons) < 2:
        print("No monitor samples in this log (is the monitor logging at UVM_HIGH?)")
        return
    half = period / 2.0

    def cyc(t):
        return int((t - first_edge) // period) if t >= first_edge else -1

    # Row k = the rising edge between monitor samples k and k+1:
    # inputs and pre-edge rd_data from sample k, outputs from sample k+1.
    rows, wr_n, rd_n = [], 0, 0
    for k in range(len(mons) - 1):
        (ta, a), (tb, b) = mons[k], mons[k + 1]
        if a.get("rst") == "1":
            wr_n = rd_n = 0                 # request counters restart at reset
        else:
            wr_n += a.get("wr") == "1"
            rd_n += a.get("rd") == "1"
        evs = [e for e in events if ta < e[0] <= tb]
        rows.append({"k": k, "cyc": cyc(ta), "edge": ta + half, "a": a, "b": b,
                     "wr_n": wr_n, "rd_n": rd_n,
                     "op": operation(" ".join(f"{x}={a.get(x, '0')}" for x in ("rst", "wr", "rd"))),
                     "errs": [e for e in evs if e[1] in ("UVM_ERROR", "UVM_FATAL")],
                     "infos": [e for e in evs if e[1] == "UVM_INFO"],
                     "warns": [e for e in evs if e[1] == "UVM_WARNING"]})

    # Which rows to show.
    filtered = errors_only or first_only or around is not None
    show = set(range(len(rows)))
    if filtered:
        if around is not None:
            centres = [r["k"] for r in rows if abs(r["edge"] - around) <= half]
        else:
            centres = [r["k"] for r in rows if r["errs"]]
            if first_only:
                centres = centres[:1]
        show = set()
        for k in centres:
            show.update(range(max(0, k - context), min(len(rows), k + context + 1)))

    bar = c("│", "grey")

    def join_cells(cells):
        """cells: list of already-padded (maybe coloured) strings, one per column."""
        out, prev_group = "", None
        for (group, _t, _w, _al), cell in zip(TABLE_COLS, cells):
            if prev_group is not None and group != prev_group:
                out += " " + bar
            out += " " + cell
            prev_group = group
        return out

    def group_line():
        out, prev_group, run = "", None, 0
        spans = []                              # (group, width incl. separators)
        for group, _t, w, _al in TABLE_COLS:
            if group != prev_group:
                spans.append([group, 0])
                prev_group = group
            spans[-1][1] += w + 1
        for idx, (group, width) in enumerate(spans):
            if idx:
                out += " " + bar
            title = GROUP_TITLE[group]
            out += c((f" {title} ".center(width, "─") if title else " " * width), "grey")
        return out

    def print_header():
        print(group_line())
        print(c(join_cells([pad(t, w, al) for _g, t, w, al in TABLE_COLS]), "bold"))
        print(c("─" * 118, "grey"))

    def bit(v):
        return c(v, "bold", "yellow") if v == "1" else c(v, "dim")

    print(c(f"Edge table: {meta['test'] or 'unknown test'}, seed {meta['seed'] or '?'}"
            f"  ({len(rows)} edges, period {period:g} ns)", "bold"))
    print(c("One row per rising edge: inputs going INTO the edge -> outputs AFTER it. "
            "'rdata before' = the byte a read on this edge consumes.", "dim"))
    print(c("wr#/rd# = write/read REQUESTS sent so far (restart at reset); "
            "cyan = output changed at this edge.", "dim"))
    t0, s0 = mons[0]
    print(c(f"Initial sample @{t0:g} ns: " + " ".join(f"{x}={s0.get(x, '?')}" for x in OUT_KEYS), "dim"))
    if filtered and not show:
        print(c("No rows match the filter (no errors?).", "green"))
    print_header()

    printed, last_op, last_k = 0, None, -1
    for r in rows:
        if r["k"] not in show:
            continue
        if last_k >= 0 and r["k"] != last_k + 1:
            print(c(f"   ⋮  ({r['k'] - last_k - 1} edges hidden)", "grey"))
        last_k = r["k"]
        if headers and r["op"] != last_op and not filtered:
            print(c(f"  ── {r['op']} " + "─" * 20, "bold", OP_STYLE.get(r["op"], "white")))
        last_op = r["op"]
        if printed and printed % 40 == 0:
            print_header()
        printed += 1

        a, b = r["a"], r["b"]
        w = {t: wd for _g, t, wd, _al in TABLE_COLS}
        cells = [c(pad(f"c{r['cyc']:03d}", w["cyc"]), "grey"),
                 c(pad(f"{r['edge']:g}", w["edge ns"], ">"), "grey"),
                 c(pad(r["op"] or "?", w["op"]), OP_STYLE.get(r["op"], "white"))]
        for key, title in (("rst", "rst"), ("wr", "wr"), ("rd", "rd")):
            cells.append(" " * (w[title] - 1) + bit(a.get(key, "?")))
        wd = pad(a.get("wdata", "??"), w["wdata"], ">")
        cells.append(c(wd, "bold", "white") if a.get("wr") == "1" else c(wd, "dim"))
        cells.append(c(pad(str(r["wr_n"]), w["wr#"], ">"), "grey"))
        cells.append(c(pad(str(r["rd_n"]), w["rd#"], ">"), "grey"))
        rd = pad(a.get("rdata", "??"), w["rdata"], ">")
        cells.append(c(rd, "bold", "white") if a.get("rd") == "1" else c(rd, "dim"))
        for key in OUT_KEYS:
            v = b.get(key, "?")
            txt = pad(v, w[key if key != "wptr" else "wptr"], ">")
            if key in ("werr", "rerr") and v == "1":
                txt = c(txt, "bold", "red")
            elif v != a.get(key):
                txt = c(txt, "bold", "cyan")         # changed at this edge
            elif key in ("full", "empty") and v == "0":
                txt = c(txt, "dim")
            cells.append(txt)

        if r["errs"]:
            mm = MISMATCH.search(r["errs"][0][3])
            short = (f"{mm.group(1)}: exp {mm.group(2)} got {mm.group(3)}" if mm
                     else r["errs"][0][3][:40])
            more = f" (+{len(r['errs']) - 1})" if len(r["errs"]) > 1 else ""
            chk = c("✗ " + short + more, "bold", "red")
        else:
            reads = [e[3] for e in r["infos"] if e[3].startswith("read")]
            chk = (c("✓ " + reads[0].split("(")[0].strip(), "green") if reads
                   else c("✓", "green", "dim"))
            if r["warns"]:
                chk += c("  ⚠ warning", "yellow")
        cells.append(chk)
        print(join_cells(cells))
        for e in r["errs"]:
            print(c(f"{'':15}└─ {e[1][4:]} @{e[0]:g} ns [{e[2]}] {e[3]}", "red"))

    print(c("─" * 118, "grey"))
    for e in events:
        if e[1] in ("UVM_ERROR", "UVM_FATAL") and e[0] > mons[-1][0]:
            print(c(f"  {e[1][4:]} @{e[0]:g} ns [{e[2]}] {e[3]}", "red"))
    if meta["scb"]:
        print("Scoreboard: " + " ".join(f"{k}={v}" for k, v in meta["scb"].items()))
    cnt = meta["counts"]
    label, style = verdict(meta)
    first_err = next((r for r in rows if r["errs"]), None)
    where = f"   first error at edge {first_err['edge']:g} ns (c{first_err['cyc']:03d})" if first_err else ""
    print(f"UVM_ERROR={cnt.get('UVM_ERROR', '?')}  UVM_FATAL={cnt.get('UVM_FATAL', '?')}  "
          f"UVM_WARNING={cnt.get('UVM_WARNING', '?')}   =>  " + c(label, *style) + where)


# --------------------------------------------------------------------------
# --summary: one line per log file
# --------------------------------------------------------------------------
def summary_view(files):
    log_w = max([10] + [len(os.path.basename(f)) for f in files])
    cols = [("log", log_w, "<"), ("test", 20, "<"), ("seed", 5, ">"), ("edges", 6, ">"),
            ("data", 5, ">"), ("writes", 7, ">"), ("reads", 6, ">"), ("left", 5, ">"),
            ("mismatch", 9, ">"), ("errors", 7, ">"), ("fatal", 6, ">"), ("result", 11, "<")]
    print(c(" ".join(pad(n, w, al) for n, w, al in cols), "bold"))
    print(c(" ".join("─" * w for _n, w, _al in cols), "grey"))
    n_pass = n_skip = 0
    for f in files:
        try:
            with open(f) as fh:
                _m, _e, meta = parse_log(fh)
        except OSError as err:
            print(c(f"{f}: {err.strerror}", "red"))
            continue
        scb = meta["scb"] or {}
        cnt = meta["counts"]
        label, style = verdict(meta)
        n_pass += label == "PASS"
        n_skip += label == "NOT A RUN"
        vals = [os.path.basename(f), (meta["test"] or "?").replace("fifo_test.", ""),
                meta["seed"] or "?", scb.get("edges_checked", "-"), scb.get("data_checks", "-"),
                scb.get("writes", "-"), scb.get("reads", "-"), scb.get("left_in_fifo", "-"),
                scb.get("mismatches", "-"), cnt.get("UVM_ERROR", "-"), cnt.get("UVM_FATAL", "-")]
        cells = [pad(str(v), w, al) for v, (_n, w, al) in zip(vals, cols)]
        if scb.get("mismatches", 0):
            cells[8] = c(cells[8], "bold", "red")
        if cnt.get("UVM_ERROR", 0):
            cells[9] = c(cells[9], "bold", "red")
        if cnt.get("UVM_FATAL", 0):
            cells[10] = c(cells[10], "bold", "red")
        print(" ".join(cells) + " " + c(label, *style))
    n_runs = len(files) - n_skip
    print(c(f"{n_pass}/{n_runs} runs passed", "bold", "green" if n_pass == n_runs else "red"))


def main():
    global USE_COLOR
    ap = argparse.ArgumentParser(description="Debug-friendly views of a UVM run log.")
    ap.add_argument("logfile", nargs="*", help="log file(s) (default: read stdin)")
    ap.add_argument("--color", action="store_true")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--no-headers", action="store_true")
    ap.add_argument("--table", action="store_true", help="one row per rising edge")
    ap.add_argument("--summary", action="store_true", help="one line per log file")
    ap.add_argument("--errors-only", action="store_true")
    ap.add_argument("--first-error", action="store_true")
    ap.add_argument("--around", type=float, default=None, metavar="NS")
    ap.add_argument("--context", type=int, default=3)
    ap.add_argument("--period", type=float, default=20.0)
    ap.add_argument("--first-edge", type=float, default=10.0)
    a = ap.parse_args()

    USE_COLOR = a.color or ((not a.no_color) and sys.stdout.isatty()
                            and "NO_COLOR" not in os.environ)
    try:
        if a.summary:
            summary_view(a.logfile)
            return
        if len(a.logfile) > 1:
            ap.error("give one log file (several only with --summary)")
        src = open(a.logfile[0]) if a.logfile else sys.stdin
        try:
            if a.table:
                table_view(src, a.period, a.first_edge, not a.no_headers,
                           a.errors_only, a.first_error, a.around, a.context)
            else:
                v = Viewer(a.period, a.first_edge, not a.no_headers)
                for raw in src:
                    v.feed(raw)
                v.close()
        finally:
            if a.logfile:
                src.close()
    except BrokenPipeError:        # e.g. piped into `head` or quitting `less`
        pass


if __name__ == "__main__":
    main()
