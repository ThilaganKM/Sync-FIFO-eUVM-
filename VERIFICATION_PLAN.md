# Synchronous FIFO: Verification Plan

**Version:** 1.0
**Author:** Thilagan KM
**DUT:** `rtl/sync_fifo.v` (treated as a black box: ports only)
**Reference:** `SPEC.md` v1.0. Every check below traces back to a clause in it.

---

## 1. Goal

Show that the DUT behaves as `SPEC.md` describes, on every clock edge, for every scenario in §9 of the spec.
A test **passes** only if the scoreboard reports zero mismatches **and** the number of checks performed matches the number of cycles and transactions driven (see §7, *Completion criteria*).

---

## 2. Testbench architecture (summary)

| Component | Role |
|---|---|
| **Item** | One clock cycle of stimulus: `rst`, `wr_en`, `rd_en`, `wr_data` (random, constrained per sequence). The monitor fills in the observed outputs: `rd_data`, `full`, `empty`, `wr_ptr`, `rd_ptr`, `wr_err`, `rd_err`. |
| **Driver** | Drives one item per clock cycle, right after each **rising** edge. Applies an initial reset before the first item. |
| **Monitor** | Takes **one snapshot per cycle, at the falling edge** (mid-cycle, when everything is stable): the inputs that the next rising edge will act on, `rd_data` (the value a read on that edge consumes), and the registered outputs (the result of the previous rising edge). Sends the snapshot to the scoreboard. |
| **Scoreboard** | A cycle-accurate **reference model**: a queue (`ubyte[]`) for the contents, plus model `wr_ptr` / `rd_ptr`, predicted flags and predicted error pulses. Steps one edge at a time and compares predictions with the DUT. |
| **Tests** | One test class per scenario (§4), selected with `+UVM_TESTNAME=...`. A shared base test builds the environment. |

**Sampling rule (SPEC §5, §7, §8):** the value consumed by a read on edge N is `rd_data` **just before** edge N.
Everything edge N produces (`full`, `empty`, pointers, `wr_err`, `rd_err`) is visible only **after** edge N, so it's compared against the model's prediction in the **next** snapshot.

**Timing scheme (resolved, verified with a probe run):** the clock generator in `sync_fifo_tb.d` evaluates the DUT **before** toggling the testbench clock. So:

| Event | What happens | Who acts |
|---|---|---|
| Rising edge N | The DUT updates its registers using the inputs held since the last rising edge. | **Driver** wakes and drives the inputs for edge N+1. |
| Falling edge (between N and N+1) | No state change. Everything is stable. | **Monitor** samples: inputs for edge N+1, `rd_data` before edge N+1, outputs after edge N. |

The driver and monitor work on **opposite edges**, so they never race each other.

---

## 3. Checks (always on, in every test)

These run in the scoreboard on every edge. They're independent of the stimulus, so every test exercises them.

| ID | Check | SPEC |
|---|---|---|
| **CHK-01** | **Data integrity.** On every accepted read, `rd_data` (pre-edge) equals the front of the model queue, which is then popped. | §5, §9.1 |
| **CHK-02** | **No phantom data.** Rejected writes are never pushed into the model, so if their data ever reaches `rd_data`, CHK-01 fails. | §4, §9.2 |
| **CHK-03** | **Status flags.** After every edge, `empty == (count == 0)` and `full == (count == 64)`. `full && empty` is never true. | §8, §9.3 |
| **CHK-04** | **Pointers.** After every edge, `wr_ptr` / `rd_ptr` equal the model pointers. These advance only on accepted writes and reads, and wrap 63 → 0. | §2, §4, §5, §9.4 |
| **CHK-05** | **Error pulses.** After every edge, `wr_err` / `rd_err` equal the predicted value: 1 for exactly the cycle after a rejected request, and 0 otherwise. | §7, §9.5 |
| **CHK-06** | **Reject has no side effects.** A rejected request leaves the count, pointers and contents unchanged. This is covered by CHK-03/04 and CHK-01 on later reads. | §7 |
| **CHK-07** | **Reset state.** After a reset edge: pointers = 0, `empty` = 1, `full` = 0, `wr_err` = `rd_err` = 0, and the model queue is cleared. `wr_en` / `rd_en` during reset have no effect. | §3, §9.6 |
| **RULE** | `rd_data` is **never** compared while `empty == 1` (undefined, SPEC §3, §5). | §3, §5 |

