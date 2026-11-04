IVERILOG = iverilog
VVP      = vvp
CFLAGS   = -g2012 -I rtl/common

sim_fetch:
	$(IVERILOG) $(CFLAGS) -o sim/phase1_fetch.vvp rtl/common/program_counter.v rtl/harvard/instruction_memory.v tb/tb_phase1_harvard.v
	$(VVP) sim/phase1_fetch.vvp

clean:
	rm -f sim/*.vvp sim/*.vcd
