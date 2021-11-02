`default_nettype none

module sbp_lookup #(
  parameter NUM_STAGES = 32,
  parameter ADDR_BITS = 11,
  parameter DATA_BITS = 64,
  parameter STAGE_ID_BITS = 6,
  parameter LOCATION_BITS = 11
) (
  input wire clk,
  input wire rst,
  input wire [31:0] ip_addr_i,
  output logic [LOCATION_BITS + STAGE_ID_BITS - 1:0] result_o
);

// single stages
//`define SINGLE_STAGE
`ifdef SINGLE_STAGE
logic [ADDR_BITS - 1:0] raddr;
logic [DATA_BITS - 1:0] rdata;
/* verilator lint_off UNUSED */
logic write;
assign wdata = '0;
/* verilator lint_on UNUSED */

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
  .write(write),
  .addr(raddr),
  .data(rdata)
);

bram_tdp #(.MEMINIT_FILENAME("stage0.mem"), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
  .a_clk(clk),
  .a_wr(0),
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

// multiple stages
`else

logic [ADDR_BITS - 1:0] raddr [NUM_STAGES];
logic [DATA_BITS - 1:0] rdata [NUM_STAGES];
/* verilator lint_off UNUSED */
logic write [NUM_STAGES];
logic [DATA_BITS - 1:0] wdata [NUM_STAGES];
/* verilator lint_on UNUSED */

logic [5:0] bit_pos [NUM_STAGES];
logic [STAGE_ID_BITS - 1:0] stage_id [NUM_STAGES];
logic [LOCATION_BITS - 1:0] location [NUM_STAGES];
logic [31:0] ip_addr [NUM_STAGES];
logic [LOCATION_BITS + STAGE_ID_BITS - 1:0] result [NUM_STAGES];

genvar i;
generate
  for (i = 0; i < NUM_STAGES; i++)
  begin : gen_sbp_lookup_stages

    initial write[i] = 0;
    initial wdata[i] = '0;

    /* first stage, takes ip_addr_i */
    if (i == 0) begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS), .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS)) sbp_lookup_stage_inst (
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
        .result_o(result[i]),
        /* verilator lint_off PINCONNECTEMPTY */
        .bit_pos_o(bit_pos[i]),
        .stage_id_o(stage_id[i]),
        .location_o(location[i]),
        .ip_addr_o(ip_addr[i]),
        /* verilator lint_on PINCONNECTEMPTY */
        /* verilator lint_off UNUSED */
        .write(write[i]),
        /* verilator lint_on UNUSED */
        .addr(raddr[i]),
        .data(rdata[i])
      );
    /* last stage */
    end else if (i == NUM_STAGES - 1) begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS), .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS)) sbp_lookup_stage_inst (
        .clk(clk),
        /* verilator lint_off UNUSED */
        .rst(rst),
        /* verilator lint_on UNUSED */
        .bit_pos_i(bit_pos[i - 1]),
        .stage_id_i(stage_id[i - 1]),
        .location_i(location[i - 1]),
        .result_i(result[i - 1]),
        .ip_addr_i(ip_addr[i - 1]),

        // passed to next stage
        .result_o(result[i]),
        /* verilator lint_off PINCONNECTEMPTY */
        .bit_pos_o(),
        .stage_id_o(),
        .location_o(),
        .ip_addr_o(),
        /* verilator lint_on PINCONNECTEMPTY */
        /* verilator lint_off UNUSED */
        .write(write[i]),
        /* verilator lint_on UNUSED */
        .addr(raddr[i]),
        .data(rdata[i])
      );
    // intermediate stages
    end else begin
      sbp_lookup_stage #(.STAGE_ID(i), .ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS), .STAGE_ID_BITS(STAGE_ID_BITS), .LOCATION_BITS(LOCATION_BITS)) sbp_lookup_stage_inst (
        .clk(clk),
        /* verilator lint_off UNUSED */
        .rst(rst),
        /* verilator lint_on UNUSED */
        .bit_pos_i(bit_pos[i - 1]),
        .stage_id_i(stage_id[i - 1]),
        .location_i(location[i - 1]),
        .result_i(result[i - 1]),
        .ip_addr_i(ip_addr[i - 1]),

        // passed to next stage
        .result_o(result[i]),
        .bit_pos_o(bit_pos[i]),
        .stage_id_o(stage_id[i]),
        .location_o(location[i]),
        .ip_addr_o(ip_addr[i]),
        /* verilator lint_off UNUSED */
        .write(write[i]),
        /* verilator lint_on UNUSED */
        .addr(raddr[i]),
        .data(rdata[i])
      );
    end

    // "NAME00" + (256* (i / 10)) + (i % 10)
    // "" is treated as a number, and digits 00 are added to, resulting in "%02d, i" for i small enough
    bram_tdp #(.STAGE_ID(i), .MEMINIT_FILENAME("../scalable-pipelined-lookup-c/output/stage00.mem" + 256**4 * ((256**1 * (i / 10)) + 256**0 * (i % 10)) ), .ADDR(ADDR_BITS), .DATA(DATA_BITS)) stage_ram_inst (
      .a_clk(clk),
      .a_wr(0),
      .a_addr(raddr[i]),
      .a_din('0),
      .a_dout(rdata[i]),
      
      .b_clk(clk),
      .b_wr(0),
      .b_addr('0),
      .b_din(0),
      /* verilator lint_off PINCONNECTEMPTY */
      .b_dout()
      /* verilator lint_on PINCONNECTEMPTY */
    );
  end
endgenerate
assign result_o = result[NUM_STAGES - 1];
`endif

endmodule