**Model acceptance rules** (decided from the model state **before** the edge):

| Model state | `wr_en` | `rd_en` | Write | Read | Count |
|---|---|---|---|---|---|
| any, `rst = 1` | x | x | ignored | ignored | → 0 |
| empty | 1 | 0 | accept | – | +1 |
| empty | 0 | 1 | – | **reject** (`rd_err`) | 0 |
| empty | 1 | 1 | accept | **reject** (`rd_err`) | +1 |
| 1–63 | 1 | 1 | accept | accept | unchanged |
| full | 1 | 0 | **reject** (`wr_err`) | – | 64 |
| full | 1 | 1 | accept | accept | 64 |

---

## 4. Test scenarios

| ID | Scenario | Stimulus | Expected result | SPEC |
|---|---|---|---|---|
| **TS-01** | **Power-on reset** | Hold `rst` for several cycles with idle inputs, then release. | Reset state as in CHK-07. FIFO usable afterwards. | §3 |
| **TS-02** | **Fill and drain** | 64 back-to-back writes with distinct data, then 64 back-to-back reads. | `full` rises exactly after the 64th write. All 64 values come back in order. `empty` rises exactly after the 64th read. No error pulses. | §4, §5, §8 |
| **TS-03** | **Uniform interleave** | Repeat *write k, read k* for k = 1, 2, 3, … | Every value is read back in order. The FIFO returns to empty after each burst. | §4, §5 |
| **TS-04** | **Non-uniform interleave** | Bursts of *write a, read b* with a ≠ b, e.g. (2,1), (3,1), (3,2), (5,3), (5,2). Two variants: **a > b** (level climbs until full) and **a < b** (level falls until empty). | Data order is kept across bursts. The level reaches the full and empty boundaries, and extra requests there are rejected as in TS-05/06. | §4–§8 |
| **TS-05** | **Read when empty (underflow)** | `rd_en` with an empty FIFO: (a) right after reset, (b) after a drain, (c) a single rejected read, (d) several rejected reads on consecutive edges. | The read is rejected. `rd_err` is high for exactly one cycle per rejected read (consecutive cycles in (d)). Pointers and flags are unchanged. | §5, §7 |
| **TS-06** | **Write when full (overflow)** | Fill to 64, then `wr_en` with distinct "poison" data: single and consecutive attempts. Then drain. | The write is rejected and `wr_err` pulses as in TS-05. Pointers are unchanged. On drain, the 64 original values come out and the poison data never appears. | §4, §7, §9.2 |
| **TS-07** | **Pointer wrap-around** | More than 64 writes and reads in total, so both pointers cross 63 → 0 several times: (a) fill/drain twice, (b) keep the level around half for 200+ cycles. | Pointers wrap 63 → 0. Data integrity holds across the wrap. | §4, §9.4 |
| **TS-08** | **Simultaneous read + write (same edge)** | `wr_en = rd_en = 1` on one edge, at each level: (a) **empty**, (b) **mid** (1–63), (c) **full**. | (a) Write accepted, read rejected, `rd_err` pulses, count +1. (b) Both accepted, count unchanged. (c) Both accepted, stays full, no `wr_err`. | §6 |
| **TS-09** | **Read-after-write latency (consecutive edges)** | Write X on edge N into an empty FIFO, read on edge N+1. Also the reverse: read the last entry on edge N, write on N+1. | X is visible on `rd_data` after edge N and is read correctly on N+1. Flags move empty → not-empty → empty with no glitches. | §5 (no write-through) |
| **TS-10** | **Reset mid-traffic** | Assert `rst`: (a) with the FIFO partly full, (b) when full, (c) in the middle of a burst while `wr_en` and/or `rd_en` are held high **during** reset. Then write and read new data. | Reset state as in CHK-07, whatever the inputs. Requests during reset do nothing. After reset, only new data is ever read, never pre-reset data. | §3, §9.6 |
| **TS-11** | **Constrained random** | 5000+ cycles, with weighted `wr_en` / `rd_en` (e.g. 70/30 fill-biased, 30/70 drain-biased, 50/50), random data and rare random resets. Run with several seeds. | All checks pass. Coverage (§5) is closed. | all |

