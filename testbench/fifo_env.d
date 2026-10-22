module fifo_env;
import uvm;
import esdl;
import fifo_agent;

class FifoEnv : uvm_env
{
    mixin uvm_component_utils;
    this(string name,uvm_component parent){super(name,parent);}
    FifoAgent agent;
    
    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        agent = agent.type_id.create("agent",this);
    }
    override void connect_phase(uvm_phase phase)
    {
        super.connect_phase(phase);
    }
}