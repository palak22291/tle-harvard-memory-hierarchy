# Abstract & Section I: Introduction (IEEE Report - Member 2: Atanu Adhikari)

## Abstract
In a conventional von Neumann processor, instructions and data share a single memory and a single bus, so an instruction fetch and a data load or store cannot happen in the same clock cycle. This structural conflict, known as the von Neumann bottleneck, adds stall cycles to every memory-referencing instruction. This project designs, implements and verifies a 32-bit Harvard-style memory organization in synthesizable Verilog RTL. The instruction path and the data path are physically separate. A program counter drives a dedicated 256 x 32-bit synchronous instruction ROM. An address decoder routes data accesses to a 256 x 32-bit local data RAM with byte-lane write enables, or to a 512 x 32-bit shared lower-level (L2) memory. Every module is verified in simulation with Icarus Verilog using directed, self-checking testbenches and waveform inspection. In Phase I, the complete Harvard memory subsystem has been implemented and verified: the instruction-fetch path (PC + IMEM), the local data memory, the address decoder with read/write control, the shared L2 memory, and the integrated top level (`harvard_top.v`). All four self-checking testbenches pass. Phase II connects the hierarchy to a simple CPU driver and builds a unified-memory (von Neumann) baseline. It then runs the same programs on both organizations to measure cycle count, CPI and speedup. <!-- TODO (Phase II): add the measured cycle counts / CPI / speedup here once tb_architecture_comparison.v has been run. Do not add numbers before they are measured. -->

**Index Terms** - Harvard architecture, von Neumann bottleneck, memory hierarchy, instruction memory, data memory, address decoding, Verilog RTL.

## I. Introduction

### A. Motivation
The stored-program (von Neumann) model keeps instructions and data in one memory and moves them over one path between memory and the processor. Backus called this shared path the "von Neumann bottleneck" [1]. The processor cannot fetch the next instruction while the current instruction is reading or writing a data operand. Every load and store therefore costs an extra bus cycle, and in a pipelined processor it causes a structural hazard: the IF stage and the MEM stage want the memory in the same cycle, so one of them has to stall [2], [3].

The Harvard organization removes this conflict by giving instructions and data separate memories and separate buses. Pure Harvard machines are now mostly found in microcontrollers and DSPs. However, nearly every modern general-purpose processor is "modified Harvard": it keeps split level-1 instruction and data caches backed by a unified lower level of the memory hierarchy [2]. Studying a small Harvard memory system at the RTL level shows directly why this split matters for pipeline throughput.

### B. Problem Statement
Project 9 of the course asks for a simplified Harvard-style memory organization. It must have independent instruction and data paths connected to a simple processor or controller. Programs that mix instruction fetches with data accesses run on it, and its timing behavior is compared with a shared-memory organization.

### C. Objectives
1. Implement a byte-addressed, word-organized instruction path: a program counter with stall and branch control, and a synchronous instruction ROM.
2. Implement a synchronous read/write data memory with byte-lane write enables. Its behavior must be clearly specified: read latency, write timing and read-during-write.
3. Implement address decoding and read/write control that map the data address space onto a fast local data memory and an optional shared lower-level (L2) memory, and flag unmapped addresses.
4. Build a unified-memory (von Neumann) baseline with a bus arbiter that stalls the processor when an instruction fetch and a data access collide.
5. Verify every module with directed, self-checking testbenches and waveforms. Then compare both organizations quantitatively on the same programs: cycle count, CPI and speedup.

### D. Phase I Status
| Module | Owner | Status |
| :--- | :--- | :--- |
| `program_counter.v`, `instruction_memory.v`, `tb_phase1_harvard.v` | Member 1 | Implemented, fetch/stall/branch waveform produced (`make sim_fetch`) |
| `data_memory.v`, `tb_dmem.v` | Member 2 | Implemented, self-checking testbench passes (`make sim_dmem`: 1584 checks, 0 errors) |
| `address_decoder.v`, `rw_control.v`, `shared_l2_memory.v`, `tb_addr_rw.v` | Member 3 | Implemented, self-checking testbench passes (`make sim_addr_rw`: 26 checks, 0 errors) |
| `harvard_top.v`, `tb_harvard_top.v` | Member 4 | Integrated PC/IMEM + decoder/R-W control + DMEM + L2, testbench passes (`make sim_harvard_top`: 25 checks, 0 errors) |

### E. Report Organization
Section II reviews related work on memory organizations. Section III describes the proposed Harvard memory subsystem and its timing behavior. Section IV presents the Phase I simulation results; the comparison with the von Neumann baseline is added in Phase II. Section V concludes the report and outlines Phase II, and Section VI lists individual contributions.

## References (for this section)
<!-- Merged with Section II references [4]-[9] into the master list in docs/phase1_report_ieee.md. -->
[1] J. Backus, "Can programming be liberated from the von Neumann style? A functional style and its algebra of programs," *Communications of the ACM*, vol. 21, no. 8, pp. 613-641, Aug. 1978.

[2] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. Cambridge, MA, USA: Morgan Kaufmann, 2017.

[3] D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition: The Hardware/Software Interface*, 2nd ed. Cambridge, MA, USA: Morgan Kaufmann, 2020.
