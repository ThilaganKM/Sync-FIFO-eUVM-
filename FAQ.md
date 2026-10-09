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

Order: makefile → top file, `Interface.d`, `Item.d`, minimal driver → waveform → monitor → scoreboard → tests.

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
| `touch verilator.stamp` as the **first** line of the recipe | Moved to the **last** line | If Verilator fails, the stamp would already exist, and the next `make` would wrongly skip Verilation. A stamp should only be created after success. |
| `(cd obj_dir; make -f ...)` | `$(MAKE) -C obj_dir -f ...` | `$(MAKE)` passes flags such as `-j` and `-n` on to the sub-make. `-C dir` is make's own "cd". |
| `rm -rf Serialized_Comparator*` | Explicit list of generated files | A glob can delete things you didn't mean to. Listing the files makes it clear what `clean` removes. |
| `run_overide` target | Removed | Comparator-specific (used a type override for that bug hunt). |
| `obj_dir/verilated_threads.o` listed twice | Listed once | Harmless duplicate. |

Useful targets:
- `make verilator.stamp`: Verilate the DUT only. It works before any testbench file exists, and lets you read the generated `euvm_dir/Vsync_fifo_euvm.d`.
- `make`: build the simulation binary (doesn't run it).
- `make run TEST=<module>.<class> SEED=<n>`: build if needed, then run.
- `make clean`: delete every generated file, **including the `.vcd`**.

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
