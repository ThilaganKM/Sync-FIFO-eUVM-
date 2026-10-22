module fifo_sequencer;
import esdl;
import uvm;
import fifo_item;

class FifoSequencer : uvm_sequencer!FifoItem
{
    mixin uvm_component_utils;
    this(string name = "FifoSequencer", uvm_component parent = null){super(name,parent);}
}