"""
Team TLE - Phase II Analytical CPI & Structural Hazard Estimate
First-order (pre-RTL) model of 32-bit Harvard Split Memory vs. Von Neumann
Unified Memory across the 16-instruction L1 (DMEM) + L2 benchmark workload.

NOTE: this is an analytical estimate with assumed latencies (1-clock
instructions on the Harvard side). The MEASURED results reported in the
paper come from the RTL simulation:  make sim_arch_compare
(Harvard 74 vs. Von Neumann 90 cycles at L2_LATENCY = 0, i.e. 1.216x).
"""

def evaluate_memory_hierarchy(
    total_instructions=16,
    dmem_ops=8,
    l2_ops=4,
    rw_ctrl_cycles=3,
    l2_extra_wait=1
):
    alu_nop_ops = total_instructions - (dmem_ops + l2_ops)

    # Harvard Architecture:
    # Instruction Fetch (IF) and Data Access (MEM via rw_control) operate on decoupled buses.
    # IF proceeds in parallel with data transactions; only multi-cycle data wait states add cycles.
    harvard_if_cycles = total_instructions
    harvard_l2_wait_cycles = l2_ops * l2_extra_wait
    harvard_total_cycles = harvard_if_cycles + harvard_l2_wait_cycles
    harvard_cpi = harvard_total_cycles / total_instructions

    # Von Neumann Architecture:
    # Unified single bus forces serialization of IF and MEM stages.
    # Every DMEM or L2 access stalls the Instruction Fetch path for the full rw_control transaction.
    vn_structural_hazard_stalls = (dmem_ops + l2_ops) * rw_ctrl_cycles
    vn_l2_wait_cycles = l2_ops * l2_extra_wait
    vn_total_cycles = total_instructions + vn_structural_hazard_stalls + vn_l2_wait_cycles
    vn_cpi = vn_total_cycles / total_instructions

    speedup = vn_total_cycles / harvard_total_cycles
    stall_reduction = 100.0 * (1.0 - (harvard_l2_wait_cycles / (vn_structural_hazard_stalls + vn_l2_wait_cycles)))

    print("==================================================================")
    print("  Team TLE - Phase II Harvard vs. Von Neumann ANALYTICAL Estimate  ")
    print("==================================================================")
    print(f"Workload Breakdown       : {total_instructions} Total Instructions "
          f"({dmem_ops} DMEM, {l2_ops} L2, {alu_nop_ops} ALU/NOP)")
    print(f"R/W Control Handshake    : {rw_ctrl_cycles} clocks per data transaction")
    print("------------------------------------------------------------------")
    print(f"Harvard Split Hierarchy  : {harvard_total_cycles:2d} cycles | CPI = {harvard_cpi:.2f} | "
          f"Structural Stalls = 0")
    print(f"Von Neumann Unified Bus  : {vn_total_cycles:2d} cycles | CPI = {vn_cpi:.2f} | "
          f"Structural Stalls = {vn_structural_hazard_stalls}")
    print("------------------------------------------------------------------")
    print(f"Throughput Speedup       : {speedup:.2f}x faster ({(speedup - 1.0) * 100:.1f}% throughput gain)")
    print(f"Bus Stall Reduction      : {stall_reduction:.1f}% reduction in memory wait cycles")
    print("==================================================================")
    print("NOTE: analytical estimate only. Measured RTL results (reported in")
    print("the paper): run `make sim_arch_compare`  ->  Harvard 74 vs. Von")
    print("Neumann 90 cycles at L2_LATENCY = 0 (1.216x speedup).")
    print("==================================================================")

if __name__ == "__main__":
    evaluate_memory_hierarchy()
