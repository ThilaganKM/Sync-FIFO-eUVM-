# Testbench Guide: Building the eUVM Components

A step-by-step guide to writing the UVM components of the FIFO testbench.
It explains **what each file is for, what goes in it, and the traps to avoid**. You write the code.

Prerequisites, already in the repo:
- `testbench/fifo_intf.d`: virtual interface `FifoIntf`.
- `testbench/sync_fifo_tb.d`: top. Instantiates the DUT, runs the clock and publishes the interface to `"uvm_test_top*"` via `uvm_config_db`.
- `sim/makefile`: `TB_SRC` lists every file below, and `make run` defaults to `TEST=fifo_test.FifoSmokeTest`.

Background reading in `FAQ.md`: the timing scheme (driver on the rising edge, monitor on the falling edge), and why `get` must be checked.

---

## Milestone 1: first waveform (no checking yet)

Goal: run a **smoke test** that resets the FIFO, writes a few bytes and reads them back, then look at the VCD.
There's no monitor or scoreboard yet. Those come in Milestone 2, once the stimulus is known to be right.

### Component hierarchy

```
uvm_test_top : FifoSmokeTest        (fifo_test.d)
└── env      : FifoEnv              (fifo_env.d)
    └── agent: FifoAgent            (fifo_agent.d)
        ├── sqr: FifoSequencer      (fifo_sequencer.d)  ◄── FifoSmokeSeq runs here (fifo_seq.d)
        └── drv: FifoDriver         (fifo_driver.d)     ──► FifoIntf ──► DUT
                    ▲ FifoItem (fifo_item.d) flows sequence → sequencer → driver
```

### Create the files

```bash
cd testbench
touch fifo_item.d fifo_sequencer.d fifo_seq.d fifo_driver.d fifo_agent.d fifo_env.d fifo_test.d
```

`touch` creates empty files (or updates the timestamp of existing ones). An empty `.d` file is still a valid D module, so `make` works at every step, even before every file is written.

**Write them in this order** (each file only imports files above it), and run `make` after each one:

| # | File | Class(es) | Imports |
|---|---|---|---|
| 1 | `fifo_item.d` | `FifoItem` | – |
| 2 | `fifo_sequencer.d` | `FifoSequencer` | `fifo_item` |
| 3 | `fifo_seq.d` | `FifoSmokeSeq` | `fifo_item` |
| 4 | `fifo_driver.d` | `FifoDriver` | `fifo_item`, `fifo_intf` |
| 5 | `fifo_agent.d` | `FifoAgent` | `fifo_sequencer`, `fifo_driver` |
| 6 | `fifo_env.d` | `FifoEnv` | `fifo_agent` |
| 7 | `fifo_test.d` | `FifoBaseTest`, `FifoSmokeTest` | `fifo_env`, `fifo_seq` |

Every file starts the same way:

```d
module fifo_xxx;      // must match the file name

import esdl;
import uvm;
import std.format: format;   // only if you use format()
import fifo_item;            // ...and the project modules it needs
```

