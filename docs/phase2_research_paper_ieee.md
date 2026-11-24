# Design, Verification, and Quantitative Evaluation of a 32-Bit Harvard Instruction and Data Memory Hierarchy in Verilog RTL

**Authors:** Palak Gupta, Atanu Adhikari, Sambhav Kumar, and Prince Singh *(Team TLE)*  
**Course:** Modern Computer Architecture — Research Paper Report  

---

## Abstract
Memory subsystem contention remains a primary throughput bottleneck in pipelined and single-cycle reduced instruction set processors. In classical Von Neumann architectures, instructions and data share a unified address space and a single physical bus, inducing structural hazards whenever an instruction fetch (`IF`) coincides with a data memory load or store (`MEM`) transaction. This paper presents the Register-Transfer Level (RTL) design, cycle-accurate verification, and quantitative performance evaluation of a 32-bit Modified Harvard memory hierarchy implemented in Verilog-2012. The proposed architecture physically decouples the read-only Instruction Memory (`IMEM`) pathway from a two-tier Data Memory hierarchy comprising a 1 KB byte-addressable Local Data SRAM (`DMEM`) and a 2 KB Shared Lower-Level Memory (`L2`). A combinational bitmask Address Decoder and a three-state (`IDLE`/`ACTIVE`/`WAIT`) Read/Write Controller (`rw_control`) arbitrate data transactions and trap out-of-bounds memory faults via `invalid_addr_err`. A parameterized wait-state model makes the L2 tier measurably slower than `DMEM`, and a single-port Von Neumann baseline (`unified_memory`, `bus_arbiter`) is built for comparison. Seven Icarus Verilog testbenches (2,213 self-checking assertions plus 12 fetch state vectors) pass with zero errors. The same CPU driver runs a 16-instruction memory-intensive benchmark on both organizations. Both produce identical final memory and accumulator contents. The Harvard hierarchy completes the benchmark in 74 clock cycles against 90 for the Von Neumann baseline (CPI 4.625 vs. 5.625, a 1.216× speedup), because it removes all 36 structural-hazard stall cycles. The speedup falls to 1.178× when four L2 wait states are added, since both organizations pay the slower L2 equally. Synthesized with Yosys and placed and routed with nextpnr on a Lattice ECP5 LFE5U-25F FPGA, the Harvard system uses 639 logic cells, 538 flip-flops and 2 block RAMs and reaches 134.0 MHz, against 640 logic cells, 490 flip-flops, 4 block RAMs and 105.7 MHz for the baseline.

**Index Terms—** Harvard Architecture, Von Neumann Bottleneck, Memory Hierarchy, Address Decoding, Structural Hazard, Cycles Per Instruction (CPI), Verilog RTL.

---

## I. Introduction
Modern computing workloads—ranging from embedded digital signal processing to dense linear algebra—exhibit high memory access intensity. In a conventional single-bus Von Neumann processor organization, both instruction words and data operands traverse a shared physical memory interface [1]. Whenever an executing instruction performs a memory load (`LOAD`) or store (`STORE`), the data transfer monopolizes the memory bus, forcing the processor controller to stall the subsequent instruction fetch (`stall = 1`). As the fraction of memory-reference instructions increases, these structural hazard bubbles severely degrade instruction throughput and inflate Cycles Per Instruction (CPI) [2].

To overcome this limitation without duplicating high-capacity off-chip memory, contemporary microprocessors employ a Harvard or Modified Harvard memory organization at the primary hierarchy level [1], [2]. By provisioning physically independent address, data, and control buses for Instruction Memory (`IMEM`) and Data Memory (`DMEM`), the processor can fetch Instruction $N+1$ concurrently during the exact same clock cycles in which Instruction $N$ reads or writes data operands.

