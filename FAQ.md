# FAQ

Questions raised, and explanations given, while building the eUVM testbench for the synchronous FIFO.
Nothing here gives away anything about bugs in the RTL.

**Contents**
- [Testbench architecture](#testbench-architecture)
  - [What fields should the item (transaction) carry?](#what-fields-should-the-item-transaction-carry)
  - [When does the read data appear? Same edge as `rd_en`?](#when-does-the-read-data-appear-same-edge-as-rd_en)
  - [Should the monitor send separate read and write events?](#should-the-monitor-send-separate-read-and-write-events)
  - [Should the scoreboard mirror the FIFO memory, address by address?](#should-the-scoreboard-mirror-the-fifo-memory-address-by-address)
  - [Scoreboard: a mirror of the FIFO memory, or check inside the real FIFO?](#scoreboard-a-mirror-of-the-fifo-memory-or-check-inside-the-real-fifo)
  - [When does the FIFO wrap around? Do the pointers go back to 0 when `rd_ptr == wr_ptr`?](#when-does-the-fifo-wrap-around-do-the-pointers-go-back-to-0-when-rd_ptr--wr_ptr)
  - [When is a write rejected? What happens when `wr_ptr` reaches 63?](#when-is-a-write-rejected-what-happens-when-wr_ptr-reaches-63)
  - [After a wrap, `wr_ptr < rd_ptr`. Isn't that a problem?](#after-a-wrap-wr_ptr--rd_ptr-isnt-that-a-problem)
  - [Should the scoreboard decide "write accepted?" from the DUT's `full` flag?](#should-the-scoreboard-decide-write-accepted-from-the-duts-full-flag)
  - [Sample vs edge: why does a table row pair two MON lines?](#sample-vs-edge-why-does-a-table-row-pair-two-mon-lines)
  - [What's a "row" in `make table`, and where should an error pulse appear in it?](#whats-a-row-in-make-table-and-where-should-an-error-pulse-appear-in-it)
  - [`UVM_FATAL [INVTST] Requested test ... not found`: what does it mean?](#uvm_fatal-invtst-requested-test--not-found-what-does-it-mean)
  - [Several errors look like different problems. How do I tell if they're one?](#several-errors-look-like-different-problems-how-do-i-tell-if-theyre-one)
  - [Where's the pass/fail result in the log?](#wheres-the-passfail-result-in-the-log)
  - [The scoreboard reported many errors. How do I read the first one correctly?](#the-scoreboard-reported-many-errors-how-do-i-read-the-first-one-correctly)
  - [`wr_ptr` is 6 bits wide. How can a 64-entry FIFO be full?](#wr_ptr-is-6-bits-wide-how-can-a-64-entry-fifo-be-full)
  - [The DUT disagrees with the spec. Could the spec be wrong?](#the-dut-disagrees-with-the-spec-could-the-spec-be-wrong)
  - [How do I view the waveform, and how do I read it correctly?](#how-do-i-view-the-waveform-and-how-do-i-read-it-correctly)
  - [The scoreboard reports 0 mismatches. How do I know it actually works?](#the-scoreboard-reports-0-mismatches-how-do-i-know-it-actually-works)
  - [Random tests, stress tests, coverage, assertions: where do I start?](#random-tests-stress-tests-coverage-assertions-where-do-i-start)
  - [What is `convert2string()`, and is it needed?](#what-is-convert2string-and-is-it-needed)
  - [Does the order of the read data matter?](#does-the-order-of-the-read-data-matter)
  - [Why can't I use `$display`, and how do I log from a sequence?](#why-cant-i-use-display-and-how-do-i-log-from-a-sequence)
  - [`rd_data` changed but `rd_ptr` didn't. Is that a timing bug?](#rd_data-changed-but-rd_ptr-didnt-is-that-a-timing-bug)
  - [When the FIFO is empty, does `rd_data` show the last value read?](#when-the-fifo-is-empty-does-rd_data-show-the-last-value-read)
  - [Why build the driver side first, and the monitor and scoreboard later?](#why-build-the-driver-side-first-and-the-monitor-and-scoreboard-later)
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
  - [Why does randomizing an item crash with `Illegal instruction`?](#why-does-randomizing-an-item-crash-with-illegal-instruction)
  - [The compiler printed many errors. Where do I start?](#the-compiler-printed-many-errors-where-do-i-start)
  - [How do `ubvec` values behave with integers and `format`?](#how-do-ubvec-values-behave-with-integers-and-format)
  - [`get_next_item` or `try_next_item` in the driver?](#get_next_item-or-try_next_item-in-the-driver)
  - [How do I print the value of a `VlPort`?](#how-do-i-print-the-value-of-a-vlport)
  - [Why did "Simulation Complete" appear in the middle of my log, before the last cycles?](#why-did-simulation-complete-appear-in-the-middle-of-my-log-before-the-last-cycles)
  - [The log is hard to follow. How do I get colours and section headers?](#the-log-is-hard-to-follow-how-do-i-get-colours-and-section-headers)
  - [Is there a table view, and a way to see every test's result at once?](#is-there-a-table-view-and-a-way-to-see-every-tests-result-at-once)
- [Git](#git)
  - [I added a file to `.gitignore` but git still tracks it. Why?](#i-added-a-file-to-gitignore-but-git-still-tracks-it-why)
  - [Untracking a file hides it from future commits. Is it gone from the repo?](#untracking-a-file-hides-it-from-future-commits-is-it-gone-from-the-repo)
  - [I committed. Is my work on GitHub now?](#i-committed-is-my-work-on-github-now)
  - [Do I need to push after every commit? Are unpushed commits safe?](#do-i-need-to-push-after-every-commit-are-unpushed-commits-safe)
  - [My commit is missing files. How do I fix it?](#my-commit-is-missing-files-how-do-i-fix-it)

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

### Scoreboard: a mirror of the FIFO memory, or check inside the real FIFO?

Neither. The standard choice is a **reference model that predicts the DUT's port behaviour**, compared against what the monitor observes **at the ports**.

| Option | What it means | Verdict |
|---|---|---|
| **Check inside the real FIFO** (white-box / backdoor) | Read the DUT's internal `mem[]` array and compare it with what was written | ❌ **Checks the DUT against itself.** The storage is internal: SPEC §2 calls the structure an implementation choice, so the testbench would break on a legal redesign (an SRAM macro, a different pointer scheme). It also proves nothing about what a *user* of the FIFO sees: a correct `mem[]` with a wrong `rd_ptr` or wrong flags still fails the spec. (With Verilator, internal signals aren't even visible to the testbench unless the RTL marks them public.) |
| **Mirror memory** (a 64-entry array indexed by model pointers) | Copy the DUT's structure in the testbench | ⚠️ Possible, but it re-implements the design. If the model copies the designer's structure, it tends to copy the designer's mistakes too. |
| **Queue model** + model pointers and flags (black-box) | `ubyte[] expected`: push on an accepted write, compare and pop on an accepted read; model `wrPtr`/`rdPtr` and predicted flags | ✅ **Industry standard.** It's written from the **spec** (behaviour), not from the RTL (structure). Order checking comes free with the queue (FIFO = queue), and every check is on a **port**, which is what the spec defines and what a user observes. |

This also answers "how do I know which slot was written?": you don't need to. The spec's observable promises are *order*, *values*, *flags*, *pointers* and *error pulses*, and the queue model plus the pointer counters check every one of them.

### When does the FIFO wrap around? Do the pointers go back to 0 when `rd_ptr == wr_ptr`?

No. Two separate things often get mixed up:

| | What it means | When it happens |
|---|---|---|
| **Wrap-around** | A pointer goes from slot **63 to slot 0** | Each pointer **independently**, when *it* advances past 63 (SPEC §4). The data stays where it is. |
| **`rd_ptr == wr_ptr`** | The FIFO is **empty or full** (SPEC §2 note: `full`/`empty` tell the two apart) | After the last read (empty), or after the 64th unread write (full). **Nothing moves.** |

The smoke test shows it: after 4 writes and 4 reads, the log has `wptr=04 rptr=04 empty=1`. The pointers are equal and **stay at 4**, and the next write goes to slot 4. Only **reset** puts the pointers back to 0.

In the model: keep `wrPtr`/`rdPtr` as `ubvec!6` and do `+= 1` on each accepted operation. 63 + 1 = 0 happens on its own, with no special case.

### When is a write rejected? What happens when `wr_ptr` reaches 63?

A write at slot 63 **wraps**: `wr_ptr` goes to 0, and writing continues at slot 0. A write is rejected only when the FIFO holds **64 unread entries**, whatever the pointer values.

Example: `rd_ptr = 3`, `wr_ptr = 9` (6 entries in slots 3–8; slots 0–2 were already read), then writes with no reads:

| Write # | Slot written | `wr_ptr` after | Entries | `full` | Result |
|---|---|---|---|---|---|
| 1 | 9 | 10 | 7 | 0 | accepted |
| 55 | 63 | **0** (wrap, §4) | 61 | 0 | accepted |
| 56 | 0 | 1 | 62 | 0 | accepted: reuses a slot that was already read |
| 58 | 2 | **3** = `rd_ptr` | **64** | **1** | accepted: now full |
| 59 | – | 3 | 64 | 1 | **rejected**: slot 3 still holds the oldest unread entry (a full FIFO never overwrites, §4); `wr_err` pulses |

When each request is rejected (FIFO state **before** the edge):

| Request | Rejected when | Result | SPEC |
|---|---|---|---|
| Write | full, and no read on the same edge | nothing stored, `wr_ptr` unchanged, `wr_err` high for one cycle after the edge | §4, §7 |
| Write | full, **with** a read on the same edge | **accepted** (the read frees a slot), no error | §6 |
| Read | empty | `rd_ptr` unchanged, `rd_err` high for one cycle after the edge | §5, §7 |
| Read | empty, **with** a write on the same edge | **still rejected** (no write-through); `rd_err` pulses | §5, §6 |
| Any | `rst = 1` | ignored, **no** error | §3 |

Equal pointers mean empty **or** full: `wr_ptr = rd_ptr = 3` above has 64 entries, while `wr_ptr = rd_ptr = 4` after the smoke test has 0. That's why the spec has both flags, and why the scoreboard model tracks the **count** (`expected.length`), not the pointer difference.

### After a wrap, `wr_ptr < rd_ptr`. Isn't that a problem?

No, it's normal for a **circular** buffer. The 64 slots form a ring (slot 63 is followed by slot 0). The valid entries run **forward from `rd_ptr`**, wrapping past 63, up to the slot before `wr_ptr`. Example: `rd_ptr = 3`, `wr_ptr = 1`, 62 entries:

```
slot:   0    1    2    3    4   ...   62   63
        ■    □    □    ■    ■   ...   ■    ■
        ↑    ↑         ↑
     newest wr_ptr   rd_ptr (oldest)
read order:  3 → 4 → … → 63 → 0
```

`rd_ptr` wraps too when it passes 63, so the two pointers take turns being numerically larger.

What **does** break is treating pointers as plain numbers:

| Calculation | `wr=9, rd=3` | `wr=1, rd=3` (after wrap) |
|---|---|---|
| `wr_ptr > rd_ptr` means "has data"? | true ✅ | false ❌ (62 entries) |
| `count = wr_ptr - rd_ptr` (signed `int`) | 6 ✅ | −2 ❌ |
| `count = (wr_ptr - rd_ptr) mod 64` (6-bit unsigned) | 6 ✅ | 62 ✅ |
| `count = expected.length` (queue model) | 6 ✅ | 62 ✅ |

Only modulo-64 arithmetic is valid, and even it can't tell **0 from 64** (both give a difference of 0). That's why `full` and `empty` exist. Comparing or subtracting ring pointers as ordinary numbers is a classic FIFO bug in RTL and testbenches alike. The scoreboard avoids it completely: decisions use `expected.length`, and the model pointers (`ubvec!6`, wrapping like the hardware) are only **compared** with the DUT's.

### Should the scoreboard decide "write accepted?" from the DUT's `full` flag?

No. **The model decides from its own state**: "accepted" means `count < 64` (or a simultaneous read), with `count = expected.length`. Then it compares the DUT's `full` with its own prediction.

If the model used the DUT's `full` to decide, it would **trust the thing it's checking**. A DUT with a wrong `full` flag would make the model accept or reject exactly as the DUT did, and the two would always agree. Rule: **DUT outputs are only ever compared, never used to drive the model.** The inputs (`wr_en`, `rd_en`, `wr_data`, `rst`) are the only DUT-side values the model consumes.

### Sample vs edge: why does a table row pair two MON lines?

Two different things:

| Word | What it is | Where you see it |
|---|---|---|
| **sample** | the monitor's mid-cycle snapshot (at the negedge) | one `MON` line (`make view`) |
| **edge** | one rising clock edge, where the DUT acts | one row of `make table` |

From the fill/drain log:

```
c001   40 ns  MON  rst=0 wr=1 rd=0 wdata=92 | rdata=00 wptr=00 rptr=00 full=0 empty=1 ...
c002   60 ns  MON  rst=0 wr=1 rd=0 wdata=23 | rdata=92 wptr=01 rptr=00 full=0 empty=0 ...

   40 ns sample          50 ns RISING EDGE         60 ns sample
   wr=1 wdata=92  ─────► DUT stores 92  ─────────► wptr=01 empty=0
```

Within **one sample**, the inputs (left of `|`) wait for the *next* edge, while the outputs (right of `|`) are the result of the *previous* edge. So a MON line straddles two edges, and reading raw MON lines means pairing "this line's inputs with the next line's outputs".

A **table row** is one edge: inputs from the sample before it, outputs from the sample after it. Seen per row, it's simply "this edge's inputs → this edge's outputs". Both descriptions are true, from different points of view; the table does the pairing so you don't have to.

### What's a "row" in `make table`, and where should an error pulse appear in it?

A **row** is one line of the `make table` output, and each row is **one rising clock edge**:

```
 cyc  edge ns │ op    rst wr rd wdata wr# rd# │   rdata │ wptr rptr full empty werr rerr │ scoreboard
 c001      50 │ WRITE   0  1  0    92   1   0 │      00 │   01   00    0     0    0    0 │ ✓
```

Read it as cause → effect: *"at the edge at 50 ns, the inputs going **into** it were `wr=1, wdata=92` (write request #1); **after** it, the DUT showed `wptr=01 empty=0`; the scoreboard agrees."*

**Error pulses.** SPEC §7: `wr_err`/`rd_err` are **registered**: a flip-flop set **by** the edge that rejects the request, high for one cycle **after** it. A **combinational** flag (gates only) would instead follow the request as soon as it's on the bus, i.e. *before* the edge.

```
              E1                      E2                      E3
wr_en    ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______________________   request, acted on at E2
registered     _______________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_   set BY E2 (SPEC §7)
combinational  ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______________________   follows the request (not §7)
```

The monitor samples mid-cycle, so in the edge table:

| | row E1 | row E2 (the rejected request) | row E3 |
|---|---|---|---|
| registered (correct) | 0 | **1** (same row as the request) | 0 |
| combinational | **1** (one row early) | 0 | 0 |

The scoreboard predicts the pulse for the request's own row and reports a mismatch if it's anywhere else.

### `UVM_FATAL [INVTST] Requested test ... not found`: what does it mean?

`+UVM_TESTNAME=fifo_test.FifoReadEmptyTest` asks the UVM **factory** to create a class named `FifoReadEmptyTest` from module `fifo_test`. The fatal at time 0 means the factory doesn't know that name. Causes, most common first:

1. **The test class doesn't exist.** Writing the *sequence* (in `fifo_seq.d`) isn't enough: each test is a class in `fifo_test.d` that selects the sequence by overriding `createSeq()`.
2. **No `mixin uvm_component_utils;`** in the class, so it was never registered with the factory.
3. **Wrong prefix.** The part before the dot is the D **module** name (`module fifo_test;`), not the file path.
4. **Stale binary.** `make run` rebuilds automatically, but running `./sync_fifo_tb` directly doesn't.

### Several errors look like different problems. How do I tell if they're one?

1. **Look for a pattern before explaining errors one by one.** Line up "what the DUT did" against "what the model expected" for every error row. Several errors are often **one shift**: the same pattern, displaced by one edge, produces an "extra" pulse on one row and a "missing" one on the next.
2. **Compare with a sibling check that passes.** If two signals are predicted by the **same** model rule and sampled the **same** way, and one passes while the other fails, the model's timing can't be the problem: the difference is in the DUT. If both fail the same way, suspect the model or the monitor first.

### Where's the pass/fail result in the log?

At the **end** of the log, in two lines:

| Line | Printed by |
|---|---|
| `[SCB] samples=130 edges_checked=129 data_checks=64 writes=64 reads=64 left_in_fifo=0 mismatches=0` | the scoreboard's `report_phase` |
| `UVM_ERROR :    0` (and `UVM_FATAL :    0`) | UVM's report server, in the `--- UVM Report Summary ---` block |

Finding them:

```bash
grep -E "samples=|UVM_(ERROR|FATAL) :" run.log     # -E: extended regex; | means "or"
tail -30 run.log                                   # the last 30 lines
make view LOG=run.log                              # then G (end of file), or /samples= to search
```

Read them in order: first **no errors and no fatals**, then **the counts make sense for the test** (every edge checked, data checks = accepted reads, writes and reads as intended). A run with 0 errors but `edges_checked=0` has checked nothing.

### The scoreboard reported many errors. How do I read the first one correctly?

Three habits, all from debugging the first fill-and-drain run (71 errors):

**1. Count transactions explicitly, using the pairing rule.** A MON line's **outputs** show what the **previous** edge did with the **previous** line's inputs. When a test does N writes, build a small table: *write k is driven in cycle c(k+1), consumed at the next edge, and its result is in the MON line of cycle c(k+2)*. It's very easy to read the result one write too early, e.g. to think `wptr=63` means "64 writes done" when it means 63 entries (slots 0–62) stored, with the 64th write still on the bus.

**2. Group the errors by kind before reading them all:**

```bash
grep "UVM_ERROR ../testbench" run.log | sed -E 's/.*\[SCB\] ([a-z_]+) mismatch.*/\1/' | sort | uniq -c
```

(`sed -E` extracts the field name from each error; `sort | uniq -c` counts each distinct name.) A pattern such as "1 × A, 1 × B, then 65 × the same pointer mismatch" usually means **one** original disagreement, followed by a model and a DUT that stay out of step by one transaction. Only the **first** error needs explaining; the rest are consequences.

**3. Check the model against the spec, not against your expectation of the DUT.** For the first error, look up each expected value in SPEC.md (depth, flag definition, acceptance rule). If the model agrees with the spec, the DUT is wrong. If it doesn't, the scoreboard is wrong. Never decide "the testbench is surely right" (or "surely wrong") without that check.

Then, and only then, open the waveform around the first error's time to **confirm** the theory.

### `wr_ptr` is 6 bits wide. How can a 64-entry FIFO be full?

`wr_ptr` is the index of the slot the **next** write goes to (SPEC §2), not the last slot written. With no reads (`rd_ptr = 0`):

| Writes done | Slots holding data | `wr_ptr` | Entries | `full` |
|---|---|---|---|---|
| 0 | none | 0 | 0 | 0 |
| 63 | 0–62 | 63 | 63 | 0 (slot 63 still free) |
| 64 | 0–63 | **0** (63 + 1 wraps) | 64 | 1 |

`wr_ptr` never needs the value 64: after the 64th write it **wraps to 0** (§4). So 6 bits are enough for the **ports**.

Note rows "0 writes" and "64 writes": both have `wr_ptr = rd_ptr = 0`, but one is empty and one is full. **The pointer values alone can't distinguish empty from full**, so `full`/`empty` can't be defined as a function of `wr_ptr` (§2 note). The entry count has **65** possible values (0–64), one more than 6 bits can represent, so a design needs one extra bit of internal state (a 7-bit counter, or a 7th "lap" bit on each pointer). That's an implementation choice inside the RTL and invisible at the ports. The scoreboard's equivalent is `expected.length`.

### The DUT disagrees with the spec. Could the spec be wrong?

It's the right question to ask first, and checking it is part of the job:

1. **Check that the spec is consistent with itself.** For example, "when is the FIFO full?" is answered by §1 (depth 64), §2 (`full`: "holds 64 entries"), §4 (a write is rejected only when full) and §8 (`full = 1` at 64 entries, `0` for 1–63). They agree, so the spec is unambiguous on this point. If clauses contradicted each other, or a case was missing, you'd raise a **spec clarification** with the architect *before* filing an RTL bug.
2. **If the spec is clear, it wins.** SPEC.md's introduction: *"If the two disagree, the spec wins, and the RTL has a bug."*
3. **Never edit the spec (or the test) to match the DUT.** The DUT behaving differently isn't a reason to redefine correct behaviour.

A common source of doubt is **index vs count**: slot indices run 0–63 (highest 63), but the entry count runs 0–64. `wr_ptr = 63` with no reads means slots 0–62 are filled, which is **63** entries: not full.

### How do I view the waveform, and how do I read it correctly?

**Option A: VaporView (inside VS Code, nothing to download).** Install the extension `lramseyer.vaporview` on the remote side. Then:
1. In the Explorer, click `sim/sync_fifo_tb.vcd`. If it opens as text, right-click it and choose **Open With… → VaporView**.
2. In VaporView's netlist panel, expand **`TOP`** and add the ports: `clk`, `rst`, `wr_en`, `wr_data`, `rd_en`, `rd_data`, `wr_ptr`, `rd_ptr`, `full`, `empty`, `wr_err`, `rd_err`.
3. Zoom to the time of interest (e.g. the first error's timestamp from the log). Show multi-bit values like the pointers in **decimal**, to match the log.

**Option B: gtkwave in WSL.** Copy the file to Windows (in VS Code, right-click it and choose **Download…**; or from WSL, `scp <user>@<server>:<path>/sim/sync_fifo_tb.vcd /mnt/d/<folder>/`), then run `gtkwave /mnt/d/<folder>/sync_fifo_tb.vcd`. In the SST pane, select `TOP`, pick the signals, and click **Append**.

Reading it correctly:
- **Stay at the `TOP` level.** It holds the DUT's ports, which is everything the spec defines. The `TOP.sync_fifo` scope also dumps the RTL's internal signals. For black-box verification, don't use them to decide pass or fail.
- **Time units:** the VCD is in **ps**, so 1290 ns = 1 290 000 ps. The log viewer shows ns.
- **Registered outputs** (`wr_ptr`, `rd_ptr`, `full`, `empty`, `wr_err`, `rd_err`) change at **rising** edges.
- **Inputs appear to change at falling edges.** The driver drives right *after* the DUT has evaluated a rising edge, and the next waveform dump point is the falling edge. So `wr_en` shows its new value half a cycle later than the driver's log time. Either way, the DUT acts on it at the **next rising edge**. It's a dump artifact, not a timing problem.
- To check one edge: read the inputs just **before** it, then the registered outputs just **after** it.

### The scoreboard reports 0 mismatches. How do I know it actually works?

Make it **fail on purpose**. A checker that has never reported an error is untested: it might be comparing a value with itself, checking nothing, or never being called. Three habits:

1. **Read the counts, not just the error total.** The scoreboard's report line is `samples=15 edges_checked=14 data_checks=4 writes=4 reads=4 left_in_fifo=0 mismatches=0`. Do the numbers make sense for the test? (4 writes and 4 reads in the smoke test; every pair of consecutive samples checked.) The scoreboard also raises an error if `edges_checked` is 0.
2. **Fault injection.** Temporarily corrupt what the checker sees, e.g. in the monitor: `if (getSimTime().getVal() == 180000) item.rd_data ^= 0x01;`, and confirm a mismatch is reported. Then **remove** it. (Do this in a scratch copy, or revert it right away, so it can never be committed.)
3. **Know where the error will appear.** A wrong `rd_data` sampled at 180 ns is reported at **200 ns**, because the read is checked when the snapshot after the consuming edge arrives. The real cause is usually **one sample before** the reported time.

In industry, this is the difference between "the test passed" and "the test **can** fail". Checkers are verified too.

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

### What is `convert2string()`, and is it needed?

It's **not needed for the testbench to work**. It's for **logging and debugging**, and it's standard practice: almost every real UVM item overrides it.

`convert2string()` is a method every `uvm_object` has. It returns a `string` describing the object, and **you decide what that string contains**. The default returns an empty string, so you override it:

```d
override string convert2string() {
    return format("rst=%b wr=%b data=%02x rd=%b", rst, wr_en, wr_data, rd_en);
}
```

`uvm_info` takes a **string**, so to log an item you have to turn it into one. UVM gives you two ways. This is real output from the same item:

**`item.sprint()`**: automatic, from the `@UVM_DEFAULT` fields, as a table:
```
UVM_INFO ... [DRV] Driving:
--------------------------------------
Name       Type            Size  Value
--------------------------------------
req        probe.FifoItem  -     @139
  wr_en                    1     false
  rd_en                    1     true
  wr_data  ubyte           8     0x89
  rst                      1     false
  rd_data  ubyte           8     0x00
  ...                      (6 more lines)
--------------------------------------
```

**`item.convert2string()`**: written by you, one line:
```
UVM_INFO ... [DRV] Driving: rst=0 wr=0 data=89 rd=1
```

| | `sprint()` / `print()` | `convert2string()` |
|---|---|---|
| Who writes it | UVM, automatically (from `@UVM_DEFAULT`) | You |
| Shows | Every field, including outputs that aren't filled in yet | Only the fields you choose |
| Size | ~17 lines per item | 1 line |
| Best for | Inspecting one object in detail | Per-cycle logs (driver, monitor, scoreboard) |

Why it matters here: the driver logs **one item per clock cycle**. A 5000-cycle random test is about 85 000 lines with `sprint()`, or 5000 with `convert2string()`. With one line per cycle, the log reads like a timeline, so you can spot the cycle where something went wrong and jump to that time in the waveform.

Format codes used: `%b` prints a `bool` as `0`/`1`; `%02x` prints a number in hex, padded to 2 digits (`0x0a` prints as `0a`). `format` comes from `import std.format: format;`.

### Does the order of the read data matter?

**Yes. Order is the definition of a FIFO** (*First In, First Out*). SPEC §9.1: every accepted write is read back exactly once, **in the same order**, with the same value. A FIFO that returns all the right bytes in the wrong order is broken: whatever consumes the stream (a CPU reading a packet, a UART transmitter) gets corrupted data.

This shapes the testbench:
- The scoreboard model is a **queue**: push at the back on each accepted write, compare and pop at the front on each accepted read. A set or a bag of values would miss reordering bugs.
- Directed tests use **distinct** data values (random or counting), so a reordering is visible. Writing `00` four times would hide it.

### Why can't I use `$display`, and how do I log from a sequence?

`$display` is a SystemVerilog system task. D has no `$` tasks: `$` is only valid inside `[ ]`, where it means "length of the array", so `$display(...)` fails with `found '$' instead of statement`.

The UVM way to log is the **report macros**: `uvm_info`, `uvm_warning`, `uvm_error`, `uvm_fatal`:

```d
uvm_info("SEQ", format("write cycle, wr_data=%02x", req.wr_data), UVM_HIGH);
//        ID     message (a string: build it with format)          verbosity
```

Compared with a plain print:

| | `writeln` / `$display` | `uvm_info` |
|---|---|---|
| Timestamp, source file and line, component path | ❌ | ✅ `UVM_INFO fifo_seq.d(27) @ 140000: ...` |
| Filter by verbosity (`+UVM_VERBOSITY=UVM_LOW` hides `UVM_HIGH` messages) | ❌ | ✅ |
| Counted in the end-of-test summary | ❌ | ✅ (`uvm_error` counts are what make a test fail) |

Use `UVM_LOW` for a few important messages per test, `UVM_MEDIUM` for per-transaction summaries, and `UVM_HIGH` for per-cycle detail. The makefile runs with `VERBOSITY=UVM_HIGH`; for a long random test, `make run VERBOSITY=UVM_LOW`.

D details from the same review: booleans are lowercase **`true` / `false`**, and `0 .. 4` in `foreach (i; 0 .. 4)` means 0, 1, 2, 3.

### `rd_data` changed but `rd_ptr` didn't. Is that a timing bug?

No. It's show-ahead behaviour (SPEC §5), and it confuses almost everyone the first time. From the smoke test:

```
time (ns)      150            160 (MON)             170            180 (MON)
event       rising edge      sample              rising edge      sample
DUT         writes d2        rptr=0, rdata=18    CONSUMES 18      rptr=1, rdata=59
driver      drives rd=1 ─────────────────────────► (acted on here)
```

- `rd_data` is **combinational**: it always shows `mem[rd_ptr]`, the **oldest** entry. It doesn't wait for `rd_en`.
- `rd_en` doesn't *fetch* data; it **consumes** the entry already on `rd_data`, at the next rising edge. So in the sample where `rd=1` is first seen, `rptr` is still the old value and `rdata` is the byte **about to be consumed**.
- After that edge, `rptr` advances and `rdata` moves to the next entry.

So the byte a read takes is **the `rdata` in the snapshot where `rd=1`**, not the one after it. SPEC §5: *"The value read is the value of `rd_data` just before that edge."* A standard (non-show-ahead) FIFO is different: there, `rd_data` updates one cycle **after** `rd_en`.

A related rule for any testbench: **never add idle cycles to the stimulus to make the checker's job easier.** If back-to-back traffic looks confusing in the log, the fix is in your understanding or your model, not in the stimulus. Back-to-back traffic is exactly what the DUT has to handle.

### When the FIFO is empty, does `rd_data` show the last value read?

No. `rd_data` shows **whatever is stored at `rd_ptr`**. After the last read, `rd_ptr` points at the next slot, which may never have been written (`00` in Verilator), or may hold data from **before a reset** or from a **previous lap** around the circular buffer. That last case looks like valid data. SPEC §3/§5: `rd_data` is **undefined while `empty`**, so the scoreboard compares `rd_data` **only when its model says the FIFO isn't empty**.

### Why build the driver side first, and the monitor and scoreboard later?

They aren't skipped. They're **Milestone 2**, straight after the first waveform. The order is deliberate, and it's standard **bring-up** practice: add one layer at a time, and prove each layer before building on it.

The testbench has two paths:

```
stimulus path:   sequence → sequencer → driver → DUT inputs          (Milestone 1)
checking path:   DUT ports → monitor → scoreboard (reference model)  (Milestone 2)
```

| Reason | Explanation |
|---|---|
| **The checker is only as good as what it observes** | The scoreboard trusts the monitor, and the monitor trusts that the stimulus was what the sequence intended. If all three are new and the first run reports a mismatch, it could be the sequence, the driver, the monitor's sampling time, the model, or the DUT. Five suspects at once. |
| **A waveform is an independent check** | With only the stimulus path, you check by eye: is `rst` high for 3 cycles, are there 4 writes then 4 reads, does `wr_ptr` step? The waveform doesn't depend on any testbench code being right. Once that looks right, the stimulus path is a **known-good** base. |
| **The monitor depends on timing you should see first** | The monitor samples on the falling edge, and has to pair "inputs going into edge N" with "outputs after edge N". Seeing those relationships in a real waveform first makes the monitor much easier to write correctly. |
| **Writing the expected values by hand is the scoreboard's design** | Predicting by hand what the smoke test should do (pointers, flags, which byte appears when) is exactly the reasoning the reference model will automate. Doing it once on 14 cycles makes the model's logic obvious. |
| **Nothing runs without agent, env and test** | Those three are needed whatever comes next. The monitor lives inside the agent, and the scoreboard inside the env, so they slot into a structure that's already running. |

Rule of thumb: **never debug two new things at once.** Each step should add one new thing, so when something breaks, there's one suspect.

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

### Why does randomizing an item crash with `Illegal instruction`?

It was observed on eUVM beta61 with this combination on the **same object**:

```d
class FifoItem: uvm_sequence_item {
    @rand bool wr_en; ...
    constraint! q{ wr_en dist [true := 7, false := 3]; } c_bias;   // class-level dist
}
...
item.randomizeWith!q{ wr_en == false; }();                        // inline constraint
```

| Variant (tested in isolation) | Result |
|---|---|
| `randomize()`, no constraints | ✅ |
| Class-level `dist` + `randomize()` | ✅ (ratio ≈ 0.70 over 1000 draws) |
| `randomizeWith` without a class-level `dist` | ✅ |
| `dist` written **inside** `randomizeWith` | ✅ (ratio ≈ 0.70) |
| Class-level `dist` **+** `randomizeWith` | ❌ `Illegal instruction (core dumped)` |

"Illegal instruction" is how a failed internal `assert` shows up in an optimised (`-O3`) build: the program stops with no UVM message.

**Workaround, and also the better design:** keep the item free of weighting constraints. The item defines what's *legal*; sequences decide what's *likely*, with `randomizeWith!q{ wr_en dist [true := 7, false := 3]; }`. That way each sequence (fill-biased, drain-biased, balanced) chooses its own weights.

General debugging lesson: when a crash has no message, **bisect**. Strip the failing code down to the smallest variant that still crashes, changing one thing at a time.

### The compiler printed many errors. Where do I start?

With the **first** one. D (like most compilers) keeps going after an error and reports what *follows from it*. Example from this project: one wrong line in `fifo_sequencer.d`:

```d
class FifoSeq : uvm_sequencer        // template used without a type parameter
```

produced four errors:

```
fifo_sequencer.d(5): Error: template class `uvm_sequencer(REQ = uvm_sequence_item, RSP = REQ)` is used as a type without instantiation ...
uvm_component_defines.d(200): Error: function `...get_object_type` does not override any function
uvm_component_defines.d(114): Error: mixin `...uvm_component_registry_mixin` error instantiating
uvm_object_defines.d(261): Error: function `...get_type_name` does not override any function
```

Only the first is a real mistake: with no valid base class, the code generated by `mixin uvm_component_utils` has nothing to `override`. Fix line 5, and all four go away.

Two more habits:
- **Errors in your own file come first in importance.** An error reported inside `/tools/euvm/.../import/uvm/...` almost always means *your* code passed something wrong into the library.
- `make 2>&1 | grep -A3 Error | head` shows only the first few errors, with 3 lines of context each. `2>&1` merges stderr (where errors go) into stdout so `grep` can see them.

### How do `ubvec` values behave with integers and `format`?

`ubvec!N` (esdl's N-bit unsigned bit vector) models hardware widths exactly, but it's **stricter than a plain integer**. Tested on eUVM beta61:

| Code | Result |
|---|---|
| `ubvec!6 p = 63;` | ❌ compile error: `none of the overloads of 'this' are callable using argument types (int)` |
| `ubvec!6 p = toubvec!6(63);` | ✅ |
| `ubvec!6 q = p + 1;` | ❌ compile error: `p + 1` is a **32-bit** `ubvec` (it widens, like Verilog's expression sizing) |
| `ubvec!6 q = cast(ubvec!6)(p + 1);` | ✅ q = 0 (truncated to 6 bits: wraps) |
| `p += 1;` (p = 63) | ✅ p = 0, wraps 63 → 0 like a 6-bit register |
| `format("%s", p)` | `3f` (hex by default) |
| `format("%d", p)` | `63` |
| `format("%2d", p)` with p = 5 | `5`: the **width is ignored** for `ubvec` |
| `format("%2d", cast(uint) p)` | ` 5` (padded) |

Rules of thumb: build a `ubvec` from a number with `toubvec!N(x)`, increment with `+=` to get hardware wrap-around, and `cast(uint)` when printing with a fixed width.

### `get_next_item` or `try_next_item` in the driver?

Both fetch the next item from the sequencer. The difference is **what happens when there isn't one**:

| | `get_next_item(req)` | `try_next_item(req)` |
|---|---|---|
| No item available | **Blocks** until a sequence sends one | Returns at once with `req is null` |
| Bus while waiting | Untouched: **the last values stay driven** | The driver drives what you choose (idle) |
| Typical use | Transaction-level drivers (one item = a whole bus transfer, e.g. an APB write) | **Cycle-based** drivers (one item = one clock cycle), like this FIFO driver |

The danger with `get_next_item` in a cycle-based driver: if the last item was a write (`wr_en=1`), `wr_en` stays high while the driver waits, and the DUT **writes on every edge**. Nothing in the log shows it, because no item is being driven. It looks like a DUT bug, but it's a testbench bug.

Cycle-based pattern:

```
forever:
    wait(vif.clock.posedge())
    seq_item_port.try_next_item(req)
    if (req is null)  drive idle
    else              drive req; seq_item_port.item_done()
```

Waiting for the edge **before** asking for an item matters too: the driver then decides something for **every** cycle, and never skips one.

### How do I print the value of a `VlPort`?

Call `.read()`:

```d
writeln(vif.wr_ptr.read());     // 03
writeln(vif.wr_ptr);            // esdl.intf.verilator.verilated.VlPortObj!(...)  <- the object, not the value
```

`writeln` / `format` print the port **object** unless you ask for its value. In assignments and comparisons (`item.wr_ptr = vif.wr_ptr;`, `if (vif.full)`), eUVM converts the port to its value for you.

### Why did "Simulation Complete" appear in the middle of my log, before the last cycles?

Because the simulator writes to **two output streams**, and they're buffered differently:

| Messages | Stream | Buffering when piped (`\| tee`, `\| grep`, `> file`) |
|---|---|---|
| `UVM_INFO ...` (all UVM reports) | stdout | **Block-buffered**: written out in ~4 KB chunks |
| `[ESDL!tb] Starting Phase ...`, `Shutting down ...`, `Simulation Complete` | stderr | **Unbuffered**: written immediately |

So the ESDL shutdown lines (stderr) reached the terminal **immediately** at the end of the run, while the last ~4 KB of UVM messages (stdout) were still sitting in the buffer. They were flushed **after** them, splitting a `[DRV]` line in half:

```
UVM_INFO ... @ 210000: ...driver [DRV] rst=0 wr=0 rd=1 wdata=00 | rdata=00 wptr=00 [ESDL!tb] Shutting down all the Routine threads
[ESDL!tb] Shutting down all the active Tasks
[ESDL!tb] Simulation Complete
rptr=00 full=0 empty=0 werr=0 rerr=0
UVM_INFO ... @ 230000: ...sequencer@@seq [SEQ] idle cycle 0
```

Nothing was wrong with the simulation. The evidence was in the report summary: `[SEQ] 14` and `[DRV] 14`, so all 14 cycles, the idle ones included, ran, and the report itself is stamped `@ 310000` (the last idle cycle at 270 ns + 40 ns drain).

Ways to check this kind of thing:
- `2>/dev/null` drops stderr: the `[ESDL!tb]` lines disappear, which shows they're on stderr.
- The **report counts by id** at the end are the ground truth for "did everything run?".

**Fix:** the makefile's `run` target uses `stdbuf -oL`, which makes stdout **line-buffered** (flushed at every newline), so both streams come out in true order. To capture both streams in a log file, redirect stderr too:

```bash
make run 2>&1 | tee run.log
```

`2>&1` sends stderr (stream 2) wherever stdout (stream 1) goes, so `tee` sees both. Without it, `run.log` only contains the UVM messages.

**Lesson:** the order of lines in a log isn't automatically the order of events. Trust the **timestamps** (`@ 230000`) and the summary counts over the line order.

### The log is hard to follow. How do I get colours and section headers?

Use the log viewer, `sim/logview.py`. The simulation log stays **plain text**, and the viewer only changes how it's **displayed**:

```bash
cd sim
make run 2>&1 | tee run.log      # run, and save the full log (stdout + stderr)
make view                        # colour-coded, paged view of run.log  (q to quit)
make view LOG=other.log          # view a different log
make run 2>&1 | python3 logview.py   # live view while it runs
```

What it does:

| Feature | Detail |
|---|---|
| Compact lines | `c007   150 ns  DRV  rst=0 wr=0 rd=1 wdata=00` instead of `UVM_INFO ../testbench/fifo_driver.d(42) @ 150000: tb.uvm_dock.root.uvm_test_top.env.agent.driver [DRV] ...`. Time in **ns** (the raw log is in ps). |
| Cycle numbers | `c000`, `c001`, ...: every SEQ, DRV and MON line belonging to the same clock cycle has the same number (from the time, with a 20 ns period and the first posedge at 10 ns; `--period` / `--first-edge` if the clock changes). |
| Section headers | `──── WRITE (from cycle c003) ────` whenever the kind of cycle changes (RESET / WRITE / READ / R+W / IDLE), worked out from the `rst`, `wr`, `rd` fields. `--no-headers` turns them off for random tests. |
| Colours | Tags (SEQ cyan, DRV yellow, MON green), data bytes bold, flags bright when `1` and dim when `0`, `werr`/`rerr` red when set, `UVM_ERROR`/`UVM_FATAL` lines red, and summary counts green at 0, red otherwise. |
| DRV lines show stimulus only | The driver never fills in the response fields, so their zeros are hidden. The real outputs come from MON lines. |

**Why not put colour codes into the log itself?** Industry practice is to keep logs plain: ANSI colour codes are invisible escape sequences (`^[[1;31m`) that break `grep`, `diff`, editors and CI log parsers. Colouring at **view time** (like `less -R`, `ccze` or IDE log viewers) keeps the archived log clean and the display friendly. The same reasoning is why the section headers are worked out by the viewer instead of being extra `uvm_info` lines in the sequence: the viewer can't get the ordering wrong. A banner printed by the sequence when a phase starts would appear *between* a cycle's DRV and MON lines, because the monitor samples half a cycle later.

Plain-text fallbacks: output that isn't a terminal (a pipe or file) is uncoloured unless you pass `--color`, and `NO_COLOR=1` disables colour too.

### Is there a table view, and a way to see every test's result at once?

Yes: `logview.py` has two more views, wrapped by makefile targets.

**`make table`: one row per rising edge.** This builds the scoreboard's pairing rule into the layout: each row is **one edge**, with the inputs that went *into* it, the `rd_data` it consumes, the outputs *after* it, and the scoreboard's verdict for **that** edge.

```
              │──── inputs into the edge ──── │ before  │──── outputs after the edge ─── │
 cyc  edge ns │ op    rst wr rd wdata wr# rd# │   rdata │ wptr rptr full empty werr rerr │ scoreboard
 c062    1270 │ WRITE   0  1  0    cf  62   0 │      92 │   62   00    0     0    0    0 │ ✓
 c063    1290 │ WRITE   0  1  0    5a  63   0 │      92 │   63   00    1     0    0    0 │ ✗ full: exp 0 got 1
               └─ ERROR @1300 ns [SCB] full mismatch: expected=0 got=1
```

| Column | Meaning |
|---|---|
| `cyc`, `edge ns` | The cycle whose inputs this edge consumes, and the edge's time |
| `wr#`, `rd#` | Write and read **requests** sent so far, restarting at reset. They answer "which write is this?" without counting by hand. |
| `rdata` (before) | `rd_data` just before the edge: the byte a read on this edge consumes (bold when `rd=1`) |
| outputs | The DUT's state after the edge. **Cyan** = changed at this edge, red `werr`/`rerr` = an error pulse. |
| scoreboard | `✓`, `✓ read 92`, or `✗` with the first mismatch. Every error is listed in full under its row (`└─`). |

```bash
make table LOG=filldrain.log                                   # whole run (q to quit)
make table LOG=filldrain.log ARGS=--first-error                # start here on a FAIL
make table LOG=filldrain.log ARGS=--errors-only                # every error, 3 edges of context
make table LOG=filldrain.log ARGS="--around 1300 --context 5"  # edges near a time
```

The footer gives the scoreboard counts, the UVM error and fatal counts, a **PASS/FAIL** verdict, and *"first error at edge … ns"*.

**`make summary`: regression table.** One line per `*.log` in `sim/`:

```
log           test               seed  edges  data  writes  reads  left  mismatch  errors  fatal result
filldrain.log FifoFillDrainTest     1    129    64      64     64     0         0       0      0 PASS
run.log       FifoTest              1     14     4       4      4     0         0       0      0 PASS
2/2 runs passed
```

The verdict rules: **FAIL** if any `UVM_ERROR` or `UVM_FATAL`; **INCOMPLETE** if the log has no UVM report summary (the run crashed or was cut short); **NO SCB** if there's no scoreboard report; **NO CHECKS** if the scoreboard checked 0 edges (zero errors with zero checks proves nothing); **NOT A RUN** for a non-simulation log, e.g. a build log; otherwise **PASS**.

Tip: name each run's log after its test (`make run TEST=fifo_test.X 2>&1 | tee x.log`), so `make summary` shows the whole regression.

---

## Git


### I added a file to `.gitignore` but git still tracks it. Why?

`.gitignore` only affects **untracked** files. Once a file has been committed, git keeps tracking it whatever `.gitignore` says. To stop tracking it while keeping it on disk:

```bash
git rm --cached <file>      # remove from the index (git's tracking), keep the file on disk
git commit -m "Stop tracking <file>"
```

`--cached` is the important flag: without it, `git rm` also deletes the file from disk.

### I committed. Is my work on GitHub now?

No. `git commit` and `git push` are separate steps:

| Step | What it does | Where the data ends up |
|---|---|---|
| Edit files | Changes the working files | The project folder on the machine you work on (here, the server `inc-hq-server4`) |
| `git commit` | Saves a snapshot **locally** | The `.git/` folder in that same project, still on the same machine |
| `git push` | Uploads commits to a **remote** | The remote's server (e.g. GitHub), only if a remote is configured |

`git remote -v` lists the configured remotes. If it prints nothing, there's nowhere to push to, and `git push` fails with `fatal: No configured push destination.` A remote is added once, e.g. `git remote add origin git@github.com:<user>/<repo>.git`, and after that `git push` uploads to it.

### Do I need to push after every commit? Are unpushed commits safe?

Commits are **complete and permanent locally** as soon as they're made: message, author, date and parent are all stored in `.git/`. When you eventually `git push`, git uploads **every** commit made so far, in order, with the original dates, so the history on GitHub looks the same whether you pushed daily or once at the end.

| | Push now, to a **private** repo | Push only at the end |
|---|---|---|
| History on GitHub | Identical | Identical |
| Backup | ✅ A second copy off the work machine | ❌ A single copy (and `/scratch` filesystems are often not backed up) |
| Free to `--amend` / rebase | Only commits not yet pushed | ✅ Everything |

Recommended: **create the GitHub repo as Private, push early and often, and make it public when it's ready.** Once a commit is pushed, don't amend or rebase it (that would need a force-push). Fix things with a new commit.

First push of an existing local repo:

```bash
git branch -m master main                                  # rename branch to GitHub's default
git remote add origin git@github.com:<user>/<repo>.git     # register the remote (SSH)
git push -u origin main                                    # upload; -u remembers the pairing for later pushes
```

Create the GitHub repo **empty** (no README, license or .gitignore), otherwise its first commit conflicts with your local history.

### My commit is missing files. How do I fix it?

First check what a commit contains:

```bash
git show --stat HEAD        # files changed in the last commit
git status --short          # what's still uncommitted: ?? = untracked, M = modified, A = staged new file
```

A common cause is running `git add` from a **subdirectory**: paths are relative to where you are, so from `sim/`, `git add testbench/` matches nothing. Run git from the repo root, or check with `git status` before committing.

If the commit **hasn't been pushed**, fix it rather than adding a "forgot some files" commit:

```bash
git add <missing files>
git commit --amend -m "corrected message"
```

`--amend` replaces the last commit with one that contains the old contents **plus** what's now staged. It can also fix the message. The commit gets a new hash. **Only amend unpushed commits**: rewriting a commit that others have already pulled makes their history diverge from yours.

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
