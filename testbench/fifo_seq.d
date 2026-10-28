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
    void doResetWith(int n, bool wr, bool rd)
    {
        foreach (i; 0 .. n)
            doCycle(true, wr, rd, format("reset cycle %d (wr=%b rd=%b)", i, wr, rd));
    }
    // n random cycles: wr_en true with probability wrPct %, rd_en with rdPct %
    // (independently), and a reset cycle with probability rstPerMille / 1000.
    void doRandom(int n, int wrPct, int rdPct, int rstPerMille)
    {
        foreach (i; 0 .. n) {
            req = FifoItem.type_id.create("req");
            start_item(req);
            req.randomizeWith!q{ wr_en dist [true := $0, false := $1];
                                 rd_en dist [true := $2, false := $3]; }
                             (wrPct, 100 - wrPct, rdPct, 100 - rdPct);
            req.rst = urandom(0, 1000) < rstPerMille;
            uvm_info("SEQ", format("random cycle %d: %s", i, req.convert2string()), UVM_HIGH);
            finish_item(req);
        }
    }


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

class FifoReadEmptySeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoReadEmptySeq"){super(name);}

    override void body()
    {
        doReset(1);
        doReads(1);//read error expected
        doIdle(2); //read error must drop since rd_err is 1 cycle long
        doWrites(3);
        doReads(6);//first 3 accepted, next three read errors expected
        doIdle(2);//read error must drop since rd_err is 1 cycle long
    }
}

class FifoWriteFullSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoWriteFullSeq"){super(name);}

    override void body()
    {
        doReset(1);
        doWrites(64);
        doWrites(1);//rejected write due to full flag
        doIdle(2);//dropping the wr_err flag
        doWrites(3);//3 consecutive rejected write errors
        doIdle(1);
        doReads(64);//read 64 data in same order
        doIdle(2);
    }
}

class FifoWriteReadSimSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoWriteReadSimSeq"){super(name);}

    override void body()
    {
        doReset(1);
        doReadWrite(1);//write accepted, read rejected, rerr is asserted
        doIdle(1);//rerr goes down
        doWrites(2);
        doReadWrite(4);//read old data while writing to fifo
        doReads(3);//drain the fifo
        doWrites(64);
        doReadWrite(4);//when fifo full, read and write on the same edge
        doReads(64);//drain the fifo
        doIdle(2);
    }
}

class FifoResetSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoResetSeq"){super(name);}

    override void body()
    {
        doReset(2);//reset initially

        doWrites(10);//reset while partly full
        doReset(2);
        doWrites(3);
        doReads(3);//check for fresh data comes back, if old bytes come then error

        doWrites(64);//reset while full
        doReset(2);
        doWrites(3);//check for fresh data comes back, if old bytes come then error
        doReads(3);

        doWrites(5);
        doResetWith(3,true,false);//reset while writes
        doReads(1);/*rerr goes high, if the FIFO really ignored those writes, 
                   it's empty and this read must be rejected. If any write 
                   slipped through, the read would succeed.*/   
        doWrites(5);
        doResetWith(3,false, true);//reset while read
        doWrites(5);
        doResetWith(3,true,true);//reset during read and write
        doWrites(3);
        doReads(3);
        doIdle(2);
    }
}

class FifoRandomSeq : FifoBaseSeq
{
    mixin uvm_object_utils;
    this(string name="FifoRandomSeq"){super(name);}
    
    override void body()
    {
        doReset(1);
        doRandom(2000,70,30,2);//2000 cycles,70% writes,30% reads,resets 2‰
        doRandom(2000,30,70,2);//2000 cycles,30% writes,70% reads,resets 2%
        doRandom(2000,50,50,2);//2000 cycles,50% writes,50% reads,resets 2%
        doIdle(2);
    }
}