In this paper, we present a complete 32-bit Harvard instruction and data memory hierarchy in synthesizable Verilog RTL. The primary contributions of this work are as follows:
1. **Decoupled Instruction Fetch Engine:** A 32-bit byte-addressed Program Counter (`program_counter.v`) with prioritized hazard stall and branch target multiplexing coupled to a synchronous $256 \times 32$-bit Instruction ROM (`instruction_memory.v`).
2. **Partitioned Multi-Tier Data Hierarchy:** A combinational bitmask Address Decoder (`address_decoder.v`) and a three-state (`IDLE`/`ACTIVE`/`WAIT`) Read/Write Controller (`rw_control.v`) interfacing a 1 KB byte-addressable Local Data SRAM (`data_memory.v`) and a 2 KB Shared Lower-Level Memory (`shared_l2_memory.v`) with hardware fault trapping (`invalid_addr_err`).
3. **Self-Checking Verification & Measured CPI Evaluation:** Seven testbenches with 2,213 self-checking assertions, an L2 multi-cycle latency model, a single-port Von Neumann baseline, and a cycle-accurate comparison in which the same CPU driver runs the same program on both organizations.
4. **Synthesis and Waveform Evidence:** An open-source synthesis and place-and-route flow (`make synth`) that reports resource utilization and maximum clock frequency for both systems, and waveform figures generated directly from the simulation VCD files.

---

## II. Related Work and Theoretical Background

### A. The Von Neumann Bottleneck and Structural Hazards
Backus [3] formalized the throughput limitation of single-bus stored-program computers as the *Von Neumann bottleneck*, observing that processor execution speed is bounded by the effective bandwidth of the single channel connecting the central processing unit (CPU) and main storage. In pipelined processor datapaths, Hennessy and Patterson [1] classify simultaneous requests to a single memory port by the Instruction Fetch (`IF`) and Memory Access (`MEM`) stages as a *structural hazard*. If the memory subsystem provides only a single address/data port, the hardware arbiter must inject pipeline stall cycles:

$$\text{CPI}_{\text{unified}} = \text{CPI}_{\text{base}} + f_{\text{mem}} \times L_{\text{mem}}$$

where $f_{\text{mem}}$ denotes the fraction of instructions that access data memory and $L_{\text{mem}}$ represents the number of bus cycles consumed by each data transaction.

### B. Modified Harvard Memory Hierarchies and Address Decoding
Smith [4] demonstrated that splitting Level-1 (L1) storage into dedicated instruction and data memories eliminates port contention while permitting a unified or shared lower-level (`L2`) backing store to amortize capacity cost. Furthermore, Harris and Harris [5] establish that power-of-two bitmask decoding (`(addr & MASK) == BASE`) minimizes combinational critical-path delay in hardware address decoders by avoiding full 32-bit magnitude comparators, provided each memory region is aligned to a natural power-of-two boundary.

### C. The Shared-Bus Baseline and Bus Arbitration
The stored-program design described by von Neumann [6] keeps instructions and data in one memory reached through one path, and that organization is the baseline used for comparison in this paper. When two requesters share one memory port, an arbiter must decide who is served first. On-chip bus standards such as ARM AMBA [7] place this decision in a central arbiter that grants the bus to one master at a time, and fixed-priority arbitration is the simplest such policy. For a processor, the natural priority is to serve the data access of the instruction that is already executing before fetching the next one, because the executing instruction cannot finish without its operand. The Von Neumann baseline in this work (`bus_arbiter.v`) uses exactly this policy, and it reports every cycle in which a fetch is waiting for a data transfer as a structural-hazard stall (`if_stall`).

### D. The Memory Wall and Multi-Level Latency
Wulf and McKee [8] observed that processor speed was improving much faster than memory speed, so that average memory access time would come to dominate execution time, a trend they called the *memory wall*. Access time also grows with memory size: the CACTI model of Wilton and Jouppi [9] estimates SRAM access and cycle time from array organization, and larger arrays are slower. This is why a small, fast local memory is placed in front of a larger, slower one. The Phase II L2 latency parameter (`L2_LATENCY`) models this cost directly by adding wait states to the larger 2 KB tier while the 1 KB `DMEM` keeps its single-clock array access.

### E. Fetch-Ahead Buffers
Jouppi [10] showed that small prefetch (stream) buffers placed beside a cache hide part of the miss latency by fetching sequential lines before they are requested. The CPU driver used for the comparison in this paper applies the same idea at its simplest: a one-entry instruction buffer that fetches instruction *N+1* while instruction *N* executes. Whether that fetch can actually overlap a data access depends on the memory organization, which is the effect this paper measures.

