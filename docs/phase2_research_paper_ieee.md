# Design, Verification, and Quantitative Evaluation of a 32-Bit Harvard Instruction and Data Memory Hierarchy in Verilog RTL

**Authors:** Palak Gupta, Member 2, Member 3, and Member 4 *(Team TLE)*  
**Course:** Modern Computer Architecture — Research Paper Report  

---

## Abstract
Memory subsystem contention remains a primary throughput bottleneck in pipelined and single-cycle reduced instruction set processors. In classical Von Neumann architectures, instructions and data share a unified address space and a single physical bus, inducing structural hazards whenever an instruction fetch (`IF`) coincides with a data memory load or store (`MEM`) transaction. This paper presents the Register-Transfer Level (RTL) design, cycle-accurate verification, and quantitative performance evaluation of a 32-bit Modified Harvard memory hierarchy implemented in Verilog-2012. The proposed architecture physically decouples the read-only Instruction Memory (`IMEM`) pathway from a two-tier Data Memory hierarchy comprising a 1 KB byte-addressable Local Data SRAM (`DMEM`) and a 2 KB Shared Lower-Level Memory (`L2`). A combinational bitmask Address Decoder and a deterministic 3-clock Read/Write Controller (`rw_control`) arbitrate data transactions and trap out-of-bounds memory faults via `invalid_addr_err`. Self-checking testbenches executed in Icarus Verilog across 1,635 directed and randomized assertions verify zero-defect functional operation. Quantitative benchmarking on a 16-instruction memory-intensive workload demonstrates that decoupling the instruction and data buses eliminates 36 structural hazard stall cycles compared to an equivalent Von Neumann unified-memory baseline, reducing effective Cycles Per Instruction (CPI) from 3.50 to 1.25 and achieving a $2.80\times$ instruction throughput speedup.

**Index Terms—** Harvard Architecture, Von Neumann Bottleneck, Memory Hierarchy, Address Decoding, Structural Hazard, Cycles Per Instruction (CPI), Verilog RTL.

---

## I. Introduction
Modern computing workloads—ranging from embedded digital signal processing to dense linear algebra—exhibit high memory access intensity. In a conventional single-bus Von Neumann processor organization, both instruction words and data operands traverse a shared physical memory interface [1]. Whenever an executing instruction performs a memory load (`LOAD`) or store (`STORE`), the data transfer monopolizes the memory bus, forcing the processor controller to stall the subsequent instruction fetch (`stall = 1`). As the fraction of memory-reference instructions increases, these structural hazard bubbles severely degrade instruction throughput and inflate Cycles Per Instruction (CPI) [2].

To overcome this limitation without duplicating high-capacity off-chip memory, contemporary microprocessors employ a Harvard or Modified Harvard memory organization at the primary hierarchy level [1], [2]. By provisioning physically independent address, data, and control buses for Instruction Memory (`IMEM`) and Data Memory (`DMEM`), the processor can fetch Instruction $N+1$ concurrently during the exact same clock cycles in which Instruction $N$ reads or writes data operands.

In this paper, we present a complete 32-bit Harvard instruction and data memory hierarchy in synthesizable Verilog RTL. The primary contributions of this work are as follows:
1. **Decoupled Instruction Fetch Engine:** A 32-bit byte-addressed Program Counter (`program_counter.v`) with prioritized hazard stall and branch target multiplexing coupled to a synchronous $256 \times 32$-bit Instruction ROM (`instruction_memory.v`).
2. **Partitioned Multi-Tier Data Hierarchy:** A combinational bitmask Address Decoder (`address_decoder.v`) and a 3-clock finite-state Read/Write Controller (`rw_control.v`) interfacing a 1 KB byte-addressable Local Data SRAM (`data_memory.v`) and a 2 KB Shared Lower-Level Memory (`shared_l2_memory.v`) with hardware fault trapping (`invalid_addr_err`).
3. **Self-Checking Verification & Quantitative CPI Evaluation:** An automated verification suite totaling 1,635 assertions across four testbenches, paired with an analytical and cycle-accurate comparison against a Von Neumann unified-memory baseline.

---

