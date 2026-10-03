#!/usr/bin/env bash
# Usage: scripts/adder_depth.sh <module> [widths...]
#   1) exhaustive functional check at N=8 (all 65536 a,b pairs) vs. a+b
#   2) Yosys synth (same gate mapping as `make synth`) -> longest path + cell count
set -euo pipefail
TOP=${1:?module name, e.g. rca}; shift
WIDTHS=${*:-8 16 32 64}
SRC=rtl/adders/$TOP.sv
mkdir -p results/adders

cat > results/adders/tb_$TOP.sv <<TB
module tb;
  logic [7:0] a, b; logic [8:0] s; int err = 0;
  $TOP #(.N(8)) dut (.a, .b, .s);
  initial begin
    for (int i = 0; i < 256; i++) for (int j = 0; j < 256; j++) begin
      a = i; b = j; #1;
      if (s !== 9'(i + j)) begin
        if (err < 5) \$display("FAIL %0d + %0d = %0d (got %0d)", i, j, i + j, s);
        err++;
      end
    end
    if (err == 0) \$display("PASS (65536 checks)"); else \$display("FAIL: %0d errors", err);
    \$finish;
  end
endmodule
TB
iverilog -g2012 -o results/adders/$TOP.vvp $SRC results/adders/tb_$TOP.sv
vvp -n results/adders/$TOP.vvp

printf "%-6s %-10s %-8s\n" N depth cells
for n in $WIDTHS; do
  out=$(yosys -p "read_verilog -sv $SRC; chparam -set N $n $TOP; synth -top $TOP; \
        abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; ltp -noff; stat" 2>&1)
  if grep -q ERROR <<<"$out"; then grep -A3 ERROR <<<"$out"; exit 1; fi
  d=$(grep -oP 'Longest topological path.*length=\K[0-9]+' <<<"$out" | tail -1)
  c=$(grep -oP 'Number of cells:\s+\K[0-9]+' <<<"$out" | tail -1)
  printf "%-6s %-10s %-8s\n" "$n" "$d" "$c"
done
