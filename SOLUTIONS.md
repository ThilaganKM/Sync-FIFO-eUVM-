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

## Student questions

Questions raised while debugging, with the answers.

1. **"The last write was at c064, so the `0x90` write is the 65th, which isn't possible?"** No. c000 is the reset cycle, and the SEQ lines number the writes `write cycle 0` (c001) … `write cycle 63` (c064): exactly **64** writes (`grep -c "SEQ\] write cycle"` gives 64). Cycle numbers aren't write numbers. The `0x90` write is the 64th, and it must be accepted, because 64 is the capacity.
2. **"The write was rejected, but `wr_ptr` didn't shift to 0. Is that the bug?"** No. A rejected write must **not** move `wr_ptr` (§4). The model expected `wr_ptr=0` because it expected the 64th write to be **accepted** (into slot 63, then a wrap to 0). The bug is that the DUT considers itself full one entry early (§8). The rejection and the frozen pointer are consequences.
3. **"Is SPEC §8 right?"** Yes. §1, §2, §4 and §8 all define full as 64 entries stored. The doubt comes from **index vs count**: slots are numbered 0–63, but the count runs 0–64, so `wr_ptr=63` with no reads means 63 entries. When the spec is consistent with itself, it wins; you don't change it to match the DUT.
4. **"`wr_ptr` is 6 bits and is already 63 at the 63rd write. How can it reach 64 for the 64th? Shouldn't the rule be `wr_ptr=63` → full?"** No. `wr_ptr` is the **next** slot to write (§2), so `wr_ptr=63` after 63 writes means slot 63 is still free. The 64th write goes into slot 63, then `wr_ptr` wraps to 0 (§4). It never needs to be 64. A rule based on `wr_ptr` can't work, because `wr_ptr = rd_ptr = 0` both before the first write (empty) and after the 64th (full). §2's note says so explicitly: the RTL must track the 0-vs-64 distinction internally (a counter or an extra pointer bit). That's exactly the kind of internal detail a black-box test can't see, but whose mistakes show up at the ports, as here: full at 63, and the 64th write rejected.
5. **"The rd_err errors look like three problems: a testbench error at reset, an RTL issue on the first read, then an off-by-one."** One problem. The DUT's `rd_err` is the correct pattern shifted one edge early, which gives an "extra" pulse on one row and a "missing" one on the next. Lining up DUT vs expected for every error row shows the shift. Comparing with `wr_err` (same model rule, same sampling, passing in TS-06) rules out the scoreboard.
6. **"Is it a monitor sampling-time issue? The monitor samples the combinational pulse and mistakes it for the previous edge's output?"** No. The monitor reports exactly what the port shows. At 40 ns the DUT really shows `rd_err = 1` before any edge has rejected a read. A **registered** output is stable for the whole cycle between edges, so any mid-cycle sample point reads it correctly (that's why `wr_err` passes). Only a signal that changes *between* edges can look early, and that's precisely the §7 violation. Moving the sample point would hide the errors without fixing the DUT: changing the checker to match the DUT.