## II. Related Work and Theoretical Background

### A. The Von Neumann Bottleneck and Structural Hazards
Backus [3] formalized the throughput limitation of single-bus stored-program computers as the *Von Neumann bottleneck*, observing that processor execution speed is bounded by the effective bandwidth of the single channel connecting the central processing unit (CPU) and main storage. In pipelined processor datapaths, Hennessy and Patterson [1] classify simultaneous requests to a single memory port by the Instruction Fetch (`IF`) and Memory Access (`MEM`) stages as a *structural hazard*. If the memory subsystem provides only a single address/data port, the hardware arbiter must inject pipeline stall cycles:

$$\text{CPI}_{\text{unified}} = \text{CPI}_{\text{base}} + f_{\text{mem}} \times L_{\text{mem}}$$

where $f_{\text{mem}}$ denotes the fraction of instructions that access data memory and $L_{\text{mem}}$ represents the number of bus cycles consumed by each data transaction.

### B. Modified Harvard Memory Hierarchies and Address Decoding
Smith [4] demonstrated that splitting Level-1 (L1) storage into dedicated instruction and data memories eliminates port contention while permitting a unified or shared lower-level (`L2`) backing store to amortize capacity cost. Furthermore, Harris and Harris [5] establish that power-of-two bitmask decoding (`(addr & MASK) == BASE`) minimizes combinational critical-path delay in hardware address decoders by avoiding full 32-bit magnitude comparators, provided each memory region is aligned to a natural power-of-two boundary.

---

## III. Proposed Architecture and Analytical Model

### A. System Organization
The proposed 32-bit Harvard hierarchy (`harvard_top.v`) separates memory traffic into two orthogonal domains:

1. **Program Counter (`program_counter.v`):** Maintains the 32-bit byte address `pc_out`. On each rising edge of `clk` (when `rst_n = 1`), the register evaluates control inputs in strict priority order: (i) if `stall = 1`, `pc_out` holds its current state (`pc_out <= pc_out`); (ii) else if `branch_en = 1`, `pc_out` loads `branch_addr`; (iii) otherwise, `pc_out` advances sequentially by one 32-bit word (`pc_out <= pc_out + 32'd4`).
2. **Synchronous Instruction Memory (`instruction_memory.v`):** Implements a $256 \times 32$-bit (1 KB) synchronous ROM initialized via `$readmemh`. Because instructions are 4-byte aligned, bits `i_addr[9:2]` index the 256-entry word array directly while ignoring byte-offset bits `i_addr[1:0]`. When `imem_en` is asserted, `i_rdata` and `i_ready` are registered on the rising clock edge (1-clock read latency).
3. **Bitmask Address Decoder (`address_decoder.v`) and R/W Controller (`rw_control.v`):** Incoming data requests (`d_addr`, `d_wdata`, `d_be[3:0]`, `req`, `we`) are decoded combinationally using aligned bitmasks:
   $$\text{dmem\_sel} = (\text{d\_addr} \;\&\; \text{0xFFFF\_FC00}) == \text{0x0000\_0000}$$
   $$\text{l2\_sel} = (\text{d\_addr} \;\&\; \text{0xFFFF\_F800}) == \text{0x0000\_0800}$$
   Aligning the 2 KB `L2` region (`0x800` bytes) to base address `0x0000_0800` ensures exact power-of-two mask matching across `0x0000_0800–0x0000_0FFF`, while leaving `0x0000_0400–0x0000_07FF` and addresses $\ge \text{0x0000\_1000}$ as unmapped trap regions that assert `invalid_addr_err`. Instruction fetches (`IF`) and data memory transactions (`MEM`) occur across independent pathways, so an instruction fetch and a data access can proceed in the same clock cycles. Each memory array provides a 1-clock synchronous read, while a complete handshake transaction through `rw_control` completes in 3 clocks.
