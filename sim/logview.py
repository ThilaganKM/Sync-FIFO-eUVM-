#!/usr/bin/env python3
"""
logview.py: a compact, colour-coded view of a UVM run log.

The simulation log itself stays plain text (easy to grep, diff and archive).
This script only changes how it is *displayed*:

  * one short line per message:   cycle | time (ns) | tag | message
  * a header whenever the kind of cycle changes (RESET, WRITE, READ, R+W, IDLE)
  * colours for tags, operations, data bytes, flags and error counts

Usage:
  python3 logview.py run.log              # view a saved log
  make run 2>&1 | python3 logview.py      # view a run live
  python3 logview.py --color run.log | less -R   # page through it, keeping colours

Options:
  --color           force colours (needed when piping, e.g. into less -R)
  --no-color        plain text (the default when output isn't a terminal)
  --no-headers      no section headers (useful for random tests, where the
                    operation changes almost every cycle)
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


def main():
    global USE_COLOR
    ap = argparse.ArgumentParser(description="Compact, colour-coded view of a UVM run log.")
    ap.add_argument("logfile", nargs="?", help="log file (default: read stdin)")
    ap.add_argument("--color", action="store_true")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--no-headers", action="store_true")
    ap.add_argument("--period", type=float, default=20.0)
    ap.add_argument("--first-edge", type=float, default=10.0)
    a = ap.parse_args()

    USE_COLOR = a.color or ((not a.no_color) and sys.stdout.isatty()
                            and "NO_COLOR" not in os.environ)
    v = Viewer(a.period, a.first_edge, not a.no_headers)
    src = open(a.logfile) if a.logfile else sys.stdin
    try:
        for raw in src:
            v.feed(raw)
        v.close()
    except BrokenPipeError:        # e.g. piped into `head`
        pass
    finally:
        if a.logfile:
            src.close()


if __name__ == "__main__":
    main()
