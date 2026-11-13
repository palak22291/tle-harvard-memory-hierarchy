`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// shared_l2_memory.v
//
// 512 x 32-bit (2 KB) synchronous read/write Shared Lower-Level Memory (L2).
//
// Address space : 0x0000_0800 – 0x0000_0FFF  (selected by address_decoder)
// Addressing    : byte address in; word index = l2_addr[10:2];
//                 bits [1:0] are the byte offset and are ignored for indexing.
// Write         : synchronous on rising edge when l2_en && l2_we.
//                 l2_be[3:0] is a per-byte write strobe (matches data_memory):
//                   l2_be[0] → bits  7:0    l2_be[1] → bits 15:8
//                   l2_be[2] → bits 23:16   l2_be[3] → bits 31:24
//                 Use 4'b1111 for a full-word store.
// Read          : synchronous, 1-cycle latency.  l2_rdata is valid one clock
//                 after l2_en && !l2_we is sampled.
// Read-during-write: NO_CHANGE – l2_rdata keeps its value during a write.
// l2_ready      : asserted for one cycle after every accepted access.
//
// No reset on the storage array → synthesis infers block RAM.
// -----------------------------------------------------------------------------
module shared_l2_memory #(
    parameter MEM_INIT_FILE = ""                    // optional $readmemh preload
)(
    input  wire                   clk,
    input  wire                   rst_n,            // async reset, active low (outputs only)
    input  wire                   l2_en,            // chip select from rw_control
    input  wire                   l2_we,            // 1 = write, 0 = read
    input  wire [3:0]             l2_be,            // byte write enables
    input  wire [`ADDR_WIDTH-1:0] l2_addr,          // byte address
    input  wire [`DATA_WIDTH-1:0] l2_wdata,         // store data
    output reg  [`DATA_WIDTH-1:0] l2_rdata,         // load data  (1-cycle latency)
    output reg                    l2_ready          // access completed
);

    reg [`DATA_WIDTH-1:0] ram [0:`L2_DEPTH-1];

    // Word index: strip the 2-KB region offset (bit 11 and below), then
    // divide by 4 (>> 2).  Bits [10:2] address the 512 words directly.
    wire [8:0] word_addr = l2_addr[10:2];

    integer i;
    initial begin
        for (i = 0; i < `L2_DEPTH; i = i + 1)
            ram[i] = {`DATA_WIDTH{1'b0}};
        if (MEM_INIT_FILE != "")
            $readmemh(MEM_INIT_FILE, ram);
    end

    // -------------------------------------------------------------------------
    // Storage array – byte-lane writes, synchronous read (NO_CHANGE on write)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (l2_en) begin
            if (l2_we) begin
                if (l2_be[0]) ram[word_addr][7:0]   <= l2_wdata[7:0];
                if (l2_be[1]) ram[word_addr][15:8]  <= l2_wdata[15:8];
                if (l2_be[2]) ram[word_addr][23:16] <= l2_wdata[23:16];
                if (l2_be[3]) ram[word_addr][31:24] <= l2_wdata[31:24];
                // NO_CHANGE: l2_rdata keeps its value (do not update)
            end else begin
                l2_rdata <= ram[word_addr];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Handshake flag – mirrors data_memory convention
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            l2_ready <= 1'b0;
        else
            l2_ready <= l2_en;
    end

    initial l2_rdata = {`DATA_WIDTH{1'b0}};

endmodule

