`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// simple_cpu_driver.v  (Member 4 - Phase II)
//
// A small accumulator machine that executes the benchmark instruction format
// from defines.vh and drives ONE instruction port and ONE data port. The same
// driver is connected to the Harvard hierarchy (separate ports) and to the
// Von Neumann baseline (both ports go through bus_arbiter), so any difference
// in cycle count comes from the memory organization alone.
//
// Instruction format (32 bits):
//   [31:28] opcode   OP_NOP 0x0 | OP_LOAD 0x1 | OP_STORE 0x2 | OP_ALU 0x3
//   [27:0]  byte address for LOAD / STORE (zero-extended to 32 bits)
//
// Semantics (one 32-bit accumulator, acc):
//   LOAD  addr : acc <= mem[addr]
//   STORE addr : mem[addr] <= acc        (full word, d_be = 4'b1111)
//   ALU        : acc <= acc + 1          (single-cycle ALU operation)
//   NOP        : no effect
//   any other opcode is treated as NOP.
//
// Micro-architecture: two stages with a one-entry instruction buffer (IB).
//   FETCH  : requests the word at pc, places it in IB, pc <= pc + 4.
//            A new fetch starts as soon as IB is empty or is being handed to
//            EXECUTE, so fetch of instruction N+1 can run while instruction N
//            is doing its data access - IF the memory system lets it.
//   EXECUTE: ALU / NOP finish in one cycle; LOAD / STORE hold the data port
//            until d_ready.
//   The driver fetches exactly MAX_INSTR instructions and raises `halted`
//   when MAX_INSTR instructions have retired (the benchmark has no HALT op).
//
// Port handshake (both ports, same as rw_control / bus_arbiter):
//   req is held until a one-cycle ready pulse; it drops combinationally in
//   the ready cycle so the slave never sees a second request by mistake.
//
// Performance counters (all stop when halted):
//   cycle_count    cycles from reset release until the last instruction retires
//   retired        instructions completed
//   load_count / store_count / alu_count / nop_count
//   data_cycles    cycles with a LOAD/STORE in flight
//   starve_cycles  cycles where EXECUTE had no instruction to work on
//   overlap_cycles cycles where a fetch and a data access were both in flight
// -----------------------------------------------------------------------------
module simple_cpu_driver #(
    parameter RESET_PC  = 32'h0000_0000,   // address of the first instruction
    parameter MAX_INSTR = 16,              // instructions to fetch and retire
    parameter ACC_INIT  = 32'hCAFE_0000    // accumulator value after reset
)(
    input  wire                   clk,
    input  wire                   rst_n,          // async reset, active low

    // ----- instruction port --------------------------------------------------
    output wire                   if_req,
    output wire [`ADDR_WIDTH-1:0] if_addr,
    input  wire [`DATA_WIDTH-1:0] if_rdata,
    input  wire                   if_ready,

    // ----- data port ---------------------------------------------------------
    output wire                   d_req,
    output reg                    d_we,
    output wire [3:0]             d_be,
    output reg  [`ADDR_WIDTH-1:0] d_addr,
    output reg  [`DATA_WIDTH-1:0] d_wdata,
    input  wire [`DATA_WIDTH-1:0] d_rdata,
    input  wire                   d_ready,

    // ----- status / counters -------------------------------------------------
    output reg                    halted,
    output reg  [`DATA_WIDTH-1:0] acc,
    output reg  [31:0]            cycle_count,
    output reg  [31:0]            retired,
    output reg  [31:0]            load_count,
    output reg  [31:0]            store_count,
    output reg  [31:0]            alu_count,
    output reg  [31:0]            nop_count,
    output reg  [31:0]            data_cycles,
    output reg  [31:0]            starve_cycles,
    output reg  [31:0]            overlap_cycles
);

    // ---------------- FETCH state ----------------
    reg [`ADDR_WIDTH-1:0] pc;
    reg                   f_busy;          // fetch request outstanding
    reg [31:0]            fetched;         // instructions fetched so far
    reg                   ib_valid;
    reg [`DATA_WIDTH-1:0] ib;

    // ---------------- EXECUTE state --------------
    reg                   ex_valid;
    reg [3:0]             ex_op;
    reg                   d_busy;          // data request outstanding

    assign if_req  = f_busy & ~if_ready;
    assign if_addr = pc;
    assign d_req   = d_busy & ~d_ready;
    assign d_be    = 4'b1111;

    wire ex_is_mem = (ex_op == `OP_LOAD) || (ex_op == `OP_STORE);
    wire ex_done   = ex_valid && (ex_is_mem ? (d_busy && d_ready) : 1'b1);
    wire ex_free   = !ex_valid || ex_done;
    wire take      = ib_valid && ex_free && !halted;   // IB -> EXECUTE this edge

    wire [3:0] ib_op   = ib[31:28];
    wire       ib_mem  = (ib_op == `OP_LOAD) || (ib_op == `OP_STORE);

    // Accumulator value the next instruction will see (forwarded from a
    // retiring instruction in the same edge)
    reg [`DATA_WIDTH-1:0] acc_next;
    always @(*) begin
        acc_next = acc;
        if (ex_done) begin
            case (ex_op)
                `OP_LOAD: acc_next = d_rdata;
                `OP_ALU:  acc_next = acc + 32'd1;
                default:  acc_next = acc;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc             <= RESET_PC;
            f_busy         <= 1'b0;
            fetched        <= 32'd0;
            ib_valid       <= 1'b0;
            ib             <= {`DATA_WIDTH{1'b0}};
            ex_valid       <= 1'b0;
            ex_op          <= `OP_NOP;
            d_busy         <= 1'b0;
            d_we           <= 1'b0;
            d_addr         <= {`ADDR_WIDTH{1'b0}};
            d_wdata        <= {`DATA_WIDTH{1'b0}};
            halted         <= 1'b0;
            acc            <= ACC_INIT;
            cycle_count    <= 32'd0;
            retired        <= 32'd0;
            load_count     <= 32'd0;
            store_count    <= 32'd0;
            alu_count      <= 32'd0;
            nop_count      <= 32'd0;
            data_cycles    <= 32'd0;
            starve_cycles  <= 32'd0;
            overlap_cycles <= 32'd0;
        end else if (!halted) begin
            // ---------------- counters ----------------
            cycle_count <= cycle_count + 32'd1;
            if (d_busy)           data_cycles    <= data_cycles + 32'd1;
            if (!ex_valid)        starve_cycles  <= starve_cycles + 32'd1;
            if (f_busy && d_busy) overlap_cycles <= overlap_cycles + 32'd1;

            // ---------------- EXECUTE: retire ---------
            acc <= acc_next;
            if (ex_done) begin
                retired <= retired + 32'd1;
                case (ex_op)
                    `OP_LOAD:  load_count  <= load_count  + 32'd1;
                    `OP_STORE: store_count <= store_count + 32'd1;
                    `OP_ALU:   alu_count   <= alu_count   + 32'd1;
                    default:   nop_count   <= nop_count   + 32'd1;
                endcase
                if (ex_is_mem) d_busy <= 1'b0;
                if (retired + 32'd1 == MAX_INSTR) halted <= 1'b1;
            end

            // ---------------- EXECUTE: issue ----------
            if (take) begin
                ex_valid <= 1'b1;
                ex_op    <= ib_op;
                if (ib_mem) begin
                    d_busy  <= 1'b1;
                    d_we    <= (ib_op == `OP_STORE);
                    d_addr  <= {4'b0000, ib[27:0]};
                    d_wdata <= acc_next;
                end
            end else if (ex_done) begin
                ex_valid <= 1'b0;
            end

            // ---------------- FETCH -------------------
            if (f_busy && if_ready) begin
                ib       <= if_rdata;
                ib_valid <= 1'b1;
                f_busy   <= 1'b0;
                pc       <= pc + 32'd4;
            end else begin
                if (take) ib_valid <= 1'b0;
                if (!f_busy && (!ib_valid || take) && fetched < MAX_INSTR) begin
                    f_busy  <= 1'b1;
                    fetched <= fetched + 32'd1;
                end
            end
        end
    end

endmodule
