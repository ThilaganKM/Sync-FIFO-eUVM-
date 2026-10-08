# Synchronous FIFO: Design Specification

**Version:** 1.0
**Author:** Thilagan KM

This document is the reference for both the RTL and the testbench.
The testbench checks the RTL **against this spec**. If the two disagree, the spec wins, and the RTL has a bug.

---

## 1. Overview

A single-clock, first-in first-out buffer.

| Parameter | Value |
|---|---|
| Data width | 8 bits |
| Depth | 64 entries |
| Clocks | 1 (`clk`). All state changes happen on its rising edge. |
| Reset | synchronous, active-high (`rst`) |
| Read style | combinational, show-ahead: `rd_data` continuously shows the oldest entry (Xilinx calls this mode *FWFT*, First-Word Fall-Through; Intel calls it *show-ahead*) |
| Write style | synchronous: data is stored on the rising edge of `clk` |

---

## 2. Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. All state changes happen on the rising edge. |
| `rst` | in | 1 | Synchronous reset, active-high. |
| `wr_en` | in | 1 | Write request. |
| `wr_data` | in | 8 | Data to write. |
| `rd_en` | in | 1 | Read request. |
| `rd_data` | out | 8 | Oldest entry in the FIFO (combinational, see §5). |
| `wr_ptr` | out | 6 | Index of the slot the **next** write goes to (0–63). |
| `rd_ptr` | out | 6 | Index of the **oldest** entry, the one shown on `rd_data` (0–63). |
| `full` | out | 1 | High when the FIFO holds 64 entries. |
| `empty` | out | 1 | High when the FIFO holds 0 entries. |
| `wr_err` | out | 1 | Pulses high when a write was rejected (see §7). |
| `rd_err` | out | 1 | Pulses high when a read was rejected (see §7). |

> `wr_ptr` and `rd_ptr` are 6 bits wide, enough to address 64 slots.
> They are equal both when the FIFO is empty and when it is full. `full` and `empty` tell the two apart.
> How the RTL tracks this internally (a counter, or an extra pointer bit) is an implementation choice and not part of the spec.

---

## 3. Reset

On a rising edge of `clk` with `rst = 1`:

| Signal | Value after reset |
|---|---|
| `wr_ptr`, `rd_ptr` | 0 |
| `empty` | 1 |
| `full` | 0 |
| `wr_err`, `rd_err` | 0 |
| FIFO contents | **logically empty.** The storage array is **not** cleared (see below). |

While `rst = 1`, `wr_en` and `rd_en` are ignored: no write, no read, no error.

**Why the storage is not cleared.** Reset clears the *pointers and flags* (where we are), not the 64 × 8 *storage array* (the data).
With `wr_ptr = rd_ptr = 0` and `empty = 1`, the old bytes can never be read: reads are rejected while empty, and every slot is overwritten by a new write before a read can reach it.
This is standard practice: SRAM has no reset, and adding reset to 512 storage flip-flops costs area and wiring for no benefit.
**Testbench note:** after reset, `rd_data` may show leftover, `0` or `X` values. Never check `rd_data` while `empty = 1`.

---

## 4. Write

On a rising edge of `clk` with `rst = 0` and `wr_en = 1`:

- **If the FIFO is not full** (before the edge), or a read happens on the same edge (§6):
  `wr_data` is stored at slot `wr_ptr`, and `wr_ptr` advances by 1.
- **If the FIFO is full** and no read happens on the same edge:
  the write is **rejected**. Nothing is stored, `wr_ptr` doesn't change, and `wr_err` pulses (§7).

**Wrap-around:** pointers are circular. After slot 63, a pointer goes back to slot 0.
A full FIFO **never overwrites** unread data. Writes to a full FIFO are rejected.

---

## 5. Read

`rd_data` is **combinational**: at all times, it shows the entry at slot `rd_ptr`, which is the oldest unread entry.
- When `empty = 1`, `rd_data` is **undefined**, and the testbench must not check it.
- Show-ahead behaviour: data is visible on `rd_data` **before** `rd_en` is asserted.
  Asserting `rd_en` **consumes** the entry.

On a rising edge of `clk` with `rst = 0` and `rd_en = 1`:

- **If the FIFO is not empty** (before the edge):
  the entry on `rd_data` just before the edge is consumed, and `rd_ptr` advances by 1.
  **The value read is the value of `rd_data` just before that edge.**
- **If the FIFO is empty:**
  the read is **rejected**. `rd_ptr` doesn't change, and `rd_err` pulses (§7).

**No write-through (bypass):** a value written on edge N is not visible on `rd_data` until **after** edge N.
So it can't be read on that same edge N.
This avoids a combinational path from `wr_data` to `rd_data`. It matches industry FWFT FIFOs, where a word written into an empty FIFO appears on the output only after the write edge, and a read request while empty is an underflow error.

---

## 6. Simultaneous read and write (`wr_en = 1` and `rd_en = 1` on the same edge)

| FIFO state before the edge | Write | Read | Entry count |
|---|---|---|---|
| empty | ✅ accepted | ❌ rejected, `rd_err` pulses (no write-through, §5) | +1 |
| neither empty nor full | ✅ accepted | ✅ accepted | unchanged |
| full | ✅ accepted, since the read frees a slot on the same edge | ✅ accepted | unchanged (stays full) |

---

## 7. Error flags

`wr_err` and `rd_err` are **registered, one-cycle pulses**:
- `wr_err` goes high **after** the edge where a write was rejected, and stays high for exactly **one cycle**.
- `rd_err` goes high **after** the edge where a read was rejected, and stays high for exactly **one cycle**.
- If rejected requests happen on consecutive edges, the flag stays high for those consecutive cycles.
- A rejected request doesn't change any other state.

---

## 8. Status flags

`full` and `empty` reflect the FIFO's state **after** each rising edge (they are derived from registered state, not from `wr_en` or `rd_en` directly).

| Entries stored | `empty` | `full` |
|---|---|---|
| 0 | 1 | 0 |
| 1 – 63 | 0 | 0 |
| 64 | 0 | 1 |

`full` and `empty` are never high at the same time.

---

## 9. Summary of what the testbench must check

1. **Data integrity:** every accepted write is read back exactly once, in the same order, with the same value.
2. **No data from rejected writes** ever appears on `rd_data`.
3. `full` / `empty` match the entry count after every edge.
4. `wr_ptr` / `rd_ptr` advance only on accepted writes and reads, and wrap from 63 to 0.
5. `wr_err` / `rd_err` pulse exactly when §7 says, and at no other time.
6. Reset puts everything into the state in §3, and `wr_en`/`rd_en` during reset have no effect.
7. Simultaneous read and write behave as in §6, including the empty and full cases.
