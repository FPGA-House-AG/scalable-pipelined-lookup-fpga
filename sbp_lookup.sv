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
  upd_i, upd_stage_id_i, upd_location_i, upd_ip_addr_i, upd_length_i, upd_childs_stage_id_i, upd_childs_location_i, upd_childs_lr_i,
  /* lookup request and result */
  lookup_i, ip_addr_i, result_o, ip_addr_o,
  /* lookup request and result on second lookup interface */
  ip_addr2_i, result2_o, ip_addr2_o
);

/* secondary lookup interface enabled */
localparam ENABLE_SECOND = 1;
localparam NUM_LOOKUP = (ENABLE_SECOND? 2: 1);

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
input wire logic lookup_i;
input wire logic [31:0] ip_addr_i, ip_addr2_i, upd_ip_addr_i;

/* update interface, to write to lookup tables */
input wire logic                     upd_i;
input wire logic [STAGE_ID_BITS-1:0] upd_stage_id_i;
input wire logic [LOCATION_BITS-1:0] upd_location_i;
input wire logic [5:0]               upd_length_i;
input wire logic [STAGE_ID_BITS-1:0] upd_childs_stage_id_i;
input wire logic [LOCATION_BITS-1:0] upd_childs_location_i;
input wire logic [1:0]               upd_childs_lr_i;

output logic [RESULT_BITS - 1:0] result_o, result2_o;
output logic [31:0] ip_addr_o, ip_addr2_o;

logic [ADDR_BITS - 1:0]  addr [NUM_STAGES][NUM_LOOKUP];
logic [DATA_BITS - 1:0] rdata [NUM_STAGES][NUM_LOOKUP];
logic wr_en                   [NUM_STAGES][NUM_LOOKUP];
logic [DATA_BITS - 1:0] wdata [NUM_STAGES][NUM_LOOKUP];

/* stage output signals (to next stage, or to output) */
logic [5:0]                 bit_pos  [NUM_STAGES][NUM_LOOKUP], bit_pos_d [NUM_LOOKUP];
logic [STAGE_ID_BITS - 1:0] stage_id [NUM_STAGES][NUM_LOOKUP], stage_id_d[NUM_LOOKUP];
logic [LOCATION_BITS - 1:0] location [NUM_STAGES][NUM_LOOKUP], location_d[NUM_LOOKUP];
logic [31:0]                ip_addr  [NUM_STAGES][NUM_LOOKUP], ip_addr_d [NUM_LOOKUP];
logic [RESULT_BITS - 1:0]   result   [NUM_STAGES][NUM_LOOKUP], result_d  [NUM_LOOKUP];
logic                       update   [NUM_STAGES][NUM_LOOKUP], update_d  [NUM_LOOKUP];

