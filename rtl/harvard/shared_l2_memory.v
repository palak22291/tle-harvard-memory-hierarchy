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
// Phase II (Member 2) - multi-cycle latency model:
//   L2_LATENCY    : number of extra wait states added to every access.
//                   0 (default) = Phase I behaviour, l2_ready one clock after
//                   l2_en is sampled.  N > 0 = l2_ready (and, for reads, the
//                   new l2_rdata) appear N clocks later than that, modelling
//                   a slower lower-level memory.
//   While an access is in flight the memory is busy; an l2_en pulse that
//   arrives while busy is ignored (rw_control never issues one, because it
//   waits for l2_ready before starting the next transaction).
//   Writes update the array when the request is accepted; only the
//   acknowledge is delayed.
//
// No reset on the storage array → synthesis infers block RAM.
// -----------------------------------------------------------------------------
module shared_l2_memory #(
    parameter MEM_INIT_FILE = "",                   // optional $readmemh preload
    parameter L2_LATENCY    = 0                     // extra wait states (0 = Phase I)
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
    // Latency counter: 0 = idle, otherwise clocks left until l2_ready.
    // -------------------------------------------------------------------------
    reg [7:0]             wait_cnt;
    reg                   rd_pend;                  // in-flight access is a read
    reg [`DATA_WIDTH-1:0] rd_buf;                   // read data held until ready

    wire accept = l2_en && (wait_cnt == 8'd0);      // new request taken this edge

    // -------------------------------------------------------------------------
    // Storage array – byte-lane writes, synchronous read (NO_CHANGE on write)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (accept) begin
            if (l2_we) begin
                if (l2_be[0]) ram[word_addr][7:0]   <= l2_wdata[7:0];
                if (l2_be[1]) ram[word_addr][15:8]  <= l2_wdata[15:8];
                if (l2_be[2]) ram[word_addr][23:16] <= l2_wdata[23:16];
                if (l2_be[3]) ram[word_addr][31:24] <= l2_wdata[31:24];
                // NO_CHANGE: l2_rdata keeps its value (do not update)
            end else if (L2_LATENCY == 0) begin
                l2_rdata <= ram[word_addr];         // Phase I: data next clock
            end else begin
                rd_buf   <= ram[word_addr];         // held until the wait ends
            end
        end else if (L2_LATENCY != 0 && wait_cnt == 8'd1 && rd_pend) begin
            l2_rdata <= rd_buf;                     // data appears with l2_ready
        end
    end

    // -------------------------------------------------------------------------
    // Handshake flag and wait-state counter (async reset, outputs only)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l2_ready <= 1'b0;
            wait_cnt <= 8'd0;
            rd_pend  <= 1'b0;
        end else if (accept) begin
            rd_pend  <= ~l2_we;
            if (L2_LATENCY == 0) begin
                l2_ready <= 1'b1;
            end else begin
                l2_ready <= 1'b0;
                wait_cnt <= L2_LATENCY;
            end
        end else if (wait_cnt != 8'd0) begin
            wait_cnt <= wait_cnt - 8'd1;
            l2_ready <= (wait_cnt == 8'd1);
        end else begin
            l2_ready <= 1'b0;
        end
    end

    initial l2_rdata = {`DATA_WIDTH{1'b0}};

endmodule

