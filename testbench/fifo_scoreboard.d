module fifo_scoreboard;
import esdl;
import uvm;
import std.format: format;
import fifo_item;

// Reference model + checker (VERIFICATION_PLAN.md §3, CHK-01 .. CHK-07).
//
// The monitor sends one FifoItem per cycle, sampled at the negedge. The rising
// edge between two consecutive samples acted on the PREVIOUS sample's inputs,
// and its result is visible in the CURRENT sample's outputs:
//
//     prev (inputs + pre-edge rd_data) --[rising edge]--> cur (outputs)
//
// The model decides everything from its OWN state (expected.length), never
// from the DUT's flags: DUT outputs are only ever compared.
class FifoScoreboard : uvm_scoreboard
{
    mixin uvm_component_utils;

    enum DEPTH = 64;

    this(string name = "FifoScoreboard",uvm_component parent = null)
    {
        super(name,parent);
    }
    @UVM_BUILD
    {
        uvm_analysis_imp!(FifoScoreboard,write) mon_analysis_imp;
    }

    // ---- reference model state ----
    ubyte[]  expected;              // FIFO contents, oldest first (a queue)
    ubvec!6  wrPtr, rdPtr;          // predicted pointers; += 1 wraps 63 -> 0
    bool     expWrErr, expRdErr;    // predicted error pulses after the edge
    bool     modelValid;            // false until the first reset: DUT state undefined
    FifoItem prev;                  // previous sample

    // ---- statistics (for the end-of-test report) ----
    int samples, edgesChecked, dataChecks, writesAccepted, readsAccepted, mismatches;

    void write(FifoItem cur)
    {
        samples++;
        if (prev is null) {                         // first sample: nothing to pair with
            prev = cur;
            return;
        }

        // 1. Predict what the edge between prev and cur did, from prev's inputs.
        if (prev.rst) {                             // SPEC §3: requests ignored, state cleared
            expected = [];
            wrPtr = toubvec!6(0);
            rdPtr = toubvec!6(0);
            expWrErr = false;
            expRdErr = false;
            modelValid = true;
        }
        else if (modelValid) {
            immutable count = expected.length;      // model state BEFORE the edge
            immutable wrAcc = prev.wr_en && (count < DEPTH || prev.rd_en);  // §4, §6
            immutable rdAcc = prev.rd_en && count > 0;                      // §5, §6

            if (rdAcc) {                            // CHK-01: value and order
                dataChecks++;
                check(prev.rd_data == expected[0], "rd_data",
                      format("%02x", expected[0]), format("%02x", prev.rd_data));
                uvm_info("SCB", format("read  %02x (%d left)", prev.rd_data, count - 1), UVM_HIGH);
                expected = expected[1 .. $];
                rdPtr += 1;
                readsAccepted++;
            }
            if (wrAcc) {
                expected ~= prev.wr_data;
                wrPtr += 1;
                writesAccepted++;
            }
            expWrErr = prev.wr_en && !wrAcc;        // §7: pulse after a rejected request
            expRdErr = prev.rd_en && !rdAcc;
        }

        // 2. Compare the DUT's state after the edge with the prediction.
        if (modelValid) {
            edgesChecked++;
            check(cur.wr_ptr == wrPtr, "wr_ptr",
                  format("%d", cast(uint) wrPtr), format("%d", cast(uint) cur.wr_ptr));   // CHK-04
            check(cur.rd_ptr == rdPtr, "rd_ptr",
                  format("%d", cast(uint) rdPtr), format("%d", cast(uint) cur.rd_ptr));
            check(cur.empty == (expected.length == 0), "empty",                          // CHK-03
                  format("%b", expected.length == 0), format("%b", cur.empty));
            check(cur.full == (expected.length == DEPTH), "full",
                  format("%b", expected.length == DEPTH), format("%b", cur.full));
            check(cur.wr_err == expWrErr, "wr_err",                                      // CHK-05
                  format("%b", expWrErr), format("%b", cur.wr_err));
            check(cur.rd_err == expRdErr, "rd_err",
                  format("%b", expRdErr), format("%b", cur.rd_err));
            // cur.rd_data is not checked here: undefined while empty (§3, §5).
            // It's checked on the edge that consumes it (step 1, as prev.rd_data).
        }
        prev = cur;
    }

    // One mismatch = one uvm_error (that's what makes the test fail).
    void check(bool ok, string what, string exp, string got)
    {
        if (ok) return;
        mismatches++;
        uvm_error("SCB", format("%s mismatch: expected=%s got=%s", what, exp, got));
    }

    override void report_phase(uvm_phase phase)
    {
        super.report_phase(phase);
        uvm_info("SCB", format("samples=%d edges_checked=%d data_checks=%d " ~
                               "writes=%d reads=%d left_in_fifo=%d mismatches=%d",
                               samples, edgesChecked, dataChecks,
                               writesAccepted, readsAccepted, expected.length, mismatches),
                 UVM_LOW);
        // "0 errors" proves nothing if nothing was checked.
        if (edgesChecked == 0)
            uvm_error("SCB", "no edges were checked (was reset ever applied?)");
    }
}
