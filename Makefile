# tiny-ai-accelerator — build targets
#   make sim        : Icarus Verilog simulation (default)
#                     TOP=rca P="N=16"  -> extra TB parameters (-Ptb_rca.N=16)
#   make sim-vl     : Verilator simulation
#   make lint       : Verilator lint
#   make synth      : Yosys generic synthesis + cell stats (preview of Week 3)
#   make wave       : open waveform in GTKWave
#   make clean

TOP     ?= mac
TB      ?= tb_$(TOP)
LIBDIRS := rtl rtl/adders
SRC     := $(firstword $(wildcard $(addsuffix /$(TOP).sv,$(LIBDIRS))))
TBSRC   := testbench/$(TB).sv
ACC_W   ?= 32
SAT     ?= 0
P       ?=

# submodules are found by file name (<module>.sv) in LIBDIRS
LIBS    := $(addprefix -y ,$(LIBDIRS))
# ACC_W/SAT only exist in the MAC testbenches; other TBs take P="NAME=VAL ..."
SIM_P   := $(if $(filter tb_mac%,$(TB)),-P$(TB).ACC_W=$(ACC_W) -P$(TB).SAT=$(SAT)) \
           $(addprefix -P$(TB).,$(P))

.PHONY: sim sim-vl lint synth wave clean

sim: | results
	iverilog -g2012 $(SIM_P) $(LIBS) -Y .sv -o results/$(TB).vvp $(TBSRC)
	vvp -n results/$(TB).vvp | tee results/$(TB)_iverilog.log

sim-vl: | results
	verilator --binary --timing -Wno-fatal --top-module $(TB) $(LIBS) \
	    -Mdir results/obj_$(TB) $(TBSRC)
	./results/obj_$(TB)/V$(TB) | tee results/$(TB)_verilator.log

lint:
	verilator --lint-only -Wall --top-module $(TOP) $(LIBS) $(SRC)

synth: | results
	yosys -q -l results/$(TOP)_synth.log \
	    -p "read_verilog -sv $(SRC); hierarchy -top $(TOP) $(addprefix -libdir ,$(LIBDIRS)); synth -top $(TOP); abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; tee -q -o results/$(TOP)_stat.txt stat; write_verilog -noattr results/$(TOP)_netlist.v"
	@cat results/$(TOP)_stat.txt

wave:
	gtkwave results/$(TB).vcd &

results:
	mkdir -p results

clean:
	rm -rf results/*
