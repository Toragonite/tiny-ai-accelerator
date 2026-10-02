// =============================================================================
// tb_fa.sv — exhaustive self-checking testbench for the 1-bit full adder
// -----------------------------------------------------------------------------
// 입력이 3비트(a, b, cin)뿐이라 8가지 경우를 전부 확인한다.
// 정답 모델은 게이트 식이 아니라 "의도한 동작"으로 정의한다:
//   세 비트의 산술 합(0~3)을 2비트로 쓰면 {cout, sum} 이어야 한다.
// =============================================================================
`timescale 1ns/1ps
module tb_fa;
    logic a, b, cin;
    logic sum, cout;

    fa dut (.a, .b, .cin, .sum, .cout);

    int errors = 0;
    logic [1:0] expected;

    initial begin
        $display(" a b cin | cout sum | expected");
        for (int i = 0; i < 8; i++) begin
            {a, b, cin} = 3'(i);
            #1;
            expected = 2'(a) + 2'(b) + 2'(cin);   // 0~3
            $display(" %b %b  %b  |  %b    %b  |  %b%b %s", a, b, cin, cout, sum,
                     expected[1], expected[0], ({cout, sum} === expected) ? "" : "<-- FAIL");
            if ({cout, sum} !== expected) errors++;
        end
        if (errors == 0) $display(" PASS  (8 checks)");
        else             $display(" FAIL  (%0d errors / 8 checks)", errors);
        $finish;
    end
endmodule
