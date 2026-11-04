`include "defines.vh"

module program_counter (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   stall,       // Freezes PC during structural hazard (Von Neumann)
    input  wire                   branch_en,   // Jump/Branch enable
    input  wire [`ADDR_WIDTH-1:0] branch_addr, // Target branch address
    output reg  [`ADDR_WIDTH-1:0] pc_out       // Current instruction byte address
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'h0000_0000;
        end else if (stall) begin
            pc_out <= pc_out; // Hold PC when memory bus is busy
        end else if (branch_en) begin
            pc_out <= branch_addr;
        end else begin
            pc_out <= pc_out + 32'd4; // Advance to next 32-bit word (+4 bytes)
        end
    end

endmodule
