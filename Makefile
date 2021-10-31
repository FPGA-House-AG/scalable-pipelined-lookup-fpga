all: sbp

meminit:
	yosys meminit.ys
	netlistsvg meminit.json -o meminit.svg

sbp_lookup_stage:
	yosys sbp_lookup_stage.ys
	netlistsvg sbp_lookup_stage.json -o sbp_lookup_stage.svg

sbp_lookup:
	yosys $@.ys
	netlistsvg $@.json -o $@.svg

obj_dir/Vsbp_lookup: sbp_lookup_tb.cc sbp_lookup.sv sbp_lookup_stage.sv bram_tdp.v
	set -e
	verilator -Wall --cc --trace --exe $^
	make -j -C obj_dir/ -f Vsbp_lookup.mk Vsbp_lookup

obj_dir/Vmeminit: meminit_tb.cc meminit.sv
	set -e
	verilator -Wall --cc --trace --exe $^
	make -j -C obj_dir/ -f Vmeminit.mk Vmeminit