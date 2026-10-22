module fifo_seq;
import esdl;
import uvm;
import fifo_item;
import std.format : format;

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
    // ALTERNATIVE: the same body() using a helper method.
    // doCycle() sends ONE clock cycle: create -> start_item -> randomize
    // (random wr_data) -> set rst/wr_en/rd_en -> log -> finish_item.
    // Every cycle goes through the same code, so the loops can't drift apart
    // by copy-paste, and the enables are always set explicitly.
    // ---------------------------------------------------------------------
    // override void body()
    // {
    //     //                          rst    wr     rd
    //     foreach (i; 0 .. 3) doCycle(true,  false, false, format("reset cycle %d", i));
    //     foreach (i; 0 .. 4) doCycle(false, true,  false, format("write cycle %d", i));
    //     foreach (i; 0 .. 4) doCycle(false, false, true,  format("read cycle %d", i));
    //     foreach (i; 0 .. 3) doCycle(false, false, false, format("idle cycle %d", i));
    // }
    //
    // void doCycle(bool rst, bool wr, bool rd, string what)
    // {
    //     req = FifoItem.type_id.create("req");   // req: declared by uvm_sequence
    //     start_item(req);
    //     req.randomize();
    //     req.rst   = rst;
    //     req.wr_en = wr;
    //     req.rd_en = rd;
    //     uvm_info("SEQ", format("%s, wr_data=%02x", what, req.wr_data), UVM_HIGH);
    //     finish_item(req);
    // }
}
