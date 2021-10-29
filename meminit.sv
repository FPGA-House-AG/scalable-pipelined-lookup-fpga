module meminit #(
    parameter DATA = 64,
    parameter ADDR = 11
) (
    // Port A
    input   wire                clk
);

//logic x;

// Shared memory
reg [DATA-1:0] mem [(2**ADDR)-1:0];

initial begin
  $display("Loading RAM.");
  $readmemh("../scalable-pipelined-lookup-c/stage0.mem", mem);
end

logic [DATA-1:0] dout;
logic [DATA-1:0] din;
logic [ADDR-1:0] addr;
logic wr;
initial wr = 0;
initial din = '0;
initial addr = '0;

// Port A
always @(posedge clk) begin
    dout <= mem[addr];
    $display("%x: %x", addr, dout);
    if (wr) begin
        dout      <= din;
        mem[addr] <= din;
    end
    //addr <= addr + 1;
end

// Port A
always @(posedge clk) begin
   // addr <= addr + 1;
end

// Port A
always @(posedge clk) begin
    //$display("%x: %x", addr, dout);
end

endmodule