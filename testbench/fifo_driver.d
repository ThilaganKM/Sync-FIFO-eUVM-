module fifo_driver;
import esdl;
import uvm;
import fifo_item;
import fifo_intf;
import std.format : format;

class FifoDriver : uvm_driver!FifoItem
{
    mixin uvm_component_utils;
    FifoIntf vif;
    this(string name= "FifoDriver", uvm_component parent = null)
    {super(name,parent);}
    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        if(!uvm_config_db!FifoIntf.get(this,"","vif",vif))
        {
            uvm_fatal("VIF","Virtual interface not found");
        }
    }
    override void run_phase(uvm_phase phase)
    {
        super.run_phase(phase);
        while(true)
        {
            wait(vif.clock.posedge());
            seq_item_port.try_next_item(req);   // fills req, or sets it to null if no item
            if(req is null)
            {
                vif.rst = false;    //idle cycles
                vif.wr_en = false;
                vif.rd_en = false;
                vif.wr_data = cast(ubyte) 0x00;   // VlPort!8 needs an 8-bit value, not an int
            }
            else
            {
                vif.rst = req.rst;
                vif.wr_en = req.wr_en;
                vif.rd_en = req.rd_en;
                vif.wr_data = req.wr_data;
                uvm_info("DRV", req.convert2string(), UVM_HIGH);
                seq_item_port.item_done();
            }
        }
    }
}