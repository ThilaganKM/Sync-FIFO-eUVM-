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
    output                  rd_err
);

    localparam DEPTH = 1 << ADDR_W;

    // Storage array. Not reset: the FIFO is only logically emptied by
    // clearing the pointers (SPEC §3).
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    //------------------------------------------------------------------
    // Status flags (SPEC §8)
    //   empty : 0 entries stored
    //   full  : 64 entries stored
    //------------------------------------------------------------------
    assign empty = (wr_ptr == rd_ptr);
    assign full  = ((wr_ptr + 1'b1) == rd_ptr);

    //------------------------------------------------------------------
    // Accept / reject decisions (SPEC §4, §5, §6)
    //   A write to a full FIFO is still accepted if a read frees a slot
    //   on the same edge. A read from an empty FIFO is always rejected
    //   (no write-through).
    //------------------------------------------------------------------
    wire wr_acc = wr_en && (!full  || rd_en);
    wire rd_acc = rd_en && (!empty || wr_en);

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
    // Error flags (SPEC §7): high for one cycle after a rejected request.
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            wr_err <= 1'b0;
        else
            wr_err <= wr_rej;
    end

    assign rd_err = rd_rej;

endmodule
