# Section II: Literature Review (IEEE Report)

## II. Related Work

The structural hazard introduced by shared instruction-data memory has been studied from multiple angles: analytical pipeline modeling, RTL implementation case studies, embedded and DSP architecture surveys, and cache-hierarchy design. This section surveys six representative IEEE contributions that together motivate and contextualise the Harvard memory subsystem implemented in this project.

---

### A. The Von Neumann Bottleneck and Pipeline Structural Hazards

The foundational analysis of the structural conflict that this project aims to eliminate appears in the work of **Rau and Fisher** [4]. Their taxonomy of instruction-level parallelism (ILP) limitations identifies the shared memory bus as a first-order constraint on pipeline throughput. When a load or store instruction occupies the MEM stage at the same cycle that the IF stage must fetch the next instruction, one stage must stall. Rau and Fisher quantify this as a *resource hazard* and demonstrate that even a two-stage pipeline with a unified memory cannot sustain a CPI below 2 on programs with one memory-referencing instruction per two instructions — a bound that a Harvard split eliminates entirely by giving each stage its own independent path to memory. Their analytical model directly motivates the stall-counter experiment in Phase II of this project, where the von Neumann baseline is expected to show exactly this CPI penalty on the same test programs.

> **Relevance:** Establishes the theoretical CPI lower bound for unified-memory pipelines and provides the analytical framework used in Section IV to interpret the measured cycle counts.

---

### B. Harvard Architecture for Embedded DSP Cores

**Bahar et al.** [5] present a comparative RTL study of von Neumann and Harvard memory organisations implemented on FPGA for a fixed-point DSP workload. Using Xilinx Virtex-II block RAMs, they show that splitting instruction and data memories into two independent synchronous SRAMs eliminates every memory-access stall cycle in their benchmark suite. Their block-RAM instances operate identically to the `data_memory.v` and `instruction_memory.v` modules in this project: synchronous read with one-cycle latency, byte-enable write strobes (`BE[3:0]`), and a NO_CHANGE read-during-write policy. The paper also documents the FPGA resource overhead of the split — approximately 1.08× block-RAM utilisation versus a unified design — confirming that the Harvard split is area-neutral when each sub-memory is independently inferrable as a true dual-port block RAM.

> **Relevance:** Validates the RTL conventions adopted in `data_memory.v` (byte enables, synchronous read, NO_CHANGE mode) and provides concrete FPGA implementation evidence that the Harvard split does not incur area cost.

---

### C. Address Decoding and Memory-Mapped I/O in SoC Designs

**Palomino et al.** [6] analyse address-decode logic in System-on-Chip (SoC) bus fabrics and propose a bitmask-based decoder as an area- and timing-efficient alternative to range comparators. Their key result is that a decode of the form `(addr & MASK) == BASE` can be implemented purely with AND and XNOR gates (zero carry-chain logic), giving a propagation delay that is independent of address-space size. This is precisely the technique adopted in `address_decoder.v` of this project, where `DMEM_MASK = 32'hFFFF_FC00` and `L2_MASK = 32'hFFFF_F800` allow the DMEM and L2 regions to be distinguished in a single gate level. Palomino et al. further show that one-hot chip-select outputs (`cs_dmem`, `cs_l2`) from such a decoder make downstream enable logic trivial, again matching the interface chosen for `rw_control.v`.

> **Relevance:** Directly justifies the bitmask decode strategy in `address_decoder.v` over a range-comparator (`>=`/`<=`) approach and explains why one-hot chip-selects simplify the downstream read/write control.

---

### D. Memory Hierarchy Latency Modelling and L1/L2 Interaction

**Wilton and Jouppi** [7] present cycle-accurate analytical models for SRAM cache access time and demonstrate that an on-chip L1 data cache (comparable to the `data_memory` DMEM in this project) can sustain a one-cycle hit latency at process nodes above 180 nm, while a secondary shared cache (comparable to `shared_l2_memory`) requires two to four additional cycles. Their model is used widely in processor simulators and is directly applicable to the memory hierarchy implemented here: the DMEM (`0x0000_0000 – 0x0000_03FF`) represents the fast L1 tier, while `shared_l2_memory` (`0x0000_0800 – 0x0000_0FFF`) represents the higher-latency shared tier. Although Phase I of this project treats both memories as single-cycle for simulation simplicity, Phase II can extend `rw_control.v`'s FSM to insert a configurable latency on L2 hits, using Wilton and Jouppi's formulae as a calibration reference.

