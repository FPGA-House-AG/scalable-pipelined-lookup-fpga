// A parameterized, inferable, true dual-port, dual-clock block RAM in Verilog.

module bram_tdp #(
    parameter STAGE_ID = 0,
    parameter DATA = 72,
    parameter ADDR = 10,
    parameter MEMINIT_FILENAME = "stage0.mem"
) (
    // Port A
    input   wire                a_clk,
    input   wire                a_wr,
    input   wire    [ADDR-1:0]  a_addr,
    input   wire    [DATA-1:0]  a_din,
    output  reg     [DATA-1:0]  a_dout,
     
    // Port B
    input   wire                b_clk,
    input   wire                b_wr,
    input   wire    [ADDR-1:0]  b_addr,
    input   wire    [DATA-1:0]  b_din,
    output  reg     [DATA-1:0]  b_dout
);
 
// Shared memory
(* ram_style = "block" *) reg [DATA-1:0] mem [(2**ADDR)-1:0];

initial begin
  $display("Initializing RAM for stage %0d with contents of %s.", STAGE_ID, MEMINIT_FILENAME);
  $readmemh(MEMINIT_FILENAME, mem);
end

// Port A
always @(posedge a_clk) begin
    a_dout      <= mem[a_addr];
    if (a_wr) begin
        a_dout      <= a_din;
        mem[a_addr] <= a_din;
    end
end
 
// Port B
always @(posedge b_clk) begin
    b_dout      <= mem[b_addr];
    if(b_wr) begin
        b_dout      <= b_din;
        mem[b_addr] <= b_din;
    end
end
 
endmodule
