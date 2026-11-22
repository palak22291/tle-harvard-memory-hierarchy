`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_architecture_comparison.v  (Member 4 - Phase II)
//
// Runs programs/benchmark_suite.hex on the Harvard system (harvard_cpu_top)
// and on the Von Neumann baseline (von_neumann_top) side by side, with the
// same CPU driver, for three L2 latency settings (0, 2, 4 wait states).
//
// Correctness (self-checking):
//   C1  both systems halt and retire exactly N_INSTR instructions
//   C2  instruction mix (LOAD / STORE / ALU / NOP) matches the program
//   C3  final accumulator is identical in both systems and equals a
//       reference model that interprets the same hex file
//   C4  final contents of all 256 DMEM words and all 512 L2 words are
//       identical in both systems and match the reference model
//   C5  no unmapped-address error during the run
//   C6  the Harvard run really overlaps fetch with data access
//       (overlap_cycles > 0) and the Von Neumann run really has structural
//       hazards (if_stall cycles > 0)
//
// Performance (reported, not asserted): total cycles, CPI, IPC, stall
// cycles and speedup, printed as a table and written to
// sim/arch_comparison.csv. The waveform is in sim/arch_comparison.vcd.
// =============================================================================

module tb_architecture_comparison;

    localparam N_INSTR   = 16;
    localparam CODE_BASE = 32'h0000_1000;
    localparam ACC_INIT  = 32'hCAFE_0000;     // simple_cpu_driver default
    localparam PROGRAM   = "programs/benchmark_suite.hex";

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

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
                $display("  FAIL %0s : got 0x%08h (%0d), expected 0x%08h (%0d)",
                         label, got, got, exp, exp);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Three Harvard / Von Neumann pairs, L2_LATENCY = 0, 2, 4
    // -------------------------------------------------------------------------
    wire        h_halted [0:2], v_halted [0:2];
    wire [31:0] h_acc [0:2], v_acc [0:2];
    wire [31:0] h_cyc [0:2], v_cyc [0:2];
    wire [31:0] h_ret [0:2], v_ret [0:2];
    wire [31:0] h_ld  [0:2], v_ld  [0:2];
    wire [31:0] h_st  [0:2], v_st  [0:2];
    wire [31:0] h_alu [0:2], v_alu [0:2];
    wire [31:0] h_nop [0:2], v_nop [0:2];
    wire [31:0] h_dcy [0:2], v_dcy [0:2];
    wire [31:0] h_stv [0:2], v_stv [0:2];
    wire [31:0] h_ovl [0:2], v_ovl [0:2];
    wire        h_err [0:2];
    wire        v_if_stall [0:2];

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : pair
            localparam LAT = 2 * g;
            wire hh, vh, he, vs;
            wire [31:0] ha, va, hc, vc, hr, vr, hl, vl, hs, vss, hal, val, hn, vn,
                        hd, vd, hst, vst, ho, vo;
            wire h_if_req, h_if_rdy, h_d_req, h_d_rdy;
            wire v_if_req, v_if_rdy, v_d_req, v_d_rdy;

            harvard_cpu_top #(
                .IMEM_INIT_FILE(PROGRAM), .MAX_INSTR(N_INSTR), .L2_LATENCY(LAT)
            ) u_h (
                .clk(clk), .rst_n(rst_n),
                .halted(hh), .acc(ha), .cycle_count(hc), .retired(hr),
                .load_count(hl), .store_count(hs), .alu_count(hal), .nop_count(hn),
                .data_cycles(hd), .starve_cycles(hst), .overlap_cycles(ho),
                .invalid_addr_err(he),
                .if_req(h_if_req), .if_ready(h_if_rdy), .d_req(h_d_req), .d_ready(h_d_rdy));

            von_neumann_top #(
                .MEM_INIT_FILE(PROGRAM), .CODE_BASE(CODE_BASE),
                .MAX_INSTR(N_INSTR), .L2_LATENCY(LAT)
            ) u_v (
                .clk(clk), .rst_n(rst_n),
                .halted(vh), .acc(va), .cycle_count(vc), .retired(vr),
                .load_count(vl), .store_count(vss), .alu_count(val), .nop_count(vn),
                .data_cycles(vd), .starve_cycles(vst), .overlap_cycles(vo),
                .if_stall(vs),
                .if_req(v_if_req), .if_ready(v_if_rdy), .d_req(v_d_req), .d_ready(v_d_rdy));

            // count Von Neumann structural-hazard stall cycles until halt
            integer vn_stalls = 0;
            always @(posedge clk) if (rst_n && !vh && vs) vn_stalls = vn_stalls + 1;

            // sticky unmapped-address flag
            reg h_err_seen = 0;
            always @(posedge clk) if (he) h_err_seen = 1;

            assign h_halted[g] = hh;  assign v_halted[g] = vh;
            assign h_acc[g] = ha;     assign v_acc[g] = va;
            assign h_cyc[g] = hc;     assign v_cyc[g] = vc;
            assign h_ret[g] = hr;     assign v_ret[g] = vr;
            assign h_ld[g]  = hl;     assign v_ld[g]  = vl;
            assign h_st[g]  = hs;     assign v_st[g]  = vss;
            assign h_alu[g] = hal;    assign v_alu[g] = val;
            assign h_nop[g] = hn;     assign v_nop[g] = vn;
            assign h_dcy[g] = hd;     assign v_dcy[g] = vd;
            assign h_stv[g] = hst;    assign v_stv[g] = vst;
            assign h_ovl[g] = ho;     assign v_ovl[g] = vo;
            assign h_err[g] = h_err_seen;
            assign v_if_stall[g] = vs;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Reference model: interpret the program with the driver's semantics
    // -------------------------------------------------------------------------
    reg [31:0] prog [0:255];
    reg [31:0] ref_dmem [0:255];
    reg [31:0] ref_l2   [0:511];
    reg [31:0] ref_acc;
    integer    ref_ld, ref_st, ref_alu, ref_nop;

    task run_reference;
        integer pc;
        reg [31:0] ins, a;
        begin
            ref_acc = ACC_INIT;
            ref_ld = 0; ref_st = 0; ref_alu = 0; ref_nop = 0;
            for (pc = 0; pc < 256; pc = pc + 1) ref_dmem[pc] = 0;
            for (pc = 0; pc < 512; pc = pc + 1) ref_l2[pc]   = 0;
            for (pc = 0; pc < N_INSTR; pc = pc + 1) begin
                ins = prog[pc];
                a   = {4'b0, ins[27:0]};
                case (ins[31:28])
                    `OP_LOAD: begin
                        ref_ld = ref_ld + 1;
                        if ((a & `L2_MASK) == `L2_BASE_ADDR) ref_acc = ref_l2[a[10:2]];
                        else                                 ref_acc = ref_dmem[a[9:2]];
                    end
                    `OP_STORE: begin
                        ref_st = ref_st + 1;
                        if ((a & `L2_MASK) == `L2_BASE_ADDR) ref_l2[a[10:2]] = ref_acc;
                        else                                 ref_dmem[a[9:2]] = ref_acc;
                    end
                    `OP_ALU: begin
                        ref_alu = ref_alu + 1;
                        ref_acc = ref_acc + 1;
                    end
                    default: ref_nop = ref_nop + 1;
                endcase
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Hierarchical access to the final memory contents of each pair
    // -------------------------------------------------------------------------
    function [31:0] h_dmem_word; input integer p; input integer i;
        case (p)
            0: h_dmem_word = pair[0].u_h.u_dmem.ram[i];
            1: h_dmem_word = pair[1].u_h.u_dmem.ram[i];
            default: h_dmem_word = pair[2].u_h.u_dmem.ram[i];
        endcase
    endfunction
    function [31:0] h_l2_word; input integer p; input integer i;
        case (p)
            0: h_l2_word = pair[0].u_h.u_l2.ram[i];
            1: h_l2_word = pair[1].u_h.u_l2.ram[i];
            default: h_l2_word = pair[2].u_h.u_l2.ram[i];
        endcase
    endfunction
    function [31:0] v_word; input integer p; input integer i;
        case (p)
            0: v_word = pair[0].u_v.u_mem.ram[i];
            1: v_word = pair[1].u_v.u_mem.ram[i];
            default: v_word = pair[2].u_v.u_mem.ram[i];
        endcase
    endfunction
    function integer vn_stall_count; input integer p;
        case (p)
            0: vn_stall_count = pair[0].vn_stalls;
            1: vn_stall_count = pair[1].vn_stalls;
            default: vn_stall_count = pair[2].vn_stalls;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Stimulus and checks
    // -------------------------------------------------------------------------
    integer p, i, mem_mismatch, fd, cyc_wait;
    real h_cpi, v_cpi, speedup;

    initial begin
        $dumpfile("sim/arch_comparison.vcd");
        $dumpvars(0, tb_architecture_comparison);

        $readmemh(PROGRAM, prog);
        run_reference;

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;

        // wait until all six systems have halted (or time out)
        cyc_wait = 0;
        while (!(h_halted[0] && v_halted[0] && h_halted[1] && v_halted[1] &&
                 h_halted[2] && v_halted[2]) && cyc_wait < 2000) begin
            @(posedge clk); cyc_wait = cyc_wait + 1;
        end
        repeat (2) @(posedge clk); #1;

        for (p = 0; p < 3; p = p + 1) begin
            // C1
            check("C1 Harvard halted",       h_halted[p], 1);
            check("C1 VonNeumann halted",    v_halted[p], 1);
            check("C1 Harvard retired",      h_ret[p], N_INSTR);
            check("C1 VonNeumann retired",   v_ret[p], N_INSTR);
            // C2
            check("C2 H loads",   h_ld[p],  ref_ld);   check("C2 V loads",   v_ld[p],  ref_ld);
            check("C2 H stores",  h_st[p],  ref_st);   check("C2 V stores",  v_st[p],  ref_st);
            check("C2 H alu",     h_alu[p], ref_alu);  check("C2 V alu",     v_alu[p], ref_alu);
            check("C2 H nop",     h_nop[p], ref_nop);  check("C2 V nop",     v_nop[p], ref_nop);
            // C3
            check("C3 H acc vs model",  h_acc[p], ref_acc);
            check("C3 V acc vs model",  v_acc[p], ref_acc);
            check("C3 H acc == V acc",  h_acc[p], v_acc[p]);
            // C4
            mem_mismatch = 0;
            for (i = 0; i < 256; i = i + 1) begin
                if (h_dmem_word(p, i) !== ref_dmem[i]) mem_mismatch = mem_mismatch + 1;
                if (v_word(p, i)      !== ref_dmem[i]) mem_mismatch = mem_mismatch + 1;
            end
            for (i = 0; i < 512; i = i + 1) begin
                if (h_l2_word(p, i)    !== ref_l2[i]) mem_mismatch = mem_mismatch + 1;
                if (v_word(p, 512 + i) !== ref_l2[i]) mem_mismatch = mem_mismatch + 1;
            end
            check("C4 DMEM+L2 words vs model", mem_mismatch, 0);
            // C5
            check("C5 no unmapped-address error", h_err[p], 0);
            // C6
            check("C6 Harvard overlaps fetch and data", (h_ovl[p] > 0), 1);
            check("C6 Von Neumann has structural stalls", (vn_stall_count(p) > 0), 1);
        end

        // ---------------- performance report ----------------
        fd = $fopen("sim/arch_comparison.csv", "w");
        $fdisplay(fd, "l2_latency,arch,instructions,cycles,cpi,data_cycles,starve_cycles,overlap_cycles,if_stall_cycles");
        $display("");
        $display("  Benchmark: %0s, %0d instructions (%0d LOAD, %0d STORE, %0d ALU, %0d NOP)",
                 PROGRAM, N_INSTR, ref_ld, ref_st, ref_alu, ref_nop);
        $display("");
        $display("  L2 lat | Arch        | Cycles |  CPI  |  IPC  | Data cyc | Starve cyc | IF+MEM overlap | IF stall | Speedup");
        $display("  -------+-------------+--------+-------+-------+----------+------------+----------------+----------+--------");
        for (p = 0; p < 3; p = p + 1) begin
            h_cpi   = h_cyc[p] * 1.0 / N_INSTR;
            v_cpi   = v_cyc[p] * 1.0 / N_INSTR;
            speedup = v_cyc[p] * 1.0 / h_cyc[p];
            $display("  %6d | Harvard     | %6d | %5.3f | %5.3f | %8d | %10d | %14d | %8d |",
                     2*p, h_cyc[p], h_cpi, 1.0/h_cpi, h_dcy[p], h_stv[p], h_ovl[p], 0);
            $display("  %6d | Von Neumann | %6d | %5.3f | %5.3f | %8d | %10d | %14d | %8d | %5.3fx",
                     2*p, v_cyc[p], v_cpi, 1.0/v_cpi, v_dcy[p], v_stv[p], v_ovl[p],
                     vn_stall_count(p), speedup);
            $fdisplay(fd, "%0d,harvard,%0d,%0d,%0.4f,%0d,%0d,%0d,0",
                      2*p, N_INSTR, h_cyc[p], h_cpi, h_dcy[p], h_stv[p], h_ovl[p]);
            $fdisplay(fd, "%0d,von_neumann,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d",
                      2*p, N_INSTR, v_cyc[p], v_cpi, v_dcy[p], v_stv[p], v_ovl[p], vn_stall_count(p));
        end
        $fclose(fd);
        $display("");
        $display("  Final accumulator (both systems, all latencies) = 0x%08h", ref_acc);
        $display("");
        $display("tb_architecture_comparison: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("tb_architecture_comparison: ALL TESTS PASSED");
        else             $fatal(1, "tb_architecture_comparison: TESTS FAILED");
        $finish;
    end

endmodule
