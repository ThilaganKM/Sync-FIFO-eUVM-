module fifo_seq;
import esdl;
import uvm;
import fifo_item;
import std.format : format;

// ---------------------------------------------------------------------------
// FifoBaseSeq: common helpers shared by every FIFO sequence.
// Every directed sequence extends this class, so its body() can be written as
// one line per phase of the test plan, e.g.
//     doReset(3); doWrites(64); doWrites(1); doReads(64);
// ---------------------------------------------------------------------------
class FifoBaseSeq : uvm_sequence!FifoItem
{
    mixin uvm_object_utils;
    this(string name="FifoBaseSeq"){super(name);}

    // Sends ONE clock cycle: create -> start_item -> randomize (random wr_data)
    // -> set rst/wr_en/rd_en explicitly -> log -> finish_item (blocks until the
    // driver has driven it). Every cycle goes through this one code path.
    void doCycle(bool rst, bool wr, bool rd, string what)
    {
        req = FifoItem.type_id.create("req");   // req: declared by uvm_sequence
        start_item(req);
        req.randomize();
        req.rst   = rst;
        req.wr_en = wr;
        req.rd_en = rd;
        uvm_info("SEQ", format("%s, wr_data=%02x", what, req.wr_data), UVM_HIGH);
        finish_item(req);
    }

    //                                              rst    wr     rd
    void doReset(int n)     { foreach (i; 0 .. n) doCycle(true,  false, false, format("reset cycle %d", i)); }
    void doWrites(int n)    { foreach (i; 0 .. n) doCycle(false, true,  false, format("write cycle %d", i)); }
    void doReads(int n)     { foreach (i; 0 .. n) doCycle(false, false, true,  format("read cycle %d", i)); }
    void doReadWrite(int n) { foreach (i; 0 .. n) doCycle(false, true,  true,  format("read+write cycle %d", i)); }
    void doIdle(int n)      { foreach (i; 0 .. n) doCycle(false, false, false, format("idle cycle %d", i)); }
}

class FifoSmokeSeq : FifoBaseSeq
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
            uvm_info("SEQ", format("reset cycle %d", i), UVM_HIGH);
            finish_item(item);
        }
        for(int i=0;i<4;i++) //write cycles
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.randomize();
            item.wr_en = true;
            item.rd_en = false;
            uvm_info("SEQ", format("write, wr_data=%02x", item.wr_data), UVM_HIGH);
            finish_item(item);

        }
        for(int i=0;i<4;i++) //read cycles
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.rd_en=true;
            item.wr_en=false;
            uvm_info("SEQ", format("read cycle %d", i), UVM_HIGH);
            finish_item(item);
        }
        for(int i=0;i<3;i++) //idle sequence
        {
            item = FifoItem.type_id.create("item");
            start_item(item);
            item.rst=false;
            item.wr_en=false;
            item.rd_en=false;
            item.wr_data=0x00;
            uvm_info("SEQ", format("idle cycle %d",i), UVM_HIGH);
            finish_item(item);
        }
    }

    // ---------------------------------------------------------------------
    // ALTERNATIVE: the same body() written with the FifoBaseSeq helpers:
    //     override void body() { doReset(3); doWrites(4); doReads(4); doIdle(3); }
    // ---------------------------------------------------------------------

}

class FifoFillDrainSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoFillDrainSeq"){super(name);}
    
    override void body()
    {
        doReset(1);
        doWrites(64);
        doReads(64);
    }
}