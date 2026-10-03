// =============================================================================
// tb_cla4.sv — exhaustive self-checking testbench for the 4-bit CLA
// -----------------------------------------------------------------------------
// Same interface as rca (#(.N(4))): a, b -> s[4:0], carry-in fixed to 0.
// a(16) x b(16) = 256 cases. 정답 모델: s = a + b
// =============================================================================
`timescale 1ns/1ps
module tb_cla4;
    logic [3:0] a, b;
    logic [4:0] s;

    cla4 dut (.a, .b, .s);

    int errors = 0;
    int checks = 0;
    logic [4:0] expected;

    initial begin
        for (int i = 0; i < 256; i++) begin
            {a, b} = 8'(i);
            #1;
            expected = 5'(a) + 5'(b);
            checks++;
            if (s !== expected) begin
                errors++;
                if (errors <= 5)
                    $display("[FAIL] %b + %b = %b, got %b", a, b, expected, s);
            end
        end
        if (errors == 0) $display(" PASS  (%0d checks)", checks);
        else             $display(" FAIL  (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
