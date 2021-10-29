
// https://danstrother.com/2010/09/11/inferring-rams-in-fpgas/
module sbp_lookup_stage #(
  parameter STAGE_ID = 1,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64
) (
  input   wire                clk,
  input   wire                rst,
  input   wire    [5:0]       bit_pos_i,
  input   wire    [5:0]       stage_id_i,
  input   wire    [31:0]      location_i,
  input   wire    [31:0]      result_i,
  input   reg     [31:0]      ip_addr_i,

  output   wire   [5:0]       bit_pos_o,
  output   wire   [5:0]       stage_id_o,
  output   logic  [9:0]       location_o,
  output   wire   [31:0]      result_o,
  output  reg     [31:0]      ip_addr_o,

  output wire read,
  output wire [ADDR_BITS - 1:0] addr,
  input wire  [DATA_BITS - 1:0] data
);

logic [5:0]       bit_pos_d;
logic [5:0]       stage_id_d;
logic [31:0]      location_d;
logic [31:0]      result_d;
logic [31:0]      ip_addr_d;

// fields in memory word
logic [31:0]      prefix_mem;
logic [5:0]       prefix_length_mem;
logic [6:0]       child_stage_mem;
logic [9:0]       child_location_mem;
logic [7:0] dummy_mem;
logic has_left;
logic has_right;

// 32 + 6 + 6 + 10 + 8 + 1 + 1 = 32 + 8(dummy) + 24 = 64 = 8 bytes
assign {prefix_mem, prefix_length_mem, child_stage_mem, child_location_mem, dummy_mem, has_left, has_right} = data;

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

assign read = (stage_id_i == STAGE_ID);
assign addr = location_i;

// ip_addr_i matches against prefix
logic prefix_match;
always_comb begin
  /* do the prefix bits match? */
  prefix_match = ((ip_addr_d ^ prefix) >> (32 - prefix_length)) == 0;
end

logic valid_match;
always_comb begin
  valid_match = prefix_match && stage_sel;
end

// right_sel is set when the right child is selected
logic right_sel;
always_comb begin
  /* is this stage selected? */
  right_sel = (stage_id_d == STAGE_ID);
end

/* location_o */
always_ff @(posedge clk) begin
  location_o <= location_d;
  if (stage_sel) begin
    location_o <= location_i;
  end
end

endmodule