Naming (D/Phobos style, see the FAQ): files and modules `lower_snake`, classes `PascalCase`, variables and functions `camelCase` or `snake_case` (UVM's own names, like `build_phase`, keep their style).

---

### 1. `fifo_item.d`: `FifoItem`

**What it is:** one object = **one clock cycle** of stimulus, plus the outputs observed in that cycle (filled in later by the monitor).

| Field | Type | `@rand`? | Notes |
|---|---|---|---|
| `wr_en`, `rd_en` | `bool` | ✅ | |
| `wr_data` | `ubyte` | ✅ | 8 bits = `ubyte` (unsigned byte) |
| `rst` | `bool` | ❌ | Set explicitly by sequences that want a reset. |
| `rd_data` | `ubyte` | ❌ | Outputs, filled by the monitor (Milestone 2). |
| `wr_ptr`, `rd_ptr` | `ubyte` | ❌ | 6-bit values fit in a `ubyte` |
| `full`, `empty`, `wr_err`, `rd_err` | `bool` | ❌ | |

Key pieces:
- `class FifoItem: uvm_sequence_item`
- `mixin uvm_object_utils;` registers it with the factory (items and sequences are **objects**, not components).
- Wrap the fields in `@UVM_DEFAULT { ... }` so `print()`, `copy()` and `compare()` include them automatically.
- Constructor: `this(string name = "FifoItem") { super(name); }`
- Recommended: `override string convert2string()` returning a one-line summary (e.g. `"rst=0 wr=1 data=a5 rd=0"`). Logs are much easier to read with it.

> ⚠️ **No `dist` constraint inside the item class.** On eUVM beta61, an item with a class-level `constraint! q{ x dist [...]; }` **crashes** (`Illegal instruction`) when the same object is later randomized with `randomizeWith`. Each one works alone. Put weightings in the **sequences** instead (`randomizeWith!q{ wr_en dist [true := 7, false := 3]; }`). That's also the better design: the item defines *what is legal*, and sequences decide *what is likely*.

### 2. `fifo_sequencer.d`: `FifoSequencer`

The shortest file: `class FifoSequencer: uvm_sequencer!FifoItem` with `mixin uvm_component_utils;` and the standard component constructor:

```d
this(string name, uvm_component parent = null) { super(name, parent); }
```

It arbitrates between sequences and hands their items to the driver. You never add logic here.

### 3. `fifo_seq.d`: `FifoSmokeSeq`

`class FifoSmokeSeq: uvm_sequence!FifoItem`, with `mixin uvm_object_utils;` and a constructor `this(string name = "FifoSmokeSeq")`.

All the work is in `override void body()`. **One item = one cycle.** The smoke sequence:

1. ~3 cycles of **reset** (`rst = true`, `wr_en = rd_en = false`)
2. **4 writes** with random data
3. **4 reads**
4. ~3 **idle** cycles (all `false`), so the inputs end in a quiet state

**Use `start_item` / `finish_item`** for every item. This is the standard UVM handshake:

```d
req = FifoItem.type_id.create("req");
start_item(req);            // waits until the driver is ready for an item
req.randomize();            // random wr_data (and everything else)...
req.rst   = false;          // ...then override the fields this cycle needs
req.wr_en = true;
req.rd_en = false;
finish_item(req);           // sends it, and BLOCKS until the driver calls item_done()
```

Why not `send_request` like the comparator? `finish_item` blocks until the driver is done, so `body()` can't return while items are still in flight. That was exactly the comparator's bug (FAQ / previous project). `req` is a member that `uvm_sequence` already declares, so you don't declare it yourself.

Tip: write a small helper, e.g. `void doCycle(bool rst, bool wr, bool rd)`, so `body()` reads like the list above instead of 14 copies of the 6 lines.

### 4. `fifo_driver.d`: `FifoDriver`

`class FifoDriver: uvm_driver!FifoItem`, with `mixin uvm_component_utils;` and the component constructor.

**`build_phase`: get the interface, and fail loudly if it's missing.**

```d
FifoIntf vif;

override void build_phase(uvm_phase phase) {
    super.build_phase(phase);
    if (!uvm_config_db!FifoIntf.get(this, "", "vif", vif))
        uvm_fatal("NOVIF", "virtual interface not set for " ~ get_full_name());
}
```

(The comparator did this in the constructor with an `assert`. The standard place is `build_phase`, and `uvm_fatal` gives a readable message instead of a crash.)

**`run_phase`: one item per rising edge.**

```
forever:
    wait for vif.clock.posedge()
    try to get an item  (seq_item_port.try_next_item(req))
    if there is one:  drive rst, wr_en, wr_data, rd_en from it;  seq_item_port.item_done()
    else:             drive idle (rst=0, wr_en=0, rd_en=0)
```

Points to understand:
- **Drive right after the rising edge.** The DUT already processed that edge (see the timing FAQ), so the new values are held for a whole cycle and acted on at the **next** rising edge.
- **`try_next_item` instead of `get_next_item`.** `get_next_item` *blocks* until a sequence provides an item, so between or after sequences the old inputs would stay on the bus. If `wr_en` was the last thing driven, the FIFO would keep writing. `try_next_item` returns `null` when there's nothing to do this cycle, so the driver drives **idle**. This is the standard pattern for a cycle-based driver.
- Writing to the interface: `vif.wr_en = req.wr_en;`, `vif.wr_data = req.wr_data;` and so on.
- Recommended: `uvm_info("DRV", req.convert2string(), UVM_HIGH);` so every driven cycle is logged.

### 5. `fifo_agent.d`: `FifoAgent`

`class FifoAgent: uvm_agent`. It holds the sequencer and the driver (and the monitor in Milestone 2).

- `build_phase`: create both with the factory:
  `sqr = FifoSequencer.type_id.create("sqr", this);` (likewise `drv`)
- `connect_phase`: `drv.seq_item_port.connect(sqr.seq_item_export);`

Always call `super.build_phase(phase)` / `super.connect_phase(phase)` first.

### 6. `fifo_env.d`: `FifoEnv`

`class FifoEnv: uvm_env`. For now it only creates `agent`. In Milestone 2 it also creates the scoreboard and connects the monitor to it.

### 7. `fifo_test.d`: `FifoBaseTest`, `FifoSmokeTest`

Two classes:

- **`FifoBaseTest: uvm_test`**: creates `env` in `build_phase`. Nothing else. Every test in the plan (TS-01 … TS-11) will extend it, so the environment is built in one place.
- **`FifoSmokeTest: FifoBaseTest`**: overrides `run_phase`:

```
raise objection
create FifoSmokeSeq, start it on env.agent.sqr      (seq.start(env.agent.sqr) blocks until body() returns)
drop objection
```

Both need `mixin uvm_component_utils;` (that's what makes `+UVM_TESTNAME=fifo_test.FifoSmokeTest` work) and the component constructor.

**Drain time:** `phase.get_objection().set_drain_time(this, 40.nsec);` (2 cycles) keeps the simulation running briefly after the drop, so the last cycles show up in the waveform. Keep it small: thanks to `finish_item`, nothing is in flight when `body()` returns.

---

### Build, run, look

```bash
cd sim
make                         # build
make run | tee run.log       # run the default test, and keep a copy of the output in run.log
```

- `tee run.log` shows the output **and** writes it to a file. `run.log` is git-ignored.
- Expected: `UVM_FATAL : 0`, `UVM_ERROR : 0`, your `DRV` lines for each cycle, and `sync_fifo_tb.vcd` in `sim/`.

Then open the VCD in gtkwave (download it to Windows, open from WSL). **Before trusting anything, check by eye:**

| What to check | Expected |
|---|---|
| `rst` | High for the first cycles, then low |
| After reset | `empty=1`, `full=0`, `wr_ptr=rd_ptr=0`, `wr_err=rd_err=0` |
| Each write cycle | `wr_ptr` steps by 1 at the rising edge **after** `wr_en` was driven. `empty` drops after the first write. |
| `rd_data` | Shows the **first** byte written as soon as the FIFO is non-empty (show-ahead) |
| Each read cycle | `rd_data` steps to the next byte written, `rd_ptr` steps by 1 |
| End | `empty=1` again, all inputs low |

If something looks wrong, first decide whether the **stimulus** is wrong (the inputs aren't what the sequence intended: a testbench bug) or the **response** is wrong (the inputs are right but the outputs disagree with `SPEC.md`). That habit is the core of the whole exercise.

---

## Milestone 2 (next)

Monitor (samples on the falling edge, one `FifoItem` per cycle) → scoreboard with the reference model (CHK-01 … CHK-07) → the directed tests of the verification plan → random → coverage.