4. **Local Data Memory (`data_memory.v`) and Shared L2 (`shared_l2_memory.v`):** `DMEM` provides $256 \times 32$-bit synchronous storage supporting byte, half-word, and word writes via active-high byte-lane enables `d_be[3:0]`. `Shared L2` provides $512 \times 32$-bit (2 KB) secondary storage indexed via `d_addr[10:2]`.

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
All modules were compiled and simulated using Icarus Verilog (`iverilog -g2012`) with falling-edge stimulus generation to eliminate clock-edge race conditions. Table II summarizes the automated verification results across all four self-checking testbenches.

| Testbench Module | Target RTL Subsystems Verified | Directed & Randomized Test Vectors | Assertions Checked | Errors | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `tb_phase1_harvard.v` | `program_counter`, `instruction_memory` | Reset idle, sequential fetch (`seq_0`–`seq_5`), stall hold, branch jump, stall-over-branch priority, mid-run async reset | 12 state vectors | 0 | **PASSED** |
| `tb_dmem.v` | `data_memory` | Power-on zero init, full-word R/W, 1-clock read latency, `0x3FC` boundary, 256-word fill, `d_be[3:0]` byte-lanes, 16 back-to-back reads, 500 random ops vs. reference model | 1,584 checks | 0 | **PASSED** |
| `tb_addr_rw.v` | `address_decoder`, `rw_control`, `data_memory`, `shared_l2_memory` | `DMEM` full/byte R/W, `L2` R/W at `0x0800` & `0x0FFC`, unmapped fault at `0x0500` (`invalid_addr_err`), alternating `DMEM`/`L2` multiplexing | 26 checks | 0 | **PASSED** |
| `tb_harvard_top.v` | `harvard_top` (Full System Integration) | Concurrent `IMEM` sequential/branch fetches during active `DMEM` (`0x000`, `0x3FC`), `L2` (`0x800`, `0xFFC`), byte-lane, and fault (`0x500`) transactions | 25 checks | 0 | **PASSED** |

### B. Quantitative Comparison: Harvard vs. Von Neumann Architecture
To evaluate architectural performance under realistic load/store pressure, both the proposed Harvard organization and an equivalent single-bus Von Neumann baseline were evaluated against the 16-instruction benchmark suite (`programs/benchmark_suite.hex` and `scripts/analyze_cpi.py`), comprising 8 `DMEM` operations (50%), 4 `Shared L2` operations (25%), and 4 `ALU/NOP` operations (25%).

| Performance Metric | Harvard Split Memory Hierarchy | Von Neumann Unified-Bus Baseline | Analytical Improvement |
| :--- | :--- | :--- | :--- |
| **Total Instructions Executed ($N_{\text{instr}}$)** | 16 instructions | 16 instructions | Identical workload |
| **Instruction Fetch (`IF`) Bus Latency** | 1 clock cycle (parallel with `MEM`) | 1 clock cycle (serialized with `MEM`) | Concurrent `IF` + `MEM` |
| **Data Transaction Handshake (`rw_control`)** | 3 clocks (overlapped with `IF`) | 3 clocks (stalls `IF` bus) | Eliminates bus contention |
| **Structural Hazard Stall Cycles** | **0 cycles** | **36 cycles** ($12 \text{ mem ops} \times 3 \text{ clks}$) | **100% hazard elimination** |
| **Secondary L2 Wait Penalty Cycles** | 4 cycles ($4 \text{ L2 ops} \times 1 \text{ wait clk}$) | 4 cycles ($4 \text{ L2 ops} \times 1 \text{ wait clk}$) | Equal backing-store latency |
| **Total Execution Time (Clock Cycles)** | **20 clock cycles** | **56 clock cycles** | **36 fewer clock cycles** |
| **Effective Cycles Per Instruction (CPI)** | **1.25 CPI** (1.00 on L1-only hits) | **3.50 CPI** | **$2.80\times$ throughput speedup** |

