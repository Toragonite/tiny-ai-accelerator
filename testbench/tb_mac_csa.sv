// =============================================================================
// tb_mac_csa.sv — verifies mac_csa against the already-verified mac (SAT=0)
//   Same inputs drive both. mac_csa must equal mac's output delayed by 1 cycle.
//   Phase 1: random en/clr (short dot products, ~30 terms)
//   Phase 2: long runs without clr so the accumulator wraps (overflow path)
//   make sim TOP=mac_csa ACC_W=16      (SAT=1 is rejected: mac_csa has no saturation)
// =============================================================================
`timescale 1ns/1ps

module tb_mac_csa #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0     // Makefile passes it to every tb_mac*; must stay 0
);
    localparam int N_RAND = 20000;
    localparam int N_LONG = 20000;

    logic                    clk = 0;
    logic                    rst_n, en, clr;
    logic signed [IN_W-1:0]  a, b;
    logic signed [ACC_W-1:0] acc_ref, acc_ref_d, acc_csa;

    mac     #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(1'b0))
        u_ref (.clk, .rst_n, .en, .clr, .a, .b, .acc(acc_ref));

    mac_csa #(.IN_W(IN_W), .ACC_W(ACC_W))
        u_csa (.clk, .rst_n, .en, .clr, .a, .b, .acc(acc_csa));

    always #5 clk = ~clk;

    // ---- 정답을 1 cycle 늦추는 레지스터 ----
    always_ff @(posedge clk) acc_ref_d <= acc_ref;

    int errors = 0, checks = 0;

    task automatic step(input logic e, input logic c);
        @(negedge clk);
        en  = e;
        clr = c;
        a   = IN_W'($urandom);
        b   = IN_W'($urandom);
        @(posedge clk); #1;
        checks++;
        if (acc_ref_d !== acc_csa) begin
            errors++;
            if (errors <= 10)
                $display("[FAIL] t=%0t csa=%0d expected=%0d", $time, acc_csa, acc_ref_d);
        end
    endtask

    initial begin
        if (SAT) $fatal(1, "mac_csa does not support SAT=1");
        $display("== mac_csa vs mac (delayed 1): IN_W=%0d ACC_W=%0d ==", IN_W, ACC_W);

        rst_n = 0; en = 0; clr = 0; a = 0; b = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Phase 1: random control
        repeat (N_RAND)
            step($urandom_range(0, 9) != 0, $urandom_range(0, 31) == 0);

        // Phase 2: one clr, then accumulate without clearing -> acc wraps
        step(1'b1, 1'b1);
        repeat (N_LONG) step(1'b1, 1'b0);

        $display("==================================================");
        if (errors == 0) $display(" PASS  (%0d checks)", checks);
        else             $display(" FAIL  (%0d errors / %0d checks)", errors, checks);
        $display("==================================================");
        $finish;
    end
endmodule
