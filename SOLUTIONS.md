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

---

## Student questions

Questions raised while debugging, with the answers.

1. **"The last write was at c064, so the `0x90` write is the 65th, which isn't possible?"** No. c000 is the reset cycle, and the SEQ lines number the writes `write cycle 0` (c001) … `write cycle 63` (c064): exactly **64** writes (`grep -c "SEQ\] write cycle"` gives 64). Cycle numbers aren't write numbers. The `0x90` write is the 64th, and it must be accepted, because 64 is the capacity.
2. **"The write was rejected, but `wr_ptr` didn't shift to 0. Is that the bug?"** No. A rejected write must **not** move `wr_ptr` (§4). The model expected `wr_ptr=0` because it expected the 64th write to be **accepted** (into slot 63, then a wrap to 0). The bug is that the DUT considers itself full one entry early (§8). The rejection and the frozen pointer are consequences.
3. **"Is SPEC §8 right?"** Yes. §1, §2, §4 and §8 all define full as 64 entries stored. The doubt comes from **index vs count**: slots are numbered 0–63, but the count runs 0–64, so `wr_ptr=63` with no reads means 63 entries. When the spec is consistent with itself, it wins; you don't change it to match the DUT.
