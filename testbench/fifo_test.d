module fifo_test;
import esdl;
import uvm;
import fifo_env;
import fifo_seq;

// ---------------------------------------------------------------------------
// FifoBaseTest: builds the environment and runs ONE sequence on the agent's
// sequencer. A test only has to say WHICH sequence, by overriding createSeq():
//
//     class FifoFillTest : FifoBaseTest
//     {
//         mixin uvm_component_utils;
//         this(string name, uvm_component parent = null) { super(name, parent); }
//         override FifoBaseSeq createSeq() { return FifoFillSeq.type_id.create("seq"); }
//     }
//
// Run it with:  make run TEST=fifo_test.FifoFillTest
// ---------------------------------------------------------------------------
class FifoBaseTest : uvm_test
{
    mixin uvm_component_utils;
    FifoEnv env;
    this(string name, uvm_component parent = null)
    {
        super(name,parent);
    }
    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        env = FifoEnv.type_id.create("env",this);
    }

    // Overridden by every test. The base test itself has no sequence.
    FifoBaseSeq createSeq() { return null; }

    override void run_phase(uvm_phase phase)
    {
        auto seq = createSeq();
        if (seq is null) {
            uvm_fatal("TEST", "FifoBaseTest runs no sequence: run a derived test (TEST=fifo_test.<Name>)");
            return;
        }
        phase.get_objection().set_drain_time(this,40.nsec);
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    }
}

// Smoke test: reset, 4 writes, 4 reads, idle (FifoSmokeSeq).
class FifoTest : FifoBaseTest
{
    mixin uvm_component_utils;
    this(string name = "FifoTest",uvm_component parent = null)
    {
        super(name,parent);
    }
    override FifoBaseSeq createSeq() { return FifoSmokeSeq.type_id.create("seq"); }
}
//Fill and drain test: reset, 64 writes, 64 reads
class FifoFillDrainTest : FifoBaseTest
{
    mixin uvm_component_utils;
    this(string name, uvm_component parent = null) { super(name, parent); }
    override FifoBaseSeq createSeq() { return FifoFillDrainSeq.type_id.create("seq"); }
}
// TS-05: read when empty (underflow)
class FifoReadEmptyTest : FifoBaseTest
{
    mixin uvm_component_utils;
    this(string name, uvm_component parent = null) { super(name, parent); }
    override FifoBaseSeq createSeq() { return FifoReadEmptySeq.type_id.create("seq"); }
}
// TS-06: write when full (overflow)
class FifoWriteFullTest : FifoBaseTest
{
    mixin uvm_component_utils;
    this(string name, uvm_component parent = null) { super(name, parent); }
    override FifoBaseSeq createSeq() { return FifoWriteFullSeq.type_id.create("seq"); }
}
