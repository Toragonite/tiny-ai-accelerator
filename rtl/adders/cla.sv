// =============================================================================
// cla.sv — N-bit block Carry-Lookahead Adder (4-bit lookahead blocks)
// -----------------------------------------------------------------------------
// cla4의 lookahead를 블록 carry-in(bc[k])까지 포함하도록 일반화해서 N/4개 이어 붙인다.
//   블록 안:   모든 carry를 g, p, bc[k]만으로 펼쳐서 한 번에 계산 (AND-OR 2단)
//   블록 사이: bc[k+1] = G_k | (P_k & bc[k])   <- 블록 단위 ripple (블록당 2단)
//     G_k = 블록이 스스로 carry를 만든다,  P_k = &p[블록] (블록 전체가 carry를 넘긴다)
// 기대 depth: 비트당 2단(RCA) -> 블록(4비트)당 2단, 즉 약 N/2.
// N은 4의 배수여야 한다.
// =============================================================================
module cla #(
    parameter int N = 8
) (
    input  logic [N-1:0] a,
    input  logic [N-1:0] b,
    output logic [N:0]   s      // N+1 bit: 최상위는 carry-out
);
    localparam int NB = N / 4;  // block 수

    logic [N-1:0] g, p;
    logic [N-1:0] c;            // c[i] = bit i로 들어가는 carry
    logic [NB:0]  bc /* verilator split_var */;   // bc[k] = block k의 carry-in

    assign g = a & b;
    assign p = a ^ b;
    assign bc[0] = 1'b0;

    for (genvar k = 0; k < NB; k++) begin : g_blk
        localparam int B = 4 * k;   // block의 LSB 위치
        logic gg, pp;               // block generate / propagate

        assign c[B]   = bc[k];
        assign c[B+1] = g[B]   | (p[B]   & bc[k]);
        assign c[B+2] = g[B+1] | (p[B+1] & g[B]) | (p[B+1] & p[B] & bc[k]);
        assign c[B+3] = g[B+2] | (p[B+2] & g[B+1]) | (p[B+2] & p[B+1] & g[B])
                      | (p[B+2] & p[B+1] & p[B] & bc[k]);

        assign gg = g[B+3] | (p[B+3] & g[B+2]) | (p[B+3] & p[B+2] & g[B+1])
                  | (p[B+3] & p[B+2] & p[B+1] & g[B]);
        assign pp = &p[B+3:B];

        assign bc[k+1] = gg | (pp & bc[k]);
    end

    assign s = {bc[NB], p ^ c};
endmodule
