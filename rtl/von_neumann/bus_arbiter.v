`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// bus_arbiter.v  (Member 3 - Phase II, Von Neumann baseline)
//
// Shares the single port of unified_memory between two masters:
//   - the instruction-fetch master (IF)
//   - the data master (MEM: LOAD / STORE)
//
// Handshake on both master ports (same as rw_control): the master holds req
// until a one-cycle ready pulse, reads rdata in that cycle and drops req.
//
// Policy: fixed priority, data first. The data request belongs to the
// instruction that is already executing, so serving it first lets that
// instruction finish; the fetch of the next instruction waits.
//
// Structural hazard flag:
//   if_stall = 1 in every cycle where the fetch master is requesting but the
//   bus is owned by (or is being given to) the data master. These are the
//   cycles a Harvard organization would not lose, because there the fetch
//   has its own memory and bus. bus_owner shows who holds the bus.
//
// FSM: IDLE -> BUSY_I / BUSY_D -> (next grant or IDLE)
//   - a grant registers m_en for exactly one clock
//   - on m_ready the arbiter can grant the next waiting master on the same
//     edge, so back-to-back transfers lose no idle cycle
// -----------------------------------------------------------------------------
module bus_arbiter (
    input  wire                   clk,
    input  wire                   rst_n,          // async reset, active low

    // ----- instruction-fetch master -----------------------------------------
    input  wire                   if_req,
    input  wire [`ADDR_WIDTH-1:0] if_addr,
    output wire [`DATA_WIDTH-1:0] if_rdata,
    output wire                   if_ready,

    // ----- data master -------------------------------------------------------
    input  wire                   d_req,
    input  wire                   d_we,
    input  wire [3:0]             d_be,
    input  wire [`ADDR_WIDTH-1:0] d_addr,
    input  wire [`DATA_WIDTH-1:0] d_wdata,
    output wire [`DATA_WIDTH-1:0] d_rdata,
    output wire                   d_ready,

    // ----- status ------------------------------------------------------------
    output wire                   if_stall,       // fetch blocked by data (structural hazard)
    output wire [1:0]             bus_owner,      // 0 = idle, 1 = fetch, 2 = data

    // ----- unified memory port -----------------------------------------------
    output reg                    m_en,
    output reg                    m_we,
    output reg  [3:0]             m_be,
    output reg  [`ADDR_WIDTH-1:0] m_addr,
    output reg  [`DATA_WIDTH-1:0] m_wdata,
    input  wire [`DATA_WIDTH-1:0] m_rdata,
    input  wire                   m_ready
);

    localparam IDLE   = 2'd0;
    localparam BUSY_I = 2'd1;
    localparam BUSY_D = 2'd2;

    reg [1:0] state;

    // Bus is free for a new grant this edge
    wire free = (state == IDLE) || m_ready;

    // Responses go back to whoever owns the bus
    assign if_ready  = (state == BUSY_I) && m_ready;
    assign d_ready   = (state == BUSY_D) && m_ready;
    assign if_rdata  = m_rdata;
    assign d_rdata   = m_rdata;
    assign bus_owner = state;

    // Fetch is waiting because data holds the bus or wins the next grant
    assign if_stall = if_req && !if_ready &&
                      ((state == BUSY_D) || (free && d_req));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            m_en    <= 1'b0;
            m_we    <= 1'b0;
            m_be    <= 4'b0;
            m_addr  <= {`ADDR_WIDTH{1'b0}};
            m_wdata <= {`DATA_WIDTH{1'b0}};
        end else begin
            m_en <= 1'b0;                     // one-cycle strobe by default
            if (free) begin
                if (d_req) begin              // data has priority
                    state   <= BUSY_D;
                    m_en    <= 1'b1;
                    m_we    <= d_we;
                    m_be    <= d_be;
                    m_addr  <= d_addr;
                    m_wdata <= d_wdata;
                end else if (if_req) begin
                    state   <= BUSY_I;
                    m_en    <= 1'b1;
                    m_we    <= 1'b0;
                    m_be    <= 4'b0;
                    m_addr  <= if_addr;
                    m_wdata <= {`DATA_WIDTH{1'b0}};
                end else begin
                    state   <= IDLE;
                end
            end
        end
    end

endmodule
