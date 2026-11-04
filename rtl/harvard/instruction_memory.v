`include "defines.vh"

module instruction_memory #(
    parameter MEM_INIT_FILE = "programs/test_program.hex"
)(
    input  wire                   clk,
    input  wire                   imem_en,     // Instruction fetch enable
    input  wire [`ADDR_WIDTH-1:0] i_addr,      // Byte address from Program Counter
    output reg  [`DATA_WIDTH-1:0] i_rdata,     // 32-bit fetched instruction
    output reg                    i_ready      // Asserted when instruction is valid
);

    reg [`DATA_WIDTH-1:0] rom [0:`IMEM_DEPTH-1];
    wire [7:0] word_addr = i_addr[9:2]; // Word-aligned index

    integer i;
    initial begin
        for (i = 0; i < `IMEM_DEPTH; i = i + 1) begin
            rom[i] = 32'h0000_0000;
        end
        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, rom);
        end
    end

    always @(posedge clk) begin
        if (imem_en) begin
            i_rdata <= rom[word_addr];
            i_ready <= 1'b1;
        end else begin
            i_rdata <= 32'h0000_0000;
            i_ready <= 1'b0;
        end
    end

endmodule