/* choose the inputs for either the lookup or update, depending on update flag */
always_ff @(posedge clk) begin
  if (clk) begin
    /* first interface is for lookups and updates, lookups have priority over updates */
    update_d[0] <= upd_i && !lookup_i;
    ip_addr_d [0] <= 0;
    bit_pos_d [0] <= 0;
    stage_id_d[0] <= 0;
    location_d[0] <= 0;
    result_d  [0] <= 0;
    /* not updating the lookup table? */
    if (lookup_i) begin
      /* perform an IP address lookup */
      ip_addr_d [0] <= ip_addr_i;
    /* updating the lookup table */
    end else begin
      /* ip_addr is now the prefix to be written */
      ip_addr_d [0]  <= upd_ip_addr_i;
      /* bit_pos input is re-used as prefix length to be written */
      bit_pos_d [0]  <= upd_length_i;
      /* the entry location to be updated */
      stage_id_d[0]  <= upd_stage_id_i;
      location_d[0]  <= upd_location_i;
      /* result input is re-used as childs pointer to be written */
      //result_d   <= { 2'b00, upd_childs_stage_id_i, 1'b0, upd_childs_location_i, 2'b0, upd_childs_lr_i };
      //result_d   <= { PAD_STAGE_ID_BITS'b00, upd_childs_stage_id_i, 1'b0, upd_childs_location_i, 2'b0, upd_childs_lr_i };
      result_d  [0] <= { {PAD_STAGE_ID_BITS{1'b0}}, upd_childs_stage_id_i,
                         {PAD_LOCATION_BITS{1'b0}}, upd_childs_location_i,
                         {PAD_CHILD_LR_BITS{1'b0}}, upd_childs_lr_i };
    end
    if (ENABLE_SECOND == 1) begin
      /* second interface is only for lookups */
      update_d  [1] <= 0;
      ip_addr_d [1] <= ip_addr2_i;
      bit_pos_d [1] <= 0;
      stage_id_d[1] <= 0;
      location_d[1] <= 0;
      result_d  [1] <= 0;
    end
  end
end

genvar k, i;
generate
  for (k = 0; k < NUM_LOOKUP; k++) begin
    for (i = 0; i < NUM_STAGES; i++) begin : gen_sbp_lookup_stages

      initial wr_en[i][k] = 0;
      initial wdata[i][k] = '0;

      /* first stage, takes ip_addr_i */
      if (i == 0) begin
        sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
          .clk(clk),
          /* verilator lint_off UNUSED */
          .rst(rst),
          /* verilator lint_on UNUSED */

          .bit_pos_i (bit_pos_d [k]),
          .stage_id_i(stage_id_d[k]),
          .location_i(location_d[k]),
          .result_i  (result_d  [k]),
          .ip_addr_i (ip_addr_d [k]),

          // passed to next stage
          .result_o  (result  [i][k]),
          .bit_pos_o (bit_pos [i][k]),
          .stage_id_o(stage_id[i][k]),
          .location_o(location[i][k]),
          .ip_addr_o (ip_addr [i][k]),

          .update_i(update_d[k]),
          .update_o(update[i][k]),

          .wr_en_o(wr_en[i][k]),
          .addr_o ( addr[i][k]),
          .data_i (rdata[i][k]),
          .data_o (wdata[i][k])
        );
      /* last stage */
      end else if (i == NUM_STAGES - 1) begin
        sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
          .clk(clk),
          /* verilator lint_off UNUSED */
          .rst(rst),
          /* verilator lint_on UNUSED */
          .bit_pos_i (bit_pos [i - 1][k]),
          .stage_id_i(stage_id[i - 1][k]),
          .location_i(location[i - 1][k]),
          .result_i  (result  [i - 1][k]),
          .ip_addr_i (ip_addr [i - 1][k]),

          // end result of lookup
          .result_o(result[i][k]),
          /* verilator lint_off PINCONNECTEMPTY */
          .bit_pos_o (),
          .stage_id_o(),
          .location_o(),
          .ip_addr_o (ip_addr[i][k]),
          /* verilator lint_on PINCONNECTEMPTY */

          .update_i(update[i - 1][k]),
          .update_o(update[i    ][k]),

          .wr_en_o(wr_en[i][k]),
          .addr_o ( addr[i][k]),
          .data_i (rdata[i][k]),
          .data_o (wdata[i][k])
        );
      // intermediate stages
      end else begin
        sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), /*.DATA_BITS(DATA_BITS),*/ .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS), .PAD_BITS(PAD_BITS)) sbp_lookup_stage_inst (
          .clk(clk),
          /* verilator lint_off UNUSED */
          .rst(rst),
          /* verilator lint_on UNUSED */
          .bit_pos_i (bit_pos [i - 1][k]),
          .stage_id_i(stage_id[i - 1][k]),
          .location_i(location[i - 1][k]),
          .result_i  (result  [i - 1][k]),
          .ip_addr_i (ip_addr [i - 1][k]),

          // passed to next stage
          .result_o  (result  [i][k]),
          .bit_pos_o (bit_pos [i][k]),
          .stage_id_o(stage_id[i][k]),
          .location_o(location[i][k]),
          .ip_addr_o (ip_addr [i][k]),

          .update_i(update[i - 1][k]),
          .update_o(update[i    ][k]),

          .wr_en_o(wr_en[i][k]),
          .addr_o ( addr[i][k]),
          .data_i (rdata[i][k]),
          .data_o (wdata[i][k])
        );
      end

    /* instantiate lookup table only once per stage */
    if (k == 0) begin
      // "NAME00" + (256* (i / 10)) + (i % 10)
      // "" is treated as a number, and digits 00 are added to, resulting in "%02d, i" for i small enough
      //bram_tdp #(.STAGE_ID(i), .MEMINIT_FILENAME("../scalable-pipelined-lookup-c/output/stage00.mem" + 256**4 * ((256**1 * (i / 10)) + 256**0 * (i % 10)) ), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
      bram_tdp #(.STAGE_ID(i), .MEMINIT_FILENAME("stage00.mem" + 256**4 * ((256**1 * (i / 10)) + 256**0 * (i % 10)) ), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
        .a_clk (clk),
        .a_wr  (wr_en[i][0]),
        .a_addr( addr[i][0]),
        .a_din (wdata[i][0]),
        .a_dout(rdata[i][0]),
        .b_clk (clk),
        .b_wr  (0),
        .b_addr( addr[i][1]),
        .b_din (0),
        .b_dout(rdata[i][1])
      );
    end
    end /* for i */
  end /* for k */
endgenerate

/* result from first interface */
assign result_o  = result [NUM_STAGES - 1][0];
assign ip_addr_o = ip_addr[NUM_STAGES - 1][0];

if (ENABLE_SECOND) begin
/* result from second interface */
assign result2_o  = result [NUM_STAGES - 1][1];
assign ip_addr2_o = ip_addr[NUM_STAGES - 1][1];
end

endmodule
