all: sbp

meminit:
	yosys meminit.ys
	netlistsvg meminit.json -o meminit.svg

sbp_lookup_stage:
	yosys sbp_lookup_stage.ys
	netlistsvg sbp_lookup_stage.json -o sbp_lookup_stage.svg

sbp_lookup:
	yosys sbp_lookup.ys
	netlistsvg sbp_lookup_stage.json -o sbp_lookup_stage.svg

obj_dir/Vmeminit: meminit_tb.cc meminit.sv
	set -e
	verilator -Wall --cc --trace --exe $^
	make -j -C obj_dir/ -f Vmeminit.mk Vmeminit