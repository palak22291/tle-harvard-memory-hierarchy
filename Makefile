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

# ---------------------------------------------------------------------------
# Phase II: synthesis (open-source flow, Yosys + nextpnr)
#   make synth    -> synth/<top>_ecp5.rpt (Lattice ECP5 LFE5U-25F, place & route, Fmax)
#                    synth/<top>_artix7.rpt (Xilinx Artix-7 resource estimate, no P&R)
# Tools: Yosys >= 0.40 and nextpnr-ecp5 (or the YoWASP builds:
#   pip install yowasp-yosys yowasp-nextpnr-ecp5, then
#   make synth YOSYS=yowasp-yosys NEXTPNR=yowasp-nextpnr-ecp5)
# Every RAM/ROM zero-fills in an initial loop and then runs $readmemh. Icarus
# applies these in source order; Yosys gives the single-word zero writes a
# higher priority, which would leave the instruction ROM empty. INIT_FIX gives
# the $readmemh image the top priority again, so the netlist holds the same
# program the simulation runs.
# ---------------------------------------------------------------------------
YOSYS   ?= yosys
NEXTPNR ?= nextpnr-ecp5
SYNTH_FREQ ?= 100
INIT_FIX = setparam -set PRIORITY 2000000000 t:\$$meminit_v2 r:WORDS=1 %d

HARVARD_SYS = rtl/common/simple_cpu_driver.v rtl/harvard/instruction_memory.v \
	rtl/harvard/address_decoder.v rtl/harvard/rw_control.v rtl/harvard/data_memory.v \
	rtl/harvard/shared_l2_memory.v rtl/harvard/harvard_cpu_top.v
VN_SYS = rtl/common/simple_cpu_driver.v rtl/von_neumann/unified_memory.v \
	rtl/von_neumann/bus_arbiter.v rtl/von_neumann/von_neumann_top.v

synth: synth_harvard synth_von_neumann
	python3 scripts/synth_summary.py

synth_harvard:
	$(MAKE) synth_one TOP=harvard_cpu_top SRCS="$(HARVARD_SYS)"

synth_von_neumann:
	$(MAKE) synth_one TOP=von_neumann_top SRCS="$(VN_SYS)"

synth_one:
	@mkdir -p synth
	$(YOSYS) -q -l synth/$(TOP)_ecp5_yosys.log -p "read_verilog -sv -I rtl/common $(SRCS); \
		hierarchy -top $(TOP); proc; flatten; $(INIT_FIX); synth_ecp5 -top $(TOP) -json synth/$(TOP)_ecp5.json; \
		tee -q -o synth/$(TOP)_ecp5.rpt stat"
	$(NEXTPNR) --25k --package CABGA256 --out-of-context --freq $(SYNTH_FREQ) --seed 1 \
		--json synth/$(TOP)_ecp5.json --report synth/$(TOP)_ecp5_pnr.json \
		--log synth/$(TOP)_ecp5_pnr.log -q
	$(YOSYS) -q -l synth/$(TOP)_artix7_yosys.log -p "read_verilog -sv -I rtl/common $(SRCS); \
		hierarchy -top $(TOP); proc; flatten; $(INIT_FIX); synth_xilinx -family xc7 -top $(TOP); \
		tee -q -o synth/$(TOP)_artix7.rpt stat"

clean:
	rm -f sim/*.vvp sim/*.vcd
