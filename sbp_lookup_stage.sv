`default_nettype none

// https://danstrother.com/2010/09/11/inferring-rams-in-fpgas/
module sbp_lookup_stage #(
  parameter STAGE_ID = 1,
  parameter STAGE_ID_BITS = 6,
  parameter LOCATION_BITS = 11,
  parameter PAD_BITS = 4,
  parameter ADDR_BITS = 11
  //parameter DATA_BITS = 72
) (
  clk, rst,
  update_i, update_o,
  ip_addr_i, bit_pos_i, stage_id_i, location_i, result_i,
  ip_addr_o, bit_pos_o, stage_id_o, location_o, result_o,
  wr_en_o, addr_o, data_i, data_o
);

localparam BIT_POS_BITS = 6;
localparam CHILD_LR_BITS = 2;

/* pad every field to nibbles */
localparam PAD_BIT_POS_BITS  = (32 -  BIT_POS_BITS) % PAD_BITS;
localparam PAD_STAGE_ID_BITS = (32 - STAGE_ID_BITS) % PAD_BITS;
localparam PAD_LOCATION_BITS = (32 - LOCATION_BITS) % PAD_BITS;
localparam PAD_CHILD_LR_BITS = (32 - CHILD_LR_BITS) % PAD_BITS;

/* [23:22][21:16] [15][14:4] [3:2][1:0] */
localparam RESULT_BITS = PAD_STAGE_ID_BITS + STAGE_ID_BITS +
                         PAD_LOCATION_BITS + LOCATION_BITS +
                         PAD_CHILD_LR_BITS + CHILD_LR_BITS;

localparam DATA_BITS = 32 + PAD_BIT_POS_BITS + BIT_POS_BITS + RESULT_BITS;

input   wire                clk;
/* verilator lint_off UNUSED */
input   wire                rst;
/* verilator lint_on UNUSED */

/* ip address to be looked up, or if update_i==1, prefix to write */
input   wire    [31:0]                   ip_addr_i;
input   wire    [5:0]                    bit_pos_i;
input   wire    [STAGE_ID_BITS-1:0]      stage_id_i;
input   wire    [LOCATION_BITS-1:0]      location_i;
input   wire    [RESULT_BITS - 1:0]      result_i;

input wire logic update_i;
output logic     update_o;

output   logic  [31:0]                   ip_addr_o;
/* next bit to test */
output   logic  [5:0]                    bit_pos_o;
/* next stage to visit */
output   logic  [STAGE_ID_BITS-1:0]      stage_id_o;
output   logic  [LOCATION_BITS-1:0]      location_o;
/* longest prefix match result so far */
output   logic  [RESULT_BITS - 1:0]      result_o;

/* lookup table memory interface */
output wire wr_en_o;
output logic [ADDR_BITS - 1:0] addr_o;
input  wire  [DATA_BITS - 1:0] data_i;
output logic [DATA_BITS - 1:0] data_o;

logic [5:0]                    bit_pos_d, bit_pos_d2;
logic [STAGE_ID_BITS-1:0]      stage_id_d, stage_id_d2, child_stage_id_d2;
logic [LOCATION_BITS-1:0]      location_d, location_d2, child_location_d2;
logic [RESULT_BITS - 1:0]      result_d, result_d2;
logic [31:0]                   ip_addr_d, ip_addr_d2;
logic                          update_d, update_d2;

// fields in memory word
logic [31:0]      prefix_mem;
logic [5:0]       prefix_length_mem;
// @TODO add result
logic [STAGE_ID_BITS-1:0] child_stage_id_mem;
logic [LOCATION_BITS-1:0] child_location_mem;

generate
  /* verilator lint_off UNUSED */
  logic has_left;
  logic has_right;
  /* verilator lint_on UNUSED */
  if (PAD_BITS > 1) begin
    /* verilator lint_off UNUSED */
    logic [PAD_BIT_POS_BITS  - 1:0] padding1;
    logic [PAD_STAGE_ID_BITS - 1:0] padding2;
    logic [PAD_LOCATION_BITS - 1:0] padding3;
    logic [PAD_CHILD_LR_BITS - 1:0] padding4;
    /* verilator lint_on UNUSED */

    // decompose memory data fields, for now use extra padding bits to have human readable nibble alignment
    //32 + (2+)6 + (2+)6 + (1+)11 + (2+)1 + 1 = 64 bits = 8 bytes
    assign {prefix_mem, padding1, prefix_length_mem, padding2, child_stage_id_mem, padding3, child_location_mem, padding4, has_left, has_right} = data_i;

  end else begin
    assign {prefix_mem, prefix_length_mem, child_stage_id_mem, child_location_mem, has_left, has_right} = data_i;
  end
endgenerate

/* stage_id and location delayed */
always_ff @(posedge clk) begin
  bit_pos_d  <= bit_pos_i;
  stage_id_d <= stage_id_i;
  location_d <= location_i;
  ip_addr_d  <= ip_addr_i;
  result_d   <= result_i;
  update_d   <=  update_i;
end

// stage_sel is set when this stage instance is selected
logic stage_sel;
always_comb begin
  /* is this stage selected? */
  stage_sel = (stage_id_d == STAGE_ID);
end

// write to stage memory
assign wr_en_o = update_i && (stage_id_i == STAGE_ID);
assign addr_o = location_i;
// data written to lookup table when updating (upd_i == 1)
assign data_o = { ip_addr_i/*prefix*/, {PAD_BIT_POS_BITS{1'b0}}, bit_pos_i/*prefix length*/, result_i };

always_ff @(posedge clk) begin
  if (wr_en_o) begin
    $display("writing 0x%x to stage %2d location %3d", data_o, stage_id_i, location_i);
  end
end

// ip_addr_i matches against prefix from stage memory?
//logic prefix_match;
logic [31:0] prefix_xor;
logic [31:0] prefix_mask;
logic [31:0] prefix_xor_masked;
always_comb begin
  prefix_mask = 32'(33'sb1_0000_0000_0000_0000_0000_0000_0000_0000 >>> prefix_length_mem);
  prefix_xor = ip_addr_d ^ prefix_mem;
  prefix_xor_masked = prefix_xor & prefix_mask;
  //prefix_match = (prefix_xor & prefix_mask) == 0;
  //$display("stage %d prefix_mask 0x%x prefix_length_mem %d", STAGE_ID, prefix_mask, prefix_length_mem);
end

//always_ff @(posedge clk) begin
//  $display("ip_addr_d 0x%x", ip_addr_d);
//  $display("prefix_mem 0x%x", prefix_mem);
//  $display("prefix_length_mem %d", prefix_length_mem);
//end

///logic valid_match;
///always_comb begin
///  valid_match = prefix_match && stage_sel;
///end

// right_sel is set when the right child is selected, i.e. bit bit_pos in ip_addr is 1
logic [31:0] mask;
///// alternative is to calculate the mask on the input and register it
/////always_ff @(posedge clk) begin
/////  mask <= 32'b1000_0000_0000_0000_0000_0000_0000_0000 >> bit_pos_i;
/////end

logic right_sel;
logic [31:0] masked_ip_addr;
always_comb begin : named
  /* is bit at bit_pos in ip_addr set? then select right child */
  mask = 32'b1000_0000_0000_0000_0000_0000_0000_0000 >> bit_pos_d;
  masked_ip_addr = ip_addr_d & mask;
  right_sel = masked_ip_addr > 0;
end

logic has_child;/*@TODO remove?*/
assign has_child = (has_left && !right_sel) || (has_right && right_sel);

//logic right_sel_d2;
logic stage_sel_d2;
logic prefix_match_d2;
///logic valid_match_d2;
logic has_child_d2;
///logic [31:0] prefix_mask_d2;
///logic [31:0] prefix_xor_d2;
logic [31:0] prefix_xor_masked_d2;
always_ff @(posedge clk) begin
  stage_id_d2 <= stage_id_d;
  location_d2 <= location_d;
  ip_addr_d2  <= ip_addr_d;
  result_d2   <= result_d;
  update_d2   <= update_d;

  if (stage_sel && !update_d) begin
    bit_pos_d2 <= bit_pos_d + 1;
  end else begin
    bit_pos_d2 <= bit_pos_d;
  end

  child_stage_id_d2 <= child_stage_id_mem;
  if (right_sel) begin
    // right child is located after left child, always in same stage
    child_location_d2 <= child_location_mem + 1;
  end else begin
    child_location_d2 <= child_location_mem;
  end

  stage_sel_d2 <= stage_sel;
  //right_sel_d2 <= right_sel ;

  ///valid_match_d2  <= valid_match;
  has_child_d2 <= has_child;/*@TODO remove?*/
  ///prefix_mask_d2 <= prefix_mask;
  ///prefix_xor_d2 <= prefix_xor;
  prefix_xor_masked_d2 <= prefix_xor_masked;
  ///prefix_match_d2 <= prefix_match;
end
assign prefix_match_d2 = (prefix_xor_masked_d2) == 0;

// ip_addr_o, ip_addr is always passed-through
always_comb begin
  ip_addr_o = ip_addr_d2;
end

/* stage_id_o */
always_comb begin
  // this stage was addressed for lookup?
  if (stage_sel_d2 && !update_d2 /* && has_child_d2 @TODO remove?*/) begin
    assert(has_child_d2);
    // pass stage index from memory
    stage_id_o = child_stage_id_d2;
  end else begin
    stage_id_o = stage_id_d2;
  end
end

/* location_o */
always_comb begin
  // this stage was addressed for lookup?
  if (stage_sel_d2 && !update_d2) begin
    // pass location index from memory (already incremented in case of right child)
    location_o = child_location_d2;
  end else begin
    location_o = location_d2;
  end
end

logic [RESULT_BITS - 1:0] result_ours_d2;
/* result_o */
always_comb begin
  result_ours_d2 = { {PAD_STAGE_ID_BITS{1'b0}}, 6'(STAGE_ID), {PAD_LOCATION_BITS{1'b0}}, location_d2, {PAD_CHILD_LR_BITS{1'b0}}, {CHILD_LR_BITS{1'b0}} };
  // this stage provided a (by design; longer) prefix match?
  if (stage_sel_d2 && prefix_match_d2 && !update_d2) begin
    result_o = result_ours_d2;
  end else begin
    result_o = result_d2;
  end
end

/* bit_pos_o */
always_comb begin
  bit_pos_o = bit_pos_d2;
end

/* update_o */
always_comb begin
  update_o = update_d2;
end

endmodule
