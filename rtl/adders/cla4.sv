// =============================================================================
// cla4.sv — 4-bit Carry-Lookahead Adder
// -----------------------------------------------------------------------------
//   g[i] = a[i] & b[i]   (generate)
//   p[i] = a[i] ^ b[i]   (propagate)
//   c[i+1] = g[i] | p[i] & c[i] 를 펼쳐서 모든 carry를 g, p만으로 계산한다.
// =============================================================================
module cla4 (
    input  logic [3:0] a,
    input  logic [3:0] b,
    output logic [4:0] s      // s[4] = carry-out
);
    logic [3:0] g, p;
    logic [4:0] c /* verilator split_var */;

    assign g = a & b;
    assign p = a ^ b;

    assign c[0] = 1'b0;
    assign c[1] = g[0];
    assign c[2] = g[1] | (p[1] & g[0]);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]);
    assign c[4] = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);

    assign s = { c[4], p ^ c[3:0] };
endmodule