### C. Discussion of Timing and Architectural Trade-offs
Waveform inspection of `sim/harvard_top.vcd` confirms three key architectural behaviors:
1. **Elimination of Structural Stalls:** During `T3` (`DMEM` write/read at `0x0000_0000`) and `T4` (`L2` write/read at `0x0000_0800`), `pc_out` continues incrementing by 4 bytes every clock cycle and `i_rdata` delivers valid instructions (`i_ready = 1`) without asserting `stall`.
2. **Hardware Memory Protection:** When the controller issues an access to unmapped gap address `0x0000_0500` (`T5`), neither `dmem_en` nor `l2_en` asserts, preventing accidental data corruption and immediately raising `invalid_addr_err`.
3. **Area vs. Bandwidth Trade-off:** While the Harvard organization doubles the primary bus routing width (requiring two 32-bit address buses and two 32-bit read data paths), the $2.80\times$ throughput gain on memory-intensive kernels justifies the modest wire-routing overhead in embedded and pipelined RISC cores.

---

## V. Individual Contributions

| Team Member | Assigned Modules & Verification Artefacts | Research Paper & Documentation Contributions |
| :--- | :--- | :--- |
| **Palak Gupta (Member 1)** | `rtl/common/defines.vh`, `rtl/common/program_counter.v`, `rtl/harvard/instruction_memory.v`, `tb/tb_phase1_harvard.v`, `programs/test_program.hex`, `programs/benchmark_suite.hex`, `scripts/analyze_cpi.py` | Authored Section III (*Proposed Architecture & Analytical Model*), Section VI (*Conclusion & Future Work*), system block diagram, and formatted the full IEEE Research Paper. |
| **Member 2** | `rtl/harvard/data_memory.v`, `rtl/harvard/shared_l2_memory.v`, `tb/tb_dmem.v` (1,584 self-checking assertions) | Authored the *Abstract*, *Section I (Introduction)*, and SRAM byte-enable/latency analysis in Section IV. |
| **Member 3** | `rtl/harvard/address_decoder.v`, `rtl/harvard/rw_control.v`, `tb/tb_addr_rw.v` (26 self-checking assertions) | Authored *Section II (Related Work & Theoretical Background)*, bitmask decoding proofs, and IEEE references. |
| **Member 4** | `rtl/harvard/harvard_top.v`, `tb/tb_harvard_top.v` (25 self-checking integration assertions) | Authored *Section IV (Experimental Evaluation, Results & Discussion)* and compiled *Section V (Individual Contributions)*. |

---

## VI. Conclusion and Future Work
This work presented the design, implementation, and self-checking verification of a 32-bit Harvard instruction and data memory hierarchy in Verilog RTL. By physically separating the synchronous Instruction ROM (`IMEM`) pathway from the byte-addressable Local Data SRAM (`DMEM`) and 2 KB-aligned Shared L2 Memory (`L2`), the architecture eliminates single-bus structural hazards during concurrent instruction fetches and data reads/writes. Power-of-two bitmask decoding in `address_decoder.v` and deterministic handshaking in `rw_control.v` ensure conflict-free routing and immediate hardware fault detection on unmapped addresses (`invalid_addr_err`). Across 1,635 automated testbench assertions, the RTL achieved 100% verification pass rates, and benchmark analysis demonstrated a $2.80\times$ throughput speedup (1.25 CPI vs. 3.50 CPI) over an equivalent Von Neumann unified-memory organization.

Future extensions to this work include integrating a set-associative L1 Instruction and Data Cache controller with write-back replacement policies, adding burst-transfer bridging between L1 `DMEM` and `Shared L2`, and synthesizing the hierarchy onto an Artix-7 FPGA target to characterize post-place-and-route maximum operating frequency ($F_{\max}$) and block RAM (BRAM) utilization.

---

## References
[1] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. San Francisco, CA, USA: Morgan Kaufmann, 2017.  
[2] D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition: The Hardware Software Interface*, 2nd ed. Cambridge, MA, USA: Morgan Kaufmann, 2020.  
[3] J. Backus, "Can programming be liberated from the von Neumann style? A functional style and its algebra of programs," *Communications of the ACM*, vol. 21, no. 8, pp. 613–641, Aug. 1978.  
[4] A. J. Smith, "Cache memories," *ACM Computing Surveys (CSUR)*, vol. 14, no. 3, pp. 473–530, Sept. 1982.  
[5] S. L. Harris and D. M. Harris, *Digital Design and Computer Architecture: RISC-V Edition*. San Francisco, CA, USA: Morgan Kaufmann, 2021.  
