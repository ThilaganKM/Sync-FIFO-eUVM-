module fifo_item;
import esdl;
import uvm;
import std.format:format;

class FifoItem:uvm_sequence_item
{
    mixin uvm_object_utils;
    @UVM_DEFAULT{
        @rand bool wr_en, rd_en; //inputs
        @rand ubyte wr_data;
        bool rst; 
        ubyte rd_data; //outputs
        ubvec!6 wr_ptr, rd_ptr;
        bool full,empty,wr_err,rd_err;
    }
    this(string name ="FifoItem"){super(name);}
    override string convert2string()
    {
        return format("rst=%b wr=%b rd=%b wdata=%02x | "~ 
        "rdata=%02x wptr=%02d rptr=%02d full=%b empty=%b werr=%b rerr=%b",
        rst, wr_en,rd_en,wr_data,rd_data,cast(uint) wr_ptr,cast(uint) rd_ptr,full,empty,wr_err, rd_err);
    }
}