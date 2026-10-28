# Solutions: bugs found in `rtl/sync_fifo.v`

> ⚠️ **Spoilers.** This file records the bugs found in the DUT, with the evidence and the spec clauses they violate.
> If this project is published as a bug-hunt activity, this file belongs **only on the `solution` branch**.

Each entry: **symptom → evidence → spec clause → verdict**, written as a bug report.

---

## Bug 1: `full` asserts at 63 entries; the 64th write is rejected

**Found by:** `FifoFillDrainTest` (TS-02), seed 1: reset, 64 writes, 64 reads.

**Scoreboard summary:** `samples=130 edges_checked=129 data_checks=64 writes=64 reads=64 left_in_fifo=0 mismatches=71`

**First error and the cycles around it** (`make view LOG=filldrain.log`):

```
c063    1270 ns  SEQ  write cycle 62, wr_data=5a
c063    1280 ns  MON  rst=0 wr=1 rd=0 wdata=5a | rdata=92 wptr=62 rptr=00 full=0 empty=0 werr=0 rerr=0
c064    1290 ns  SEQ  write cycle 63, wr_data=90
c064    1300 ns  MON  rst=0 wr=1 rd=0 wdata=90 | rdata=92 wptr=63 rptr=00 full=1 empty=0 werr=0 rerr=0
ERROR         1300 ns  SCB  full mismatch: expected=0 got=1
c065    1320 ns  MON  rst=0 wr=0 rd=1 wdata=87 | rdata=92 wptr=63 rptr=00 full=1 empty=0 werr=1 rerr=0
ERROR         1320 ns  SCB  wr_ptr mismatch: expected=0 got=63
ERROR         1320 ns  SCB  wr_err mismatch: expected=0 got=1
```

**Reading it** (pairing rule: a MON line's outputs show what the previous edge did with the previous line's inputs):

| Time | DUT | Spec | Clause |
|---|---|---|---|
| 1300 ns, after the **63rd** write | `full=1` with 63 entries (`wptr=63`, `rptr=0`, no reads) | `full=0` for 1–63 entries | §8 |
| Edge at 1310 ns: the **64th** write (`0x90`) | rejected: `wptr` stays 63, `werr=1` at 1320 ns | accepted (not full); `wr_ptr` wraps to 0; `full=1` after it | §4, §8 |
| Overall | holds only 63 entries; byte `0x90` is never read back | capacity 64 | §1 |

**Why 71 errors:** one disagreement. Error counts by kind: 65 × `wr_ptr`, then 1 each of `full`, `wr_err`, `rd_data`, `rd_ptr`, `empty`, `rd_err`. After the rejected write, the model holds one more byte than the DUT: every later `wr_ptr` check differs by that one write, and at the end of the drain, the DUT is empty while the model still expects `0x90`.

**Testbench or RTL?** The scoreboard's expectations were checked clause by clause against the spec: depth 64 (§1); `full=0` with 63 entries (§8); a write into a FIFO with 63 entries is accepted (§4). The model agrees with the spec, so the DUT is wrong. **Verdict: RTL bug.**

