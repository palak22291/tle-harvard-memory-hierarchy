`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// data_memory.v  (Member 2)
//
// 256 x 32-bit (1 KB) synchronous read/write Data RAM (local L1 DMEM).
//
// Address space : 0x0000_0000 - 0x0000_03FF (selected by the address decoder)
// Addressing    : byte address in, word index = d_addr[9:2]; d_addr[1:0] is the
//                 byte offset and is ignored for indexing (byte lanes are picked
//                 with d_be instead).
// Write         : synchronous, on the rising edge when dmem_en && dmem_we.
//                 d_be[3:0] is a per-byte write strobe:
//                   d_be[0] -> bits  7:0    d_be[1] -> bits 15:8
//                   d_be[2] -> bits 23:16   d_be[3] -> bits 31:24
//                 Use 4'b1111 for a full-word store (SW).
// Read          : synchronous, 1-cycle latency. Address is sampled on the rising
//                 edge when dmem_en && !dmem_we; d_rdata is valid after that edge.
// Read-during-write: NO_CHANGE mode - d_rdata keeps its previous value during a
//                 write cycle (matches the Xilinx block-RAM NO_CHANGE mode).
// d_ready       : 1 for one cycle after every accepted access (read or write).
//
// No reset on the storage array so that synthesis tools can infer block RAM.
// -----------------------------------------------------------------------------
module data_memory #(
    parameter MEM_INIT_FILE = ""                     // optional $readmemh preload
)(
    input  wire                   clk,
    input  wire                   rst_n,             // async reset, active low (outputs only)
    input  wire                   dmem_en,           // chip select from address decoder
    input  wire                   dmem_we,           // 1 = write, 0 = read
    input  wire [3:0]             d_be,              // byte write enables
    input  wire [`ADDR_WIDTH-1:0] d_addr,            // byte address
    input  wire [`DATA_WIDTH-1:0] d_wdata,           // store data
    output reg  [`DATA_WIDTH-1:0] d_rdata,           // load data (1-cycle latency)
    output reg                    d_ready            // access completed
);

    reg [`DATA_WIDTH-1:0] ram [0:`DMEM_DEPTH-1];
    wire [7:0] word_addr = d_addr[9:2];

    integer i;
    initial begin
        for (i = 0; i < `DMEM_DEPTH; i = i + 1) begin
            ram[i] = {`DATA_WIDTH{1'b0}};
        end
        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, ram);
        end
    end

    // Storage array: byte-lane writes and synchronous read.
    always @(posedge clk) begin
        if (dmem_en) begin
            if (dmem_we) begin
                if (d_be[0]) ram[word_addr][7:0]   <= d_wdata[7:0];
                if (d_be[1]) ram[word_addr][15:8]  <= d_wdata[15:8];
                if (d_be[2]) ram[word_addr][23:16] <= d_wdata[23:16];
                if (d_be[3]) ram[word_addr][31:24] <= d_wdata[31:24];
            end else begin
                d_rdata <= ram[word_addr];
            end
        end
    end

    // Handshake flag.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_ready <= 1'b0;
        end else begin
            d_ready <= dmem_en;
        end
    end

    initial d_rdata = {`DATA_WIDTH{1'b0}};

endmodule
