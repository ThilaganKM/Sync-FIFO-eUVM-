module sync_fifo_tb;

import esdl;
import esdl.intf.verilator.verilated;
import esdl.intf.verilator.trace;
import uvm;
import std.stdio;

import fifo_intf;

////////////////////////////////////////////////////////////////////////////////
// Top
// Instantiates the Verilated DUT, generates the clock, dumps the waveform and
// connects the virtual interface to the DUT ports.
////////////////////////////////////////////////////////////////////////////////
class Top: Entity
{
    import Vsync_fifo_euvm;

    enum HALF_PERIOD = 10;              // ns -> 20 ns clock (50 MHz)

    DVsync_fifo   dut;
    FifoIntf      vif;
    VerilatedVcdD trace;

    // Testbench-side clock. UVM components wait on vif.clock.posedge()/negedge().
    Signal!(ubvec!1) clock;

    override void doBuild()
    {
        dut = new DVsync_fifo();
        traceEverOn(true);
        openTrace("sync_fifo_tb.vcd");
    }

    override void doConnect()
    {
        vif.clock(clock);

        // DUT inputs
        vif.rst(dut.rst);
        vif.wr_en(dut.wr_en);
        vif.wr_data(dut.wr_data);
        vif.rd_en(dut.rd_en);

        // DUT outputs
        vif.rd_data(dut.rd_data);
        vif.wr_ptr(dut.wr_ptr);
        vif.rd_ptr(dut.rd_ptr);
        vif.full(dut.full);
        vif.empty(dut.empty);
        vif.wr_err(dut.wr_err);
        vif.rd_err(dut.rd_err);
    }

    void openTrace(string vcdname)
    {
        if (trace is null) {
            trace = new VerilatedVcdD();
            dut.trace(trace, 99);
            trace.open(vcdname);
            writeln("Trace is open: ", vcdname);
        }
    }

    void closeTrace()
    {
        if (trace !is null) {
            trace.close();
            trace = null;
            writeln("Trace is closed");
        }
    }

    void dumpTrace()
    {
        if (trace !is null) {
            trace.dump(getSimTime().getVal());
            trace.flush();
        }
    }

    // Clock generator.
    // On each edge the DUT is evaluated FIRST, then the testbench clock is
    // toggled. So when a UVM component wakes up on vif.clock.posedge(), the
    // DUT has already processed that edge:
    //   - posedge: registers have updated. The driver drives the next inputs
    //              here; the DUT only acts on them at the next posedge.
    //   - negedge: no state change; combinational outputs settle with the new
    //              inputs. Everything is stable, so the monitor samples here.
    // Driving and sampling on opposite edges avoids races between the driver
    // and the monitor (both would otherwise wake on the same edge, in no
    // guaranteed order).
    Task!stimulateClock stimulateClockTask;

    void stimulateClock()
    {
        dut.clk = false;
        dut.eval();
        dumpTrace();
        clock = false;

        while (true) {
            wait(HALF_PERIOD.nsec);
            dut.clk = true;
            dut.eval();
            dumpTrace();
            clock = true;

            wait(HALF_PERIOD.nsec);
            dut.clk = false;
            dut.eval();
            dumpTrace();
            clock = false;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
// SyncFifoTb
// The UVM root. Publishes the virtual interface to every component under the
// test, including the test itself ("uvm_test_top*" glob: no dot, so it also
// matches "uvm_test_top"). New components need no edit here.
////////////////////////////////////////////////////////////////////////////////
class SyncFifoTb: uvm_tb
{
    Top top;

    override void initial()
    {
        uvm_config_db!(FifoIntf).set(null, "uvm_test_top*", "vif", top.vif);
    }
}

void main(string[] args)
{
    uint seed;

    CommandLine cmdl = new CommandLine(args);

    if (cmdl.plusArgs("seed=" ~ "%d", seed))
        writeln("Using random seed: ", seed);
    else
        seed = 1;

    auto tb = new SyncFifoTb;

    tb.multicore(0, 1);
    tb.elaborate("tb", args);
    tb.set_seed(seed);
    tb.start();
}
