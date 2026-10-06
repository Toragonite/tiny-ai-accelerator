#!/usr/bin/env bash
# Usage: scripts/systolic_sweep.sh [size|prec|all]
#   size : INT8 (IN_W=8, ACC_W=32) arrays N x N, N = 2 4 8 16
#   prec : 4x4 array, IN_W = 4 / 8 / 16 with ACC_W = 2*IN_W + 16 (16 guard bits)
# Each point runs scripts/ppa_sky130.sh and adds
#   peak_gops = 2 ops (mul + add) x ROWS x COLS x fmax
#   um2/PE    = area / (ROWS x COLS)
# and prints a Markdown table (pre-P&R, sky130 HD tt corner).
set -euo pipefail
MODE=${1:-all}
cd "$(dirname "$0")/.."

row() {   # $1 rows, $2 cols, $3 in_w, $4 acc_w
  local out
  out=$(scripts/ppa_sky130.sh systolic ROWS=$1 COLS=$2 IN_W=$3 ACC_W=$4)
  awk -v r="$1" -v c="$2" -v w="$3" -v a="$4" '{
    for (i = 1; i <= NF; i++) m[$i] = $(i + 1)
    pe = r * c
    printf "| %dx%d | %d | %d | %s | %s | %.0f | %.0f | %s | %.0f | %.1f |\n",
      r, c, w, a, m["cells"], m["FFs"], m["area_um2"], m["area_um2"] / pe,
      m["fmax_mhz"], m["delay_ps"], 2 * pe * m["fmax_mhz"] / 1000
  }' <<<"$out"
}

header() {
  echo "| array | IN_W | ACC_W | cells | FFs | area (um2) | um2/PE | fmax (MHz) | delay (ps) | peak GOPS |"
  echo "|---|---|---|---|---|---|---|---|---|---|"
}

if [[ $MODE == size || $MODE == all ]]; then
  echo "### Array size (INT8)"; header
  for n in 2 4 8 16; do row $n $n 8 32; done
fi
if [[ $MODE == prec || $MODE == all ]]; then
  echo; echo "### Precision (4x4)"; header
  for w in 4 8 16; do row 4 4 $w $((2 * w + 16)); done
fi
