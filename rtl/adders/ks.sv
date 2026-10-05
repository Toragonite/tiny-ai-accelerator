// =============================================================================
// ks.sv — N-bit Kogge-Stone (parallel-prefix) adder
// -----------------------------------------------------------------------------
// (G, P) 쌍을 결합 연산 o 로 합친다:
//   (G_hi, P_hi) o (G_lo, P_lo) = (G_hi | P_hi & G_lo,  P_hi & P_lo)
// level l 에서 bit i 는 2^l 칸 아래(i - 2^l)와 결합한다 -> 범위가 1, 2, 4, 8 ... 로 두 배씩 넓어짐.
// $clog2(N) level 뒤 G[L][i] = bit 0..i 전체의 generate = c[i+1] (carry-in = 0).
// 기대 depth: level당 2단 -> 약 2*log2(N). 대신 결합 노드가 level마다 거의 N개라 면적이 큼.
// =============================================================================
module ks #(
    parameter int N = 8
) (
    input  logic [N-1:0] a,
    input  logic [N-1:0] b,
    output logic [N:0]   s      // N+1 bit: 최상위는 carry-out
);
    localparam int L = $clog2(N);   // prefix level 수

    logic [N-1:0] G [L+1] /* verilator split_var */;   // G[l] = level l의 generate
    /* verilator lint_off UNUSED */
    logic [N-1:0] P [L+1] /* verilator split_var */;   // P[L]과 상위 level 아래쪽 비트는 쓰이지 않음
    /* verilator lint_on UNUSED */

    assign G[0] = a & b;
    assign P[0] = a ^ b;

    // level 하나를 벡터 한 줄로: (x << D)는 bit i 자리에 bit i-D 값을 가져온다.
    //   i <  D: 아래에 결합할 비트가 없다 -> G는 그대로(<<가 0을 채움), P는 1을 채워서 그대로
    for (genvar l = 0; l < L; l++) begin : g_lvl
        localparam int D = 1 << l;  // 결합 거리
        assign G[l+1] = G[l] | (P[l] & (G[l] << D));
        assign P[l+1] = P[l] & {P[l][N-1-D:0], {D{1'b1}}};
    end

    assign s = {G[L][N-1], P[0] ^ {G[L][N-2:0], 1'b0}};
endmodule