### F. Positioning of This Work
The references above explain the bottleneck analytically [1], [3], [8] or describe how real buses and caches avoid it [4], [7], [10]. This paper adds a small, fully open RTL experiment: the same CPU driver and the same instruction stream run on a Harvard hierarchy and on a Von Neumann baseline, with the same memory technology behind both, and the cycle counts, stall counts and final memory contents are compared from simulation rather than from a formula.

---

## III. Proposed Architecture

### A. System Organization
The proposed 32-bit Harvard hierarchy (`harvard_top.v`) separates memory traffic into two orthogonal domains:

1. **Program Counter (`program_counter.v`):** Maintains the 32-bit byte address `pc_out`. On each rising edge of `clk` (when `rst_n = 1`), the register evaluates control inputs in strict priority order: (i) if `stall = 1`, `pc_out` holds its current state (`pc_out <= pc_out`); (ii) else if `branch_en = 1`, `pc_out` loads `branch_addr`; (iii) otherwise, `pc_out` advances sequentially by one 32-bit word (`pc_out <= pc_out + 32'd4`).
2. **Synchronous Instruction Memory (`instruction_memory.v`):** Implements a $256 \times 32$-bit (1 KB) synchronous ROM initialized via `$readmemh`. Because instructions are 4-byte aligned, bits `i_addr[9:2]` index the 256-entry word array directly while ignoring byte-offset bits `i_addr[1:0]`. When `imem_en` is asserted, `i_rdata` and `i_ready` are registered on the rising clock edge (1-clock read latency).
3. **Bitmask Address Decoder (`address_decoder.v`) and R/W Controller (`rw_control.v`):** Incoming data requests (`d_addr`, `d_wdata`, `d_be[3:0]`, `req`, `we`) are decoded combinationally using aligned bitmasks:
   $$\text{dmem\_sel} = (\text{d\_addr} \;\&\; \text{0xFFFF\_FC00}) == \text{0x0000\_0000}$$
   $$\text{l2\_sel} = (\text{d\_addr} \;\&\; \text{0xFFFF\_F800}) == \text{0x0000\_0800}$$
   Aligning the 2 KB `L2` region (`0x800` bytes) to base address `0x0000_0800` ensures exact power-of-two mask matching across `0x0000_0800–0x0000_0FFF`, while leaving `0x0000_0400–0x0000_07FF` and addresses $\ge \text{0x0000\_1000}$ as unmapped trap regions that assert `invalid_addr_err`. Instruction fetches (`IF`) and data memory transactions (`MEM`) occur across independent pathways, so an instruction fetch and a data access can proceed in the same clock cycles. Each memory array provides a 1-clock synchronous read, while a complete `DMEM` transaction through `rw_control` takes 4 clocks from `req` to `d_ready` (measured in Section IV-B).
4. **Local Data Memory (`data_memory.v`) and Shared L2 (`shared_l2_memory.v`):** `DMEM` provides $256 \times 32$-bit synchronous storage supporting byte, half-word, and word writes via active-high byte-lane enables `d_be[3:0]`. `Shared L2` provides $512 \times 32$-bit (2 KB) secondary storage indexed via `d_addr[10:2]`.

Fig. 1 shows the system as it is built for the Phase II comparison: the same CPU driver drives either the Harvard hierarchy, with its own instruction bus and data bus, or the single-port Von Neumann baseline.

![Fig. 1. System block diagram. (a) Harvard hierarchy in `harvard_cpu_top.v`: the instruction bus goes straight to `instruction_memory.v`, the data bus goes through `address_decoder.v` and `rw_control.v` to `DMEM` or L2. (b) Von Neumann baseline in `von_neumann_top.v`: fetch and data requests share one port through `bus_arbiter.v` (drawn by `scripts/draw_block_diagram.py`).](figures/fig_block_diagram.png)

### B. Memory Map Specification
Table I summarizes the address space organization and hardware decoding logic.

