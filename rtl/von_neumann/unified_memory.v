`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// unified_memory.v  (Member 3 - Phase II, Von Neumann baseline)
//
// One 2048 x 32-bit (8 KB) synchronous RAM with ONE port. Instructions and
// data live in the same array and share the same address/data bus, which is
// what makes this a Von Neumann (Princeton) organization.
//
// Address map (byte addresses, word index = m_addr[12:2]):
//   0x0000_0000 - 0x0000_03FF  data, same window as the Harvard DMEM
//   0x0000_0800 - 0x0000_0FFF  data, same window as the Harvard L2
//   0x0000_1000 - 0x0000_13FF  code segment: the program is preloaded here
//                               (CODE_BASE), so a STORE to 0x000 can never
//                               overwrite an instruction
//   Addresses above 0x1FFF alias into the array (bits [31:13] are ignored).
//
// Timing (same rules as data_memory / shared_l2_memory):
//   - request accepted on the rising edge that samples m_en (1-cycle pulse)
//   - writes update the array on that edge, byte lanes picked by m_be
//   - m_ready (and m_rdata for reads) one clock after acceptance
//   - accesses to the L2 window (0x800-0xFFF) add L2_LATENCY wait states, so
//     both architectures are compared with the same memory technology for
//     the same addresses
//   - an m_en that arrives while an access is in flight is ignored
//
// No reset on the storage array (block-RAM friendly); reset clears the
// handshake outputs only.
// -----------------------------------------------------------------------------
module unified_memory #(
    parameter MEM_INIT_FILE = "",               // program image ($readmemh)
    parameter CODE_BASE     = 32'h0000_1000,    // byte address of the code segment
    parameter CODE_WORDS    = 256,              // words loaded from MEM_INIT_FILE
    parameter L2_LATENCY    = 0                 // extra wait states in the L2 window
)(
    input  wire                   clk,
    input  wire                   rst_n,        // async reset, active low (outputs only)
    input  wire                   m_en,         // request strobe from bus_arbiter
    input  wire                   m_we,         // 1 = write, 0 = read
    input  wire [3:0]             m_be,         // byte write enables
    input  wire [`ADDR_WIDTH-1:0] m_addr,       // byte address
    input  wire [`DATA_WIDTH-1:0] m_wdata,      // store data
    output reg  [`DATA_WIDTH-1:0] m_rdata,      // load / fetch data
    output reg                    m_ready       // one-cycle completion pulse
);

    localparam DEPTH = 2048;

    reg [`DATA_WIDTH-1:0] ram [0:DEPTH-1];
    wire [10:0] word_addr = m_addr[12:2];

    // Same window test the Harvard address decoder uses for L2
    wire in_l2_window = ((m_addr & `L2_MASK) == `L2_BASE_ADDR);

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            ram[i] = {`DATA_WIDTH{1'b0}};
        if (MEM_INIT_FILE != "")
            $readmemh(MEM_INIT_FILE, ram, CODE_BASE >> 2, (CODE_BASE >> 2) + CODE_WORDS - 1);
        m_rdata = {`DATA_WIDTH{1'b0}};
    end

    // wait_cnt = clocks left until m_ready (0 = idle)
    reg [7:0]             wait_cnt;
    reg                   rd_pend;
    reg [`DATA_WIDTH-1:0] rd_buf;

    wire accept = m_en && (wait_cnt == 8'd0);
    wire slow   = in_l2_window && (L2_LATENCY != 0);

    // Storage array and read data
    always @(posedge clk) begin
        if (accept) begin
            if (m_we) begin
                if (m_be[0]) ram[word_addr][7:0]   <= m_wdata[7:0];
                if (m_be[1]) ram[word_addr][15:8]  <= m_wdata[15:8];
                if (m_be[2]) ram[word_addr][23:16] <= m_wdata[23:16];
                if (m_be[3]) ram[word_addr][31:24] <= m_wdata[31:24];
            end else if (!slow) begin
                m_rdata <= ram[word_addr];          // ready next clock
            end else begin
                rd_buf  <= ram[word_addr];          // held until the wait ends
            end
        end else if (wait_cnt == 8'd1 && rd_pend) begin
            m_rdata <= rd_buf;
        end
    end

    // Handshake and wait-state counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_ready  <= 1'b0;
            wait_cnt <= 8'd0;
            rd_pend  <= 1'b0;
        end else if (accept) begin
            if (slow) begin
                m_ready  <= 1'b0;
                wait_cnt <= L2_LATENCY;
                rd_pend  <= ~m_we;
            end else begin
                m_ready  <= 1'b1;
                rd_pend  <= 1'b0;
            end
        end else if (wait_cnt != 8'd0) begin
            wait_cnt <= wait_cnt - 8'd1;
            m_ready  <= (wait_cnt == 8'd1);
        end else begin
            m_ready  <= 1'b0;
        end
    end

endmodule
