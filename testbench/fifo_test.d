module fifo_test;
import esdl;
import uvm;
import fifo_env;
import fifo_seq;

class FifoTest : uvm_test
{
    mixin uvm_component_utils;
    FifoEnv env;
    FifoSmokeSeq seq;
    this(string name = "FifoTest",uvm_component parent = null)
    {
        super(name,parent);
    }
    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        env = FifoEnv.type_id.create("env",this);
        seq = FifoSmokeSeq.type_id.create("seq");
    }
    override void run_phase(uvm_phase phase)
    {
        phase.get_objection().set_drain_time(this,40.nsec);
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    }
}