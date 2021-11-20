`default_nettype none

module sbp_lookup #(
  parameter NUM_STAGES = 32,
  parameter ADDR_BITS = 11,
  //parameter DATA_BITS = 72,
  parameter STAGE_ID_BITS = 6,
  parameter LOCATION_BITS = 11,
  parameter PAD_BITS = 4
) (
  clk, rst,
  /* update interface */
  upd_i, upd_stage_id_i, upd_location_i, upd_length_i, upd_childs_stage_id_i, upd_childs_location_i, upd_childs_lr_i,
  /* lookup request */
  ip_addr_i,
  /* lookup result */
  result_o, ip_addr_o
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

input wire logic clk;
input wire logic rst;
input wire logic [31:0] ip_addr_i;

/* update interface, to write to lookup tables */
input wire logic                     upd_i;
input wire logic [STAGE_ID_BITS-1:0] upd_stage_id_i;
input wire logic [LOCATION_BITS-1:0] upd_location_i;
input wire logic [5:0]               upd_length_i;
input wire logic [STAGE_ID_BITS-1:0] upd_childs_stage_id_i;
input wire logic [LOCATION_BITS-1:0] upd_childs_location_i;
input wire logic [1:0]               upd_childs_lr_i;

output logic [RESULT_BITS - 1:0] result_o;
output logic [31:0] ip_addr_o;

logic [ADDR_BITS - 1:0]  addr_a [NUM_STAGES];
logic [DATA_BITS - 1:0] rdata_a [NUM_STAGES];
logic wr_en_a                   [NUM_STAGES];
logic [DATA_BITS - 1:0] wdata_a [NUM_STAGES];

logic [5:0]                 bit_pos  [NUM_STAGES], bit_pos_d;
logic [STAGE_ID_BITS - 1:0] stage_id [NUM_STAGES], stage_id_d;
logic [LOCATION_BITS - 1:0] location [NUM_STAGES], location_d;
logic [31:0]                ip_addr  [NUM_STAGES], ip_addr_d;
logic [RESULT_BITS - 1:0]   result   [NUM_STAGES], result_d;
logic                       update   [NUM_STAGES], update_d;

/* choose the inputs for either the lookup or update, depending on update flag */
always_ff @(posedge clk) begin
  if (clk) begin
    update_d   <= upd_i;
    /* not updating the lookup table? */
    if (!upd_i) begin
      /* perform an IP address lookup */
      ip_addr_d  <= ip_addr_i;
      bit_pos_d  <= 0;
      stage_id_d <= 0;
      location_d <= 0;
      result_d   <= 0;
    /* updating the lookup table */
    end else begin
      /* ip_addr is now the prefix to be written */
      ip_addr_d  <= ip_addr_i;
      /* bit_pos input is re-used as prefix length to be written */
      bit_pos_d  <= upd_length_i;
      /* the entry location to be updated */
      stage_id_d <= upd_stage_id_i;
      location_d <= upd_location_i;
      /* result input is re-used as childs pointer to be written */
      //result_d   <= { 2'b00, upd_childs_stage_id_i, 1'b0, upd_childs_location_i, 2'b0, upd_childs_lr_i };
      //result_d   <= { PAD_STAGE_ID_BITS'b00, upd_childs_stage_id_i, 1'b0, upd_childs_location_i, 2'b0, upd_childs_lr_i };
      result_d   <= { {PAD_STAGE_ID_BITS{1'b0}}, upd_childs_stage_id_i,
                      {PAD_LOCATION_BITS{1'b0}}, upd_childs_location_i,
                      {PAD_CHILD_LR_BITS{1'b0}}, upd_childs_lr_i };
    end
  end
end

genvar i;
generate
  for (i = 0; i < NUM_STAGES; i++)
  begin : gen_sbp_lookup_stages

    initial wr_en_a[i] = 0;
    initial wdata_a[i] = '0;

    /* first stage, takes ip_addr_i */
    if (i == 0) begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
        .clk(clk),
        /* verilator lint_off UNUSED */
        .rst(rst),
        /* verilator lint_on UNUSED */

        .bit_pos_i (bit_pos_d),
        .stage_id_i(stage_id_d),
        .location_i(location_d),
        .result_i  (result_d),
        .ip_addr_i (ip_addr_d),

        // passed to next stage
        .result_o  (result  [i]),
        .bit_pos_o (bit_pos [i]),
        .stage_id_o(stage_id[i]),
        .location_o(location[i]),
        .ip_addr_o (ip_addr [i]),

        .update_i(update_d),
        .update_o(update[i]),

        .wr_en_o(wr_en_a[i]),
        .addr_o ( addr_a[i]),
        .data_i (rdata_a[i]),
        .data_o (wdata_a[i])
      );
    /* last stage */
    end else if (i == NUM_STAGES - 1) begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
        .clk(clk),
        /* verilator lint_off UNUSED */
        .rst(rst),
        /* verilator lint_on UNUSED */
        .bit_pos_i (bit_pos [i - 1]),
        .stage_id_i(stage_id[i - 1]),
        .location_i(location[i - 1]),
        .result_i  (result  [i - 1]),
        .ip_addr_i (ip_addr [i - 1]),

        // end result of lookup
        .result_o(result[i]),
        /* verilator lint_off PINCONNECTEMPTY */
        .bit_pos_o (),
        .stage_id_o(),
        .location_o(),
        .ip_addr_o (ip_addr[i]),
        /* verilator lint_on PINCONNECTEMPTY */

        .update_i(update[i - 1]),
        .update_o(update[i]),

        .wr_en_o(wr_en_a[i]),
        .addr_o (addr_a[i]),
        .data_i (rdata_a[i]),
        .data_o (wdata_a[i])
      );
    // intermediate stages
    end else begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
        .clk(clk),
        /* verilator lint_off UNUSED */
        .rst(rst),
        /* verilator lint_on UNUSED */
        .bit_pos_i (bit_pos [i - 1]),
        .stage_id_i(stage_id[i - 1]),
        .location_i(location[i - 1]),
        .result_i  (result  [i - 1]),
        .ip_addr_i (ip_addr [i - 1]),

        // passed to next stage
        .result_o  (result  [i]),
        .bit_pos_o (bit_pos [i]),
        .stage_id_o(stage_id[i]),
        .location_o(location[i]),
        .ip_addr_o (ip_addr [i]),

        .update_i(update[i - 1]),
        .update_o(update[i]),

        .wr_en_o(wr_en_a[i]),
        .addr_o ( addr_a[i]),
        .data_i (rdata_a[i]),
        .data_o (wdata_a[i])
      );
    end

    // "NAME00" + (256* (i / 10)) + (i % 10)
    // "" is treated as a number, and digits 00 are added to, resulting in "%02d, i" for i small enough
    bram_tdp #(.STAGE_ID(i), .MEMINIT_FILENAME("../scalable-pipelined-lookup-c/output/stage00.mem" + 256**4 * ((256**1 * (i / 10)) + 256**0 * (i % 10)) ), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
      .a_clk (clk),
      .a_wr  (wr_en_a[i]),
      .a_addr( addr_a[i]),
      .a_din (wdata_a[i]),
      .a_dout(rdata_a[i]),
      
      .b_clk (clk),
      .b_wr  (0),
      .b_addr('0),
      .b_din (0),
      /* verilator lint_off PINCONNECTEMPTY */
      .b_dout()
      /* verilator lint_on PINCONNECTEMPTY */
    );
  end
endgenerate

assign result_o  = result [NUM_STAGES - 1];
assign ip_addr_o = ip_addr[NUM_STAGES - 1];

endmodule