| Memory Region | Byte Address Range (Hex) | Word Depth | Capacity | Access Mode | Hardware Mask | Active Select / Flag |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Instruction ROM (`IMEM`)** | `0x0000_0000 – 0x0000_03FF` | $256 \times 32$-bit | 1 KB | Read-Only (`RX`) | Dedicated Bus | `imem_en` |
| **Local Data SRAM (`DMEM`)** | `0x0000_0000 – 0x0000_03FF` | $256 \times 32$-bit | 1 KB | Read/Write (`RW`, `d_be`) | `0xFFFF_FC00` | `dmem_en` |
| **Unmapped Trap Gap** | `0x0000_0400 – 0x0000_07FF` | — | 1 KB | No Access (Fault) | Default | `invalid_addr_err` |
| **Shared L2 SRAM (`L2`)** | `0x0000_0800 – 0x0000_0FFF` | $512 \times 32$-bit | 2 KB | Read/Write (`RW`) | `0xFFFF_F800` | `l2_en` |
| **Unmapped Upper Space** | `0x0000_1000 – 0xFFFF_FFFF` | — | ~4 GB | No Access (Fault) | Default | `invalid_addr_err` |

---

## IV. Experimental Evaluation, Results, and Discussion

### A. Verification Methodology and Functional Coverage
All modules were compiled and simulated using Icarus Verilog (`iverilog -g2012`) with falling-edge stimulus generation to eliminate clock-edge race conditions. Table II summarizes the automated verification results across all seven self-checking testbenches.

| Testbench Module | Target RTL Subsystems Verified | Directed & Randomized Test Vectors | Assertions Checked | Errors | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `tb_phase1_harvard.v` | `program_counter`, `instruction_memory` | Reset idle, sequential fetch (`seq_0`–`seq_5`), stall hold, branch jump, stall-over-branch priority, mid-run async reset | 12 state vectors | 0 | **PASSED** |
| `tb_dmem.v` | `data_memory` | Power-on zero init, full-word R/W, 1-clock read latency, `0x3FC` boundary, 256-word fill, `d_be[3:0]` byte-lanes, 16 back-to-back reads, 500 random ops vs. reference model, all 16 `d_be` patterns, address aliasing, async `d_ready` clear | 1,712 checks | 0 | **PASSED** |
| `tb_addr_rw.v` | `address_decoder`, `rw_control`, `data_memory`, `shared_l2_memory` | `DMEM` full/byte R/W, `L2` R/W at `0x0800` & `0x0FFC`, unmapped fault at `0x0500` (`invalid_addr_err`), alternating `DMEM`/`L2` multiplexing | 26 checks | 0 | **PASSED** |
| `tb_harvard_top.v` | `harvard_top` (Full System Integration) | `IMEM` sequential/branch fetches, `DMEM` (`0x000`, `0x3FC`), `L2` (`0x800`, `0xFFC`), byte-lane, and fault (`0x500`) transactions | 25 checks | 0 | **PASSED** |
| `tb_von_neumann.v` | `bus_arbiter`, `unified_memory` (Von Neumann baseline) | Fetch from code segment `0x1000`, data-window R/W, code not overwritten by `STORE 0x000`, data-over-fetch priority with `if_stall`, L2-window wait states, byte lanes, 200 random overlapping fetch/data pairs vs. reference model, per-cycle bus monitor | 319 checks | 0 | **PASSED** |
| `tb_architecture_comparison.v` | driver on both tops, `L2_LATENCY` 0/2/4 | Retirement, mix, accumulator and 768 memory words vs. model and across systems, overlap/stall present | 57 checks | 0 | **PASSED** |
| `tb_l2_latency.v` | `shared_l2_memory` (`L2_LATENCY` = 0/2/4), full data path | Ready timing per latency, data hidden until ready, byte lanes, request-while-busy ignored, back-to-back access, end-to-end `req`→`d_ready` latency | 74 checks | 0 | **PASSED** |

