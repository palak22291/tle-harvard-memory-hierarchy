`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// address_decoder.v
//
// Combinational address decoder for the Harvard memory subsystem.
//
// Memory Map (from defines.vh):
//   0x0000_0000 – 0x0000_03FF  →  DMEM  (1 KB,  mask = FFFF_FC00)
//   0x0000_0800 – 0x0000_0FFF  →  L2    (2 KB,  mask = FFFF_F800)
//   everything else             →  invalid_addr_err
//
// Decode uses bit-mask comparison (same approach documented in the IEEE
// proposed-solution section) so synthesis maps cleanly to AND/OR trees
// rather than range comparators.
//
// Outputs are one-hot chip-selects that feed rw_control and the memory
// arrays directly; they are deasserted whenever `d_valid` is low so that
// the memories stay quiet during idle cycles.
// -----------------------------------------------------------------------------
module address_decoder (
    input  wire [`ADDR_WIDTH-1:0] d_addr,          // Byte address from CPU / rw_control
    input  wire                   d_valid,          // Address-valid strobe (from rw_control)

    output wire                   cs_dmem,          // Chip-select → data_memory
    output wire                   cs_l2,            // Chip-select → shared_l2_memory
    output wire                   invalid_addr_err  // High when address is unmapped
);

    // -------------------------------------------------------------------------
    // Bitmask decode
    //   DMEM : (d_addr & DMEM_MASK) == DMEM_BASE_ADDR
    //   L2   : (d_addr & L2_MASK)   == L2_BASE_ADDR
    // -------------------------------------------------------------------------
    wire dmem_hit = ((d_addr & `DMEM_MASK) == `DMEM_BASE_ADDR);
    wire l2_hit   = ((d_addr & `L2_MASK)   == `L2_BASE_ADDR);

    assign cs_dmem         = d_valid & dmem_hit;
    assign cs_l2           = d_valid & l2_hit & ~dmem_hit; // L2 cannot overlap DMEM
    assign invalid_addr_err = d_valid & ~dmem_hit & ~l2_hit;

endmodule

