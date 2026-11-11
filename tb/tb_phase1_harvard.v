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

    integer errors = 0;

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

    always #5 clk = ~clk; // 100 MHz clock (posedge at 5, 15, 25, ... ns)

    task automatic check_state;
        input [`ADDR_WIDTH-1:0] exp_pc;
        input [`DATA_WIDTH-1:0] exp_instr;
        input                   exp_ready;
        input [8*32-1:0]        label;
        begin
            if (pc_out !== exp_pc || i_rdata !== exp_instr || i_ready !== exp_ready) begin
                errors = errors + 1;
                $display("FAIL [%0s] @ %t: got PC=0x%08h Instr=0x%08h Ready=%b | expected PC=0x%08h Instr=0x%08h Ready=%b",
                         label, $time, pc_out, i_rdata, i_ready, exp_pc, exp_instr, exp_ready);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/phase1_fetch.vcd");
        $dumpvars(0, tb_phase1_harvard);
        $timeformat(-9, 0, " ns", 8);
        $monitor("Time=%t | PC=0x%08h | Stall=%b | Br=%b | En=%b | Instr=0x%08h | Ready=%b",
                 $time, pc_out, stall, branch_en, imem_en, i_rdata, i_ready);

        // 1. Reset & disabled IMEM check
        clk = 0; rst_n = 0; stall = 0; branch_en = 0; branch_addr = {`ADDR_WIDTH{1'b0}}; imem_en = 0;
        @(posedge clk); #1;
        check_state(32'h0000_0000, 32'h0000_0000, 1'b0, "reset_idle");

        // 2. Release reset on negedge clk and verify sequential instruction fetch
        @(negedge clk);
        rst_n = 1;
        imem_en = 1;

        @(posedge clk); #1; check_state(32'h0000_0004, 32'h1000_0004, 1'b1, "seq_0");
        @(posedge clk); #1; check_state(32'h0000_0008, 32'h2000_0008, 1'b1, "seq_1");
        @(posedge clk); #1; check_state(32'h0000_000C, 32'h3000_000C, 1'b1, "seq_2");
        @(posedge clk); #1; check_state(32'h0000_0010, 32'h1000_0010, 1'b1, "seq_3");

        // 3. Stall holds PC at 0x0000_0010 across rising edge, then resumes
        @(negedge clk);
        stall = 1;
        @(posedge clk); #1; check_state(32'h0000_0010, 32'h2000_0014, 1'b1, "stall_hold");

        @(negedge clk);
        stall = 0;
        @(posedge clk); #1; check_state(32'h0000_0014, 32'h2000_0014, 1'b1, "post_stall");
        @(posedge clk); #1; check_state(32'h0000_0018, 32'h0000_0000, 1'b1, "seq_5");

        // 4. Branch jump to 0x0000_0004 and verify subsequent instruction fetch
        @(negedge clk);
        branch_en = 1;
        branch_addr = 32'h0000_0004;
        @(posedge clk); #1; check_state(32'h0000_0004, 32'h0000_0000, 1'b1, "branch_jump");

        @(negedge clk);
        branch_en = 0;
        @(posedge clk); #1; check_state(32'h0000_0008, 32'h2000_0008, 1'b1, "post_branch_fetch");

        // 5. Priority check: simultaneous stall=1 and branch_en=1 must hold PC
        @(negedge clk);
        stall = 1;
        branch_en = 1;
        branch_addr = 32'h0000_0010;
        @(posedge clk); #1; check_state(32'h0000_0008, 32'h3000_000C, 1'b1, "stall_over_branch");

        // 6. Disable IMEM check: i_ready drops to 0 and i_rdata clears to 0
        @(negedge clk);
        stall = 0;
        branch_en = 0;
        imem_en = 0;
        @(posedge clk); #1; check_state(32'h0000_000C, 32'h0000_0000, 1'b0, "imem_disabled");

        // 7. Asynchronous reset check mid-execution
        @(negedge clk);
        rst_n = 0;
        #1;
        if (pc_out !== 32'h0000_0000) begin
            errors = errors + 1;
            $display("FAIL [async_reset] @ %t: got PC=0x%08h | expected 0x00000000", $time, pc_out);
        end

        if (errors == 0) begin
            $display("ALL TESTS PASSED (Phase 1 Instruction Fetch Verification)");
        end else begin
            $fatal(1, "TESTS FAILED with %0d errors", errors);
        end
        $finish;
    end

endmodule
