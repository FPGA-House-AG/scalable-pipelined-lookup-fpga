module sbp_lookup #(
  parameter NUM_STAGES = 32,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64
) (
  input logic clk,
  input logic rst,
  input logic [31:0] ip_addr_i,
);

logic read;
logic [ADDR_BITS - 1:0] raddr;
logic [DATA_BITS - 1:0] rdata;
logic [DATA_BITS - 1:0] wdata;
assign wdata = '0;

sbp_lookup_stage #(.STAGE_ID(0), .ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) sbp_lookup_stage_inst (
  .clk(clk),
  .rst(rst),
  .bit_pos_i(0),
  .stage_id_i(0),
  .location_i(0),
  .result_i(0),
  .ip_addr_i(ip_addr_i),

  .read(read),
  .addr(raddr),
  .data(rdata)
);

bram_tdp #(.MEMINITFILE("stage0.mem"), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
  .a_clk(clk),
  .a_wr(wr),
  .a_addr(raddr),
  .a_din(data_in),
  .a_dout(rdata),
  
  .b_clk(clk),
  .b_wr(0),
  .b_addr('0),
  .b_din(0),
);