> Pointer advance only on valid transactions is not a separate stimulus: it's the always-on check **CHK-04**, exercised by every test above.

---

## 5. Functional coverage

Implemented in `testbench/fifo_coverage.d` (`FifoCoverage`), a second subscriber on the monitor's analysis port. It pairs consecutive samples like the scoreboard and samples **one esdl covergroup per edge**. Merged across all passing logs with `make coverage`.

| Coverpoint | Bins | Why | # |
|---|---|---|---|
| `lvlop` (level × op cross) | level **before** the edge {empty, one, 2–62, 63, full} × op {idle, wr, rd, rw}, non-reset edges | Every SPEC §6 row and every reject case, at every boundary | 20 |
| `werrTr`, `rerrTr` | `*_err_rise` (0→1), `*_err_held` (1→1, consecutive rejects) | §7 single and consecutive pulses | 4 |
| `wrWrap`, `rdWrap` | `wr_ptr_63_to_0`, `rd_ptr_63_to_0` on non-reset edges | §4 wrap-around of both pointers | 2 |
| `rstCase` | level before reset {empty, 1–63, full} × requests during reset {none, wr, rd, both} | §3 reset from every level, with and without requests | 12 |
| **Total** | | | **38** |

The cross is a coverpoint on a combined value (`levelBin * 4 + op`) because esdl's per-bin report crashes on `cross` (see FAQ). The level comes from the DUT's outputs (`full` → 64, else `(wr_ptr − rd_ptr) mod 64`), which is valid because the scoreboard independently checks those outputs; coverage only counts passing runs.

**Code coverage:** Verilator `--coverage` (line and toggle) on the DUT, as a secondary metric (not yet enabled).

---

## 6. Traceability: SPEC §9 → checks → tests

| SPEC §9 item | Checks | Tests |
|---|---|---|
| 1. Data integrity | CHK-01 | TS-02, 03, 04, 07, 09, 11 |
| 2. No data from rejected writes | CHK-02, CHK-01 | TS-06, 11 |
| 3. `full` / `empty` | CHK-03 | TS-02, 04, 05, 06, 08, 11 |
| 4. Pointers advance and wrap | CHK-04 | all; TS-07 for wrap |
| 5. Error pulses | CHK-05 | TS-05, 06, 08, 11 |
| 6. Reset | CHK-07 | TS-01, 10, 11 |
| 7. Simultaneous read + write | CHK-01–05 | TS-08, 11 |

---

## 7. Completion criteria

1. Every test TS-01 … TS-11 passes with **0 scoreboard mismatches** (`UVM_ERROR` = 0).
2. **Check counts are reported and sane:** the number of snapshots checked equals the number of cycles driven, and the number of data comparisons equals the number of accepted reads. *(Lesson from the comparator project: 0 errors with 0 checks proves nothing.)*
3. At end of test, the model queue length is reported and matches the DUT's final level.
4. Functional coverage of §5 is 100% across the regression.
5. TS-11 passes on at least 10 different seeds.
6. Every failure found is classified as an **RTL bug** or a **testbench bug**, with log and waveform evidence.

---

## 8. Build order

1. Makefile, `fifo_intf.d`, top `sync_fifo_tb.d` ✅ (timing scheme in §2 verified). Then `Item.d`, driver and monitor; run TS-01 and inspect the waveform.
2. Scoreboard with CHK-01 … CHK-07.
3. Directed tests TS-02 … TS-10.
4. Constrained random TS-11.
5. Coverage (§5) and closure.
