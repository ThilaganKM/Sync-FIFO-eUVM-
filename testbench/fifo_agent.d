module fifo_agent;
import esdl;
import uvm;
import fifo_driver;
import fifo_sequencer;
import fifo_monitor;

class FifoAgent : uvm_agent
{
    mixin uvm_component_utils;
    this(string name = "FifoAgent", uvm_component parent = null)
    {super(name,parent);}
    FifoDriver driver;
    FifoSequencer sequencer;
    FifoMonitor monitor;

    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        driver = FifoDriver.type_id.create("driver",this);
        sequencer = FifoSequencer.type_id.create("sequencer",this);
        monitor = FifoMonitor.type_id.create("monitor",this);
    }
    override void connect_phase(uvm_phase phase)
    {
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    }
}