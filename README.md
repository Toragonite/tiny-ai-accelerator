# tiny-ai-accelerator

**Design and PPA Exploration of a Parameterized INT8 Systolic AI Accelerator**
(Personal Research Project)

A small AI accelerator written in SystemVerilog and taken through the front of an ASIC flow
(RTL → simulation → logic synthesis → place & route → PPA analysis), used to study
how **parallelism (array size)** and **numerical precision (INT16/INT8/INT4)** affect
Area, Fmax, Power and Throughput.

## Status

| Stage | Block | Status |
|---|---|---|
| 1 | INT8 MAC unit (`rtl/mac.sv`) | ✅ RTL + self-checking TB (Icarus + Verilator) |
| 2 | Processing Element (PE) | ⏳ |
| 3 | 2×2 systolic array | ⏳ |
| 4 | 4×4 / 8×8 parameterized array | ⏳ |
| 5 | Input/weight buffers | ⏳ |
| 6 | Controller FSM | ⏳ |
| 7 | Logic synthesis (Yosys) | 🟡 generic-cell preview only |
| 8 | Place & Route (OpenROAD) | ⏳ |
| 9 | PPA sweeps (size × precision) | ⏳ |

## Layout

```
rtl/              synthesizable SystemVerilog
testbench/        self-checking testbenches
synthesis/        Yosys scripts / constraints
physical_design/  OpenROAD flow configs
scripts/          sweep & plotting scripts
results/          logs, waveforms, reports (generated)
docs/notes/       study notes
```

## Quick start

```bash
make sim      # Icarus Verilog simulation
make sim-vl   # Verilator simulation
make lint     # Verilator -Wall lint
make synth    # Yosys generic synthesis + cell count
make wave     # view results/tb_mac.vcd in GTKWave
```

## Early data point — MAC cell count vs. precision (Yosys, generic gates, ACC_W=32)

| IN_W | Cells |
|---|---|
| 4  | 384 |
| 8  | 719 |
| 16 | 2019 |

The multiplier grows roughly with IN_W², which is the first hint of why low-precision
arithmetic matters for accelerator area and power. (Real PPA with a standard-cell library
comes in the synthesis / P&R stage.)
