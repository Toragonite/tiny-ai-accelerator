#!/usr/bin/env bash
# Usage: scripts/ppa_sky130.sh <top> [PARAM=VALUE ...]
#   e.g. scripts/ppa_sky130.sh systolic ROWS=4 COLS=4
#
# Pre-P&R PPA estimate on the SkyWater 130nm HD standard cells (tt, 25C, 1.8V):
#   Yosys synth -flatten -> dfflibmap (FFs) -> ABC liberty mapping, timing-driven
#   (-D 1000 ps = "as fast as you can"; tighter targets did not change the result)
# Prints one line:  top params | cells FFs area_um2 delay_ps fmax_mhz
#   delay_ps : ABC stime, longest combinational path between FFs / ports,
#              no wire load, no clock-to-q / setup
#   fmax_mhz : 1 / (delay + FF_OVH), FF_OVH = 500 ps assumed for clk->q + setup
# Real numbers (wires, clock tree, placement) come from OpenROAD later.
set -euo pipefail
TOP=${1:?top module, e.g. systolic}; shift
PDK_ROOT=${PDK_ROOT:-$HOME/pdk}
LIB=${SKY130_LIB:-$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}
FF_OVH=500
[ -f "$LIB" ] || { echo "liberty not found: $LIB (set PDK_ROOT or SKY130_LIB)" >&2; exit 1; }

CHPARAM=""
for kv in "$@"; do CHPARAM+="chparam -set ${kv%%=*} ${kv#*=} $TOP; "; done

mkdir -p results/ppa
TAG=$(echo "$TOP $*" | tr ' =' '_-')
LOG=results/ppa/$TAG.log

yosys -l "$LOG" -q -p "read_verilog -sv rtl/*.sv; $CHPARAM hierarchy -top $TOP; \
    synth -flatten -top $TOP; dfflibmap -liberty $LIB; \
    abc -liberty $LIB -constr synthesis/abc_sky130.constr -D 1000; opt_clean; \
    tee -o results/ppa/$TAG.stat stat -liberty $LIB" >/dev/null 2>&1 \
  || { grep -iE -A3 'error' "$LOG" >&2; exit 1; }

cells=$(grep -oP 'Number of cells:\s+\K[0-9]+' results/ppa/$TAG.stat | tail -1)
ffs=$(awk '/sky130_fd_sc_hd__df/ {s += $2} END {print s + 0}' results/ppa/$TAG.stat)
area=$(grep -oP 'Chip area for module .*: \K[0-9.]+' results/ppa/$TAG.stat | tail -1)
delay=$(grep -oP 'Delay =\s+\K[0-9.]+' "$LOG" | tail -1)
fmax=$(awk -v d="$delay" -v o="$FF_OVH" 'BEGIN {printf "%.0f", 1e6 / (d + o)}')

printf "%-10s %-28s | cells %-7s FFs %-6s area_um2 %-10.0f delay_ps %-7.0f fmax_mhz %s\n" \
    "$TOP" "$*" "$cells" "$ffs" "$area" "$delay" "$fmax"
