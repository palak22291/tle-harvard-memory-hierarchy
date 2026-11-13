# Section VI: Individual Contributions (IEEE Report)

## VI. Individual Contributions
Work was divided by module so that each member owns a complete, independently verified part of the design. The table lists Phase I contributions, taken from the team task split and the repository commit history.

| Member | RTL and testbenches | Report | Phase I video segment |
| :--- | :--- | :--- | :--- |
| **Palak Gupta** (palak22291) | Repository setup (`Makefile`, `.gitignore`, directory structure); `rtl/common/defines.vh` (memory map, address masks); `rtl/common/program_counter.v` (stall and branch support); `rtl/harvard/instruction_memory.v`; `programs/test_program.hex`; `tb/tb_phase1_harvard.v` (self-checking fetch, stall and branch tests); L2 address-map alignment to `0x0000_0800` | Section III (Proposed Solution); README block diagram and memory map | Introduction and instruction-fetch demonstration |
| **Atanu Adhikari** (techatanu) | `rtl/harvard/data_memory.v` (256 x 32-bit synchronous RAM with byte-lane writes); `tb/tb_dmem.v` (1584-check self-checking testbench with reference model); diagnosed the stale-read handshake fault in the integrated data path and supplied the tested fix | Abstract and Section I (Introduction); Section IV (Verification Results, waveform figures); Section V; this section; combined report and PDF; README simulation guide | Data memory module |
| **Sambhav Kumar** (alGo-explO) | `rtl/harvard/address_decoder.v` (bitmask decoding, unmapped-address error); `rtl/harvard/rw_control.v` (IDLE/ACTIVE/WAIT handshake FSM); `rtl/harvard/shared_l2_memory.v` (512 x 32-bit L2); `tb/tb_addr_rw.v` (26 checks); Makefile target `sim_addr_rw` | Section II (Literature Review) | Address decoding and read/write control |
| **Prince Singh** (princesingh2024) | `rtl/harvard/harvard_top.v` (integration of PC/IMEM, decoder, R/W control, DMEM and L2); `tb/tb_harvard_top.v` (25-check integration testbench); Makefile target `sim_harvard_top` | - | Integrated RTL compilation and simulation |
