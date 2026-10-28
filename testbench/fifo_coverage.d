module fifo_coverage;

import esdl;
import uvm;
import std.stdio: writeln;
import std.format: format;
import fifo_item;

// Functional coverage (VERIFICATION_PLAN.md §5).
//
// Subscribes to the monitor's analysis port, like the scoreboard, and pairs
// consecutive samples: the rising edge between `prev` and `cur` acted on
// prev's INPUTS, starting from the state shown in prev's OUTPUTS.
//
// The scoreboard decides whether each edge was CORRECT; this component only
// records WHAT HAPPENED. Its numbers are meaningful for passing runs.
//
// esdl covergroup notes (see FAQ): bins use [ ], the class needs a body and a
// 2-argument constructor, and `cross` is avoided because the per-bin report
// crashes with it. Crosses are coverpoints on a COMBINED value instead
// (e.g. lvlop = levelBin * 4 + op). Values outside every bin (we use -1 for
// "not applicable on this edge") are simply not counted.
class FifoCoverage : uvm_component
{
    mixin uvm_component_utils;

    @UVM_BUILD
    {
        uvm_analysis_imp!(FifoCoverage, write) mon_analysis_imp;
    }

    // ---- values sampled by the covergroup (set them, then cg.sample()) ----
    int lvlop;      // non-reset edge: levelBin * 4 + op          (20 bins)
    int werrTr;     // prev.wr_err * 2 + cur.wr_err: 1 = rise, 3 = held
    int rerrTr;     // same for rd_err
    int wrWrap;     // 1 when wr_ptr went 63 -> 0 on a non-reset edge
    int rdWrap;     // 1 when rd_ptr went 63 -> 0 on a non-reset edge
    int rstCase;    // reset edge: rstLevel * 4 + requests       (12 bins)

    // levelBin: 0 = empty, 1 = one entry, 2 = 2..62, 3 = 63 entries, 4 = full
    // op / requests: 0 = none (idle), 1 = write, 2 = read, 3 = read + write
    // rstLevel: 0 = empty, 1 = 1..63 entries, 2 = full
    class CG : covergroup!q{
        coverpoint lvlop {
            bins empty_idle = [0];   bins empty_wr = [1];   bins empty_rd = [2];   bins empty_rw = [3];
            bins one_idle   = [4];   bins one_wr   = [5];   bins one_rd   = [6];   bins one_rw   = [7];
            bins mid_idle   = [8];   bins mid_wr   = [9];   bins mid_rd   = [10];  bins mid_rw   = [11];
            bins n63_idle   = [12];  bins n63_wr   = [13];  bins n63_rd   = [14];  bins n63_rw   = [15];
            bins full_idle  = [16];  bins full_wr  = [17];  bins full_rd  = [18];  bins full_rw  = [19];
        }
        coverpoint werrTr { bins wr_err_rise = [1]; bins wr_err_held = [3]; }
        coverpoint rerrTr { bins rd_err_rise = [1]; bins rd_err_held = [3]; }
        coverpoint wrWrap { bins wr_ptr_63_to_0 = [1]; }
        coverpoint rdWrap { bins rd_ptr_63_to_0 = [1]; }
        coverpoint rstCase {
            bins rst_empty_none = [0];  bins rst_empty_wr = [1];  bins rst_empty_rd = [2];  bins rst_empty_both = [3];
            bins rst_mid_none   = [4];  bins rst_mid_wr   = [5];  bins rst_mid_rd   = [6];  bins rst_mid_both   = [7];
            bins rst_full_none  = [8];  bins rst_full_wr  = [9];  bins rst_full_rd  = [10]; bins rst_full_both  = [11];
        }
    } { this(string n, string h = "") { super(n, h); } }

    CG cg;
    FifoItem prev;
    bool valid;         // false until the first reset: the state before it is undefined
    int edgesSampled;

    this(string name, uvm_component parent = null)
    {
        super(name, parent);
        cg = new CG("fifo_cov");
    }

    // Number of entries stored, from a sample's outputs (state after its edge).
    static int levelOf(FifoItem s)
    {
        if (s.full)  return 64;
        if (s.empty) return 0;
        return (cast(int) s.wr_ptr - cast(int) s.rd_ptr) & 63;
    }

    void write(FifoItem cur)
    {
        if (prev is null) {
            prev = cur;
            return;
        }
        if (valid) {
            immutable lvl = levelOf(prev);                // level BEFORE this edge
            immutable req = (prev.wr_en ? 1 : 0) + (prev.rd_en ? 2 : 0);

            lvlop = rstCase = wrWrap = rdWrap = -1;       // -1 = not applicable
            if (prev.rst) {
                immutable rl = (lvl == 0) ? 0 : (lvl == 64) ? 2 : 1;
                rstCase = rl * 4 + req;
            }
            else {
                immutable lb = (lvl == 0) ? 0 : (lvl == 1) ? 1 : (lvl == 63) ? 3 : (lvl == 64) ? 4 : 2;
                lvlop  = lb * 4 + req;
                wrWrap = (prev.wr_ptr == toubvec!6(63) && cur.wr_ptr == toubvec!6(0)) ? 1 : 0;
                rdWrap = (prev.rd_ptr == toubvec!6(63) && cur.rd_ptr == toubvec!6(0)) ? 1 : 0;
            }
            werrTr = (prev.wr_err ? 2 : 0) + (cur.wr_err ? 1 : 0);
            rerrTr = (prev.rd_err ? 2 : 0) + (cur.rd_err ? 1 : 0);
            cg.sample();
            edgesSampled++;
        }
        if (prev.rst)
            valid = true;                                 // state is defined from here on
        prev = cur;
    }

    override void report_phase(uvm_phase phase)
    {
        super.report_phase(phase);
        uvm_info("COV", format("functional coverage %.1f %% over %d edges " ~
                               "(merge across runs: make coverage)",
                               cg.get_coverage() * 100, edgesSampled), UVM_LOW);
        // Per-bin hit counts, between markers, for `make coverage` to merge.
        writeln("COVERAGE-BEGIN");
        writeln(cg.get_cover_yaml_string());
        writeln("COVERAGE-END");
    }
}
