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

logic [5:0]                    bit_pos_d;
logic [STAGE_ID_BITS-1:0]      stage_id_d;
logic [LOCATION_BITS-1:0]      location_d;
logic [RESULT_BITS - 1:0]      result_d;
logic [31:0]                   ip_addr_d;
logic                          update_d;

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

// data written to lookup table when updating (upd_i == 1)
assign data_o = { ip_addr_i/*prefix*/, {PAD_BIT_POS_BITS{1'b0}}, bit_pos_i/*prefix length*/, result_i };

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

always_ff @(posedge clk) begin
  if (wr_en_o) begin
    $display("writing 0x%x to stage %2d location %3d", data_o, stage_id_i, location_i);
  end
end

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

// right_sel is set when the right child is selected, i.e. bit bit_pos in ip_addr is 1
logic right_sel;
`define OLD 1
`ifdef OLD
logic [31:0] mask;
logic [31:0] masked_ip_addr;
always_comb begin : named
  /* is bit at bit_pos in ip_addr set? then select right child */
  mask = 32'b1000_0000_0000_0000_0000_0000_0000_0000 >> bit_pos_d;
  masked_ip_addr = ip_addr_d & mask;
  right_sel = masked_ip_addr > 0;
end
`else
assign right_sel = ip_addr_d[31 - bit_pos_d[4:0]];
`endif


`define REG_OUT 1
`ifdef REG_OUT
// ip_addr_o, ip_addr is passed-through
always_ff @(posedge clk) begin
  ip_addr_o <= ip_addr_d;
end

/* stage_id_o */
always_ff @(posedge clk) begin
  logic has_child = (has_left && !right_sel) || (has_right && right_sel);
  if (stage_sel && !update_d && has_child) begin
    stage_id_o <= child_stage_id_mem;
  end else begin
    stage_id_o <= stage_id_d;
  end
end

/* location_o */
always_ff @(posedge clk) begin
  if (stage_sel && !update_d) begin
    if (right_sel)
      // right child is located after left child, always in same stage
      location_o <= child_location_mem + 1;
    else
      location_o <= child_location_mem;
  end else begin
    location_o <= location_d;
  end
end

logic [RESULT_BITS - 1:0]      result_ours_d;
/* result_o */
always_ff @(posedge clk) begin
  //result_ours_d <= { {PAD_STAGE_ID_BITS{1'b0}}, stage_id_i, {PAD_LOCATION_BITS{1'b0}}, location_i, {PAD_CHILD_LR_BITS{1'b0}}, {CHILD_LR_BITS{1'b0}} };
  result_ours_d <= { {PAD_STAGE_ID_BITS{1'b0}}, 6'(STAGE_ID), {PAD_LOCATION_BITS{1'b0}}, location_i, {PAD_CHILD_LR_BITS{1'b0}}, {CHILD_LR_BITS{1'b0}} };
  if (valid_match && !update_d) begin
    /* RESULT_BITS */
    //result_o <= { {PAD_STAGE_ID_BITS{1'b0}}, stage_id_d, {PAD_LOCATION_BITS{1'b0}}, location_d, {PAD_CHILD_LR_BITS{1'b0}}, {CHILD_LR_BITS{1'b0}} };
    result_o <= result_ours_d;
  end else begin
    result_o <= result_d;
  end
end

/* bit_pos_o */
always_ff @(posedge clk) begin
  if (stage_sel && !update_d) begin
    bit_pos_o <= bit_pos_d + 1;
  end else begin
    bit_pos_o <= bit_pos_d;
  end
end

/* update_o */
always_ff @(posedge clk) begin
  update_o <= update_d;
end

`else // !REG_OUT

// ip_addr_o, ip_addr is passed-through
always_comb begin
  ip_addr_o = ip_addr_d;
end

/* stage_id_o */
always_comb begin
  logic has_child = (has_left && !right_sel) || (has_right && right_sel);
  if (stage_sel && !update_d && has_child) begin
    stage_id_o = child_stage_id_mem;
  end else begin
    stage_id_o = stage_id_d;
  end
end

/* location_o */
always_comb begin
  if (stage_sel && !update_d) begin
    if (right_sel)
      // right child is located after left child, always in same stage
      location_o = child_location_mem + 1;
    else
      location_o = child_location_mem;
  end else begin
    location_o = location_d;
  end
end

logic [RESULT_BITS - 1:0]      result_ours_d;
/* result_o */
always_comb begin
  result_ours_d = { {PAD_STAGE_ID_BITS{1'b0}}, 6'(STAGE_ID), {PAD_LOCATION_BITS{1'b0}}, location_i, {PAD_CHILD_LR_BITS{1'b0}}, {CHILD_LR_BITS{1'b0}} };
  if (valid_match && !update_d) begin
    result_o = result_ours_d;
  end else begin
    result_o = result_d;
  end
end

/* bit_pos_o */
always_comb begin
  if (stage_sel && !update_d) begin
    bit_pos_o = bit_pos_d + 1;
  end else begin
    bit_pos_o = bit_pos_d;
  end
end

/* update_o */
always_comb begin
  update_o = update_d;
end

`endif

endmodule
