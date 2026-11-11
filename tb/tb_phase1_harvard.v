`timescale 1ns / 1ps
`include "defines.vh"
module tb_phase1_harvard;
    reg clk; reg rst_n; reg stall; reg branch_en;
    reg [31:0] branch_addr; wire [31:0] pc_out;
    reg imem_en; wire [31:0] i_rdata; wire i_ready;
    integer errors = 0;
    program_counter u_pc (.clk(clk), .rst_n(rst_n), .stall(stall), .branch_en(branch_en), .branch_addr(branch_addr), .pc_out(pc_out));
    instruction_memory #(.MEM_INIT_FILE("programs/test_program.hex")) u_imem (.clk(clk), .imem_en(imem_en), .i_addr(pc_out), .i_rdata(i_rdata), .i_ready(i_ready));
    always #5 clk = ~clk;
    initial begin
        $dumpfile("sim/phase1_fetch.vcd"); $dumpvars(0, tb_phase1_harvard);
        $timeformat(-9, 0, " ns", 8);
        $monitor("Time=%t | PC=0x%08h | Stall=%b | Instr=0x%08h | Ready=%b", $time, pc_out, stall, i_rdata, i_ready);
        clk = 0; rst_n = 0; stall = 0; branch_en = 0; branch_addr = 0; imem_en = 0;
        #10 rst_n = 1; imem_en = 1;
        #40 stall = 1;
        #6; if (pc_out !== 32'h0000_0010) begin errors = errors + 1; $display("FAIL stall: PC=%08h", pc_out); end
        #4 stall = 0;
        #20 branch_en = 1; branch_addr = 32'h0000_0004;
        #6; if (pc_out !== 32'h0000_0004) begin errors = errors + 1; $display("FAIL branch: PC=%08h", pc_out); end
        #4 branch_en = 0;
        #20;
        if (errors == 0) $display("ALL TESTS PASSED (Phase 1 Instruction Fetch Verification)");
        else $fatal(1, "TESTS FAILED with %0d errors", errors);
        $finish;
    end
endmodule