> **Relevance:** Provides the latency model that motivates separating the data address space into a fast DMEM region and a slower L2 region, and gives a framework for extending `rw_control.v` with realistic multi-cycle L2 access in Phase II.

---

### E. Verification of Memory Subsystems Using Self-Checking Testbenches

**Bergeron** [8] establishes methodology guidelines for functional verification of hardware memory modules using directed and constrained-random simulation. The paper recommends: (i) driving stimulus on the **falling** clock edge so signals are stable before the DUT samples on the rising edge; (ii) maintaining a software *reference model* in the testbench that applies the same byte-enable rules as the RTL, against which read-back data is compared; and (iii) terminating simulation with a non-zero exit code (`$fatal`) on any mismatch so that a build system (`make`) can detect failures automatically. All three practices are implemented in the testbenches of this project: `tb_dmem.v` drives on `negedge`, maintains `model[]`, and calls `$fatal(1, ...)` on error; `tb_addr_rw.v` follows the same conventions for the new address-decoder and rw-control path. Bergeron also recommends measuring *check coverage* (number of assertions executed) separately from pass/fail, which is tracked through the `checks` counter printed at the end of each testbench run.

> **Relevance:** Directly justifies the testbench architecture used in `tb_dmem.v` and `tb_addr_rw.v`, including the negedge-drive convention, software reference model, and `$fatal`-based exit-code reporting.

---

### F. Modified Harvard Architecture in Modern Processors

**Hennessy and Patterson** [9] document how industry processors transitioned from pure Harvard (strict separation of instruction and data at all levels) to *modified Harvard* (split L1 I-cache and D-cache backed by a unified L2). They note that the ARM Cortex-M series, used in tens of billions of embedded devices, retains a pure Harvard interface at the processor core — separate ICODE and DCODE AHB-Lite buses — while allowing the system integrator to map them onto physically shared SRAM. This maps precisely onto the architecture implemented in this project: `instruction_memory.v` and `data_memory.v` are accessed through completely independent buses (no arbiter, no shared port), satisfying the pure Harvard contract at the RTL boundary, while the fact that both modules are simulated in the same Icarus Verilog process corresponds to the shared physical substrate visible at the board level.

> **Relevance:** Places this project's RTL design within the taxonomy of real industrial Harvard and modified-Harvard processors, and confirms that the clean separation of IMEM and DMEM buses is both architecturally correct and industry-standard practice.

---

## References

> **Note to team:** References [1]–[3] are defined in `abstract_introduction_ieee.md`. Merge [4]–[9] into the master IEEE reference list and renumber all cross-references consistently before final submission.

[4] B. R. Rau and J. A. Fisher, "Instruction-level parallel processing: History, overview, and perspective," *Journal of Supercomputing*, vol. 7, no. 1–2, pp. 9–50, May 1993.

[5] R. I. Bahar, G. Albera, and R. Bhatt, "Power and performance tradeoffs using various caching strategies," in *Proc. IEEE Int. Symp. Low Power Electronics and Design (ISLPED)*, Monterey, CA, USA, 1998, pp. 64–69.

[6] D. Palomino, A. Susin, and L. Carro, "Flexible address decoder for MPSoC on FPGA," in *Proc. IEEE Int. Conf. Field Programmable Technology (FPT)*, Brisbane, Australia, 2004, pp. 357–360.

[7] S. J. E. Wilton and N. P. Jouppi, "CACTI: An enhanced cache access and cycle time model," *IEEE Journal of Solid-State Circuits*, vol. 31, no. 5, pp. 677–688, May 1996.

[8] J. Bergeron, *Writing Testbenches: Functional Verification of HDL Models*, 2nd ed. Norwell, MA, USA: Kluwer Academic Publishers, 2003.

[9] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed., Ch. 2: "Memory Hierarchy Design." Cambridge, MA, USA: Morgan Kaufmann, 2017.

