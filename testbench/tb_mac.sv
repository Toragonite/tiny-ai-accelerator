// =============================================================================
// tb_mac.sv — Self-checking testbench for mac.sv
//   1) Directed tests : reset, corner values, dot product, clear behavior
//   2) Random tests   : random a/b/en/clr, compared against a golden model
// Runs on Icarus Verilog (-g2012) and Verilator (--binary --timing).
// =============================================================================
`timescale 1ns/1ps

module tb_mac #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0
);
    localparam int N_RAND  = 5000;
    logic                    clk = 0;
    logic                    rst_n;
    logic                    en, clr;
    logic signed [IN_W-1:0]  a, b;
    logic signed [ACC_W-1:0] acc;

    mac #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT)) dut (.*);

    always #5 clk = ~clk;   // 100 MHz

    // ACC_W-bit signed range
    localparam longint ACC_MAX_L =  (longint'(1) <<< (ACC_W-1)) - 1;
    localparam longint ACC_MIN_L = -(longint'(1) <<< (ACC_W-1));

    // ---------------- golden model ----------------
    longint model;
    int     errors = 0;
    int     checks = 0;

    task automatic model_step();
        longint p;
        p = longint'(a) * longint'(b);
        if (clr)     model = en ? p : 0;
        else if (en) model = model + p;
        // wrap to ACC_W bits (same as hardware two's-complement wrap)
        // model = longint'($signed(model[ACC_W-1:0]));
        // 변경 전: model = longint'($signed(model[ACC_W-1:0]));
        if (SAT) begin
            if      (model > ACC_MAX_L) model = ACC_MAX_L;   // 위로 고정
            else if (model < ACC_MIN_L) model = ACC_MIN_L;   // 아래로 고정
        end else begin
            model = longint'($signed(model[ACC_W-1:0]));     // wrap
        end
    endtask

    // drive inputs, clock once, check
    task automatic drive(input logic e, input logic c,
                         input logic signed [IN_W-1:0] x,
                         input logic signed [IN_W-1:0] y);
        en = e; clr = c; a = x; b = y;
        @(posedge clk);
        model_step();
        #1;  // let NBA settle
        check();
    endtask

    task automatic check();
        checks++;
        if (longint'(acc) !== model) begin
            errors++;
            if (errors <= 10)
                $display("[FAIL] t=%0t en=%0b clr=%0b a=%0d b=%0d | acc=%0d expected=%0d",
                         $time, en, clr, a, b, acc, model);
        end
    endtask

    initial begin
        $dumpfile("results/tb_mac.vcd");
        $dumpvars(0, tb_mac);

        // ---------------- reset ----------------
        rst_n = 0; en = 0; clr = 0; a = 0; b = 0; model = 0;
        repeat (2) @(posedge clk);
        #1; check();
        rst_n = 1;

        // ---------------- directed ----------------
        $display("-- directed: corner values");
        drive(1, 1,  127,  127);   // 16129
        drive(1, 1, -128, -128);   // 16384 (largest product)
        drive(1, 1, -128,  127);   // -16256
        drive(1, 1,    0, -128);   // 0

        $display("-- directed: dot product [1,2,3,4]·[5,6,7,8] = 70");
        drive(1, 1, 1, 5);
        drive(1, 0, 2, 6);
        drive(1, 0, 3, 7);
        drive(1, 0, 4, 8);
        if (acc !== 70) begin errors++; $display("[FAIL] dot product = %0d", acc); end
        else             $display("   acc = %0d  OK", acc);

        $display("-- directed: hold when en=0");
        drive(0, 0, 100, 100);
        drive(0, 0, -50, 99);

        $display("-- directed: clr without en -> 0");
        drive(0, 1, 11, 22);

        $display("-- directed: 1024 x (-128*-128) = 16,777,216 (no overflow in 32b)");
        drive(1, 1, -128, -128);
        repeat (1023) drive(1, 0, -128, -128);
        $display("   acc = %0d", acc);

        $display("-- directed: 1024 x (-128*127) = -16,646,144 (negative overflow test)");
        drive(1, 1, -128, 127);
        repeat (1023) drive(1, 0, -128, 127);
        $display("   acc = %0d", acc);
       
       	// ---------------- random ----------------
        $display("-- random: %0d cycles", N_RAND);
        repeat (N_RAND) begin
            drive($urandom_range(0, 9) != 0,     // en  ~90%
                  $urandom_range(0, 31) == 0,    // clr ~3%
                  IN_W'($urandom), IN_W'($urandom));
        end

        // ---------------- summary ----------------
        $display("==================================================");
        if (errors == 0) $display(" PASS  (%0d checks)", checks);
        else             $display(" FAIL  (%0d errors / %0d checks)", errors, checks);
        $display("==================================================");
        $finish;
    end
endmodule