**Root cause (from the designer's side):** `full` was computed from the 6-bit pointers alone, as `full = (wr_ptr + 1 == rd_ptr)`, i.e. "full when the next write would land on the oldest entry". That's the classic "one slot wasted" ring buffer: it can only distinguish 64 pointer states, so to tell empty (`wr_ptr == rd_ptr`) from full it gives up one slot, and the FIFO holds 63. The spec requires 64, which needs 65 states (0..64 entries), so one extra bit of state (SPEC §2 note).

**Fix** (`rtl/sync_fifo.v`): a 7-bit entry counter drives both flags.

```diff
-    assign empty = (wr_ptr == rd_ptr);
-    assign full  = ((wr_ptr + 1'b1) == rd_ptr);
+    reg [ADDR_W:0] count;
+
+    assign empty = (count == 0);
+    assign full  = (count == DEPTH[ADDR_W:0]);
 ...
+    always @(posedge clk) begin
+        if (rst)
+            count <= {(ADDR_W+1){1'b0}};
+        else if (wr_acc && !rd_acc)
+            count <= count + 1'b1;
+        else if (rd_acc && !wr_acc)
+            count <= count - 1'b1;
+    end
```

`empty` changes too: with a counter, `wr_ptr == rd_ptr` no longer has to mean empty (it's also true when full), so both flags come from the one source of truth. The alternative fix is a 7th "lap" bit on each pointer: empty when all 7 bits are equal, full when the low 6 are equal and the lap bits differ.

**Regression:** `FifoTest` (smoke) and `FifoFillDrainTest`, seed 1, after the fix:

```
FifoTest:          samples=15  edges_checked=14  data_checks=4  ... mismatches=0   UVM_ERROR : 0
FifoFillDrainTest: samples=130 edges_checked=129 data_checks=64 ... mismatches=0   UVM_ERROR : 0
```

The test that found the bug now passes, and the earlier test still passes (no regression). **Status: fixed.**

---

## Bug 2: `rd_err` is combinational, not a registered pulse

**Found by:** `FifoReadEmptyTest` (TS-05), seed 1: reset, 1 read, 2 idle, 3 writes, 6 reads (3 accepted + 3 rejected), 2 idle. `FifoWriteFullTest` (TS-06) **passes** with the same scoreboard.

**`make summary`:**
```
readempty.log FifoReadEmptyTest   1  15  3  3  3  0  4  4  0 FAIL
writefull.log FifoWriteFullTest   1 138 64 64 64  0  0  0  0 PASS
```

**Edge table** (`make table LOG=readempty.log`):
```
 c000      30 │ RESET   1  0  0    cc   0   0 │      00 │   00   00    0     1    0    1 │ ✗ rd_err: exp 0 got 1
 c001      50 │ READ    0  0  1    92   0   1 │      00 │   00   00    0     1    0    0 │ ✗ rd_err: exp 1 got 0
 ...
 c009     210 │ READ    0  0  1    18   3   4 │      26 │   03   03    0     1    0    1 │ ✗ rd_err: exp 0 got 1
 c010     230 │ READ    0  0  1    7e   3   5 │      00 │   03   03    0     1    0    1 │ ✓
 c011     250 │ READ    0  0  1    69   3   6 │      00 │   03   03    0     1    0    1 │ ✓
 c012     270 │ READ    0  0  1    7d   3   7 │      00 │   03   03    0     1    0    0 │ ✗ rd_err: exp 1 got 0
```

**Reading it.** The rejected reads are rows c001 (read right after reset) and c010–c012 (after the FIFO was drained by the legal read on c009, which consumes `26`).

| Row | Rejected read? | DUT `rd_err` after the edge | Expected |
|---|---|---|---|
| c000 (reset) | – | **1** | 0 |
| c001 | yes | **0** | 1 |
| c009 (legal read) | – | **1** | 0 |
| c010, c011 | yes | 1 | 1 |
| c012 | yes | **0** | 1 |

The DUT's pattern is the expected one **shifted one edge earlier**, and that single shift explains all 4 mismatches (c010/c011 "pass" only because the next request's early pulse lands on them).

**Testbench or RTL?**
- The scoreboard predicts both flags with the same rule (`expWrErr = prev.wr_en && !wrAcc`, `expRdErr = prev.rd_en && !rdAcc`), and the monitor samples both at the same moment. TS-06 places 4 rejected writes' `wr_err` pulses on exactly the right rows, so the model's timing is correct.
- SPEC §7: the pulse goes high **after** the edge where the request was rejected. SPEC §3: `rd_err = 0` after reset. The DUT shows `rd_err = 1` straight after a reset edge, while the read request was merely waiting on the bus.

**Verdict: RTL bug.** `rd_err` follows the read request combinationally (high while a read is requested on an empty FIFO, i.e. *before* the edge), instead of being a registered pulse set by the rejecting edge. Violates §7 (and §3 after reset).

**Waveform confirmation (to do):** in the TS-05 VCD, a registered output (like `wr_err`) only changes at rising edges, while `rd_err` changes at the same timestamps as `rd_en`.

**Root cause (from the designer's side):** `wr_err` was a flip-flop in the error-flag `always` block, but `rd_err` was a plain continuous assignment of the reject condition: `assign rd_err = rd_rej;`. The reject condition is combinational (`rd_en` and FIFO empty), so `rd_err` followed the request **during** the cycle before the edge, instead of being captured **by** the edge. The asymmetry between two flags that the spec defines identically (§7) is the tell-tale sign.

**Fix** (`rtl/sync_fifo.v`): register `rd_err` exactly like `wr_err`.

```diff
-    output                  rd_err
+    output reg              rd_err
 ...
     always @(posedge clk) begin
-        if (rst)
+        if (rst) begin
             wr_err <= 1'b0;
-        else
+            rd_err <= 1'b0;
+        end
+        else begin
             wr_err <= wr_rej;
+            rd_err <= rd_rej;
+        end
     end
-
-    assign rd_err = rd_rej;
```

**Regression** (all four tests, seed 1):
```
filldrain.log FifoFillDrainTest   1 129 64 64 64 0 0 0 0 PASS
readempty.log FifoReadEmptyTest   1  15  3  3  3 0 0 0 0 PASS
run.log       FifoTest            1  14  4  4  4 0 0 0 0 PASS
writefull.log FifoWriteFullTest   1 138 64 64 64 0 0 0 0 PASS
4/4 runs passed
```
TS-05 now shows `rd_err = 1` on exactly the rejected-read rows (c001, c010–c012) and 0 after reset. **Status: fixed.**


---

## Bug 3: at empty, a read on the same edge as a write is accepted (write-through)

**Found by:** `FifoWriteReadSimTest` (TS-08), seed 1: reset; (a) read+write at empty; idle; 2 writes; (b) 4 read+writes at level 3; 3 reads; 64 writes; (c) 4 read+writes at full; 64 reads.

**Result:** `edges_checked=146 data_checks=75 ... mismatches=22`, errors only between 60 and 260 ns. By kind: 10 × `rd_ptr`, 7 × `rd_data`, 3 × `empty`, 2 × `rd_err`.

**First error** (`make table ARGS=--first-error`):
```
 c000      30 │ RESET   1  0  0    cc   0   0 │      00 │   00   00    0     1    0    0 │ ✓
 c001      50 │ R+W     0  1  1    92   1   1 │      00 │   01   01    0     1    0    0 │ ✗ rd_ptr: exp 0 got 1 (+2)
               └─ ERROR @60 ns [SCB] rd_ptr mismatch: expected=0 got=1
               └─ ERROR @60 ns [SCB] empty mismatch: expected=0 got=1
               └─ ERROR @60 ns [SCB] rd_err mismatch: expected=1 got=0
 c002      70 │ IDLE    0  0  0    23   1   1 │      00 │   01   01    0     1    0    0 │ ✗ rd_ptr: exp 0 got 1 (+1)
 c003      90 │ WRITE   0  1  0    68   2   1 │      00 │   02   01    0     0    0    0 │ ✗ rd_ptr: exp 0 got 1
```

**Reading it.** At empty, with `wr_en = rd_en = 1`:

| After the c001 edge | Expected (§6 empty row) | DUT |
|---|---|---|
| `wptr` | 1 (write accepted) | 1 |
| `rptr` | 0 (read **rejected**) | **1** |
| `empty` | 0 (level 1) | **1** (level 0) |
| `rerr` | 1 | **0** |

`rptr` advancing, no `rerr` and the level staying 0 are the signature of an **accepted** read. The DUT stored `0x92` and consumed it on the same edge, so it never appeared on `rd_data`: a **write-through**, forbidden by §5. Byte `0x92` is lost.

**Why 22 errors, and why they stop.** One byte offset: the DUT's level is one lower than the model's from c001 on. Every byte read in phase (b) is one position ahead of the model (7 × `rd_data`), and `rd_ptr` is one ahead (10 ×). `empty` disagrees until both levels are non-zero. During the drain, the DUT runs empty **one read early** and rejects a read that the model accepts (the second `rd_err` mismatch). That extra rejection cancels the extra acceptance at c001: pointers and levels realign, and phase (c) at full and the final drain pass.

**Testbench or RTL?** The model follows §6 row by row (`rdAcc = rd_en && count > 0`, independent of `wr_en`), and its (c) behaviour at full, also from §6, passes. The DUT violates §5 (no write-through), §6 (empty row: read rejected) and §7 (an `rd_err` pulse for the rejected read). **Verdict: RTL bug.**

**Root cause (from the designer's side):** the read-acceptance condition mirrored the write-acceptance one:

```verilog
wire wr_acc = wr_en && (!full  || rd_en);   // correct: at full, a read frees a slot (§6)
wire rd_acc = rd_en && (!empty || wr_en);   // WRONG: at empty, a write does NOT make data readable (§5)
```

Writes and reads aren't symmetric in this spec. A simultaneous **read** really does free a slot for a write at full, but a simultaneous **write** doesn't produce readable data at empty (no write-through). Copying the write rule's shape into the read rule created the bug.

**Fix:**
```diff
-    wire rd_acc = rd_en && (!empty || wr_en);
+    wire rd_acc = rd_en && !empty;
```

**Regression** (`make regress`, seed 1): 5/5 PASS, `FifoWriteReadSimTest` 146 edges, 75 data checks, 0 mismatches. Row c001 now shows `wptr=01 rptr=00 empty=0 rerr=1`, and `0x92` appears on `rd_data` from the next row. **Status: fixed.**

---

## Bug 4: `wr_ptr` advances during reset when `wr_en` is high

**Found by:** `FifoResetTest` (TS-10), seed 1. Cases (a) reset while partly full and (b) reset while full **pass**; case (c), reset held for 3 cycles **with `wr_en = 1`**, fails.

**Result:** `edges_checked=125 ... mismatches=23`: 20 × `wr_ptr`, 3 × `rd_data`.

**First error** (`make table ARGS=--first-error`):
```
 c096    1950 │ WRITE   0  1  0    0b   8   3 │      d8 │   08   03    0     0    0    0 │ ✓
 c097    1970 │ RESET   1  1  0    4d   0   0 │      d8 │   09   00    0     1    0    0 │ ✗ wr_ptr: exp 0 got 9
 c098    1990 │ RESET   1  1  0    9f   0   0 │      af │   10   00    0     1    0    0 │ ✗ wr_ptr: exp 0 got 10
 c099    2010 │ RESET   1  1  0    df   0   0 │      af │   11   00    0     1    0    0 │ ✗ wr_ptr: exp 0 got 11
 c100    2030 │ READ    0  0  1    7e   0   1 │      af │   11   00    0     1    0    1 │ ✗ wr_ptr: exp 0 got 11
```

**Reading it.** On every reset row with `wr_en = 1`, `wptr` **advances** (8 → 9 → 10 → 11), as if the write were accepted, instead of going to 0. On the same rows, `rptr` → 0, `empty` → 1 and the error flags stay 0, all as §3 requires. Only the write pointer lets a write request override reset. Row c100's read is correctly rejected (the FIFO reports empty), but its write pointer has moved on: inconsistent internal state.

**Consequence: stale data returned.** The final `doWrites(3); doReads(3)` store the new bytes at slots 11+, while the reads come from slots 0–2, which still hold pre-reset data:
```
 c120    2430 │ READ ... │  27 │ ... │ ✗ rd_data: exp 62 got 27
 c121    2450 │ READ ... │  6a │ ... │ ✗ rd_data: exp aa got 6a
 c122    2470 │ READ ... │  b9 │ ... │ ✗ rd_data: exp 3d got b9
```
3 stale bytes come back and 3 new ones are lost: the most serious violation of §3 ("logically empty"; old data must never be read).

**Testbench or RTL?** The model follows §3 literally (on a reset edge: clear the queue and pointers, ignore `wr_en`/`rd_en`, no error pulses), and the same model passes (a), (b) and every other test. **Verdict: RTL bug**, violating §3 (`wr_ptr = 0` after reset; `wr_en` ignored while `rst = 1`; pre-reset contents never returned).

The user's diagnosis: "on reset, along with `wr_en`, `wr_ptr` still increments and doesn't go to 0". Correct. The table adds that it's write-side only, and the `rd_data` errors show the user-visible damage.

**Root cause (from the designer's side):** the write block used two **independent** `if` statements:

```verilog
always @(posedge clk) begin
    if (rst)
        wr_ptr <= 0;
    if (wr_acc) begin              // evaluated even when rst = 1
        mem[wr_ptr] <= wr_data;
        wr_ptr      <= wr_ptr + 1'b1;
    end
end
```

In a Verilog `always` block, when two non-blocking assignments to the same register execute in one edge, **the last one wins**. With `rst = 1` and `wr_en = 1`, both run, and `wr_ptr <= wr_ptr + 1` overrides `wr_ptr <= 0`. The memory write also goes through during reset. The read pointer's block uses `if (rst) … else if (rd_acc) …`, so it was correct: the asymmetry is the tell-tale sign, as with bug 2.

**Fix:** give reset priority with `else if`:

```diff
         if (rst)
             wr_ptr <= {ADDR_W{1'b0}};
-
-        if (wr_acc) begin
+        else if (wr_acc) begin
             mem[wr_ptr] <= wr_data;
             wr_ptr      <= wr_ptr + 1'b1;
         end
```

**Regression** (`make regress`, seed 1): 6/6 PASS. `FifoResetTest`: 125 edges, 9 data checks, 0 mismatches. During reset with `wr_en=1`, `wptr` now stays 0; the final reads return the new bytes `62 aa 3d`. **Status: fixed.**

---

## Student questions

Questions raised while debugging, with the answers.

1. **"The last write was at c064, so the `0x90` write is the 65th, which isn't possible?"** No. c000 is the reset cycle, and the SEQ lines number the writes `write cycle 0` (c001) … `write cycle 63` (c064): exactly **64** writes (`grep -c "SEQ\] write cycle"` gives 64). Cycle numbers aren't write numbers. The `0x90` write is the 64th, and it must be accepted, because 64 is the capacity.
2. **"The write was rejected, but `wr_ptr` didn't shift to 0. Is that the bug?"** No. A rejected write must **not** move `wr_ptr` (§4). The model expected `wr_ptr=0` because it expected the 64th write to be **accepted** (into slot 63, then a wrap to 0). The bug is that the DUT considers itself full one entry early (§8). The rejection and the frozen pointer are consequences.
3. **"Is SPEC §8 right?"** Yes. §1, §2, §4 and §8 all define full as 64 entries stored. The doubt comes from **index vs count**: slots are numbered 0–63, but the count runs 0–64, so `wr_ptr=63` with no reads means 63 entries. When the spec is consistent with itself, it wins; you don't change it to match the DUT.
4. **"`wr_ptr` is 6 bits and is already 63 at the 63rd write. How can it reach 64 for the 64th? Shouldn't the rule be `wr_ptr=63` → full?"** No. `wr_ptr` is the **next** slot to write (§2), so `wr_ptr=63` after 63 writes means slot 63 is still free. The 64th write goes into slot 63, then `wr_ptr` wraps to 0 (§4). It never needs to be 64. A rule based on `wr_ptr` can't work, because `wr_ptr = rd_ptr = 0` both before the first write (empty) and after the 64th (full). §2's note says so explicitly: the RTL must track the 0-vs-64 distinction internally (a counter or an extra pointer bit). That's exactly the kind of internal detail a black-box test can't see, but whose mistakes show up at the ports, as here: full at 63, and the 64th write rejected.
5. **"The rd_err errors look like three problems: a testbench error at reset, an RTL issue on the first read, then an off-by-one."** One problem. The DUT's `rd_err` is the correct pattern shifted one edge early, which gives an "extra" pulse on one row and a "missing" one on the next. Lining up DUT vs expected for every error row shows the shift. Comparing with `wr_err` (same model rule, same sampling, passing in TS-06) rules out the scoreboard.
6. **"Is it a monitor sampling-time issue? The monitor samples the combinational pulse and mistakes it for the previous edge's output?"** No. The monitor reports exactly what the port shows. At 40 ns the DUT really shows `rd_err = 1` before any edge has rejected a read. A **registered** output is stable for the whole cycle between edges, so any mid-cycle sample point reads it correctly (that's why `wr_err` passes). Only a signal that changes *between* edges can look early, and that's precisely the §7 violation. Moving the sample point would hide the errors without fixing the DUT: changing the checker to match the DUT.
7. **"Even for the rejected read, `rd_ptr` increments."** More precisely, the DUT **didn't** reject it: `rd_ptr` advancing, `rd_err` staying 0 and the level staying 0 are what an *accepted* read looks like. The bug is the acceptance decision (the read accepted at empty because a write happened on the same edge), not a pointer update on a rejected read.
8. **"`empty` went back to 0 at c003 because `rd_ptr == wr_ptr` is no longer true."** After the bug-1 fix, `empty` comes from the entry **count**, not from comparing pointers. At c003 the DUT's level is 1 and the model's is 2: both non-zero, so `empty` agrees, but the levels still differ by one. That's why the `rd_ptr` mismatch continues. A mismatch disappearing doesn't mean the DUT has recovered.
9. **"Even on reset, `wr_ptr` is not resetting to 0."** Correct, and slightly more: `wr_ptr` **advanced** on each reset edge (8 → 9 → 10 → 11), as if the write were accepted, while `rd_ptr`, `empty` and the error flags did reset. Comparing the write side with the read side, as with the two error flags in bug 2, localises the bug. And the user-visible damage is in the later `rd_data` errors: stale pre-reset bytes returned.