### B. Results and Discussion, Part 1: Latency and Memory Hierarchy Behavior
In Phase I the shared L2 answered in the same single clock as `DMEM`, so the two tiers of the hierarchy could not be told apart in timing. For Phase II, `shared_l2_memory.v` gained a parameter `L2_LATENCY` that adds wait states to every L2 access. The request is accepted on the clock edge that samples `l2_en`. Writes update the array at that edge, but `l2_ready` and, for reads, the new `l2_rdata` appear `L2_LATENCY` clocks later than in Phase I. A request that arrives while the memory is busy is ignored. `rw_control` already waits for `l2_ready` in its `WAIT` state, so it needed no change, and `L2_LATENCY = 0` reproduces the Phase I timing exactly (all Phase I testbenches still pass).

Table III lists the latency seen by the requester, counted in clocks from asserting `req` to `d_ready`, as measured by `tb_l2_latency.v` (`make sim_l2_latency`) on three copies of the complete data path.

| `L2_LATENCY` | `DMEM` write | `DMEM` read | `L2` write | `L2` read |
| :--- | :--- | :--- | :--- | :--- |
| 0 (Phase I) | 4 | 4 | 4 | 4 |
| 2 | 4 | 4 | 6 | 6 |
| 4 | 4 | 4 | 8 | 8 |

Three observations follow from the measurements:
1. **Fixed controller overhead.** A local `DMEM` access costs 4 clocks end to end, although the SRAM itself has a 1-clock synchronous read. The other 3 clocks come from the handshake: `rw_control` spends one clock driving `d_valid` to the decoder (`IDLE`→`ACTIVE`), one clock pulsing the memory enable, and one clock in `WAIT` registering the read data and `d_ready`. Reads and writes cost the same because both wait for the memory's ready pulse.
2. **The hierarchy is visible in timing.** `DMEM` latency stays at 4 clocks for every L2 setting, while each extra L2 wait state adds exactly one clock to every L2 transaction. Data placed in the local 1 KB `DMEM` is therefore always at least as fast as data in the 2 KB L2, which is the reason for keeping frequently used operands in the lower address window.
3. **Read data is hidden until it is valid.** With `L2_LATENCY > 0`, `l2_rdata` keeps its previous value until `l2_ready` rises, so the controller cannot capture a stale word early. This is the same failure that caused the Phase I stale-read bug, now closed off at the memory as well as in `rw_control`.

### C. Results and Discussion, Part 2: CPI, Throughput and Waveform Comparison
**Method.** Both organizations run `programs/benchmark_suite.hex` (16 instructions: 6 `LOAD`, 6 `STORE`, 3 `ALU`, 1 `NOP`) on the same `simple_cpu_driver.v`, a two-stage accumulator machine with a one-entry instruction buffer that starts fetching instruction *N+1* as soon as *N* enters execute. In `harvard_cpu_top.v` the fetch port goes straight to `instruction_memory.v` and the data port through `rw_control.v`; in `von_neumann_top.v` both ports share `bus_arbiter.v` and the single-port `unified_memory.v` (code at `0x1000`). Both use single-clock arrays plus `L2_LATENCY` wait states on `0x800`–`0xFFF`. `tb_architecture_comparison.v` first checks that both systems retire all 16 instructions with identical accumulator (`0xCAFE_0000`) and identical contents in all 768 `DMEM`/L2 words, matching a reference model; only then are cycles compared (Table IV).

| `L2_LATENCY` | Architecture | Cycles | CPI | IPC | Data-access cycles | Execute starved | Structural stalls | Speedup |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | Harvard | 74 | 4.625 | 0.216 | 60 | 10 | 0 | **1.216×** |
| 0 | Von Neumann | 90 | 5.625 | 0.178 | 36 | 50 | 36 | — |
| 2 | Harvard | 82 | 5.125 | 0.195 | 68 | 10 | 0 | **1.195×** |
| 2 | Von Neumann | 98 | 6.125 | 0.163 | 44 | 50 | 44 | — |
| 4 | Harvard | 90 | 5.625 | 0.178 | 76 | 10 | 0 | **1.178×** |
| 4 | Von Neumann | 106 | 6.625 | 0.151 | 52 | 50 | 52 | — |

Table V: first 16 clocks at `L2_LATENCY = 0` (from `sim/arch_comparison.vcd` via `scripts/vcd_timeline.py`).

