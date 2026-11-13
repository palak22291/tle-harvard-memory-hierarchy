`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// rw_control.v
//
// Synchronous Read/Write Control for the Harvard data-memory subsystem.
//
// Role
//   · Accepts a CPU-side transaction (req, we, d_be, d_addr, d_wdata).
//   · Drives address_decoder's d_valid strobe.
//   · Routes the resulting chip-selects to the correct memory port
//     (data_memory or shared_l2_memory).
//   · Returns read data and a one-cycle `d_ready` acknowledge to the CPU.
//   · Asserts `invalid_addr_err` when the decoder flags an unmapped address.
//
// Timing
//   · FSM: IDLE → ACTIVE → WAIT → IDLE.
//   · ACTIVE: asserts memory enable and transitions to WAIT (does NOT ack yet).
//   · WAIT: polls dmem_ready / l2_ready; captures rdata and asserts d_ready
//     exactly one cycle after the memory completes its synchronous access.
//   · This correctly handles the 1-cycle synchronous-read latency of both
//     data_memory.v and shared_l2_memory.v (FIX for Phase I test failures).
//   · Byte-enable signals (d_be) are passed through unmodified so that
//     data_memory and shared_l2_memory can implement byte-lane writes.
//
// Connections to address_decoder
//   · This module drives `d_valid`; the decoder is purely combinational.
// -----------------------------------------------------------------------------
module rw_control (
    input  wire                   clk,
    input  wire                   rst_n,            // Active-low synchronous reset

    // ----- CPU-side interface ------------------------------------------------
    input  wire                   req,              // Transaction request
    input  wire                   we,               // 1 = write, 0 = read
    input  wire [3:0]             d_be,             // Byte write enables
    input  wire [`ADDR_WIDTH-1:0] d_addr,           // Byte address
    input  wire [`DATA_WIDTH-1:0] d_wdata,          // Write data
    output reg  [`DATA_WIDTH-1:0] d_rdata,          // Read data (muxed from memories)
    output reg                    d_ready,          // Transaction complete pulse
    output reg                    invalid_addr_err, // Unmapped address flag

    // ----- address_decoder interface -----------------------------------------
    output reg                    d_valid,          // Strobe to address_decoder
    input  wire                   cs_dmem,          // Decoded: DMEM selected
    input  wire                   cs_l2,            // Decoded: L2  selected
    input  wire                   addr_err_in,      // Decoded: unmapped address

    // ----- data_memory (DMEM) interface --------------------------------------
    output reg                    dmem_en,          // DMEM chip enable
    output reg                    dmem_we,          // DMEM write enable
    output reg  [3:0]             dmem_be,          // DMEM byte enables
    output reg  [`ADDR_WIDTH-1:0] dmem_addr,        // DMEM byte address
    output reg  [`DATA_WIDTH-1:0] dmem_wdata,       // DMEM write data
    input  wire [`DATA_WIDTH-1:0] dmem_rdata,       // DMEM read data
    input  wire                   dmem_ready,       // DMEM handshake

    // ----- shared_l2_memory (L2) interface -----------------------------------
    output reg                    l2_en,            // L2 chip enable
    output reg                    l2_we,            // L2 write enable
    output reg  [3:0]             l2_be,            // L2 byte enables
    output reg  [`ADDR_WIDTH-1:0] l2_addr,          // L2 byte address
    output reg  [`DATA_WIDTH-1:0] l2_wdata,         // L2 write data
    input  wire [`DATA_WIDTH-1:0] l2_rdata,         // L2 read data
    input  wire                   l2_ready          // L2 handshake
);

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam IDLE   = 2'b00;
    localparam ACTIVE = 2'b01;
    localparam ERR    = 2'b10;
    localparam WAIT   = 2'b11;   // FIX: wait for the memory's ready pulse

    reg [1:0] state;
    reg       sel_l2;            // FIX: which memory was started (0 = DMEM, 1 = L2)
    reg       we_q;              // FIX: latched write-enable of the current transaction

    // =========================================================================
    // Helper: clear all memory-port outputs
    // =========================================================================
    task deassert_ports;
        begin
            d_valid   = 1'b0;
            dmem_en   = 1'b0;  dmem_we = 1'b0;
            dmem_be   = 4'b0;  dmem_addr  = {`ADDR_WIDTH{1'b0}};
            dmem_wdata = {`DATA_WIDTH{1'b0}};
            l2_en     = 1'b0;  l2_we   = 1'b0;
            l2_be     = 4'b0;  l2_addr    = {`ADDR_WIDTH{1'b0}};
            l2_wdata  = {`DATA_WIDTH{1'b0}};
        end
    endtask

    // =========================================================================
    // Sequential FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= IDLE;
            sel_l2          <= 1'b0;
            we_q            <= 1'b0;
            d_valid         <= 1'b0;
            d_ready         <= 1'b0;
            d_rdata         <= {`DATA_WIDTH{1'b0}};
            invalid_addr_err <= 1'b0;
            dmem_en  <= 1'b0;  dmem_we <= 1'b0;
            dmem_be  <= 4'b0;  dmem_addr  <= {`ADDR_WIDTH{1'b0}};
            dmem_wdata <= {`DATA_WIDTH{1'b0}};
            l2_en    <= 1'b0;  l2_we   <= 1'b0;
            l2_be    <= 4'b0;  l2_addr    <= {`ADDR_WIDTH{1'b0}};
            l2_wdata <= {`DATA_WIDTH{1'b0}};
        end else begin
            // --- Defaults: de-assert all strobes every cycle -----------------
            d_ready          <= 1'b0;
            invalid_addr_err <= 1'b0;
            d_valid          <= 1'b0;
            dmem_en  <= 1'b0;  dmem_we <= 1'b0;
            l2_en    <= 1'b0;  l2_we   <= 1'b0;

            case (state)
                // ---- Wait for a new request ---------------------------------
                IDLE: begin
                    if (req) begin
                        // Drive decoder combinationally this cycle
                        d_valid <= 1'b1;
                        state   <= ACTIVE;
                    end
                end

                // ---- Route transaction to the selected memory ---------------
                ACTIVE: begin
                    d_valid <= 1'b0; // decoder no longer needs to be active

                    if (addr_err_in) begin
                        // Unmapped address: flag error, ack CPU, go idle
                        invalid_addr_err <= 1'b1;
                        d_ready          <= 1'b1;
                        state            <= IDLE;

                    end else if (cs_dmem) begin
                        dmem_en    <= 1'b1;
                        dmem_we    <= we;
                        dmem_be    <= d_be;
                        dmem_addr  <= d_addr;
                        dmem_wdata <= d_wdata;
                        sel_l2     <= 1'b0;   // FIX: remember target
                        we_q       <= we;     // FIX: remember read/write
                        state      <= WAIT;   // FIX: do NOT ack yet

                    end else if (cs_l2) begin
                        l2_en    <= 1'b1;
                        l2_we    <= we;
                        l2_be    <= d_be;
                        l2_addr  <= d_addr;
                        l2_wdata <= d_wdata;
                        sel_l2   <= 1'b1;     // FIX: remember target
                        we_q     <= we;       // FIX: remember read/write
                        state    <= WAIT;     // FIX: do NOT ack yet

                    end else begin
                        // Decoder not yet stable – hold one more cycle
                        d_valid <= 1'b1;
                    end
                end

                // ---- FIX: memory has now performed the access ---------------
                WAIT: begin
                    if (sel_l2 ? l2_ready : dmem_ready) begin
                        if (!we_q) d_rdata <= sel_l2 ? l2_rdata : dmem_rdata;
                        d_ready <= 1'b1;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

