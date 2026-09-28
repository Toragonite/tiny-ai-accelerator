# tiny-ai-accelerator — build targets
#   make sim        : Icarus Verilog simulation (default)
#   make sim-vl     : Verilator simulation
#   make lint       : Verilator lint
#   make synth      : Yosys generic synthesis + cell stats (preview of Week 3)
#   make wave       : open waveform in GTKWave
#   make clean

TOP     ?= mac
TB      ?= tb_$(TOP)
RTL     := $(wildcard rtl/*.sv)
TBSRC   := testbench/$(TB).sv
ACC_W   ?= 32
SAT     ?= 0

.PHONY: sim sim-vl lint synth wave clean

sim: | results
	iverilog -g2012 -P$(TB).ACC_W=$(ACC_W) -P$(TB).SAT=$(SAT) -o results/$(TB).vvp $(RTL) $(TBSRC)
	vvp -n results/$(TB).vvp | tee results/$(TB)_iverilog.log

sim-vl: | results
	verilator --binary --timing -Wno-fatal --top-module $(TB) \
	    -Mdir results/obj_$(TB) $(RTL) $(TBSRC)
	./results/obj_$(TB)/V$(TB) | tee results/$(TB)_verilator.log

lint:
	verilator --lint-only -Wall --top-module $(TOP) rtl/$(TOP).sv

synth: | results
	yosys -q -l results/$(TOP)_synth.log \
	    -p "read_verilog -sv rtl/$(TOP).sv; synth -top $(TOP); abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; tee -q -o results/$(TOP)_stat.txt stat; write_verilog -noattr results/$(TOP)_netlist.v"
	@cat results/$(TOP)_stat.txt

wave:
	gtkwave results/$(TB).vcd &

results:
	mkdir -p results

clean:
	rm -rf results/*
