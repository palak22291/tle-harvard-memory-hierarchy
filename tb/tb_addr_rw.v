`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// tb_addr_rw.v  – Self-checking testbench for:
//     address_decoder.v  +  rw_control.v  +  shared_l2_memory.v
//     (integrates with the existing data_memory.v)
//
// Tests:
//   T1  Reset / idle – no spurious enables
//   T2  DMEM write  (0x0000_0000, full-word)
//   T3  DMEM read   (0x0000_0000)
//   T4  DMEM byte-lane write then read
//   T5  L2 write    (0x0000_0800, full-word)
//   T6  L2 read     (0x0000_0800)
//   T7  L2 boundary word (0x0000_0FFC)
//   T8  Unmapped address → invalid_addr_err, no memory enable
//   T9  DMEM upper boundary (0x0000_03FC)
//   T10 Back-to-back alternating DMEM / L2 accesses
// -----------------------------------------------------------------------------
module tb_addr_rw;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                    clk, rst_n;

    // CPU side
    reg                    req, we;
    reg  [3:0]             d_be;
    reg  [`ADDR_WIDTH-1:0] d_addr;
    reg  [`DATA_WIDTH-1:0] d_wdata;
    wire [`DATA_WIDTH-1:0] d_rdata;
    wire                   d_ready;
    wire                   invalid_addr_err;

    // address_decoder ↔ rw_control
    wire                   d_valid;
    wire                   cs_dmem, cs_l2, addr_err_in;

    // DMEM port
    wire                   dmem_en, dmem_we;
    wire [3:0]             dmem_be;
    wire [`ADDR_WIDTH-1:0] dmem_addr;
    wire [`DATA_WIDTH-1:0] dmem_wdata, dmem_rdata;
    wire                   dmem_ready;

    // L2 port
    wire                   l2_en, l2_we;
    wire [3:0]             l2_be;
    wire [`ADDR_WIDTH-1:0] l2_addr;
    wire [`DATA_WIDTH-1:0] l2_wdata, l2_rdata;
    wire                   l2_ready;

    // -------------------------------------------------------------------------
    // Instantiations
    // -------------------------------------------------------------------------
    address_decoder u_dec (
        .d_addr         (d_valid ? d_addr : {`ADDR_WIDTH{1'b0}}),
        .d_valid        (d_valid),
        .cs_dmem        (cs_dmem),
        .cs_l2          (cs_l2),
        .invalid_addr_err (addr_err_in)
    );

    rw_control u_rwc (
        .clk            (clk),
        .rst_n          (rst_n),
        .req            (req),
        .we             (we),
        .d_be           (d_be),
        .d_addr         (d_addr),
        .d_wdata        (d_wdata),
        .d_rdata        (d_rdata),
        .d_ready        (d_ready),
        .invalid_addr_err (invalid_addr_err),
        .d_valid        (d_valid),
        .cs_dmem        (cs_dmem),
        .cs_l2          (cs_l2),
        .addr_err_in    (addr_err_in),
        .dmem_en        (dmem_en),  .dmem_we  (dmem_we),
        .dmem_be        (dmem_be),  .dmem_addr (dmem_addr),
        .dmem_wdata     (dmem_wdata), .dmem_rdata (dmem_rdata),
        .dmem_ready     (dmem_ready),
        .l2_en          (l2_en),    .l2_we    (l2_we),
        .l2_be          (l2_be),    .l2_addr   (l2_addr),
        .l2_wdata       (l2_wdata), .l2_rdata  (l2_rdata),
        .l2_ready       (l2_ready)
    );

    data_memory u_dmem (
        .clk        (clk),    .rst_n    (rst_n),
        .dmem_en    (dmem_en), .dmem_we (dmem_we),
        .d_be       (dmem_be), .d_addr  (dmem_addr),
        .d_wdata    (dmem_wdata), .d_rdata (dmem_rdata),
        .d_ready    (dmem_ready)
    );

    shared_l2_memory u_l2 (
        .clk        (clk),    .rst_n   (rst_n),
        .l2_en      (l2_en),  .l2_we   (l2_we),
        .l2_be      (l2_be),  .l2_addr (l2_addr),
        .l2_wdata   (l2_wdata), .l2_rdata (l2_rdata),
        .l2_ready   (l2_ready)
    );

    // -------------------------------------------------------------------------
    // Clock: 100 MHz
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Check infrastructure
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
                $display("  FAIL %0s : got 0x%08h, expected 0x%08h (t=%0t)",
                         label, got, exp, $time);
            end
        end
    endtask

    // Drive a request on the FALLING edge so it is stable at the next RISING edge.
    task do_write;
        input [`ADDR_WIDTH-1:0] addr;
        input [`DATA_WIDTH-1:0] data;
        input [3:0]             be;
        begin
            @(negedge clk);
            req = 1; we = 1; d_be = be; d_addr = addr; d_wdata = data;
            @(posedge clk); #1;         // ACTIVE state: decoder resolves
            @(posedge clk); #1;         // Memory write + d_ready
            check("write d_ready", d_ready, 1);
            @(negedge clk);
            req = 0; we = 0;
        end
    endtask

    task do_read;
        input [`ADDR_WIDTH-1:0] addr;
        output [`DATA_WIDTH-1:0] got;
        begin
            @(negedge clk);
            req = 1; we = 0; d_be = 4'b0; d_addr = addr;
            @(posedge clk); #1;         // ACTIVE
            @(posedge clk); #1;         // Memory read + d_ready
            check("read d_ready", d_ready, 1);
            got = d_rdata;
            @(negedge clk);
            req = 0;
        end
    endtask

    task do_err;
        input [`ADDR_WIDTH-1:0] addr;
        begin
            @(negedge clk);
            req = 1; we = 0; d_be = 4'b0; d_addr = addr;
            @(posedge clk); #1;         // ACTIVE
            @(posedge clk); #1;         // ERR + d_ready
            check("err d_ready",         d_ready,          1);
            check("err invalid_addr_err", invalid_addr_err, 1);
            @(negedge clk);
            req = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [`DATA_WIDTH-1:0] rd;

    initial begin
        $dumpfile("sim/addr_rw.vcd");
        $dumpvars(0, tb_addr_rw);

        clk = 0; rst_n = 0; req = 0; we = 0; d_be = 0; d_addr = 0; d_wdata = 0;
        @(posedge clk); #1;

        // T1 – reset / idle
        $display("T1  reset: d_ready=0, no enables");
        check("T1 d_ready",  d_ready,  0);
        check("T1 dmem_en",  dmem_en,  0);
        check("T1 l2_en",    l2_en,    0);
        @(negedge clk); rst_n = 1;

        // T2 – DMEM write
        $display("T2  DMEM full-word write  0x0000_0000 ← 0xDEAD_BEEF");
        do_write(32'h0000_0000, 32'hDEAD_BEEF, 4'b1111);

        // T3 – DMEM read back
        $display("T3  DMEM read  0x0000_0000");
        do_read(32'h0000_0000, rd);
        check("T3 rdata", rd, 32'hDEAD_BEEF);

        // T4 – DMEM byte-lane write
        $display("T4  DMEM byte-lane write  byte0 ← 0x42");
        do_write(32'h0000_0000, 32'h0000_0042, 4'b0001);
        do_read (32'h0000_0000, rd);
        check("T4 byte0", rd, 32'hDEAD_BE42);

        // T5 – L2 write
        $display("T5  L2 full-word write  0x0000_0800 ← 0xCAFE_F00D");
        do_write(32'h0000_0800, 32'hCAFE_F00D, 4'b1111);

        // T6 – L2 read back
        $display("T6  L2 read  0x0000_0800");
        do_read(32'h0000_0800, rd);
        check("T6 rdata", rd, 32'hCAFE_F00D);

        // T7 – L2 boundary word
        $display("T7  L2 boundary 0x0000_0FFC ← 0x1234_5678");
        do_write(32'h0000_0FFC, 32'h1234_5678, 4'b1111);
        do_read (32'h0000_0FFC, rd);
        check("T7 rdata", rd, 32'h1234_5678);

        // T8 – Unmapped address
        $display("T8  unmapped 0x0000_0500 → invalid_addr_err");
        do_err(32'h0000_0500);

        // T9 – DMEM upper boundary
        $display("T9  DMEM boundary 0x0000_03FC ← 0xBEEF_CAFE");
        do_write(32'h0000_03FC, 32'hBEEF_CAFE, 4'b1111);
        do_read (32'h0000_03FC, rd);
        check("T9 rdata", rd, 32'hBEEF_CAFE);

        // T10 – Alternating DMEM / L2
        $display("T10 alternating DMEM/L2 accesses");
        do_write(32'h0000_0004, 32'hAAAA_AAAA, 4'b1111);
        do_write(32'h0000_0804, 32'hBBBB_BBBB, 4'b1111);
        do_read (32'h0000_0004, rd);  check("T10 dmem", rd, 32'hAAAA_AAAA);
        do_read (32'h0000_0804, rd);  check("T10 l2",   rd, 32'hBBBB_BBBB);

        // ---- Results --------------------------------------------------------
        $display("");
        $display("tb_addr_rw: %0d checks, %0d errors", checks, errors);
        if (errors == 0)
            $display("tb_addr_rw: ALL TESTS PASSED");
        else
            $fatal(1, "tb_addr_rw: TESTS FAILED");
        $finish;
    end

    // Safety timeout
    initial begin
        #5_000_000;
        $fatal(1, "tb_addr_rw: TIMEOUT");
    end

endmodule

