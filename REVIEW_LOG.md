# Code Review Log

Each testbench file was written by hand and then reviewed. This log keeps every review: what was wrong or could be better, **why**, and what changed.
It's meant to be read alongside `TESTBENCH_GUIDE.md`: the guide says what to build, and this log shows the mistakes people actually make while building it.

Severity used below:
- 🔴 **Error**: won't compile, or behaves wrongly.
- 🟡 **Should fix**: works, but breaks a convention, or will cause trouble later.
- 🟢 **Suggestion**: optional improvement.

---

## Review 1: `fifo_item.d` (first draft)

```d
class Fifo_item:uvm_sequence_item
{
    mixin uvm_object_utils;
    @UVM_DEFAULT{
        @rand bool wr_en, rd_en; //inputs
        @rand ubyte wr_data;
        ubyte rd_data; //outputs
        ubvec!6 wr_ptr, rd_ptr;
        ubit full,empty,wr_err,rd_err;
    }
    this(string name ="Fifo_item"){super(name);}
}
```

What's right: it's a `uvm_sequence_item` with `mixin uvm_object_utils`, the fields are inside `@UVM_DEFAULT`, the stimulus fields are `@rand` and the outputs aren't, and `wr_data` / `rd_data` are `ubyte`.

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | No `module` line and **no imports** | `uvm_sequence_item`, `uvm_object_utils`, `@rand`, `@UVM_DEFAULT` come from `uvm` / `esdl`, and `ubvec` from `esdl`. Without the imports, every one of them is `undefined identifier`. Without `module fifo_item;`, D still names the module after the file, but stating it is the convention and guards against renames. | Add `module fifo_item;`, `import esdl;` and `import uvm;` at the top. |
| 2 | 🔴 | `ubit` doesn't exist | There's no `ubit` type in D, esdl or uvm (checked by searching the eUVM imports). It looks like SystemVerilog's `bit`. | Use `bool` for 1-bit flags. |
| 3 | 🔴 | `rst` field missing | Sequences have to be able to assert reset in the middle of traffic (TS-10, SPEC §3), and the driver drives `vif.rst` from the item. | Add `bool rst;` (inputs group, **not** `@rand`). |
| 4 | 🟡 | Class name `Fifo_item` | D style is `PascalCase` with no underscores. The linter flags it, and the rest of the testbench (guide, makefile test name) expects `FifoItem`. | Rename to `FifoItem` (and the default name string). |
| 5 | 🟡 | Mixed types for 1-bit values: `bool` for the enables, `ubit` (intended `ubvec!1`) for the flags | One convention for every 1-bit signal keeps comparisons and printing uniform. `bool` reads naturally (`if (item.full)`) and assigns straight to and from a `VlPort!1`. | `bool` for all 1-bit fields. |
| 6 | 🟢 | `ubvec!6` for the pointers | **Good choice, keep it.** It's the exact port width, and it wraps the way hardware does: `r += 1` on a `ubvec!6` holding 63 gives 0 (tested), which is what the scoreboard's model pointers need (SPEC §4). Caveat, found while testing: a `ubvec` is **strict about integers**. `ubvec!6 p = 63;` doesn't compile; write `toubvec!6(63)`. And `p + 1` has a **wider** type (32 bits), so assigning it back needs `cast(ubvec!6)(p + 1)`. `p += 1` avoids both. See the FAQ. | – |
| 7 | 🟢 | No `convert2string()` | `print()` dumps a multi-line table. One line per cycle in the driver and monitor logs is far easier to scan when debugging. | `override string convert2string()` returning e.g. `format("rst=%b wr=%b data=%02x rd=%b", ...)` (needs `import std.format: format;`). |
| 8 | 🟢 | Layout: `//inputs` / `//outputs` comments at the end of lines, missing spaces (`Fifo_item:uvm_sequence_item`, `@UVM_DEFAULT{`), no newline at the end of the file | Readability. A group comment on its own line makes it clear which fields belong to it. | `// Stimulus (driven by the driver)` and `// Response (filled by the monitor)` headers, `class FifoItem: uvm_sequence_item`, `@UVM_DEFAULT {`. |

> **Lesson:** D has no implicit global namespace like SystemVerilog's `import uvm_pkg::*` in a compilation unit. **Every file imports what it uses.**

### Follow-up (second draft)

The 🔴 errors are fixed: there's a module line and imports, `bool` replaces `ubit`, and `rst` is added. The file compiles.
Still open: the class is `Fifoitem`. PascalCase capitalises **each word**, so it should be **`FifoItem`**. Every other file will refer to `FifoItem`, so a mismatch shows up as `undefined identifier FifoItem` as soon as the sequencer is written.
Question raised: *what is `convert2string`, and is it needed?* See the FAQ: it's optional, for logging, and standard practice.

### Follow-up (third draft): adding `convert2string()`

The class is now `FifoItem` ✅. Agreed design for `convert2string()`: **one line, stimulus on the left, response on the right**, with the same format in every log (driver and monitor), so lines from different components line up when compared:

```
rst=0 wr=1 wdata=a5 rd=0 | rdata=3c wptr= 5 rptr= 0 full=0 empty=0 werr=0 rerr=0
```

Pointers are printed with `cast(uint)` because `format`'s width (`%2d`) is ignored for `ubvec` values (tested: `%2d` of `ubvec!6` 5 prints `5`, not ` 5`). With a fixed width, the columns line up from cycle to cycle.

### Review 1, final check: `convert2string()` as written

```d
return format("rst=%b wr=%b rd=%b wdata=%02x |
        rdata = %02x wptr=%02d rptr=%02d full=%b empty=%b werr=%b rerr=%b",
        rst, wr_en,rd_en,wr_data,rd_data,cast(uint) wr_ptr,cast(uint) rd_ptr,full,empty,wr_err, rd_err);
```