| Cycle | Harvard IF | Harvard MEM | VN IF | VN MEM | VN if_stall |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | IF | · | IF | · | · |
| 2 | IF | · | IF | · | · |
| 3 | · | · | IF | · | · |
| 4 | IF | MEM | · | · | · |
| 5 | IF | MEM | IF | MEM | STALL |
| 6 | · | MEM | IF | MEM | STALL |
| 7 | · | MEM | IF | MEM | STALL |
| 8 | · | MEM | IF | · | · |
| 9 | IF | MEM | IF | · | · |
| 10 | IF | MEM | · | · | · |
| 11 | · | MEM | IF | MEM | STALL |
| 12 | · | MEM | IF | MEM | STALL |
| 13 | · | MEM | IF | MEM | STALL |
| 14 | IF | MEM | IF | · | · |
| 15 | IF | MEM | IF | · | · |
| 16 | · | MEM | · | · | · |

![Fig. 2. Harvard (H) vs. Von Neumann (VN) waveform for the same 16 clocks as Table V, at `L2_LATENCY = 0`. Shaded clocks are Von Neumann structural stalls (`if_stall`): the fetch waits while the data transfer holds the shared bus, while on the Harvard side `if_req` and `d_req` are high in the same clocks (drawn from `sim/arch_comparison.vcd` by `scripts/plot_waveforms.py`).](figures/fig_arch_comparison_waveform.png)

**Discussion.** (1) Harvard fetches during data accesses (cycles 4–5, 9–10), so execute starves only 10 cycles; Von Neumann blocks the fetch for every data transfer (cycles 5–7, 11–13), giving 36 structural stalls and 74 vs. 90 cycles (1.216×). (2) Each Harvard data access costs 5 driver cycles through `rw_control` versus 3 on the baseline, so the gain comes entirely from overlap and is conservative. (3) Each L2 wait state adds 4 cycles to both systems, so the gap stays 16 cycles and the speedup falls to 1.178× at `L2_LATENCY = 4`. (4) The analytical model in `scripts/analyze_cpi.py` predicted 2.80× by assuming one-clock Harvard instructions; the RTL measurements in Table IV are the reported results.

### D. Discussion of Timing and Architectural Trade-offs
Waveform inspection of `sim/harvard_top.vcd` (Fig. 3) confirms three key architectural behaviors:
1. **Where fetch and data overlap:** Phase I `harvard_top.v` holds its PC with `stall = req & ~d_ready`, so its PC does not advance during data accesses. The overlap appears with the Phase II driver in `harvard_cpu_top.v` (Table V).
2. **Hardware Memory Protection:** When the controller issues an access to unmapped gap address `0x0000_0500` (`T5`), neither `dmem_en` nor `l2_en` asserts, preventing accidental data corruption and immediately raising `invalid_addr_err`.
3. **Area vs. Bandwidth Trade-off:** The Harvard organization needs two 32-bit address buses and two 32-bit read data paths. In this design that cost is small: after synthesis (Table VI) the Harvard system uses about the same logic as the baseline (639 vs. 640 ECP5 logic cells) and 48 more flip-flops (538 vs. 490), while the 1.18–1.22× cycle gain holds on this kernel.

![Fig. 3. Phase I `harvard_top.v`: `imem_en` and `i_ready` stay high while `rw_control` steps through `IDLE`(0) / `ACTIVE`(1) / `WAIT`(3) for a `DMEM` write and read-back of `0xDEADBEEF` (Phase I figure from `sim/harvard_top.vcd`; it can be redrawn with `scripts/plot_waveforms.py --all`).](figures/fig_harvard_top_dmem_access.png)

### E. Synthesis Results
Both systems were synthesized with the same parameters as the comparison run (`L2_LATENCY = 0`, `programs/benchmark_suite.hex` in the instruction memory) using `make synth`. Yosys `synth_ecp5` maps each design to a Lattice ECP5 LFE5U-25F, and nextpnr-ecp5 places and routes it out of context against a 100 MHz target; the maximum frequency is the post-route value. As a second estimate, Yosys `synth_xilinx` maps the same RTL to Xilinx 7-series (Artix-7) cells; this gives resource counts only, because no Vivado place and route was run. A check in `scripts/synth_summary.py` confirms that no output port of either netlist is tied to a constant, so no logic was optimized away. The results are in Table VI.

