`default_nettype none

module sbp_lookup #(
  parameter NUM_STAGES = 32,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64
) (
  input logic clk,
  input logic rst,
  input logic [31:0] ip_addr_i,
  output logic [16:0] result_o
);
/* verilator lint_off UNUSED */
logic read;
/* verilator lint_on UNUSED */
logic [ADDR_BITS - 1:0] raddr;
logic [DATA_BITS - 1:0] rdata;
logic [DATA_BITS - 1:0] wdata;
assign wdata = '0;

sbp_lookup_stage #(.STAGE_ID(0), .ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) sbp_lookup_stage_inst (
  .clk(clk),
  /* verilator lint_off UNUSED */
  .rst(rst),
  /* verilator lint_on UNUSED */
  .bit_pos_i(0),
  .stage_id_i(0),
  .location_i(0),
  .result_i(0),
  .ip_addr_i(ip_addr_i),

  // passed to next stage
  .result_o(result_o),

  /* verilator lint_off PINCONNECTEMPTY */
  .bit_pos_o(),
  .stage_id_o(),
  .location_o(),
  .ip_addr_o(),
  /* verilator lint_on PINCONNECTEMPTY */
  /* verilator lint_off UNUSED */
  .read(read),
  /* verilator lint_on UNUSED */
  .addr(raddr),
  .data(rdata)
);

logic wr = 0;

bram_tdp #(.MEMINIT_FILENAME("stage0.mem"), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
  .a_clk(clk),
  .a_wr(wr),
  .a_addr(raddr),
  .a_din(wdata),
  .a_dout(rdata),
  
  .b_clk(clk),
  .b_wr(0),
  .b_addr('0),
  .b_din(0),
  /* verilator lint_off PINCONNECTEMPTY */
  .b_dout()
  /* verilator lint_on PINCONNECTEMPTY */
);

endmodule

