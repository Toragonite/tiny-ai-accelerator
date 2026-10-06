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
| 1 | INT8 MAC unit (`rtl/mac.sv`), optional saturation | ✅ RTL + self-checking TB (Icarus + Verilator) |
| 1a | Pipelined MAC (`mac_pipe`), carry-save accumulating MAC (`mac_csa`) | ✅ verified against `mac` |
| 1b | Adder study: ripple-carry, block CLA, Kogge-Stone (`rtl/adders/`) | ✅ exhaustive / random TBs, depth sweep |
| 2 | Processing Element (`rtl/pe.sv`) | ✅ |
| 3 | 2×2 systolic array | ✅ |
| 4 | Parameterized R×C array (`rtl/systolic.sv`) | ✅ verified 2×2 … 8×8, non-square, wrap/saturate |
| 5 | Input/weight buffers | ⏳ |
| 6 | Controller FSM | ⏳ |
| 7 | Logic synthesis (Yosys → sky130 HD) | 🟡 pre-P&R area / delay estimates |
| 8 | Place & Route (OpenROAD) | ⏳ |
| 9 | PPA sweeps (size × precision) | 🟡 pre-P&R sweep done |

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
make sim TOP=systolic P="ROWS=4 COLS=4"   # Icarus: C = A x B vs. reference model
make sim-vl TOP=systolic                  # Verilator
make lint TOP=systolic                    # Verilator -Wall lint
make synth TOP=mac                        # Yosys generic synthesis + cell count
scripts/ppa_sky130.sh systolic ROWS=8 COLS=8   # sky130 area / delay estimate
scripts/systolic_sweep.sh                 # size and precision PPA tables
scripts/adder_depth.sh ks                 # adder logic depth vs. width
```

`TOP` selects the design (default `mac`); the testbench is `testbench/tb_<TOP>.sv`.
The sky130 scripts expect the PDK under `$PDK_ROOT` (default `~/pdk`).

## Systolic array

`rtl/systolic.sv` computes `C = A × B` on an R×C grid of PEs, output-stationary: each PE keeps
one `C[i][j]` in its accumulator while A moves right and B moves down one PE per cycle.
Row i of A and column j of B are skewed by i and j cycles so that `A[i][k]` and `B[k][j]` meet
in PE(i,j); the valid / first-term flags travel with A, so bubbles and restarts need no
central control. `done` rises on the edge where the last term reaches PE(R−1, C−1),
R+C−2 edges after it is sampled.

### PPA vs. array size (INT8, ACC_W=32)

Pre-P&R estimate: Yosys + ABC timing-driven mapping to sky130_fd_sc_hd (tt, 25 °C, 1.8 V),
no wire load, 500 ps assumed for clock-to-q + setup.

| array | IN_W | ACC_W | cells | FFs | area (um2) | um2/PE | fmax (MHz) | delay (ps) | peak GOPS |
|---|---|---|---|---|---|---|---|---|---|
| 2x2 | 8 | 32 | 2421 | 183 | 20563 | 5141 | 115 | 8192 | 0.9 |
| 4x4 | 8 | 32 | 9843 | 819 | 84136 | 5258 | 114 | 8252 | 3.6 |
| 8x8 | 8 | 32 | 39374 | 3435 | 341107 | 5330 | 117 | 8060 | 15.0 |
| 16x16 | 8 | 32 | 160343 | 14043 | 1376809 | 5378 | 113 | 8349 | 57.9 |

Area grows with the number of PEs (area per PE stays flat), while Fmax does not depend on the
array size: the critical path (`a*b + acc`) lies inside one PE and PEs only talk to their
neighbours, so throughput scales with R×C at a constant clock.

### PPA vs. precision (4×4, ACC_W = 2·IN_W + 16)

| array | IN_W | ACC_W | cells | FFs | area (um2) | um2/PE | fmax (MHz) | delay (ps) | peak GOPS |
|---|---|---|---|---|---|---|---|---|---|
| 4x4 | 4 | 24 | 4278 | 547 | 39329 | 2458 | 159 | 5771 | 5.1 |
| 4x4 | 8 | 32 | 9843 | 819 | 84136 | 5258 | 114 | 8252 | 3.6 |
| 4x4 | 16 | 48 | 28864 | 1363 | 231618 | 14476 | 72 | 13433 | 2.3 |

Peak throughput per area: INT4 ≈ 130, INT8 ≈ 43, INT16 ≈ 10 GOPS/mm². Halving the operand width
roughly halves the PE area (the multiplier scales with IN_W²) and also shortens the critical
path, so low precision wins twice.

## Arithmetic studies

**Adders — logic depth (gate levels, as written) vs. width** (`scripts/adder_depth.sh`)

| N | ripple-carry | block CLA (4-bit) | Kogge-Stone |
|---|---|---|---|
| 8  | 15  | 8  | 7  |
| 16 | 31  | 12 | 9  |
| 32 | 63  | 20 | 11 |
| 64 | 127 | 36 | 13 |
| cells @ 64 | 317 | 596 | 1091 |

Ripple-carry is 2N−1, Kogge-Stone 2·log₂N+1. With the generic gate set and no delay target,
ABC optimizes for area and rewrites the fast adders into slower ones (Kogge-Stone N=64: 13 → 97
levels), which is why synthesis needs a timing constraint, not only a fast architecture.

**MAC accumulation loop** (generic gates after ABC)

| design | stages | longest stage (levels) | cells |
|---|---|---|---|
| `mac` | 1 | 59 | 719 |
| `mac_pipe` | 2 | 52 (accumulate) vs. 30 (multiply) | 749 |
| `mac_csa` | 2 | 7 (carry-save loop) | 910 |

The feedback loop `acc → adder → acc` cannot be pipelined. Keeping the accumulator in
carry-save form leaves one full-adder level in the loop and moves the carry-propagate add
to the output, where it is needed once per dot product.

## Early data point — MAC cell count vs. precision (Yosys, generic gates, ACC_W=32)

| IN_W | Cells |
|---|---|
| 4  | 384 |
| 8  | 719 |
| 16 | 2019 |

The multiplier grows roughly with IN_W², which is the first hint of why low-precision
arithmetic matters for accelerator area and power. (Real PPA with a standard-cell library
comes in the synthesis / P&R stage.)