| System | ECP5 logic cells | ECP5 flip-flops | ECP5 block RAM (DP16KD) | ECP5 Fmax | Artix-7 LUTs | Artix-7 flip-flops | Artix-7 block RAM (RAMB36 eq.) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Harvard (`harvard_cpu_top`) | 639 / 24,288 (2.6%) | 538 | 2 / 56 | **134.0 MHz** | 155 | 538 | 1 |
| Von Neumann (`von_neumann_top`) | 640 / 24,288 (2.6%) | 490 | 4 / 56 | **105.7 MHz** | 153 | 490 | 2 |

Three points follow from Table VI:
1. **Memory use.** The Harvard `DMEM` (1 KB) and L2 (2 KB) each take one ECP5 block RAM. Yosys builds the 256-word instruction ROM, which holds only 15 non-zero words, from logic cells instead of a block RAM. The Von Neumann `unified_memory.v` is one 8 KB array, which takes 4 block RAMs.
2. **Clock frequency.** The Harvard critical path runs from the L2 block RAM output into the read-data register of `rw_control` (7.46 ns). The Von Neumann critical path runs from the unified-memory block RAM through two levels of LUT logic into the CPU accumulator register (9.46 ns), against one LUT level on the Harvard path.
3. **Time, not only cycles.** At these frequencies the benchmark takes 74 / 134.0 MHz = 552 ns on Harvard and 90 / 105.7 MHz = 851 ns on Von Neumann, a 1.54× difference in run time. The reported values use placement seed 1; with seeds 2 to 5 the Harvard Fmax stays between 133.4 and 134.4 MHz and the Von Neumann Fmax between 106.7 and 108.6 MHz, so the ranking does not depend on the seed. These are open-source results on a Lattice part; Vivado results on an Artix-7 device would give different absolute values.

---

## V. Individual Contributions

Table VII lists the RTL modules, testbenches and paper sections owned by each team member across Phase I and Phase II.

| Team Member | Assigned Modules & Verification Artefacts | Research Paper & Documentation Contributions |
| :--- | :--- | :--- |
| **Palak Gupta (Member 1)** | `rtl/common/defines.vh`, `rtl/common/program_counter.v`, `rtl/harvard/instruction_memory.v`, `tb/tb_phase1_harvard.v`, `programs/test_program.hex`, `programs/benchmark_suite.hex`, `scripts/analyze_cpi.py` (analytical estimate) | Authored Section III (*Proposed Architecture*), Section VI (*Conclusion & Future Work*), system block diagram, and formatted the full IEEE Research Paper (Markdown, LaTeX, PDF). |
| **Atanu Adhikari (Member 2)** | `rtl/harvard/data_memory.v`, `tb/tb_dmem.v` (1,712 self-checking assertions); Phase II: multi-cycle `L2_LATENCY` model in `rtl/harvard/shared_l2_memory.v`, `tb/tb_l2_latency.v` (74 assertions, latency table); synthesis flow (`make synth`, `scripts/synth_summary.py`) and figure scripts (`scripts/plot_waveforms.py`, `scripts/draw_block_diagram.py`) | Authored the *Abstract*, *Section I (Introduction)*, Section IV-B (*Results and Discussion, Part 1: Latency and Memory Hierarchy Behavior*), and Section IV-E (*Synthesis Results*). |
| **Sambhav Kumar (Member 3)** | `rtl/harvard/address_decoder.v`, `rtl/harvard/rw_control.v`, `rtl/harvard/shared_l2_memory.v`, `tb/tb_addr_rw.v` (26 assertions); Phase II: Von Neumann baseline `rtl/von_neumann/unified_memory.v` and `rtl/von_neumann/bus_arbiter.v`, `tb/tb_von_neumann.v` (319 assertions) | Authored *Section II (Related Work & Theoretical Background)*, expanded it in Phase II (Sections II-C to II-F), and formatted the IEEE references. |
| **Prince Singh (Member 4)** | `rtl/harvard/harvard_top.v`, `tb/tb_harvard_top.v` (25 assertions); Phase II: `rtl/common/simple_cpu_driver.v`, `rtl/harvard/harvard_cpu_top.v`, `rtl/von_neumann/von_neumann_top.v`, `tb/tb_architecture_comparison.v` (57 assertions), `scripts/vcd_timeline.py` | Authored Section IV-C (*Results Part 2*), compiled Section V, and updated the Abstract and Conclusion to the measured results. |

