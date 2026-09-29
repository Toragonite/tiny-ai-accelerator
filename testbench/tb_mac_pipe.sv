// =============================================================================
// tb_mac_pipe.sv — verifies mac_pipe against the already-verified mac
//   Same inputs drive both. mac_pipe must equal mac's output delayed by 1 cycle.
// =============================================================================
`timescale 1ns/1ps

module tb_mac_pipe #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0
);
    localparam int N_RAND = 20000;

    logic                    clk = 0;
    logic                    rst_n, en, clr;
    logic signed [IN_W-1:0]  a, b;
    logic signed [ACC_W-1:0] acc_ref, acc_ref_d, acc_pipe;

    // ---- 칩 두 개를 실험대에 올리고 같은 입력을 연결 ----
    mac      #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT))
        u_ref  (.clk, .rst_n, .en, .clr, .a, .b, .acc(acc_ref));

    mac_pipe   #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT))
        u_pipe (.clk, .rst_n, .en, .clr, .a, .b, .acc(acc_pipe));

    always #5 clk = ~clk;

    // ---- 정답을 1 cycle 늦추는 레지스터 ----
    always_ff @(posedge clk) acc_ref_d <= acc_ref;

    int errors = 0, checks = 0;

    initial begin
        $display("== mac_pipe vs mac (delayed 1): IN_W=%0d ACC_W=%0d SAT=%0d ==", IN_W, ACC_W, SAT);
        $dumpfile("results/tb_mac_pipe.vcd");
        $dumpvars(0, tb_mac_pipe);

        rst_n = 0; en = 0; clr = 0; a = 0; b = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        repeat (N_RAND) begin
            // 클럭이 내려갈 때 입력을 바꾼다 (올라가는 순간과 겹치지 않게)
            @(negedge clk);
            en  = $urandom_range(0, 9) != 0;     // ~90%
            clr = $urandom_range(0, 31) == 0;    // ~3%
            a   = $urandom;
            b   = $urandom;

            // 클럭이 올라간 직후에 비교한다
            @(posedge clk); #1;
            checks++;
            if (acc_ref_d !== acc_pipe) begin
                errors++;
                if (errors <= 10)
                    $display("[FAIL] t=%0t pipe=%0d expected=%0d", $time, acc_pipe, acc_ref_d);
            end
        end

        $display("==================================================");
        if (errors == 0) $display(" PASS  (%0d checks)", checks);
        else             $display(" FAIL  (%0d errors / %0d checks)", errors, checks);
        $display("==================================================");
        $finish;
    end
endmodule
