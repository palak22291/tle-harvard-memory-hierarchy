IVERILOG = iverilog
VVP      = vvp
CFLAGS   = -g2012 -I rtl/common

sim_fetch:
	$(IVERILOG) $(CFLAGS) -o sim/phase1_fetch.vvp rtl/common/program_counter.v rtl/harvard/instruction_memory.v tb/tb_phase1_harvard.v
	$(VVP) sim/phase1_fetch.vvp

sim_dmem:
	$(IVERILOG) $(CFLAGS) -o sim/dmem.vvp rtl/harvard/data_memory.v tb/tb_dmem.v
	$(VVP) sim/dmem.vvp

sim_addr_rw:
	$(IVERILOG) $(CFLAGS) -o sim/addr_rw.vvp \
		rtl/harvard/address_decoder.v \
		rtl/harvard/rw_control.v \
		rtl/harvard/data_memory.v \
		rtl/harvard/shared_l2_memory.v \
		tb/tb_addr_rw.v
	$(VVP) sim/addr_rw.vvp

sim_harvard_top:
	$(IVERILOG) $(CFLAGS) -o sim/harvard_top.vvp \
		rtl/common/program_counter.v \
		rtl/harvard/instruction_memory.v \
		rtl/harvard/data_memory.v \
		rtl/harvard/address_decoder.v \
		rtl/harvard/rw_control.v \
		rtl/harvard/shared_l2_memory.v \
		rtl/harvard/harvard_top.v \
		tb/tb_harvard_top.v
	$(VVP) sim/harvard_top.vvp

# Phase II (Member 2): L2 multi-cycle latency + data-hierarchy latency table
sim_l2_latency:
	$(IVERILOG) $(CFLAGS) -o sim/l2_latency.vvp \
		rtl/harvard/address_decoder.v \
		rtl/harvard/rw_control.v \
		rtl/harvard/data_memory.v \
		rtl/harvard/shared_l2_memory.v \
		tb/tb_l2_latency.v
	$(VVP) sim/l2_latency.vvp

# Phase II (Member 3): Von Neumann baseline - bus arbiter + unified memory
sim_von_neumann:
	$(IVERILOG) $(CFLAGS) -o sim/von_neumann.vvp \
		rtl/von_neumann/unified_memory.v \
		rtl/von_neumann/bus_arbiter.v \
		tb/tb_von_neumann.v
	$(VVP) sim/von_neumann.vvp

# Phase II (Member 4): same CPU driver on Harvard vs. Von Neumann, side by side
sim_arch_compare:
	$(IVERILOG) $(CFLAGS) -o sim/arch_comparison.vvp \
		rtl/common/simple_cpu_driver.v \
		rtl/harvard/instruction_memory.v \
		rtl/harvard/address_decoder.v \
		rtl/harvard/rw_control.v \
		rtl/harvard/data_memory.v \
		rtl/harvard/shared_l2_memory.v \
		rtl/harvard/harvard_cpu_top.v \
		rtl/von_neumann/unified_memory.v \
		rtl/von_neumann/bus_arbiter.v \
		rtl/von_neumann/von_neumann_top.v \
		tb/tb_architecture_comparison.v
	$(VVP) sim/arch_comparison.vvp

sim_all: sim_fetch sim_dmem sim_addr_rw sim_harvard_top sim_l2_latency sim_von_neumann sim_arch_compare

clean:
	rm -f sim/*.vvp sim/*.vcd
