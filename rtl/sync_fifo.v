`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Synchronous FIFO
//
//   8-bit x 64-entry, single clock, synchronous active-high reset.
//   Show-ahead (FWFT) read: rd_data always shows the oldest entry,
//   rd_en consumes it on the rising edge.
//
//   See SPEC.md (v1.0) for the full behaviour.
//////////////////////////////////////////////////////////////////////////////////

module sync_fifo #(
    parameter DATA_W = 8,
    parameter ADDR_W = 6               // 2**ADDR_W = 64 entries
) (
    input                   clk,
    input                   rst,

    input                   wr_en,
    input      [DATA_W-1:0] wr_data,

    input                   rd_en,
    output     [DATA_W-1:0] rd_data,

    output reg [ADDR_W-1:0] wr_ptr,
    output reg [ADDR_W-1:0] rd_ptr,

    output                  full,
    output                  empty,
    output reg              wr_err,
    output reg              rd_err
);

    localparam DEPTH = 1 << ADDR_W;

    // Storage array. Not reset: the FIFO is only logically emptied by
    // clearing the pointers (SPEC §3).
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    //------------------------------------------------------------------
    // Status flags (SPEC §8)
    //   empty : 0 entries stored
    //   full  : 64 entries stored
    // The pointers are equal both when empty and when full (SPEC §2), so
    // the number of entries (0..64, 65 values) is kept in a 7-bit counter.
    //------------------------------------------------------------------
    reg [ADDR_W:0] count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH[ADDR_W:0]);

    //------------------------------------------------------------------
    // Accept / reject decisions (SPEC §4, §5, §6)
    //   A write to a full FIFO is still accepted if a read frees a slot
    //   on the same edge. A read from an empty FIFO is always rejected
    //   (no write-through).
    //------------------------------------------------------------------
    wire wr_acc = wr_en && (!full  || rd_en);
    wire rd_acc = rd_en && !empty;

    wire wr_rej = !rst && wr_en && !wr_acc;
    wire rd_rej = !rst && rd_en && !rd_acc;

    //------------------------------------------------------------------
    // Write side: store the data at wr_ptr and advance the pointer.
    // Pointers wrap naturally from 63 to 0.
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            wr_ptr <= {ADDR_W{1'b0}};

        if (wr_acc) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // Read side: show-ahead output, rd_en consumes the oldest entry.
    //------------------------------------------------------------------
    assign rd_data = mem[rd_ptr];

    always @(posedge clk) begin
        if (rst)
            rd_ptr <= {ADDR_W{1'b0}};
        else if (rd_acc)
            rd_ptr <= rd_ptr + 1'b1;
    end

    //------------------------------------------------------------------
    // Entry count: +1 on an accepted write, -1 on an accepted read,
    // unchanged when both or neither happen.
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            count <= {(ADDR_W+1){1'b0}};
        else if (wr_acc && !rd_acc)
            count <= count + 1'b1;
        else if (rd_acc && !wr_acc)
            count <= count - 1'b1;
    end

    //------------------------------------------------------------------
    // Error flags (SPEC §7): high for one cycle after a rejected request.
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            wr_err <= 1'b0;
            rd_err <= 1'b0;
        end
        else begin
            wr_err <= wr_rej;
            rd_err <= rd_rej;
        end
    end

endmodule
