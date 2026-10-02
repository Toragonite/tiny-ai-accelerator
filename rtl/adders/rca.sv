// =============================================================================
// rca.sv — N-bit Ripple-Carry Adder (study: adder structure vs. delay)
// -----------------------------------------------------------------------------
// N개의 Full Adder(FA)를 사슬로 연결한다. bit i의 carry-out이 bit i+1의 carry-in.
//   s[i]   = a[i] ^ b[i] ^ c[i]
//   c[i+1] = ?               <- FA의 carry 식 (진리표에서 유도)
// =============================================================================
module rca #(
    parameter int N = 8
) (
    input  logic [N-1:0] a,
    input  logic [N-1:0] b,
    output logic [N:0]   s      // N+1 bit: 최상위는 carry-out
);
    logic [N:0] c /* verilator split_var */;   // c[0] = carry-in, c[N] = carry-out
    assign c[0] = 1'b0;

    for (genvar i = 0; i < N; i++) begin : g_fa
        assign s[i]   = a[i] ^ b[i] ^ c[i];
        assign c[i+1] = (a[i] & b[i]) | ((a[i] ^ b[i]) & c[i]);
    end

    assign s[N] = c[N];
endmodule
