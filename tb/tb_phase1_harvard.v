`timescale 1ns / 1ps
`include "defines.vh"

module tb_phase1_harvard;

    reg                   clk;
    reg                   rst_n;
    reg                   stall;
    reg                   branch_en;
    reg [`ADDR_WIDTH-1:0] branch_addr;
    wire [`ADDR_WIDTH-1:0] pc_out;

    reg                   imem_en;
    wire [`DATA_WIDTH-1:0] i_rdata;
    wire                  i_ready;

    program_counter u_pc (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .branch_en(branch_en),
        .branch_addr(branch_addr),
        .pc_out(pc_out)
    );

    instruction_memory #(
        .MEM_INIT_FILE("programs/test_program.hex")
    ) u_imem (
        .clk(clk),
        .imem_en(imem_en),
        .i_addr(pc_out),
        .i_rdata(i_rdata),
        .i_ready(i_ready)
    );

    always #5 clk = ~clk; // 100 MHz clock

    initial begin
        $dumpfile("sim/phase1_fetch.vcd");
        $dumpvars(0, tb_phase1_harvard);
        $monitor("Time=%0t ns | PC=0x%08h | Stall=%b | Instr=0x%08h | Ready=%b", 
                 $time, pc_out, stall, i_rdata, i_ready);

        clk = 0; rst_n = 0; stall = 0; branch_en = 0; branch_addr = 32'h0; imem_en = 0;

        #15 rst_n = 1; imem_en = 1;
        #40 stall = 1; // Demonstrate stall holding PC
        #10 stall = 0;
        #20 branch_en = 1; branch_addr = 32'h0000_0004; // Demonstrate branch jump
        #10 branch_en = 0;
        #20 $display("Phase 1 Instruction Path Verification Complete.");
        $finish;
    end

endmodule
