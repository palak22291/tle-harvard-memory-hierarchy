`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_harvard_top.v  –  Phase I Top Integration Testbench
//
// Instantiates harvard_top and exercises the complete Harvard memory hierarchy:
//   · Sequential instruction fetch via PC + IMEM
//   · DMEM write / read-back through address decoder + rw_control
//   · L2   write / read-back through address decoder + rw_control
//   · Simultaneous IMEM fetch + DMEM access (key Harvard advantage)
//   · Invalid / unmapped address flagged by decoder
//   · Branch and stall interaction with the PC
// =============================================================================

module tb_harvard_top;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg                    clk, rst_n;

    // Instruction path
    reg                    imem_en;
    reg                    branch_en;
    reg  [`ADDR_WIDTH-1:0] branch_addr;
    wire [`ADDR_WIDTH-1:0] pc_out;
    wire [`DATA_WIDTH-1:0] i_rdata;
    wire                   i_ready;

    // Data path
    reg                    req;
    reg                    we;
    reg  [3:0]             d_be;
    reg  [`ADDR_WIDTH-1:0] d_addr;
    reg  [`DATA_WIDTH-1:0] d_wdata;
    wire [`DATA_WIDTH-1:0] d_rdata;
    wire                   d_ready;
    wire                   invalid_addr_err;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    harvard_top #(
        .IMEM_INIT_FILE("programs/test_program.hex"),
        .DMEM_INIT_FILE(""),
        .L2_INIT_FILE  ("")
    ) u_top (
        .clk             (clk),
        .rst_n           (rst_n),
        .imem_en         (imem_en),
        .branch_en       (branch_en),
        .branch_addr     (branch_addr),
        .pc_out          (pc_out),
        .i_rdata         (i_rdata),
        .i_ready         (i_ready),
        .req             (req),
        .we              (we),
        .d_be            (d_be),
        .d_addr          (d_addr),
        .d_wdata         (d_wdata),
        .d_rdata         (d_rdata),
        .d_ready         (d_ready),
        .invalid_addr_err(invalid_addr_err)
    );

    // -------------------------------------------------------------------------
    // Clock  100 MHz
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Self-checking helpers
    // -------------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;

    task check;
        input [255:0] label;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s : got=0x%08h  exp=0x%08h  t=%0t",
                         label, got, exp, $time);
            end
        end
    endtask

    // Drive data-path request on the falling edge (stable before rising sample)
    task data_write;
        input [`ADDR_WIDTH-1:0] addr;
        input [`DATA_WIDTH-1:0] data;
        input [3:0]             be;
        begin
            @(negedge clk);
            req = 1; we = 1; d_be = be; d_addr = addr; d_wdata = data;
            @(posedge clk); #1;   // IDLE → ACTIVE
            @(posedge clk); #1;   // ACTIVE → IDLE  (memory write + d_ready)
            check("write d_ready", d_ready, 1);
            @(negedge clk); req = 0; we = 0;
        end
    endtask

    task data_read;
        input  [`ADDR_WIDTH-1:0] addr;
        output [`DATA_WIDTH-1:0] got;
        begin
            @(negedge clk);
            req = 1; we = 0; d_be = 4'b0; d_addr = addr;
            @(posedge clk); #1;
            @(posedge clk); #1;
            check("read d_ready", d_ready, 1);
            got = d_rdata;
            @(negedge clk); req = 0;
        end
    endtask

    task data_err;
        input [`ADDR_WIDTH-1:0] addr;
        begin
            @(negedge clk);
            req = 1; we = 0; d_be = 4'b0; d_addr = addr;
            @(posedge clk); #1;
            @(posedge clk); #1;
            check("err d_ready",    d_ready,          1);
            check("err addr_err",   invalid_addr_err, 1);
            @(negedge clk); req = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [`DATA_WIDTH-1:0] rd;

    initial begin
        $dumpfile("sim/harvard_top.vcd");
        $dumpvars(0, tb_harvard_top);
        $timeformat(-9, 0, " ns", 8);

        // Initialise
        clk = 0; rst_n = 0;
        imem_en = 0; branch_en = 0; branch_addr = 0;
        req = 0; we = 0; d_be = 0; d_addr = 0; d_wdata = 0;

        // ---- T1: Reset asserted – PC at 0, no enables -----------------------
        $display("T1  reset: PC=0, no fetch, no data access");
        @(posedge clk); #1;
        check("T1 pc_out",  pc_out,  32'h0000_0000);
        check("T1 i_ready", i_ready, 1'b0);
        check("T1 d_ready", d_ready, 1'b0);

        // ---- T2: Release reset, enable IMEM, sequential fetch ---------------
        $display("T2  sequential instruction fetch");
        @(negedge clk); rst_n = 1; imem_en = 1;
        @(posedge clk); #1;
        check("T2 PC after rst",   pc_out,  32'h0000_0004);
        check("T2 i_ready",        i_ready, 1'b1);

        @(posedge clk); #1;
        check("T2 PC seq+1",       pc_out,  32'h0000_0008);

        @(posedge clk); #1;
        check("T2 PC seq+2",       pc_out,  32'h0000_000C);

        // ---- T3: DMEM write then read-back ----------------------------------
        $display("T3  DMEM write 0x0000_0000 <- 0xDEAD_BEEF");
        data_write(32'h0000_0000, 32'hDEAD_BEEF, 4'b1111);
        $display("T3  DMEM read  0x0000_0000");
        data_read(32'h0000_0000, rd);
        check("T3 dmem rdata", rd, 32'hDEAD_BEEF);

        // ---- T4: L2 write then read-back ------------------------------------
        $display("T4  L2 write 0x0000_0800 <- 0xCAFE_F00D");
        data_write(32'h0000_0800, 32'hCAFE_F00D, 4'b1111);
        $display("T4  L2 read  0x0000_0800");
        data_read(32'h0000_0800, rd);
        check("T4 l2 rdata", rd, 32'hCAFE_F00D);

        // ---- T5: Unmapped address -------------------------------------------
        $display("T5  unmapped 0x0000_0500 -> invalid_addr_err");
        data_err(32'h0000_0500);

        // ---- T6: Branch jump ------------------------------------------------
        $display("T6  branch to 0x0000_0004");
        @(negedge clk);
        branch_en = 1; branch_addr = 32'h0000_0004;
        @(posedge clk); #1;
        check("T6 PC after branch", pc_out, 32'h0000_0004);
        @(negedge clk); branch_en = 0;

        // ---- T7: DMEM boundary word -----------------------------------------
        $display("T7  DMEM boundary 0x0000_03FC <- 0xBEEF_CAFE");
        data_write(32'h0000_03FC, 32'hBEEF_CAFE, 4'b1111);
        data_read (32'h0000_03FC, rd);
        check("T7 dmem boundary", rd, 32'hBEEF_CAFE);

        // ---- T8: L2 boundary word -------------------------------------------
        $display("T8  L2 boundary 0x0000_0FFC <- 0x1234_5678");
        data_write(32'h0000_0FFC, 32'h1234_5678, 4'b1111);
        data_read (32'h0000_0FFC, rd);
        check("T8 l2 boundary", rd, 32'h1234_5678);

        // ---- T9: Byte-lane write (DMEM) -------------------------------------
        $display("T9  DMEM byte-lane: byte0 of 0x0000_0000 <- 0x42");
        data_write(32'h0000_0000, 32'h0000_0042, 4'b0001);
        data_read (32'h0000_0000, rd);
        check("T9 byte0", rd, 32'hDEAD_BE42);

        // ---- Results --------------------------------------------------------
        $display("");
        $display("tb_harvard_top: %0d checks, %0d errors", checks, errors);
        if (errors == 0)
            $display("tb_harvard_top: ALL TESTS PASSED (Phase I Integration)");
        else
            $fatal(1, "tb_harvard_top: TESTS FAILED");
        $finish;
    end

    // Safety timeout
    initial begin
        #10_000_000;
        $fatal(1, "tb_harvard_top: TIMEOUT");
    end

endmodule
