module fifo_intf;

import esdl;
import esdl.intf.verilator.verilated;

// Virtual interface: the only way the driver and monitor touch the DUT.
// The top (sync_fifo_tb.d) connects each VlPort to the matching port of the
// Verilated DUT, and hands this object to the UVM components via uvm_config_db.
class FifoIntf: VlInterface
{
    // Testbench clock. An eUVM Signal, so posedge()/negedge() can be waited on.
    // (VlPorts have no edge events.)
    Port!(Signal!(ubvec!1)) clock;

    // DUT inputs (written by the driver)
    VlPort!1 rst;
    VlPort!1 wr_en;
    VlPort!8 wr_data;
    VlPort!1 rd_en;

    // DUT outputs (read by the monitor)
    VlPort!8 rd_data;
    VlPort!6 wr_ptr, rd_ptr;
    VlPort!1 full, empty;
    VlPort!1 wr_err, rd_err;
}
