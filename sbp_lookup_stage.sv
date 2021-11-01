`default_nettype none

// https://danstrother.com/2010/09/11/inferring-rams-in-fpgas/
module sbp_lookup_stage #(
  parameter STAGE_ID = 1,
  parameter STAGE_BITS = 6,
  parameter LOCATION_BITS = 11,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64
) (
  input   wire                clk,
  /* verilator lint_off UNUSED */
  input   wire                rst,
  /* verilator lint_on UNUSED */
  input   wire    [5:0]       bit_pos_i,
  input   wire    [STAGE_BITS-1:0]       stage_id_i,
  input   wire    [LOCATION_BITS-1:0]      location_i,
  input   wire    [LOCATION_BITS + STAGE_BITS - 1:0]      result_i,
  input   reg     [31:0]      ip_addr_i,

  output   wire   [5:0]       bit_pos_o,
  output   wire   [STAGE_BITS-1:0]       stage_id_o,
  output   logic  [LOCATION_BITS-1:0]      location_o,
  output   wire   [LOCATION_BITS + STAGE_BITS - 1:0]      result_o,
  output  reg     [31:0]      ip_addr_o,
/* verilator lint_off UNUSED */
  output wire read,
/* verilator lint_on UNUSED */
  output wire [ADDR_BITS - 1:0] addr,
  input wire  [DATA_BITS - 1:0] data
);

logic [5:0]       bit_pos_d;
logic [STAGE_BITS-1:0]       stage_id_d;
logic [LOCATION_BITS-1:0]      location_d;
logic [LOCATION_BITS + STAGE_BITS - 1:0]      result_d;
logic [31:0]      ip_addr_d;

// fields in memory word
logic [31:0]      prefix_mem;
logic [5:0]       prefix_length_mem;
// @TODO add result
logic [STAGE_BITS-1:0]       child_stage_id_mem;
logic [LOCATION_BITS-1:0]      child_location_mem;

/* verilator lint_off UNUSED */
logic [6:0] dummy_mem;
logic has_left;
logic has_right;
/* verilator lint_on UNUSED */

// 32 + 6 + 6 + 11 + 7 + 1 + 1 = 32 + 8(dummy) + 24 = 64 = 8 bytes
assign {prefix_mem, prefix_length_mem, child_stage_id_mem, child_location_mem, dummy_mem, has_left, has_right} = data;

/* stage_id and location delayed */
always_ff @(posedge clk) begin
  if (clk) begin
    bit_pos_d  <= bit_pos_i;
    stage_id_d <= stage_id_i;
    location_d <= location_i;
    ip_addr_d  <= ip_addr_i;
    result_d   <= result_i;
  end
end

// ip_addr is passed through
always_ff @(posedge clk) begin
  ip_addr_o <= ip_addr_d;
end

// stage_sel is set when this stage instance is selected
logic stage_sel;
always_comb begin
  /* is this stage selected? */
  stage_sel = (stage_id_d == STAGE_ID);
end

// read from stage memory
assign read = 1;
assign addr = location_i;

// ip_addr_i matches against prefix from stage memory?
logic prefix_match;
always_comb begin
  /* do the prefix bits match? */
  prefix_match = ((ip_addr_d ^ prefix_mem) >> (32 - prefix_length_mem)) == 0;
end

logic valid_match;
always_comb begin
  valid_match = prefix_match && stage_sel;
end

// right_sel is set when the right child is selected
logic right_sel;
logic [31:0] mask;
logic [31:0] masked_ip_addr;
always_comb begin
  /* is bit at bit_pos in ip_addr set? then select right child */
  mask = 32'b1000_0000_0000_0000_0000_0000_0000_0000 >> bit_pos_d;
  masked_ip_addr = ip_addr_d & mask;
  right_sel = masked_ip_addr > 0;
end

/* location_o */
always_ff @(posedge clk) begin
  if (stage_sel) begin
    if (right_sel)
      location_o <= child_location_mem + 1;
    else
      location_o <= child_location_mem;
  end else begin
    location_o <= location_d;
  end
end

/* stage_id_o */
always_ff @(posedge clk) begin
  if (stage_sel) begin
    stage_id_o <= child_stage_id_mem;
  end else begin
    stage_id_o <= stage_id_d;
  end
end

/* result_o */
always_ff @(posedge clk) begin
  if (valid_match) begin
    result_o <= { stage_id_d, location_d };
  end else begin
    result_o <= result_d;
  end
end

/* bit_pos_o */
always_ff @(posedge clk) begin
  if (stage_sel) begin
    // @TODO verify
    bit_pos_o <= bit_pos_d + 1;
  end else begin
    bit_pos_o <= bit_pos_d;
  end
end


endmodule