The 11 format codes and the 11 arguments match in count, order and type ✅. `%02d` for the pointers (zero-padded, `05`) is a fine alternative to `%2d`.

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | The string literal is split across two lines | In D, a `"..."` literal **can** contain a line break, so this compiles, but the newline and the 8 indentation spaces become **part of the string**. Real output: every log line is split in two:<br>`[DRV] rst=0 wr=0 rd=1 wdata=89 \| `<br>`        rdata = 00 wptr=05 ...`<br>That breaks the "one line per cycle" goal, and `grep` on a log line finds only half of it. | Keep the literal on one line, or split it with **`~`** (D's concatenation operator): `"rst=%b ... \| " ~` on the first line, `"rdata=%02x ..."` on the next. Adjacent literals joined with `~` are merged at compile time. |
| 2 | 🟢 | `rdata = %02x` has spaces around `=`, unlike every other field | One consistent `key=value` style makes the log easy to read and to `grep` (`grep "rdata=3c"`). | `rdata=%02x` |
| 3 | 🟢 | Still open from Review 1: `FifoItem:uvm_sequence_item`, `@UVM_DEFAULT{`, `std.format:format`, end-of-line group comments, no newline at the end of the file | Readability only | Spaces after `:` and before `{`, group comments on their own lines, a final newline |

> **Lesson:** "it compiles" isn't "it's correct". This bug only shows up when you **look at the output**.

### Review 1, closed

The string is now split with `~` ✅. One leftover: `"... wdata=%02x |" ~ "rdata=..."` joins with **no space** after `|`, so the output reads `wdata=89 |rdata=00`. Put a space inside the first literal: `"... | " ~`.

---

## Review 2: `fifo_sequencer.d` (first draft)

```d
module fifo_sequencer;
import esdl;
import uvm;

class FifoSeq : uvm_sequencer
{
    mixin uvm_component_utils;
    this(string name = "FifoSeq", uvm_component parent = null){super(name,parent);}
}
```

What's right: `module` line and imports, `mixin uvm_component_utils` (a sequencer is a **component**, unlike the item), and the constructor passes `name` and `parent` to `super`.

Compiler output (first lines):
```
fifo_sequencer.d(5): Error: template class `uvm.seq.uvm_sequencer.uvm_sequencer(REQ = uvm_sequence_item, RSP = REQ)`
    is used as a type without instantiation; to instantiate it use `uvm_sequencer!(arguments)`
uvm_component_defines.d(200): Error: function `...get_object_type` does not override any function
uvm_object_defines.d(261): Error: function `...get_type_name` does not override any function
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `uvm_sequencer` with no type parameter | `uvm_sequencer` is a **template** (SV: a parameterised class `uvm_sequencer #(REQ, RSP)`). It needs the item type it carries. A bare template name isn't a type, so the class has no base, and the `uvm_component_utils` mixin errors are just the **cascade** from that one mistake. Even `uvm_sequencer!()` (defaults to the generic `uvm_sequence_item`) would be wrong: the driver is a `uvm_driver!FifoItem`, and the agent couldn't connect the two. | `class FifoSequencer: uvm_sequencer!FifoItem` |
| 2 | 🔴 | No `import fifo_item;` | Needed as soon as `FifoItem` appears in the file. | Add `import fifo_item;` |
| 3 | 🟡 | Class name `FifoSeq` | In UVM naming, **`Seq` means sequence** (`FifoSmokeSeq`, `FifoFillSeq`, ...). A *sequencer* named `FifoSeq` is the classic sequence/sequencer mix-up, and every later file would read ambiguously. | `FifoSequencer` |
| 4 | 🟢 | Default name `"FifoSeq"` in the constructor | Components are always created by their parent with an explicit instance name (`FifoSequencer.type_id.create("sqr", this)`), so the default is never used, and the UVM convention is not to give one: `this(string name, uvm_component parent = null)`. A missing name is then a compile error instead of a silently wrong name. Harmless here. | Drop the default |

> **Lesson: read compiler errors top-down and fix the first one first.** Later errors are often consequences of the first (here, 1 real mistake produced 4+ error messages).

### Review 2, follow-up

`class FifoSequencer: uvm_sequencer!FifoItem` with `import fifo_item;` ✅. It compiles. The default constructor name (`"FifoSequencer"`) was kept: fine, since it was only a 🟢 suggestion.
Still open in `fifo_item.d`: no space after `|` (`"... |" ~`), so the output reads `|rdata=`.

---

## Review 3: `fifo_seq.d` (first draft)

```d
class FifoSmokeSeq : uvm_sequence!FifoItem
{
    mixin uvm_object_utils;
    this(string name="FifoSmokeSeq"){super(name);}
    FifoItem item;
    override void body()
    {
        for(int i=0;i<3;i++) //reset sequence
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.rst=1;
            $display("Generated reset cycle %d",i+1);
            finish_item(item);
        }
        for(int i=0;i<4;i++) //write cycles
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.randomize();
            item.wr_en = True;
            $display("Generated write cycle with wr_data=%02x",item.wdata);
            finish_item(item);
        }
        for(int i=0;i<4;i++) //read cycles
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.rd_en=True;
            $display("Generated read cycle at location index=%0d",item.rd_ptr);
            finish_item(item);
        }
    }
}
```

What's right: `uvm_sequence!FifoItem` with the item type, `mixin uvm_object_utils` (a sequence is an **object**), a default name in the constructor (correct for objects), and **`start_item` / `finish_item` around every item**, which is the handshake that stops `body()` returning early. A fresh item is created every cycle, so no field leaks from one cycle to the next.

Compiler output:
```
fifo_seq.d(18): Error: found `$` instead of statement
fifo_seq.d(27): Error: found `$` instead of statement
fifo_seq.d(36): Error: found `$` instead of statement
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `$display(...)` | SystemVerilog system task. In D, `$` isn't a valid way to start a statement (it means "array length" inside `[ ]`). In UVM, components and sequences log through the **report server**, so messages get an ID, a verbosity level, a timestamp and a source location, can be filtered with `+UVM_VERBOSITY`, and are counted in the end-of-test summary. | `uvm_info("SEQ", format("write cycle, wr_data=%02x", req.wr_data), UVM_HIGH);` (needs `import std.format: format;`) |
| 2 | 🔴 | `True` | D's boolean literals are lowercase `true` / `false`. `True` is an undefined identifier. *Not reported yet:* the parser stopped at the `$` errors before checking names. Expect it on the next build. | `true` |
| 3 | 🔴 | `item.wdata` | The field is `wr_data`. (`wdata` is only the **label** chosen in `convert2string`.) Also hidden behind the parse errors. | `item.wr_data` |
| 4 | 🔴 | Write cycles: `randomize()` without overriding `rd_en` | `randomize()` sets **every** `@rand` field, so each "write" cycle also gets a random `rd_en`. About half of them would be read+write cycles, and the sequence wouldn't do what its comment says. | After `randomize()`, set every enable explicitly: `wr_en = true; rd_en = false;` (`rst` is already `false` in a fresh item). |
| 5 | 🔴 | `item.rd_ptr` in the read loop's message | `rd_ptr` is a DUT **output**. The sequence only **generates stimulus** and never sees the DUT, so this field is always 0 here (the monitor fills it in Milestone 2). The message would print `index=0` every time, which is misleading. A sequence that needs DUT state must get it another way (responses or the scoreboard), not from its own fresh item. | Log only what the sequence decides: `"read cycle %d"` |
| 6 | 🟡 | No idle cycles at the end | The driver drives idle when no item is available, so this works. But explicit idle cycles document the intent, make the end of the waveform clean, and keep the sequence correct on its own, whatever the driver does. | 3 cycles with all enables `false` |
| 7 | 🟢 | `item.rst=1` | Works (D converts the literals `0`/`1` to `bool`), but `true` says what you mean, and it's consistent with the other fields. | `item.rst = true;` |
| 8 | 🟢 | The same 5 lines repeated 3 times (4 with idle) | Copy-paste is how fix #4 was missed in one loop. A helper makes every cycle go through the same code. | `void doCycle(bool rst, bool wr, bool rd)` doing create / start / randomize / set / finish. Then `body()` is `foreach (i; 0 .. 3) doCycle(true, false, false);` and so on. |
| 9 | 🟢 | Own `FifoItem item;` member | Works. `uvm_sequence!FifoItem` already declares `req` for exactly this purpose, so most UVM code uses `req`. | Optional: use `req` |

> **Lesson:** compiler errors come in stages. **Syntax** errors (`$`) stop the compiler before it checks **names** (`True`, `wdata`). After you fix the first batch, a second batch can appear. That's progress, not new breakage.

### Question raised: "the outputs come out; I don't think the order matters"

**Order is the whole point of a FIFO**: *First In, First Out*. SPEC §9.1: *"every accepted write is read back exactly once, **in the same order**, with the same value."* If the smoke sequence writes `a5, 3c, 7e, 10`, the expected output is:

| Read # | `rd_data` consumed | Why |
|---|---|---|
| 1 | `a5` | Oldest entry |
| 2 | `3c` | |
| 3 | `7e` | |
| 4 | `10` | After this edge `empty = 1`, and `rd_data` is undefined (SPEC §5) |

A DUT that returned `3c, a5, 7e, 10` has **all the right values** but is broken: a CPU reading a packet out of order gets corrupted data. This is also why the scoreboard model is a **queue** (push at the back, compare and pop at the front), not a set of values.

And because of show-ahead (SPEC §5), `a5` is visible on `rd_data` **right after the first write's edge, before any read is requested**. Check this in the waveform.

### Review 3, follow-up (second draft)

It compiles ✅. `$display` became `uvm_info`, `true` is lowercase, the write loop now sets `rd_en = false` after `randomize()`, and idle cycles were added.
**The stimulus is now correct**: reset (`rst=1`, no enables), 4 writes (random data, `rd_en=0`), 4 reads (`wr_en=0`), 3 idle. The remaining problems are in the **messages** and in one conceptual slip:

| # | Sev. | Line | Issue | Why it matters | Fix |
|---|---|---|---|---|---|
| 1 | 🔴 | 39 | `"read at location %0d", item.wr_ptr` | Same issue as before, moved from `rd_ptr` to `wr_ptr`: a DUT **output**, always 0 in a fresh item. The log would claim every read is "at location 0". | `format("read cycle %d", i)` |
| 2 | 🔴 | 47–48 | Idle loop sets `item.wr_ptr = false; item.rd_ptr = false;` | Idle means **`wr_en = false; rd_en = false;`**. The pointers are outputs, and a sequence never drives them. It compiles only because `ubvec` accepts a `bool`, so the compiler can't catch the mix-up. The cycle is still idle only by luck (a fresh item's enables default to `false`). | `item.wr_en = false; item.rd_en = false;` |
| 3 | 🟡 | 19, 50 | `"reset cycle %0d", item.wr_data` in the reset loop, and the **same message** in the idle loop | Prints `wr_data` (always 0), not the cycle number. The idle loop's copy says "reset cycle", so the log would show 6 "reset" cycles and no idle ones. | `format("reset cycle %d", i)` / `format("idle cycle %d", i)` |
| 4 | 🟢 | – | Four copies of the item boilerplate | Issues 1–3 are all **copy-paste mistakes**: each loop drifted slightly from the others. That's the concrete case for the `doCycle(rst, wr, rd)` helper: one code path, one place to get it right. | Optional, recommended |

> **Lesson:** a misleading log is a bug. During debugging you trust the log. A log that says "reset cycle" during idle cycles, or "location 0" for every read, sends you the wrong way.

### Review 3, closed: helper added as a commented alternative

The author's version stays as the active code. A **commented-out alternative** `body()` with a `doCycle(rst, wr, rd, what)` helper was added at the end of the class, for readers who want the shorter pattern:

```d
//                  rst    wr     rd
foreach (i; 0 .. 3) doCycle(true,  false, false, format("reset cycle %d", i));
...
void doCycle(bool rst, bool wr, bool rd, string what) { create; start_item; randomize; set rst/wr_en/rd_en; log; finish_item; }
```

Why the alternative exists: every cycle goes through one code path, so the loops can't drift apart through copy-paste (the cause of the message mistakes in the follow-up review), and the three control fields are always set explicitly after `randomize()`. To switch, comment out the active `body()` and uncomment the alternative.

Still open in the active code: line 39 logs `item.wr_ptr`, a DUT output that is always 0 in the sequence (follow-up issue #1).

---

## Review 4: `fifo_driver.d` (first draft)

```d
import esdl;
import euvm;
import fifo_item;
import fifo_intf;
import std.format : format;

class Driver : uvm_driver
{
    mixin uvm_component_utils;
    FifoIntf vif;
    this(string name= "Driver", uvm_component parent = null)
    {super(name,parent);
    uvm_config_db!FifoIntf.get(this,"","vif",vif);
    assert(vif !is null);
    }
    override void run_phase(uvm_phase phase)
    {
        super.run_phase(phase);
        while(true)
        {
            seq_item_port.get_next_item(req);
            wait(vif.clock.posedge());
            vif.rst = req.rst;
            vif.wr_en = req.wr_en;
            vif.rd_en = req.rd_en;
            vif.wr_data = req.wr_data;
            seq_item_port.item_done();
        }
    }
}
```

What's right: `mixin uvm_component_utils`, a `FifoIntf vif` handle, a forever loop in `run_phase`, **driving right after `vif.clock.posedge()`** (matches the timing scheme), all four inputs driven from the item, and `item_done()` after driving, which is what unblocks the sequence's `finish_item`.

Compiler output:
```
fifo_driver.d(2): Error: unable to read module `euvm`
    Expected 'euvm.d' or 'euvm/package.d' in one of the following import paths:
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `import euvm;` | **eUVM** is the name of the *project* (UVM in D). The *module* you import is `uvm`, as in every other file. | `import uvm;` |
| 2 | 🔴 | `uvm_driver` without a type parameter | Same as the sequencer (Review 2): `uvm_driver` is a template. With no type, `req` would be a generic `uvm_sequence_item`, so `req.rst` / `req.wr_en` don't exist, and the agent couldn't connect it to a `uvm_sequencer!FifoItem`. *Hidden behind error 1; expect it next.* | `uvm_driver!FifoItem` |
| 3 | 🔴 | `get_next_item` (blocking) | `get_next_item` **waits** until a sequence provides an item. Meanwhile the driver doesn't touch the bus, so the **last values stay driven**. If a sequence ends on a write cycle (`wr_en=1`), the FIFO keeps writing **every cycle** until the next item, with no item and no log line to show it. The smoke sequence happens to end with idle cycles, which hides this today; a later sequence won't. | Wait for `posedge` **first**, then `seq_item_port.try_next_item(req)`. If `req is null`, drive idle (`rst = wr_en = rd_en = false`); otherwise drive the item and call `item_done()`. The driver then owns every cycle. |
| 4 | 🟡 | `config_db.get` in the **constructor**, checked with `assert` | It works here (the comparator did the same), but it isn't standard. **UVM practice:** configuration is read in `build_phase`, the phase meant for it, so overrides set by a test's `build_phase` are guaranteed to be visible. And a failed `assert` stops the program with a D assertion error (or `Illegal instruction` in an optimised build), with no UVM report. `uvm_fatal` names the component and is counted in the summary. | Move it to `override void build_phase(uvm_phase phase)`, after `super.build_phase(phase);`, as `if (!uvm_config_db!FifoIntf.get(this, "", "vif", vif)) uvm_fatal("NOVIF", "...");` |
| 5 | 🟡 | Class name `Driver` | Too generic: there will be a monitor, a scoreboard, maybe a second agent. Every class here is prefixed `Fifo…`, and the agent / guide use `FifoDriver`. | `FifoDriver` |
| 6 | 🟡 | No `module fifo_driver;` | D falls back to the file name, so it works, but every other file declares it. | Add it as line 1 |
| 7 | 🟢 | No log of what was driven | When a test fails, the driver log answers "what did the DUT actually receive in that cycle?". | `uvm_info("DRV", req.convert2string(), UVM_HIGH);` after driving |
| 8 | 🟢 | Default name `"Driver"` in the constructor; unused `import std.format` | Components are always named by their parent (see Review 2 #4). Unused imports are noise. | `this(string name, uvm_component parent = null)`. Keep `std.format` only if you use `format`. |

### Review 4, follow-up (second draft)

Fixed ✅: `module` line, `import uvm`, `uvm_driver!FifoItem`, `FifoDriver`, `config_db.get` in `build_phase` with `uvm_fatal`, a `convert2string()` log per cycle. **It compiles.** But it **crashes at time 0**:

```d
seq_item_port.try_next_item(req);
wait(vif.clock.posedge());
vif.rst = req.rst;            // req may be null
...
seq_item_port.item_done();
```

Run in a scratch environment (smoke sequence + this driver, connected by a throwaway test):
```
Segmentation fault (core dumped)          <- not one log line printed
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | No `null` check after `try_next_item` | `try_next_item` **returns `null`** when no item is ready. That's its whole point. At time 0 the sequence hasn't produced an item yet, so `req` is `null`, and `req.rst` dereferences a null object: a **segmentation fault**, with no UVM message. `item_done()` without an item would also be a UVM error. | `if (req is null) { drive idle } else { drive; log; item_done(); }` |
| 2 | 🔴 | `try_next_item` **before** `wait(posedge)` | The order decides *when* the driver looks for an item. Asked right after `item_done()`, in the same time step, the sequence hasn't had a chance to call `start_item` for its next item, so `try_next_item` would often find nothing, and an **unwanted idle cycle** would appear between consecutive items. Waiting for the edge first gives the sequence a whole cycle to get its next item ready. | `wait(vif.clock.posedge());` as the **first** line of the loop |
| 3 | 🟢 | `"Virutal"` typo in the fatal message; the default constructor name kept; `std.format` imported but unused | Cosmetic | `"Virtual interface not found"` |

With 1 and 2 fixed (tested in the scratch copy), the same run gives **14 consecutive cycles, one per rising edge, no gaps**, `UVM_FATAL : 0`:

```
@10000  [DRV] rst=1 wr=0 rd=0 wdata=00 | ...      reset  x3   (10, 30, 50 ns)
@70000  [DRV] rst=0 wr=1 rd=0 wdata=4a | ...      write  x4   (70 .. 130 ns)
@150000 [DRV] rst=0 wr=0 rd=1 wdata=00 | ...      read   x4   (150 .. 210 ns)
@230000 [DRV] rst=0 wr=0 rd=0 wdata=00 | ...      idle   x3   (230 .. 270 ns)
```

> **Lesson:** an API that can return `null` must be checked **every time**. In D, a null class reference is a segfault, not an exception, so there's no stack trace and no UVM report. If a simulation dies silently, a null handle is the first suspect (as with the `uvm_config_db` scope earlier).

### Review 4, closed (third draft + two one-line fixes)

The loop structure is now right ✅: `wait(posedge)` first, then a `null` branch that drives idle and an item branch that drives, logs and calls `item_done()`. Two lines needed fixing (applied by the reviewer on request, nothing else changed):

| Line | Was | Now | Why |
|---|---|---|---|
| 28 | `if(seq_item_port.try_next_item(req) is null)` | `seq_item_port.try_next_item(req);` then `if(req is null)` | `try_next_item` returns **`void`**. It hands the item back through its **`out` parameter**: the signature is `void try_next_item(out REQ t)`. So the call has to stand on its own line, and you check `req` afterwards. `out` in D means "the function writes this argument" (it's reset at the start of the call, then assigned), so `req` is either the next item or `null`. |
| 34 | `vif.wr_data = 0x00;` | `vif.wr_data = cast(ubyte) 0x00;` | Compiler: ``template `opAssign` is not callable using argument types `!()(int)` ``. A bare literal like `0x00` has type **`int`** (32 bits), and an 8-bit `VlPort!8` refuses a wider value instead of silently truncating it. The same strictness as `ubvec` (see the FAQ). `req.wr_data` worked because the field is already a `ubyte`. |

Scratch run with the smoke sequence: 14 cycles, one per edge, `UVM_FATAL : 0`, `UVM_ERROR : 0`.

---

## Review 5: `fifo_agent.d`, `fifo_env.d`, `fifo_test.d` (first drafts)

### `fifo_agent.d`: ✅ correct

Creates the driver and sequencer in `build_phase` with the factory (`type_id.create(name, this)`, with `this` as parent), and connects `driver.seq_item_port` to `sequencer.seq_item_export` in `connect_phase`, calling `super.*_phase` first. It compiles and needs no change. (🟢 The default constructor name could go, as for the other components.)

### `fifo_env.d`: works, one 🟡

```d
agent = agent.type_id.create("agent",this);
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🟡 | `agent.type_id` (the **variable**) instead of `FifoAgent.type_id` (the **class**) | `type_id` is a `static` member, and D lets you reach a static member through a variable of that type, even one that's still `null`. So it compiles and works, but it reads as if it used the object before creating it. Every other create in the testbench names the class. | `agent = FifoAgent.type_id.create("agent", this);` |
| 2 | 🟢 | Empty `connect_phase` (only calls `super`) | Harmless. It will get real content in Milestone 2 (monitor → scoreboard), so keeping it is fine. | – |

Note the constructor here has **no defaults**: `this(string name, uvm_component parent)`. That's the strict form for components, and it's the one Reviews 2 and 4 recommended.

### `fifo_test.d`: 3 errors

```d
FifoSequencer seq;
...
seq = FifoSequencer.type_id.create("seq");
...
phase.get_objection().set_drain_time(this,200);
phase.raise_objection(this);
seq.start(env.agent.sequencer);
```

Compiler output:
```
fifo_test.d(20): Error: function `create` is not callable using argument types `(string)`
                 missing argument for parameter #2: `uvm_component parent`
fifo_test.d(24): Error: none of the overloads of `set_drain_time` are callable using argument types `(FifoTest, int)`
                 Candidates are: `set_drain_time(uvm_object obj, Time drain)`
fifo_test.d(26): Error: no property `start` for `this.seq` of type `fifo_sequencer.FifoSequencer`
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `seq` is a **`FifoSequencer`** (the component), not a **`FifoSmokeSeq`** (the sequence) | The classic sequence/sequencer mix-up (see Review 2 #3). The test should **start a sequence on the sequencer**. Both errors at lines 20 and 26 come from this one mistake: a component's `create` needs a parent, and a sequencer has no `start`. | `FifoSmokeSeq seq;`, `import fifo_seq;` (`import fifo_sequencer` is then unused), and `seq = FifoSmokeSeq.type_id.create("seq");`. Objects take **only a name**. |
| 2 | 🔴 | `set_drain_time(this, 200)` | The second argument is a **`Time`**, not an integer. D won't guess a unit (200 ps? 200 ns?). eUVM gives units as `40.nsec`, `1.usec`, etc. | `set_drain_time(this, 40.nsec);` (2 clock cycles, enough to see the final idle cycles in the waveform) |
| 3 | 🟡 | One class `FifoTest`, instead of `FifoBaseTest` + `FifoSmokeTest` | The plan has **11 tests** (TS-01 … TS-11). If each built its own env, an env change would be made 11 times. With a base test, the env is built once, and each test only overrides `run_phase` with its sequence. Also, the makefile's default is `TEST ?= fifo_test.FifoSmokeTest`, so `make run` looks for a class that doesn't exist (`UVM_FATAL ... not found`). | `class FifoBaseTest: uvm_test` (builds `env`) and `class FifoSmokeTest: FifoBaseTest` (overrides `run_phase`). Both need `mixin uvm_component_utils;`. |
| 4 | 🟢 | Sequence created in `build_phase` | It works. The convention is to create the sequence where it's used, in `run_phase`: it's a short-lived object, not part of the component tree. | Move the `create` into `run_phase` |

### Review 5, `fifo_test.d` closed (second draft + one-line fix)

The author fixed the main errors ✅: `seq` is now a `FifoSmokeSeq` (`import fifo_seq`), it's created with a name only, and the drain time is `40.nsec`. Remaining fixes, minimal, applied by the reviewer on request:

| Where | Was | Now | Why |
|---|---|---|---|
| `fifo_test.d:26` | `seq.start(env.agent.seq);` | `seq.start(env.agent.sequencer);` | The agent's member is called **`sequencer`** (`fifo_agent.d:13`). A handle path has to use the names the parent actually declared. |
| `sim/makefile` | `TEST ?= fifo_test.FifoSmokeTest` | `TEST ?= fifo_test.FifoTest` | Kept the author's class name. The makefile default now matches it, so plain `make run` finds the test. |

Not done (kept minimal): the `FifoBaseTest` / `FifoSmokeTest` split (#3). It becomes worth doing when the **second** test is written: at that point, move `build_phase` into a base class and let each test override only `run_phase`.

Scratch run, full testbench (`make run`): 14 `[DRV]` cycles, `[SEQ]` messages from `uvm_test_top.env.agent.sequencer@@seq`, `UVM_FATAL : 0`, `UVM_ERROR : 0`, `UVM_WARNING : 0`, and `sync_fifo_tb.vcd` written (timescale 1 ps).

---

## Design review: the monitor (before writing code)

Four questions were answered before any monitor code was written:

| # | Question | Answer given | Review |
|---|---|---|---|
| 1 | When does the monitor sample, and what does a sample contain? | "At the negedge; all the signals needed for the comparison." | ✅ Negedge is right. Be precise about **which edge each value belongs to**. A sample at the negedge between rising edges N and N+1 holds: the **inputs** (`rst`, `wr_en`, `rd_en`, `wr_data`) that edge **N+1** will act on; **`rd_data`**, the value a read on edge **N+1** would consume (SPEC §5); and the registered **outputs** (`full`, `empty`, pointers, error flags), the result of edge **N**. So one snapshot mixes two edges, and the scoreboard pairs **snapshot k's inputs** with **snapshot k+1's outputs** to check what edge N+1 did. |
| 2 | How often does it send a transaction? | "Sample correctly at the time the DUT updates, so on every negedge." | ✅ Every negedge. One correction to the reasoning: the negedge is chosen because the DUT does **not** update there. Mid-cycle, everything is stable, which avoids racing the rising edge where registers change. And every cycle (not only "interesting" ones), because idle cycles are checked too: flags must hold, and an error pulse must drop after exactly one cycle (SPEC §7, "at no other time"). This doesn't contradict the comparator lesson ("events, not levels"): there, one *event* was reported several times by mistake. Here, the transaction is **defined** as one cycle, so each cycle is reported exactly once, and `checks == cycles` stays verifiable. |
| 3 | How does the transaction reach the scoreboard? | "Via the analysis port." | ✅ `uvm_analysis_port!FifoItem` in the monitor, `uvm_analysis_imp` in the scoreboard, and `port.write(item)`. It's a **broadcast**: one port can feed many subscribers (scoreboard, coverage collector) without the monitor knowing who listens, and `write()` is non-blocking, so the monitor never stalls. |
| 4 | Does the monitor check anything? | "Only observes and reconstructs the packets." | ✅ Passive. Checking belongs to the scoreboard, so the same monitor can be reused, e.g. in a passive agent at SoC level where there's no driver. For this FIFO, "reconstructing" is trivial: one transaction = one cycle snapshot. (A bus monitor, say AXI, would assemble a multi-cycle burst into one transaction.) |

**Pitfall to avoid when writing it: create a fresh item every cycle.** The comparator's monitor created one object before its loop and re-sent the **same object** each time. That only worked because its scoreboard used each item immediately. This scoreboard has to **keep the previous snapshot** (point 1). If the monitor reuses one object, the "previous" snapshot the scoreboard stored is the same object, overwritten in place by the next cycle, and every comparison silently compares a cycle with itself. `write()` passes a **reference**, not a copy.

---

## Review 6: `fifo_monitor.d` (first draft)

```d
class FifoMonitor : uvm_monitor
{
    mixin uvm_component_utils;
    FifoIntf vif;
    FifoItem item;
    @UVM_BUILD
    {
        uvm_analysis_port!item mon_analysis_port;
    }
    this(string name="FifoMonitor",uvm_component parent = null){super(name,parent);}

    override void build_phase(uvm_phase phase)
    {
        if(!uvm_config_db.get(this,"","vif",vif))
        {
            uvm_fatal("VIF","virtual interface not found");
        }
    }
    override void run_phase(uvm_phase phase)
    {
        super.run_phase(phase);
        item = FifoItem.type_id.create("item");
        while(true)
        {
            wait(vif.clock.negedge);
            item.rd_data = vif.rd_data;
            ...                          // 10 fields copied
            mon_analysis_port.write(item);
        }
    }
}
```

What's right: `uvm_monitor` with the mixin, the port declared inside `@UVM_BUILD` (eUVM constructs it automatically), `vif` checked with `uvm_fatal`, sampling on **`negedge`**, `write()` once per cycle, and no checking in the monitor.

Compiler output, peeled one error at a time:
```
fifo_monitor.d(14): Error: template instance `uvm_analysis_port!(item)` does not match template declaration `uvm_analysis_port(T)`
                    `item` is not a type                       (+ 6 cascade errors from uvm_component_utils)
-- after fixing that:
fifo_monitor.d(20): Error: template `uvm_config_db(T = int)` does not have property `get`
```

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `uvm_analysis_port!item` | `item` is the **variable** (and the comparator's *class* name, where this line came from). The template needs the **type**. The 6 errors after it are a cascade. | `uvm_analysis_port!FifoItem` |
| 2 | 🔴 | `uvm_config_db.get(...)` | `uvm_config_db` is a template too. It needs the type of the value being fetched, as in the driver. | `uvm_config_db!FifoIntf.get(...)` |
| 3 | 🔴 | **One item created before the loop and re-sent every cycle** | The pitfall from the design review. Measured with a throwaway subscriber that keeps the previous item: **`received=15  same_object_as_previous=14`**. With `create` moved inside the loop: **`same_object_as_previous=0`**. With one shared object, a scoreboard that pairs snapshot k with snapshot k+1 would compare an object with itself, every cycle, and never fail. That's a testbench that can't catch bugs. | Move `create` inside the loop, after the `wait`. Make `item` a local variable (`auto item = FifoItem.type_id.create("item");`) and drop the class member, so it **can't** be reused by accident. |
| 4 | 🔴 | `rst` not sampled (10 of the 11 fields) | The scoreboard has to know when reset was applied to predict the reset state (CHK-07, SPEC §3), and to ignore requests during reset. | `item.rst = vif.rst;` |
| 5 | 🔴 | The agent doesn't create the monitor | `fifo_agent.d` was not updated, so the monitor class compiles but is **never instantiated**: no samples, no errors, and nothing to show it's missing. | In the agent: `import fifo_monitor;`, a `FifoMonitor monitor;` member, and `monitor = FifoMonitor.type_id.create("monitor", this);` in `build_phase` |
| 6 | 🟡 | `build_phase` doesn't call `super.build_phase(phase)` | Tested: the `@UVM_BUILD` port is still constructed here, so nothing breaks today. But the base class's `build_phase` is where UVM does its own build work (e.g. applying configuration), and skipping it is a classic source of "it worked until…" bugs. Every other component calls it first. | `super.build_phase(phase);` as the first line |
| 7 | 🟢 | No log line | One `[MON]` line per cycle, with real DUT outputs, lets you read the DUT's behaviour from the log even before the scoreboard exists. | `uvm_info("MON", item.convert2string(), UVM_HIGH);` before `write` |
| 8 | 🟢 | `vif.clock.negedge` without `()` | Legal D (no-argument functions can be called without parentheses), but the driver writes `posedge()`. | `negedge()` for consistency |

**Correction to earlier guidance:** assigning ports directly (`item.rd_data = vif.rd_data;`, `item.wr_ptr = vif.wr_ptr;`) **compiles**. The `cast(ubyte) ... .read()` form suggested before the review isn't needed for reads. The strictness only applies in the other direction: **writing an `int` literal into a port** (driver Review 4: `vif.wr_data = 0x00`).

Note for the scoreboard: the monitor delivered **15** samples for **14** driven cycles. It samples every negedge while the simulation runs, including the drain time. So the scoreboard's "checks == cycles" count should be based on the samples it receives, not on the number of items driven.

### Review 6, closed (second draft + fixes applied by the reviewer on request)

The author fixed #1–#6 ✅ (port type, `rst` sampled, `super.build_phase`, the monitor created in the agent, the item no longer a class member). Remaining changes, applied on request:

| Line | Change | Why |
|---|---|---|
| 20 | `uvm_config_db!FifoIntfget(` → `uvm_config_db!FifoIntf.get(` | A missing `.`: the compiler would read `FifoIntfget` as one (unknown) identifier. |
| 31 | `item = ...create(...)` → `auto item = ...create(...)` | With the class member removed, `item` has to be declared. `auto` declares a **local** whose type is inferred from the right-hand side (`FifoItem`). Being local to the loop body, it can't survive into the next cycle: reuse is now impossible. |
| 30 | `negedge` → `negedge()` | Suggestion #8, consistency with the driver |
| 43 | Added `uvm_info("MON", item.convert2string(), UVM_HIGH);` | Suggestion #7, one line per sample with real DUT outputs |

Scratch run of the smoke test: builds, `UVM_FATAL : 0`, `UVM_ERROR : 0`, **15 `[MON]` lines** (one per negedge, 20 ns … 300 ns). The analysis port has no subscriber yet, which is legal: `write()` to an unconnected analysis port simply delivers to nobody.

---

## Design review: reading the monitor log like a scoreboard

Five questions about the smoke test's MON lines (the `make view` output, cycles c003–c011), answered **before** the scoreboard was written. The answers become the reference model's rules.

| Q | Answer given | Review |
|---|---|---|
| 1. Which edge lies between c003's inputs and c004's outputs, and what did it do? | "The edge at 70 ns. The write happened: `wptr` +1, `empty` → 0, `rdata` = 18 (show-ahead)." | Evidence ✅, edge ❌. At **70 ns** the DUT evaluated its edge *first*, and only then did the driver put `wr=1, wdata=18` on the bus. The edge that **acts on** those inputs is the **next** one, at **90 ns**, between MON@80 (c003) and MON@100 (c004). Rule: *inputs driven at edge N are consumed at edge N+1.* |
| 2. `rdata=18` at c004 with no read yet: bug? | "Not a bug: show-ahead (combinational) read port." | ✅ SPEC §5: `rd_data` always shows the entry at `rd_ptr`, before `rd_en`. Precisely: it appears **after** the write edge (90 ns), not on it. That's "no write-through" (§5). |
| 3. c007 requests a read with `rdata=18`. What does the next edge consume, and what shows it? | Suspected a timing problem: c007 seems to show `wptr` from c006's inputs but `rdata` from c007's inputs. `rptr` is still 0 even though `rdata=18`. Proposed inserting idle cycles. | ❌ No timing issue. **`rdata` doesn't depend on c007's inputs at all.** It's `mem[rd_ptr]`, and it has been `18` since c004. In c007, **nothing has been read yet**: the read requested there happens at the **next** edge (170 ns). So `rptr=0` is correct, and `rdata=18` is the value **about to be consumed** (SPEC §5: *"the value read is the value of `rd_data` just before that edge"*). The evidence is in c008: `rptr` 0→1 and `rdata` → `59` (the next entry). See the timeline below. **Don't insert idle cycles:** never change the stimulus to make the checker's job easier. Back-to-back traffic is exactly what the DUT has to handle, and the plan's tests depend on it. |
| 4. Is every byte read back exactly once, in order? | "Yes, cycles 7–10." | ✅ The bytes consumed are the `rdata` values in the snapshots with `rd=1`: c007 `18`, c008 `59`, c009 `d3`, c010 `d2` = the write order. |
| 5. `rdata=00` at c011: failure? | "No: the FIFO is empty, so no valid read. Doesn't `rdata` show the last read data?" | ✅ Not a failure. Correction: `rdata` doesn't hold "the last read data". It shows **whatever is in the slot at `rd_ptr`** (slot 4 here, never written, so `00` in Verilator). After a reset or a wrap-around, that slot can hold **old data that looks valid**. SPEC §3/§5: `rd_data` is **undefined while `empty`**, so the scoreboard **must not compare it** then. |
| Bonus: what must the model remember? | "Track the timing between driver and monitor: pointers, rdata, wdata, rst, all signals." | Too broad. A model keeps **only the state it can't recompute**, and **predicts** everything else from it. See below. |

### The timeline behind Q3

```
time (ns)      150            160 (c007 MON)        170            180 (c008 MON)
event       rising edge      sample              rising edge      sample
DUT         writes d2        rptr=0, rdata=18    CONSUMES 18      rptr=1, rdata=59
driver      drives rd=1 ─────────────────────────► (acted on here)
```

In one snapshot, the **left half** (inputs) belongs to the *next* edge, and the **right half** (outputs) to the *previous* edge. `rdata` is a right-half value that also tells you what the next edge will consume. That's show-ahead, by design, not a race.

### Minimal reference-model state

| Model variable | Type | Updated when | Used to predict / check |
|---|---|---|---|
| `expected` | `ubyte[]` (queue) | push `wr_data` on an accepted write, pop on an accepted read | `rd_data` = `expected[0]` (only when non-empty); `count` = `expected.length` → `empty`, `full` |
| `wrPtr`, `rdPtr` | `ubvec!6` | `+= 1` on accepted write / read; 0 on reset | `wr_ptr`, `rd_ptr` |
| `expWrErr`, `expRdErr` | `bool` | set from the reject decision on each edge | `wr_err`, `rd_err` in the **next** snapshot |
| `prev` | `FifoItem` | every snapshot | pairs the previous snapshot's inputs with this snapshot's outputs |
| check counters | `int` | every comparison | end-of-test report (checks == cycles) |

Not state: `wr_data` and `rst` are **inputs**, read fresh from each snapshot. `rd_data`, `empty` and `full` are **derived** from the queue, so storing them separately would only give a second copy that can drift out of sync.

---

## Design review: the scoreboard algorithm (first draft)

> *"For every reset, check `empty=1`, `full=0` and both pointers 0. For every write, first check it's valid (`full != 1`), then push it into `mem[wr_ptr]`. For every read, check it's valid (`empty != 1`), then pop from `mem[rd_ptr]`. Wrap-around only happens when `rd_ptr == wr_ptr`: the pointers go to 0 and the next data is stored from index 0, so the FIFO mimics reset behaviour. I hope the RTL was written that way."*

What's right: a reset check with the right expected values (CHK-07), and the idea of accepting or rejecting each request before updating the model.

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | **Wrap-around misunderstood** | SPEC §4: each pointer wraps **independently**, from 63 to 0, **when it advances past 63**. `rd_ptr == wr_ptr` means **empty or full** (SPEC §2 note), not "wrap", and nothing resets. The smoke test's own log shows it: after the last read, **c011: `wptr=04 rptr=04 empty=1`**. The pointers are equal and stay at 4. The next write goes to slot 4, not 0. | Model pointers as `ubvec!6` and `+= 1` on each accepted operation: 63 + 1 = 0 automatically (FAQ). No special case. |
| 2 | 🔴 | Acceptance decided from the **DUT's** `full` / `empty` | This makes the checker trust the thing it checks. If the DUT's `full` were wrong, the model would accept or reject exactly as the DUT did and agree with it. **The model must decide from its own state** (`expected.length`), then compare the DUT's flags against that. | `wrAcc` / `rdAcc` from the model's count |
| 3 | 🔴 | Simultaneous read + write missing | SPEC §6: at **full**, a write **is** accepted when a read happens on the same edge. At **empty**, the read is **rejected** even though a write happens (no write-through). "Write valid if not full" gets the first case wrong. | `wrAcc = wr_en && (count < 64 \|\| rd_en)`; `rdAcc = rd_en && count > 0` |
| 4 | 🔴 | **No data comparison** | The algorithm pops data but never **compares** it with what the DUT returned. That's CHK-01, the main purpose of the scoreboard. | On an accepted read, compare the **pre-edge** `rd_data` (in `prev`) with `expected[0]`, *then* pop |
| 5 | 🔴 | Flags, pointers and error pulses only checked at reset | CHK-03/04/05 must hold **after every edge**: `empty`/`full` vs. the count, the pointers vs. the model pointers, and `wr_err`/`rd_err` vs. "a request was rejected on the previous edge". | Compare them on every snapshot |
| 6 | 🟡 | `mem[wr_ptr]` / `mem[rd_ptr]` | That's the mirror-memory approach again (see the FAQ). A **queue** does push-back / pop-front without any index. | `expected ~= data;` / `expected = expected[1 .. $];` |
| 7 | 🟡 | No `prev`/`cur` pairing, no first snapshot | Each check pairs the previous snapshot's **inputs** with this snapshot's **outputs**. Before the first reset, the DUT's state is **undefined** (the spec only defines it after reset), so nothing can be predicted yet. | Keep `prev`. Skip checks until the first reset has been seen. |
| 8 | 🟡 | "I hope the RTL was written that way" | **The scoreboard follows the spec, never the RTL.** A model written to match what you expect the RTL to do will match its bugs too. When model and DUT disagree, the spec decides who's wrong. | – |

### Corrected per-snapshot algorithm

```
on receive(cur):
    if prev is null:                      // first snapshot: nothing to pair with
        prev = cur; return

    // The rising edge between prev and cur acted on prev's INPUTS.
    if prev.rst:                                          // SPEC §3
        expected = []; wrPtr = rdPtr = 0; expWrErr = expRdErr = false
        modelValid = true
    else if modelValid:
        count = expected.length                           // model state BEFORE the edge
        wrAcc = prev.wr_en && (count < 64 || prev.rd_en)  // §4, §6 (full + read frees a slot)
        rdAcc = prev.rd_en && count > 0                   // §5, §6 (no write-through)
        if rdAcc:                                         // CHK-01: data and order
            check prev.rd_data == expected[0]             //   pre-edge value = value consumed
            pop expected[0];  rdPtr += 1
        if wrAcc:
            push prev.wr_data; wrPtr += 1
        expWrErr = prev.wr_en && !wrAcc                   // §7: pulse after a rejected request
        expRdErr = prev.rd_en && !rdAcc

    if modelValid:                                        // DUT state AFTER the edge
        check cur.wr_ptr == wrPtr && cur.rd_ptr == rdPtr  // CHK-04
        check cur.empty == (expected.length == 0)         // CHK-03
        check cur.full  == (expected.length == 64)
        check cur.wr_err == expWrErr && cur.rd_err == expRdErr   // CHK-05
        // cur.rd_data is NOT checked here; while empty it's undefined (§3/§5)
    prev = cur
```

Why the order inside the `else` matters: the data check uses `expected[0]` **before** the pop, and before the push (a push goes to the back, so with count > 0 the front is unchanged either way). At **empty**, `rdAcc` is false, so the byte pushed on that edge can never be "read" on the same edge. That's no write-through, enforced by construction.

---

## `fifo_scoreboard.d`: written by the reviewer on request, from the agreed algorithm

At the author's request, the scoreboard was implemented from the corrected algorithm in the design review above, keeping the author's skeleton (class name, constructor, `@UVM_BUILD` analysis imp, `write` method). `fifo_env.d` got the two wiring lines it needs: create `scoreboard` in `build_phase`, and in `connect_phase`, `agent.monitor.mon_analysis_port.connect(scoreboard.mon_analysis_imp);`.

Structure:

| Part | What it does | Plan item |
|---|---|---|
| `write(cur)`, step 1 | From `prev`'s inputs and the **model's** count: reset → clear the model; else decide `wrAcc` / `rdAcc` (§4–§6), check `prev.rd_data` against `expected[0]` on an accepted read and pop, push on an accepted write, predict `expWrErr` / `expRdErr` | CHK-01, CHK-02, CHK-07 |
| `write(cur)`, step 2 | Compare `cur`'s `wr_ptr`, `rd_ptr`, `empty`, `full`, `wr_err`, `rd_err` with the prediction | CHK-03, -04, -05, -06 |
| `modelValid` | No checks until the first reset has been seen (the DUT's state before reset is undefined) | SPEC §3 |
| `check(ok, what, exp, got)` | One `uvm_error("SCB", "<what> mismatch: expected=.. got=..")` per mismatch | – |
| `report_phase` | Prints `samples`, `edges_checked`, `data_checks`, `writes`, `reads`, `left_in_fifo`, `mismatches`, and raises an error if **nothing** was checked | Completion criteria 2–3 |

D details used: `expected ~= x` (append), `expected = expected[1 .. $]` (drop the front; `$` is the length inside `[ ]`), `immutable` (a local that can't change after it's set), `ubvec!6 += 1` (wraps 63 → 0), `toubvec!6(0)` (a `ubvec` from an integer).

### Verification of the checker itself

1. **Smoke test passes**, and the counts add up: `samples=15 edges_checked=14 data_checks=4 writes=4 reads=4 left_in_fifo=0 mismatches=0`. 14 = 15 − 1: every pair of consecutive samples was checked (the first pair already includes the reset edge). 4 data checks = 4 accepted reads.
2. **Fault injection**: a checker that has never failed hasn't been tested. In a scratch copy only, the monitor was made to report a wrong `wr_ptr` at 120 ns and to flip one bit of `rd_data` at 180 ns:
   ```
   ERROR   120 ns  SCB  wr_ptr mismatch: expected=2 got=7
   ERROR   200 ns  SCB  rd_data mismatch: expected=59 got=58
   ...  mismatches=2        UVM_ERROR :    2
   ```
   Both caught. The `rd_data` sampled at **180** ns is reported at **200** ns: the read is checked when the snapshot **after** the consuming edge arrives. Reading reports this way (error time = one sample after the cause) matters when debugging.

---

## Base test and base sequence (set up by the reviewer, existing behaviour unchanged)

| File | Change |
|---|---|
| `fifo_seq.d` | New **`FifoBaseSeq`**: `doCycle(rst, wr, rd, what)` plus phase helpers `doReset(n)`, `doWrites(n)`, `doReads(n)`, `doReadWrite(n)`, `doIdle(n)`. `FifoSmokeSeq` now extends `FifoBaseSeq`. **Its own `body()` is unchanged.** The old commented alternative became a one-line pointer: `doReset(3); doWrites(4); doReads(4); doIdle(3);`. |
| `fifo_test.d` | New **`FifoBaseTest`**: builds `env`, and its `run_phase` starts the sequence returned by **`createSeq()`** (raise objection → `start` → drop, 40 ns drain). `FifoTest` now extends it and only overrides `createSeq()` to return `FifoSmokeSeq`. Running `FifoBaseTest` itself stops with `UVM_FATAL [TEST] FifoBaseTest runs no sequence`. |

Design: the **template method** pattern. The base class owns the fixed procedure (build env, objections, start, drain), and each test fills in the one part that varies (which sequence). A new test is 5 lines, and the objection/drain logic exists once.

Verified (scratch build):
- `make run` (FifoTest): unchanged, `edges_checked=14 data_checks=4 mismatches=0`.
- `make run TEST=fifo_test.FifoBaseTest`: `FATAL ... FifoBaseTest runs no sequence`, as intended.
- The helper version of the smoke body gives the **same control, pointers and flags** in all 28 DRV/MON lines, and still 0 mismatches, but **different data bytes**. `doCycle` calls `randomize()` on every cycle (reset, read and idle cycles too), while the original loops only randomize write cycles, so the random stream is consumed differently. Both are correct, because `wr_data` is a don't-care when `wr_en = 0`. Lesson: "same seed" only reproduces a run if the stimulus code consumes random numbers in the **same order**. Changing the stimulus code changes the values.

---

## Review 7: `FifoFillDrainSeq` (first draft)

```d
class FifoFillDrainSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoSmokeSeq"){super(name);}
    FifoItem item;
    override void body()
    {
        doReset(1);
        doWrites(63);
        doReads(63);
    }
}
```

What's right: it extends `FifoBaseSeq` and uses the helpers, so the body reads like the plan.

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | **63** writes / reads instead of **64** | The FIFO is 64 deep (SPEC §1). TS-02's purpose is "`full` rises exactly after the 64th write". With 63 the FIFO is never full, so the test can't check its main point. Slot **indices** go to 63, but the **count** is 64: a classic off-by-one. And if 63 was chosen because 64 produced errors: **never change a spec-derived test to make the DUT pass.** A failing spec-correct test is a finding to investigate (testbench or RTL?), not something to shrink away. | `doWrites(64); doReads(64);` |
| 2 | 🟡 | Default name `"FifoSmokeSeq"` | Copy-paste: the log would label this sequence as the smoke sequence. | `"FifoFillDrainSeq"` |
| 3 | 🟡 | Unused `FifoItem item;` | The helpers use `req`. | Remove |
| 4 | 🟢 | No trailing idle | Optional: the drain time already covers the edge after the last read. | `doIdle(2);` |
| – | 🔴 | No `FifoFillDrainTest` | Needed to run it (`TEST=fifo_test.FifoFillDrainTest`). | 5-line class overriding `createSeq()` (see the comment in `fifo_test.d`) |

### Review 7, follow-up

Fixed ✅: `doWrites(64); doReads(64);`, the default name is now `"FifoFillDrainSeq"`, the unused member is gone, and `FifoFillDrainTest` was added to `fifo_test.d`. First run (seed 1): `samples=130 edges_checked=129 data_checks=64 writes=64 reads=64 left_in_fifo=0 mismatches=71`, `UVM_ERROR : 71`. The counts confirm every edge was checked. Next step: debug from the **first** error.

---

## Review 8: `FifoReadEmptySeq` (TS-05) and `FifoWriteFullSeq` (TS-06)

```d
// TS-05
doReset(1);
doReads(1);    // read error expected
doIdle(2);     // rd_err must drop: 1-cycle pulse
doWrites(3);
doReads(6);    // first 3 accepted, next 3 rejected
doIdle(2);

// TS-06
doReset(1);
doWrites(64);
doWrites(1);   // rejected write
doIdle(2);     // wr_err drops
doWrites(3);   // 3 consecutive rejected writes
doIdle(1);
doReads(64);   // the original 64 bytes, in order
doIdle(2);
```

✅ Both cover every case in the plan: TS-05 (a) after reset, (b) after a drain, (c) single, (d) consecutive; TS-06 single + consecutive rejects, then a full drain. `doReads(6)` puts the drain and the underflow back-to-back with no idle cycle in between, which is slightly stronger than two separate phases. No poison data is needed for TS-06: the scoreboard never pushes a rejected write, so a DUT that stored one would show up as an `rd_data` mismatch during the drain (CHK-02).

| # | Sev. | Issue | Fix |
|---|---|---|---|
| 1 | 🔴 | No `FifoReadEmptyTest` / `FifoWriteFullTest` in `fifo_test.d`: `TEST=...` would give `UVM_FATAL ... not found` | Two 5-line classes overriding `createSeq()` |
| 2 | 🟢 | Comment "rejected write due to full flag" | The DUT rejects because the FIFO **is** full. The flag only *reports* that state. Wording: "rejected: FIFO full (SPEC §4)" |

### Review 8, follow-up: predictions and the first run

First run: `UVM_FATAL [INVTST] Requested test from command line +UVM_TESTNAME=fifo_test.FifoReadEmptyTest not found.` (same for `FifoWriteFullTest`). Cause: issue #1 above, the test classes hadn't been added yet.

Predictions given before running, all correct: (1) after the first read, `rptr=0 empty=1 rerr=1`; (2) `rerr` drops on the idle edge; (3) `rerr=1` for exactly 3 edges; (4) on the 65th write request, `wptr=0 full=1 werr=1`; (5) `werr` for 3 edges; (6) `full` drops on the first read. Refinement for (3)/(5): in the **edge table**, a registered error pulse appears on the **same row** as the rejected request (each row's outputs are *after* its edge), while in the raw MON stream it appears **one sample later** than the request. A flag that shows up one row *early* in the table would be reacting before the edge (combinational), which is against SPEC §7.

### Review 8: first real runs of TS-05 and TS-06

`make summary`: `FifoWriteFullTest` **PASS** (138 edges, 64 data checks, 0 mismatches); `FifoReadEmptyTest` **FAIL** (4 mismatches). The debugging of the failure is recorded in `SOLUTIONS.md` (spoilers).

---

## Design: TS-08 simultaneous read + write (before code)

SPEC §6 gives three behaviours for `wr_en = rd_en = 1` on one edge, depending on the level **before** the edge: at **empty**, the write is accepted and the read rejected (no write-through, `rd_err`), count +1; in the **middle**, both are accepted, count unchanged; at **full**, both are accepted (the read frees a slot), still full, no `wr_err`. So the sequence brings the FIFO to each level, then applies `doReadWrite(n)`:

```
reset
(a) empty:  doReadWrite(1); doIdle(1)
            doWrites(2)                       // level 3
(b) middle: doReadWrite(4)                    // overlapping old reads / new writes keep FIFO order
            doReads(3)                        // drain
            doWrites(64)                      // full
(c) full:   doReadWrite(4)                    // accepted every edge; the opposite of TS-06
            doReads(64); doIdle(2)            // every byte checked in order
```

Predictions requested before running: the outputs after (a), which byte is read first in (b), and why (c) differs from TS-06 (§6 vs §4).

### Review 9: `FifoWriteReadSimSeq` (TS-08) and `FifoWriteReadSimTest`

The sequence follows the design, with comments stating what each step **expects** ✅. One count was off:

| # | Sev. | Issue | Why it matters | Fix |
|---|---|---|---|---|
| 1 | 🔴 | `doReads(2)` to drain after phase (b) | Level bookkeeping: (a) read+write at **empty** = write **accepted**, read rejected → level 1; `doWrites(2)` → 3; (b) four read+writes → still 3. So 7 bytes in, 4 out, **3** left. The question "isn't 6 enough? is the extra read meant to trigger `rd_err`?" missed the byte written in (a). With 2 reads, 1 byte stays, `doWrites(64)` fills the FIFO after 63 and **rejects the 64th**: an unintended TS-06 case inside TS-08, and the "fill from empty" boundary disappears. No false errors (the scoreboard tracks the real level), but the test no longer does what its comments say. | `doReads(3);` with a comment showing the count |

The test class `FifoWriteReadSimTest` was added to `fifo_test.d` (on request). Compiles.

> **Lesson:** keep a **level table** (writes in, reads out, level after) for every directed sequence. A directed test is only meaningful if it puts the DUT exactly where its comments claim.

### Review 9, follow-up: TS-08 predictions

| # | Prediction | Review |
|---|---|---|
| 1–4 | (a) `wptr`→1, `rptr`=0, `rerr`=1, `empty`→0; the new byte shows on `rdata` afterwards; (b) `wptr` 3→7, `rptr` 0→4; the first read in (b) consumes the byte from (a) | ✅ |
| 5 | (c) "pointers don't move, at 64" | ❌ At full with read+write, **both** requests are accepted, so **both** pointers advance every edge. A 6-bit pointer is 0–63, so never 64. Level bookkeeping: `rptr` 4 → 7 after the 3-read drain; 64 writes take `wptr` from 7 to 71 mod 64 = **7**; so full with `wptr = rptr = 7`, then (c) moves both to 8…11. |
| 6 | (c) differs from TS-06 "because of show-ahead" | ⚠️ The right clause (§6), the wrong reason. It's not about show-ahead. When full, `wr_ptr == rd_ptr`: the slot read at this edge is the slot written, so the read frees it as the write fills it, and no unread data is overwritten. TS-06 had no read on the same edge, so there was no free slot. |

First run: `UVM_ERROR : 22`. Debugging recorded in `SOLUTIONS.md`.
