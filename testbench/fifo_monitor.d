module fifo_monitor;
import esdl;
import uvm;
import fifo_intf;
import fifo_item;

class FifoMonitor : uvm_monitor
{
    mixin uvm_component_utils;
    FifoIntf vif;
    @UVM_BUILD
    {
        uvm_analysis_port!FifoItem mon_analysis_port;
    }
    this(string name="FifoMonitor",uvm_component parent = null){super(name,parent);}

    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        if(!uvm_config_db!FifoIntf.get(this,"","vif",vif))
        {
            uvm_fatal("VIF","virtual interface not found");
        }
    }
    override void run_phase(uvm_phase phase)
    {
        super.run_phase(phase);
        while(true)
        {
            wait(vif.clock.negedge());
            auto item = FifoItem.type_id.create("item");   // fresh object every cycle
            item.rst = vif.rst;
            item.rd_data = vif.rd_data;
            item.wr_ptr = vif.wr_ptr;
            item.rd_ptr = vif.rd_ptr;
            item.full = vif.full;
            item.empty = vif.empty;
            item.wr_err = vif.wr_err;
            item.rd_err = vif.rd_err;
            item.wr_en = vif.wr_en;
            item.rd_en = vif.rd_en;
            item.wr_data = vif.wr_data;
            uvm_info("MON", item.convert2string(), UVM_HIGH);
            mon_analysis_port.write(item);
        }
    }
}