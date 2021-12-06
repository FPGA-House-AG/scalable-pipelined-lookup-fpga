TIMING CLOSURE

Integrate into Corondum only for testing timing closure

https://github.com/corundum/corundum.git
52ba4c40e22c31f4f8aa36346666fb98869adb6f

fpga/mqnic/AU50/fpga_100g/rtl/fpga.v

Before 'cmac_usplus_0 qsfp_cmac_inst' instanstiate sbp_lookup

wire [16:0] lookup_result;
wire [16:0] lookup_result2;
sbp_lookup #(.PAD_BITS(2))
sbp_lookup_inst (
    .clk(qsfp_tx_clk_int),
    .rst(qsfp_tx_rst_int),
    .ip_addr_i(qsfp_tx_axis_tdata_int[31:0]),
    .ip_addr2_i(qsfp_rx_axis_tdata_int[31:0]),
    .upd_i(qsfp_tx_axis_tdata_int[0:0]),
    .upd_stage_id_i(qsfp_tx_axis_tdata_int[5:0]), .upd_location_i(qsfp_tx_axis_tdata_int[10:0]), .upd_length_i(qsfp_tx_axis_tdata_int[5:0]),
    .upd_childs_stage_id_i(qsfp_tx_axis_tdata_int[5:0]), .upd_childs_location_i(qsfp_tx_axis_tdata_int[10:0]),
    .upd_childs_lr_i(qsfp_tx_axis_tdata_int[1:0]),
    .result_o(lookup_result),
    .result2_o(lookup_result2)
);

<...>

At the end, ensure the lookup_results are not optimized out, use all bits:

assign qsfp_led_stat_g = qsfp_rx_status | ^lookup_result | ^lookup_result2;

