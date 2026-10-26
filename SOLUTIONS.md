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

## Student questions

Questions raised while debugging, with the answers.

1. **"The last write was at c064, so the `0x90` write is the 65th, which isn't possible?"** No. c000 is the reset cycle, and the SEQ lines number the writes `write cycle 0` (c001) … `write cycle 63` (c064): exactly **64** writes (`grep -c "SEQ\] write cycle"` gives 64). Cycle numbers aren't write numbers. The `0x90` write is the 64th, and it must be accepted, because 64 is the capacity.
2. **"The write was rejected, but `wr_ptr` didn't shift to 0. Is that the bug?"** No. A rejected write must **not** move `wr_ptr` (§4). The model expected `wr_ptr=0` because it expected the 64th write to be **accepted** (into slot 63, then a wrap to 0). The bug is that the DUT considers itself full one entry early (§8). The rejection and the frozen pointer are consequences.
3. **"Is SPEC §8 right?"** Yes. §1, §2, §4 and §8 all define full as 64 entries stored. The doubt comes from **index vs count**: slots are numbered 0–63, but the count runs 0–64, so `wr_ptr=63` with no reads means 63 entries. When the spec is consistent with itself, it wins; you don't change it to match the DUT.
4. **"`wr_ptr` is 6 bits and is already 63 at the 63rd write. How can it reach 64 for the 64th? Shouldn't the rule be `wr_ptr=63` → full?"** No. `wr_ptr` is the **next** slot to write (§2), so `wr_ptr=63` after 63 writes means slot 63 is still free. The 64th write goes into slot 63, then `wr_ptr` wraps to 0 (§4). It never needs to be 64. A rule based on `wr_ptr` can't work, because `wr_ptr = rd_ptr = 0` both before the first write (empty) and after the 64th (full). §2's note says so explicitly: the RTL must track the 0-vs-64 distinction internally (a counter or an extra pointer bit). That's exactly the kind of internal detail a black-box test can't see, but whose mistakes show up at the ports, as here: full at 63, and the 64th write rejected.
