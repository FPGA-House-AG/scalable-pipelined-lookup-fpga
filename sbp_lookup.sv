`default_nettype none

module sbp_lookup #(
  parameter NUM_STAGES = 32,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64
  parameter STAGE_ID_BITS = 6,
  parameter LOCATION_BITS = 11
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

`ifdef UNDEFINED
logic [SAMPLE_WIDTH-1:0] value [NUM_STAGES];
logic [AGE_WIDTH-1:0] age [NUM_STAGES];
logic gt [NUM_STAGES];
logic remove [NUM_STAGES-1];

logic [ADDR_BITS - 1:0] raddr [NUM_STAGES];
logic [DATA_BITS - 1:0] rdata [NUM_STAGES];
logic [DATA_BITS - 1:0] wdata [NUM_STAGES];

logic [ADDR_BITS - 1:0] bit_pos [NUM_STAGES];
logic [STAGE_ID_BITS - 1:0] stage_id [NUM_STAGES];
logic [LOCATION_BITS - 1:0] location [NUM_STAGES];

genvar i;
generate
  for (i = 0; i < NUM_STAGES; i++)
  begin : gen_sbp_lookup_stages
    /* first stage */
    if (i == 0) begin
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
    /* right-most cell, storing maximum */
    end else if (i == NUM_STAGES - 1) begin
      median_cell
      #(
        .SAMPLE_WIDTH (SAMPLE_WIDTH),
        .AGE_WIDTH (AGE_WIDTH),
        .WINDOW_WIDTH (WINDOW_WIDTH),
        .RANK(i)
      )
      median_cell_inst
      (
        .rst(rst),
        .clk(clk),
        /* input sample to be stored in exactly one cell */
        .sample_i(sample_i),
        /* stored sample value output to neighbours */
        .value_o(value[i]),
        .age_o(age[i]),
        .gt_o(gt[i]),
        .remove_o(/*remove[i]*/),

        .value_ln_i(value[i - 1]),
        .age_ln_i(age[i - 1]),
        .value_rn_i(0),
        .age_rn_i(0),

        .remove_i(remove[i - 1]),
        .gt_ln_i(gt[i - 1]),
        .gt_rn_i(1'b1)
      );
    end else begin
      median_cell
      #(
        .SAMPLE_WIDTH (SAMPLE_WIDTH),
        .AGE_WIDTH (AGE_WIDTH),
        .WINDOW_WIDTH (WINDOW_WIDTH),
        .RANK(i)
      )
      median_cell_inst
      (
        .rst(rst),
        .clk(clk),
        /* input sample to be stored in exactly one cell */
        .sample_i(sample_i),
        /* stored sample value output to neighbours */
        .value_o(value[i]),
        .age_o(age[i]),
        .gt_o(gt[i]),
        .remove_o(remove[i]),

        .value_ln_i(value[i - 1]),
        .age_ln_i(age[i - 1]),
        .value_rn_i(value[i + 1]),
        .age_rn_i(age[i + 1]),

        .remove_i(remove[i - 1]),
        .gt_ln_i(gt[i - 1]),
        .gt_rn_i(gt[i + 1])
      );
    end
  end
endgenerate
`endif

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