---

## VI. Conclusion and Future Work
This work presented the design, implementation and self-checking verification of a 32-bit Harvard instruction and data memory hierarchy in Verilog RTL, together with a Von Neumann baseline built from the same memory technology. Separating the instruction ROM (`IMEM`) from the data hierarchy, a 1 KB local `DMEM` and a 2 KB shared L2, lets an instruction fetch run in the same clock cycles as a data load or store. Power-of-two bitmask decoding in `address_decoder.v` routes each data access and flags unmapped addresses (`invalid_addr_err`). All seven testbenches pass, 2,213 self-checking assertions and 12 fetch state vectors, with zero errors. With the same CPU driver and the same 16-instruction benchmark, the Harvard hierarchy finished in 74 cycles against 90 for the Von Neumann baseline (CPI 4.625 vs. 5.625, a 1.216× speedup), and it removed all 36 structural-hazard stall cycles. The gain held, at 1.178×, with four L2 wait states, and it was obtained even though the Harvard data path pays an extra decode stage in `rw_control`. The analytical estimate of 2.80× made before the RTL existed was not confirmed: in the real design each fetch and data transfer takes several clocks, and only part of the fetch time can be hidden. After synthesis and place and route on a Lattice ECP5, the Harvard system needs about the same logic as the baseline (639 vs. 640 logic cells), fewer block RAMs (2 vs. 4) and reaches a higher clock (134.0 vs. 105.7 MHz), so on this kernel it is also faster in run time (552 vs. 851 ns).

Future work includes a pipelined driver that issues one fetch per clock to hide more fetch time, a set-associative L1 cache with write-back between `DMEM` and L2, and Vivado place and route on an Artix-7 board to confirm the open-source frequency and utilization results on the Xilinx part.

---

## References
[1] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. San Francisco, CA, USA: Morgan Kaufmann, 2017.  
[2] D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition: The Hardware Software Interface*, 2nd ed. Cambridge, MA, USA: Morgan Kaufmann, 2020.  
[3] J. Backus, "Can programming be liberated from the von Neumann style? A functional style and its algebra of programs," *Communications of the ACM*, vol. 21, no. 8, pp. 613–641, Aug. 1978.  
[4] A. J. Smith, "Cache memories," *ACM Computing Surveys (CSUR)*, vol. 14, no. 3, pp. 473–530, Sept. 1982.  
[5] S. L. Harris and D. M. Harris, *Digital Design and Computer Architecture: RISC-V Edition*. San Francisco, CA, USA: Morgan Kaufmann, 2021.  
[6] J. von Neumann, "First Draft of a Report on the EDVAC," Moore School of Electrical Engineering, University of Pennsylvania, Philadelphia, PA, USA, Tech. Rep., Jun. 1945.  
[7] ARM Ltd., *AMBA Specification (Rev 2.0)*, ARM IHI 0011A, Cambridge, U.K., 1999.  
[8] W. A. Wulf and S. A. McKee, "Hitting the memory wall: Implications of the obvious," *ACM SIGARCH Computer Architecture News*, vol. 23, no. 1, pp. 20–24, Mar. 1995.  
[9] S. J. E. Wilton and N. P. Jouppi, "CACTI: An enhanced cache access and cycle time model," *IEEE Journal of Solid-State Circuits*, vol. 31, no. 5, pp. 677–688, May 1996.  
[10] N. P. Jouppi, "Improving direct-mapped cache performance by the addition of a small fully-associative cache and prefetch buffers," in *Proc. 17th Annu. Int. Symp. Computer Architecture (ISCA)*, Seattle, WA, USA, 1990, pp. 364–373.  
