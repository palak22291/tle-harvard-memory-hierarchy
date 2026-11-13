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

sim_all: sim_fetch sim_dmem sim_addr_rw sim_harvard_top

clean:
	rm -f sim/*.vvp sim/*.vcd
