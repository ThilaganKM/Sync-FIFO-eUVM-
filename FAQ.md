# FAQ

Questions raised, and explanations given, while building the eUVM testbench for the synchronous FIFO.
Nothing here gives away anything about bugs in the RTL.

**Contents**
- [Testbench architecture](#testbench-architecture)
  - [What fields should the item (transaction) carry?](#what-fields-should-the-item-transaction-carry)
  - [When does the read data appear? Same edge as `rd_en`?](#when-does-the-read-data-appear-same-edge-as-rd_en)
  - [Should the monitor send separate read and write events?](#should-the-monitor-send-separate-read-and-write-events)
  - [Should the scoreboard mirror the FIFO memory, address by address?](#should-the-scoreboard-mirror-the-fifo-memory-address-by-address)
  - [Random tests, stress tests, coverage, assertions: where do I start?](#random-tests-stress-tests-coverage-assertions-where-do-i-start)
- [Verification plan](#verification-plan)
  - [How was the verification plan derived from my scenario list?](#how-was-the-verification-plan-derived-from-my-scenario-list)
- [Build flow](#build-flow)
  - [Why start with the makefile when no testbench exists yet?](#why-start-with-the-makefile-when-no-testbench-exists-yet)
  - [What has to change in the makefile copied from the comparator?](#what-has-to-change-in-the-makefile-copied-from-the-comparator)
  - [What does `make verilator.stamp` produce, and what is `Vsync_fifo_euvm.d`?](#what-does-make-verilatorstamp-produce-and-what-is-vsync_fifo_euvmd)
  - [The comparator has `Serialized_Comparator_tb.v` and `Serialized_Comparator.d`. Which one is the testbench top?](#the-comparator-has-serialized_comparator_tbv-and-serialized_comparatord-which-one-is-the-testbench-top)
  - [Why did my `.d` file turn orange in VS Code?](#why-did-my-d-file-turn-orange-in-vs-code)
  - [How do I get D autocompletion in VS Code (Remote-SSH)?](#how-do-i-get-d-autocompletion-in-vs-code-remote-ssh)
- [Testbench top and interface](#testbench-top-and-interface)
  - [Why must `touch verilator.stamp` be the first line of its recipe?](#why-must-touch-verilatorstamp-be-the-first-line-of-its-recipe)
  - [How does the top file's clock line up the DUT, the driver and the monitor?](#how-does-the-top-files-clock-line-up-the-dut-the-driver-and-the-monitor)
  - [Why `"uvm_test_top*"` and not `"uvm_test_top.*"` in `uvm_config_db::set`?](#why-uvm_test_top-and-not-uvm_test_top-in-uvm_config_dbset)
  - [Why are the files and classes named `fifo_intf` / `FifoIntf`?](#why-are-the-files-and-classes-named-fifo_intf--fifointf-not-interface--intf-as-in-the-comparator)
  - [How do I print the value of a `VlPort`?](#how-do-i-print-the-value-of-a-vlport)
- [Git](#git)
  - [I added a file to `.gitignore` but git still tracks it. Why?](#i-added-a-file-to-gitignore-but-git-still-tracks-it-why)
  - [Untracking a file hides it from future commits. Is it gone from the repo?](#untracking-a-file-hides-it-from-future-commits-is-it-gone-from-the-repo)

---

## Testbench architecture

### What fields should the item (transaction) carry?

The **stimulus** fields: `wr_en`, `rd_en`, `wr_data`, and `rst`.

| Field | Random? | Why |
|---|---|---|
| `wr_en`, `rd_en`, `wr_data` | Yes (`@rand`), constrained per sequence | These are what a sequence controls each cycle. |
| `rst` | No, or heavily constrained | The driver applies the first reset on its own. Keep `rst` in the item so a sequence can reset mid-traffic (SPEC §3, §9.6). If `rst` were a free random bit, about half the cycles would be resets and the FIFO would never fill. |

The same item class also carries the **observed outputs** (`rd_data`, `full`, `empty`, `wr_ptr`, `rd_ptr`, `wr_err`, `rd_err`). The monitor fills these in, so the scoreboard receives one object per cycle with everything it needs. This is the usual UVM pattern: one transaction class, stimulus fields randomised by the sequence, response fields filled by the monitor.

### When does the read data appear? Same edge as `rd_en`?

No. In a show-ahead (FWFT) FIFO the data is visible **before** the read:

```
          edge N-1          edge N            edge N+1
clk    ____/‾‾‾‾\____/‾‾‾‾\____/‾‾‾‾\____
rd_en  ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______________   driven after N-1, held up to N
rd_data  ====< oldest = A   >< next = B >===   A is visible BEFORE edge N
                             ↑
                    edge N: A is consumed, rd_ptr++
                    after edge N: rd_data = B; flags and error pulses update
```

- The value consumed on edge N is **`rd_data` just before edge N** (SPEC §5). The edge doesn't produce the output: it removes A, and B appears after it.
- Everything the edge produces (`full`, `empty`, pointers, `wr_err`, `rd_err`) is visible only **after** edge N (SPEC §7, §8).

A practical consequence for eUVM + Verilator: when a process wakes up on `vif.clock.posedge()`, you have to find out whether reading a DUT port gives the value from before or after the edge. Check it on the waveform before writing any checks, because a sampling error gives false failures that are off by one cycle, and they look exactly like RTL bugs.

### Should the monitor send separate read and write events?

The recommended approach for a FIFO is **one snapshot per clock edge**, not separate read and write events. At each rising edge the monitor records:

- the inputs going into this edge (`rst`, `wr_en`, `rd_en`, `wr_data`), plus `rd_data` just before the edge (the value a read on this edge takes);
- the registered outputs, which reflect the result of the **previous** edge.

The spec defines behaviour cycle by cycle (what happens when read and write coincide, when flags change, when error pulses rise), so a cycle-accurate snapshot is the natural way to check it. With separate read and write events, the scoreboard has to put them back together to handle simultaneous read and write.

### Should the scoreboard mirror the FIFO memory, address by address?

No. Use a **queue** reference model.

| Approach | What it checks | Industry use |
|---|---|---|
| Mirror memory, indexed by address | The DUT's internal storage | Rare. It ties the testbench to one implementation. The storage array isn't a port, and SPEC §2 says the internal structure is an implementation choice. |
| **Model queue (`ubyte[]`)** + predicted state | Ordering, data on `rd_data`, flags, pointers, error pulses, all through the ports | ✅ The standard approach (**black-box** checking) |

Per edge, the model:
1. decides from its state **before** the edge whether the write and the read are accepted or rejected (SPEC §4–§6);
2. on an accepted read, compares the pre-edge `rd_data` with the front of the queue, then pops it;
3. on an accepted write, pushes `wr_data`;
4. predicts `full`, `empty`, `wr_ptr`, `rd_ptr`, `wr_err` and `rd_err`, and compares them with the next snapshot.

The pointers **are** checked, because `wr_ptr` and `rd_ptr` are output ports: the model keeps its own counters for them.

### Random tests, stress tests, coverage, assertions: where do I start?

All of these are real techniques, but industry practice is to work from a **verification plan**: every spec requirement maps to a *check* and to a *stimulus* that exercises it.

Available in this toolchain:
- **Functional coverage:** eUVM covergroups (`esdl.cover`: coverpoints, bins, crosses, transitions).
- **Code coverage:** `verilator --coverage` (line and toggle).
- **Assertions:** Verilator supports a subset of SVA. For this testbench, per-cycle scoreboard checks do the same job and are easier to debug.

Recommended order:
1. A **directed smoke test** (reset, a few writes, read them back).
2. The scoreboard.
3. Directed corner-case tests, one per spec item.
4. **Constrained random**, with weights (e.g. 70/30 write/read to push towards full, 30/70 towards empty).
5. **Coverage last.** Coverage measured on a testbench that hasn't been checked yet only measures stimulus that nobody verified.

---

## Verification plan

### How was the verification plan derived from my scenario list?

The starting point was eight scenarios. Each was checked against SPEC §9, and the result is `VERIFICATION_PLAN.md`. The main changes, and why:

| Original scenario | Change | Reason |
|---|---|---|
| Read when empty / write when full asserts the error flag | Reworded as *the request is rejected and the error flag pulses*. Added single vs consecutive rejects, and "nothing else changes". | SPEC §7: the pulse lasts **exactly one cycle**, stays high across consecutive rejects, and a reject has no side effects. |
| Pointers only advance on valid transactions | Became an **always-on check** (CHK-04), not a test. | It's a property that must hold on every edge, not a stimulus. Plans keep *checks* separate from *scenarios*. |
| Simultaneous read and write, read after write, write after read | Split into TS-08 (**same edge**, at empty / mid / full) and TS-09 (**consecutive edges**). | Read-after-write happens on different edges, so it isn't simultaneous. SPEC §6 defines three different behaviours for the same-edge case, depending on the level. |
| Reset at start, mid transfer, mid sequence | Added `wr_en` / `rd_en` held high **during** reset, and "pre-reset data never comes back". | SPEC §3 and §9.6 say both of these explicitly. |
| (missing) | **TS-07 wrap-around**: more than 64 writes, so pointers go 63 → 0. | SPEC §4 and §9.4. A single fill and drain only goes round once. |
| (missing) | **TS-11 constrained random.** | Directed tests only find the bugs you thought of. Random finds the combinations you didn't. |

The plan also has a traceability table (SPEC §9 → checks → tests) and completion criteria. One criterion is that **the number of checks must match the number of cycles driven**: a test that reports 0 errors after 0 checks proves nothing.

---

## Build flow

### Why start with the makefile when no testbench exists yet?

Because the testbench is built **incrementally** (industry term: *bring-up*), and nothing can be compiled or run without the build flow:

| Reason | Explanation |
|---|---|
| Nothing compiles without it | Every `.d` file is compiled by `ldc2` and linked with the Verilated DUT. |
| Verilator generates a file the testbench imports | `verilator --euvm` turns `rtl/sync_fifo.v` into `euvm_dir/Vsync_fifo_euvm.d`, which holds the exact port names and types the testbench connects to. |
| Build problems stay separate from testbench problems | Writing ten files and building once mixes compile, link and runtime errors together. Building after each small step means each error has one obvious cause. |
| The first check is a waveform | Reset plus a few writes, viewed in gtkwave, shows how the DUT and the testbench's sampling point line up, before any scoreboard depends on it. |

Order: makefile → top file (`sync_fifo_tb.d`), interface (`fifo_intf.d`), `Item.d`, minimal driver → waveform → monitor → scoreboard → tests.

### What has to change in the makefile copied from the comparator?

The comparator makefile hard-codes `Serialized_Comparator` in about 15 places. Rather than doing find-and-replace, the new makefile puts every project-specific name into **a variable defined once at the top**. That's standard makefile practice, and it means a rename touches one line.

| Comparator makefile | New makefile | Why |
|---|---|---|
| `Serialized_Comparator` repeated everywhere | `DUT = sync_fifo`, and `V$(DUT)...` for generated names | Verilator names its outputs `V<module>`: `Vsync_fifo.mk`, `Vsync_fifo__ALL.a`, `Vsync_fifo_euvm.d`, ... |
| Executable named like the DUT | `TOP = sync_fifo_tb` (binary and top D file) | Keeps the testbench binary distinct from the RTL module name, so a glob like `sync_fifo*` can't hit unrelated files. |
| `VLATOR_SRC = ...` | Replaced by `VLATOR_OBJS`, which **is** used | In the comparator, `VLATOR_SRC` was defined but never referenced: dead code. |
| `CC`, `CFLAGS` | Removed | Never used either. Every `g++` call has its own flags. |
| Testbench files listed inside the link rule | `TB_SRC` variable, grown one file at a time | Make fails if a listed file doesn't exist yet, so only list files once you've written them. |
| `+UVM_TESTNAME=Test.test` hard-coded | `TEST ?= ...`, `SEED ?= 1`, `VERBOSITY ?= UVM_HIGH` | `?=` sets a default that the command line can override: `make run TEST=... SEED=7`. You need this to run the plan's 11 tests and several seeds. |
| `touch verilator.stamp` first, and nothing cleans up on failure | Kept `touch` **first**, and added `.DELETE_ON_ERROR:` | If Verilator failed, the stamp would already exist, and the next `make` would wrongly skip Verilation. `.DELETE_ON_ERROR` makes make delete a target whose recipe fails. See [the stamp question below](#why-must-touch-verilatorstamp-be-the-first-line-of-its-recipe). |
| `(cd obj_dir; make -f ...)` | `$(MAKE) -C obj_dir -f ...` | `$(MAKE)` passes flags such as `-j` and `-n` on to the sub-make. `-C dir` is make's own "cd". |
| `rm -rf Serialized_Comparator*` | Explicit list of generated files | A glob can delete things you didn't mean to. Listing the files makes it clear what `clean` removes. |
| `run_overide` target | Removed | Comparator-specific (used a type override for that bug hunt). |
| `obj_dir/verilated_threads.o` listed twice | Listed once | Harmless duplicate. |

Useful targets:
- `make verilator.stamp`: Verilate the DUT only. It works before any testbench file exists, and lets you read the generated `euvm_dir/Vsync_fifo_euvm.d`.
- `make`: build the simulation binary (doesn't run it).
- `make run TEST=<module>.<class> SEED=<n>`: build if needed, then run.
- `make clean`: delete every generated file, **including the `.vcd`**.

### What does `make verilator.stamp` produce, and what is `Vsync_fifo_euvm.d`?

`verilator --euvm` translates the RTL into C++ (`obj_dir/`) plus D glue code (`euvm_dir/`). The file the testbench imports is `euvm_dir/Vsync_fifo_euvm.d`, and it has **two layers**:

| Layer | Class | Port types | Who uses it |
|---|---|---|---|
| Raw C++ model, seen from D | `extern(C++) class Vsync_fifo : VerilatedModel` | `ubvec!(N)*`, raw pointers into the C++ model's signals | Nobody directly. It's the bridge to C++. |
| D wrapper | `class DVsync_fifo : Entity` | `VlInExport!(N)` for DUT inputs, `VlOutExport!(N)` for DUT outputs | The testbench top: `dut = new DVsync_fifo();` |

`DVsync_fifo.doConnect()` binds each export to its C++ signal. The wrapper also provides `eval()` (run the model to settle after inputs change) and `trace(...)` (VCD dumping).

On the **testbench side**, the virtual interface declares `VlPort!(N)` members, and the top connects each one to the matching export, e.g. `vif.wr_en(dut.wr_en)`. So:

```
 testbench (fifo_intf.d)        generated wrapper (DVsync_fifo)        C++ model
 VlPort!1  wr_en   ──connect──▶ VlInExport!1  wr_en   ──doConnect──▶  ubvec!1* wr_en
 VlPort!8  rd_data ──connect──▶ VlOutExport!8 rd_data ──doConnect──▶  ubvec!8* rd_data
```

Port widths for this DUT: `clk`, `rst`, `wr_en`, `rd_en`, `full`, `empty`, `wr_err`, `rd_err` are 1 bit, `wr_data` and `rd_data` are 8 bits, and `wr_ptr` and `rd_ptr` are 6 bits.

To list the ports yourself:
```bash
grep -n "Export" euvm_dir/Vsync_fifo_euvm.d
```
(Searching for `VlPort` finds nothing here: `VlPort` is the **testbench-side** type, not the generated one.)

### The comparator has `Serialized_Comparator_tb.v` and `Serialized_Comparator.d`. Which one is the testbench top?

The **`.d` file**. In the eUVM flow there is **no Verilog testbench**. The top is D code:

| File | Language | Role in the eUVM flow |
|---|---|---|
| `Serialized_Comparator_tb.v` | Verilog | **Not used.** It's a standalone Verilog testbench for a plain simulator (Icarus, Vivado). The makefile never compiles it. |
| `Serialized_Comparator.d` | D | **The top.** It instantiates the Verilated DUT (`new DV<module>()`), generates the clock, connects the virtual interface, opens the VCD, and contains `main()`, which starts UVM. |

What a Verilog testbench does with `module ... endmodule`, `reg`, instantiation, `always #10 clk = ~clk` and `initial`, the D top does with an `Entity` class, a `Task` for the clock, and UVM components for stimulus. Verilog syntax in a `.d` file can't compile.

### Why did my `.d` file turn orange in VS Code?

The file started with the Verilog directive `` `timescale ``. In D, a backtick starts a **WYSIWYG (raw) string literal**, which runs until the next backtick. There was no closing backtick, so the highlighter treated the **whole rest of the file as one string** and coloured it all as string text (orange). The compiler would fail with `unterminated string constant`.

General lesson: when syntax colouring suddenly goes uniform from some point onwards, look for an unclosed string, character literal or comment at the point where it starts.

### How do I get D autocompletion in VS Code (Remote-SSH)?

Use the **code-d** extension (`webfreak.code-d`), installed on the **remote** side. It has three parts:

| Part | Role |
|---|---|
| `code-d` | VS Code extension (UI) |
| `serve-d` | Language server: highlighting, diagnostics, go-to-definition |
| **DCD** (`dcd-server`, `dcd-client`) | The completion engine. **Without it, there's no autocompletion.** |

code-d downloads `serve-d` and DCD into `~/.local/share/code-d/bin` on first use. On this server, the DCD download **timed out** (`Error: timeout of 10000ms exceeded` in the extension host log), so only `serve-d` was installed. Manual fix:

```bash
cd ~/.local/share/code-d/bin
curl -L -o dcd.tar.gz https://github.com/dlang-community/DCD/releases/download/v0.13.6/dcd-v0.13.6-linux-x86_64.tar.gz
tar xzf dcd.tar.gz && rm dcd.tar.gz
ls          # expect: dcd-client  dcd-server  serve-d
```

- `curl -L` follows redirects (GitHub release links redirect to a download server). `-o` names the output file.
- `tar xzf`: e**x**tract, g**z**ip-compressed, from **f**ile.

Then tell code-d where the eUVM imports are, so it can complete `uvm`, `esdl` and `std` symbols. In the remote settings (`~/.vscode-server/data/Machine/settings.json`, or *Preferences: Open Remote Settings*):

```json
{
    "d.stdlibPath": ["/tools/euvm/euvm-1.0-beta61-linux-x86_64/import"],
    "d.dubPath": "/tools/euvm/euvm-1.0-beta61-linux-x86_64/bin/dub"
}
```

`"auto"` only works if `ldc2` is on the PATH that the VS Code server sees, and that isn't guaranteed (the server isn't started from an interactive `.bashrc` shell). An explicit path always works. Then run **Developer: Reload Window**.

Completion for a symbol only works once the file **imports** the module that defines it. In a file with no `import esdl;`, DCD doesn't know `Signal` or `VlPort`.

---

## Testbench top and interface

### Why must `touch verilator.stamp` be the first line of its recipe?

Because the stamp has to be **older** than the files Verilation generates.

A stamp file stands in for a group of outputs that make can't track one by one. The rule `$(VLATOR_OBJS): verilator.stamp` says "these outputs depend on the stamp". If the stamp is touched **last**, it ends up newer than the `.o` files the same recipe just compiled. On the next `make`, those `.o` files look out of date. The rule that lists them has no recipe of its own, so make falls back to its **built-in** `%.o: %.cpp` rule, which compiles without the Verilator include paths:

```
euvm_dir/Vsync_fifo_euvm_funcs.cpp:1:10: fatal error: Vsync_fifo.h: No such file or directory
make: *** [<builtin>: euvm_dir/Vsync_fifo_euvm_funcs.o] Error 1
```

The `[<builtin>]` tag is the giveaway: the recipe that ran isn't in your makefile.

The correct pattern is **touch first + `.DELETE_ON_ERROR:`**:
- Touching first makes every generated file newer than the stamp.
- `.DELETE_ON_ERROR:` (a special GNU make target) deletes a target whose recipe fails. So a failed Verilation removes the stamp, and the next `make` retries it.

Tested behaviour: a clean build works; a second `make` prints `Nothing to be done`; touching the RTL re-Verilates once; a failing step leaves no stamp, and the next `make` recovers.

*(History: an earlier version of this makefile moved `touch` to the end to fix the failure case. That introduced the bug above, which was caught by the first rebuild.)*

### How does the top file's clock line up the DUT, the driver and the monitor?

With Verilator, the DUT only changes when the testbench calls `dut.eval()`. The testbench's own clock (`Signal clock`, which UVM components wait on) is a separate signal. **The order of these two decides what every component sees.**

`sync_fifo_tb.d` does this on each edge:

```d
dut.clk = true;   // 1. give the DUT its clock edge
dut.eval();       // 2. DUT processes the edge: registers update
dumpTrace();      // 3. record the waveform
clock = true;     // 4. only now wake up UVM components waiting on posedge
```

So a component that wakes on `vif.clock.posedge()` sees the DUT **after** the edge. The testbench uses this as follows:

| Edge | DUT | Testbench |
|---|---|---|
| Rising | Registers update, using the inputs held since the last rising edge. | **Driver** drives the next inputs. The DUT won't act on them until the next rising edge. |
| Falling | No state change. Combinational outputs settle with the new inputs. | **Monitor** samples everything. Mid-cycle, all values are stable. |

A probe run confirmed it (times in ps; 20 ns clock):

```
@50000  POS  driver drives wr_en=1, wr_data=a2
@60000  NEG  monitor: wr_en=1 wr_data=a2  wr_ptr=00 empty=1   <- inputs for edge 70 + state before it
@70000  POS  DUT already shows wr_ptr=01 empty=0              <- edge 70 accepted the write
@80000  NEG  monitor: wr_ptr=01 empty=0 rd_data=a2            <- show-ahead: the new word is visible
```

**Why not drive and sample on the same edge?** If the driver and monitor both wake on `posedge`, eUVM runs them in no guaranteed order. The monitor might read the inputs before or after the driver has changed them: a **race**. SystemVerilog solves this with *clocking blocks* (sample just before the edge, drive just after it). Using opposite edges is the standard way to get the same result without them.

**Why not copy the comparator's clock?** The comparator raised the testbench clock first and called `dut.eval()` **half a period later**. So the DUT really "saw" each rising edge at the time of the falling edge, which shifts the waveform half a cycle away from what the testbench thinks. And its driver and monitor both wait on `posedge`, which is exactly the race described above.

### Why `"uvm_test_top*"` and not `"uvm_test_top.*"` in `uvm_config_db::set`?

The second argument of `set` is a **glob** that's matched against the full path of each component that calls `get`.

| Pattern | Matches `uvm_test_top` (the test itself)? | Matches `uvm_test_top.env.agent.driver`? |
|---|---|---|
| `"uvm_test_top.*"` | ❌ No: there's no `.` after the name | ✅ Yes |
| `"uvm_test_top*"` | ✅ Yes | ✅ Yes |

With `"uvm_test_top.*"`, a `get` inside the test returned `false` and left `vif` as `null`. The first access to `vif.clock` then crashed with a **segmentation fault**, and there was no UVM message to explain why. Two lessons:
1. Make the scope cover every component that needs the handle.
2. **Always check the return value of `get`**, and stop with a clear message:
   ```d
   if (!uvm_config_db!(FifoIntf).get(this, "", "vif", vif))
       uvm_fatal("NOVIF", "virtual interface not found in uvm_config_db");
   ```
   That turns a mysterious segfault into `UVM_FATAL ... [NOVIF] virtual interface not found`.

### Why are the files and classes named `fifo_intf` / `FifoIntf`, not `Interface` / `intf` as in the comparator?

The D linter (DScanner, run by code-d) warned:

```
Module/package name 'Interface' does not match style guidelines. [dscanner.style.phobos_naming_convention]
Class name 'intf' does not match style guidelines.
```

The D standard library (Phobos) style, which is what most D code follows:

| Kind | Style | This project |
|---|---|---|
| Module / file | `lowercase_with_underscores` | `fifo_intf`, `sync_fifo_tb` |
| Class / struct | `PascalCase` | `FifoIntf`, `Top`, `SyncFifoTb` |
| Function / variable | `camelCase` | `stimulateClock`, `openTrace` |
| Constant (`enum`) | `UPPER_CASE` (common in practice) | `HALF_PERIOD` |

The comparator didn't follow this. The FIFO testbench does, from the first file onwards, so the linter output stays clean and any warning means something.

Exception: names fixed by UVM or by generated code keep their own style (`uvm_test`, `uvm_config_db`, `DVsync_fifo`, `build_phase`).

### How do I print the value of a `VlPort`?

Call `.read()`:

```d
writeln(vif.wr_ptr.read());     // 03
writeln(vif.wr_ptr);            // esdl.intf.verilator.verilated.VlPortObj!(...)  <- the object, not the value
```

`writeln` / `format` print the port **object** unless you ask for its value. In assignments and comparisons (`item.wr_ptr = vif.wr_ptr;`, `if (vif.full)`), eUVM converts the port to its value for you.

---

## Git


### I added a file to `.gitignore` but git still tracks it. Why?

`.gitignore` only affects **untracked** files. Once a file has been committed, git keeps tracking it whatever `.gitignore` says. To stop tracking it while keeping it on disk:

```bash
git rm --cached <file>      # remove from the index (git's tracking), keep the file on disk
git commit -m "Stop tracking <file>"
```

`--cached` is the important flag: without it, `git rm` also deletes the file from disk.

### Untracking a file hides it from future commits. Is it gone from the repo?

No. **Every old commit still contains it**, and `git push` uploads the whole history, so anyone can check out the old commit and read the file. To really keep a file out of a public repo, you have to remove it from **history**. That's only safe **before the first push**: rewriting history that others have already pulled breaks their clones.

In this project, the private files were only ever in one commit, which contained nothing else. So the fix was to drop that commit with a rebase:

```bash
git rm --cached AGENTS.md CLAUDE.md               # stop tracking; files stay on disk
git commit -m "Stop tracking AI context files"
git rebase --onto df5137d b89975b                 # replay everything after b89975b onto df5137d
git log --all --oneline -- AGENTS.md CLAUDE.md    # prints nothing = the files are in no commit
```

- `git rebase --onto <new-base> <old-base>` takes the commits **after** `<old-base>` and replays them on top of `<new-base>`. Here, `<old-base>` is the commit to drop and `<new-base>` is its parent, so that commit simply disappears.
- The replayed commits get **new hashes**, because a commit's hash depends on its parent.
- Git drops the "Stop tracking" commit automatically ("patch contents already upstream"): once the files never existed in history, deleting them is a no-op.
- `git log -- <paths>` lists commits that touched those paths. With `--all`, it searches every branch.
- Do the `git rm --cached` step **first**. If you rebase while the files are still tracked, git deletes them from disk when it drops the commit that added them.

If a private file is mixed into commits with other changes, the general tool is `git filter-repo --path <file> --invert-paths`.
