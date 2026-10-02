// =============================================================================
// tb_rca.sv — self-checking testbench for the N-bit ripple-carry adder
// -----------------------------------------------------------------------------
// 정답 모델은 SystemVerilog의 `+` 연산자 (의도한 동작 = 산술 덧셈).
//   1) corner cases: 0+0, max+1 (carry가 끝까지 전파), max+max, ...
//   2) random: NUM_RAND 쌍
//   make sim TOP=rca P="N=16"
// =============================================================================
`timescale 1ns/1ps
module tb_rca;
    parameter int N        = 8;
    parameter int NUM_RAND = 20000;

    logic [N-1:0] a, b;
    logic [N:0]   s;

    rca #(.N(N)) dut (.a, .b, .s);

    int errors = 0;
    int checks = 0;

    task automatic check(input logic [N-1:0] x, input logic [N-1:0] y);
        logic [N:0] expected;
        a = x;
        b = y;
        #1;
        expected = (N+1)'(x) + (N+1)'(y);
        checks++;
        if (s !== expected) begin
            errors++;
            if (errors <= 5)
                $display("[FAIL] N=%0d  %0d + %0d = %0d, got %0d", N, x, y, expected, s);
        end
    endtask

    localparam logic [N-1:0] MAX = '1;   // 111...1

    initial begin
        // corner cases
        check('0, '0);
        check(MAX, N'(1));    // carry ripples through every bit
        check(N'(1), MAX);
        check(MAX, MAX);
        check(MAX, '0);
        check({1'b1, {(N-1){1'b0}}}, {1'b1, {(N-1){1'b0}}});   // MSB + MSB

        // random
        for (int k = 0; k < NUM_RAND; k++)
            check(N'({$urandom, $urandom}), N'({$urandom, $urandom}));   // up to 64 bit

        if (errors == 0) $display(" PASS  N=%0d (%0d checks)", N, checks);
        else             $display(" FAIL  N=%0d (%0d errors / %0d checks)", N, errors, checks);
        $finish;
    end
endmodule
