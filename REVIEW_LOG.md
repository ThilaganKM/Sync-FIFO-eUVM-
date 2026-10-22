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
