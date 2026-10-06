// =============================================================================
// tb_systolic.sv — self-checking testbench for the systolic array (C = A x B)
// -----------------------------------------------------------------------------
// 정답 모델: 행렬곱 C[i][j] = sum_k A[i][k] * B[k][j], k = 0..K-1 순서로 누산.
//   SAT=0 -> ACC_W 비트로 wrap,  SAT=1 -> 매 누산마다 ACC_W 범위로 saturate (mac과 같은 정의)
// For every matrix:
//   - stream K columns of A / rows of B, with random bubbles (in_valid = 0)
//   - done must rise exactly ROWS+COLS-2 edges after the edge that sampled the last k,
//     and all C must be correct at that point
//   - the next matrix starts on the edge right after done (tightest legal spacing)
// Cases: corner (K=1, all -128, all 127, -128 x 127 mix) + N_RAND random (K = 1..K_MAX)
//   make sim TOP=systolic P="ROWS=4 COLS=4"
//   make sim TOP=systolic P="ROWS=2 COLS=8 ACC_W=16 SAT=1"
// =============================================================================
`timescale 1ns/1ps
module tb_systolic;
    parameter int ROWS   = 4;
    parameter int COLS   = 4;
    parameter int IN_W   = 8;
    parameter int ACC_W  = 32;
    parameter bit SAT    = 0;
    parameter int K_MAX  = 64;
    parameter int N_RAND = 200;

    localparam longint ACC_MAX = (64'sd1 <<< (ACC_W - 1)) - 1;
    localparam longint ACC_MIN = -(64'sd1 <<< (ACC_W - 1));
    localparam int     IN_MAX  = (1 << (IN_W - 1)) - 1;
    localparam int     IN_MIN  = -(1 << (IN_W - 1));
    localparam int     LAT     = ROWS + COLS - 2;   // edges: last k sampled -> done

    logic                                 clk = 0;
    logic                                 rst_n, in_valid, in_first, in_last;
    logic                                 done;
    logic [ROWS*IN_W-1:0]                 a_flat;   // a_flat[i*IN_W +: IN_W] = A[i][k]
    logic [COLS*IN_W-1:0]                 b_flat;   // b_flat[j*IN_W +: IN_W] = B[k][j]
    logic [ROWS*COLS*ACC_W-1:0]           c_flat;   // C[i][j] at (i*COLS + j)*ACC_W

    systolic #(.ROWS(ROWS), .COLS(COLS), .IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT)) dut (
        .clk, .rst_n, .in_valid, .in_first, .in_last,
        .a_col(a_flat), .b_row(b_flat), .c(c_flat), .done
    );

    always #5 clk = ~clk;

    int A [ROWS][K_MAX];
    int B [K_MAX][COLS];
    int errors = 0, checks = 0, mats = 0;

    // ---- reference model: intended arithmetic, step by step like the accumulator ----
    function automatic longint fit(input longint x);
        if (SAT) return (x > ACC_MAX) ? ACC_MAX : (x < ACC_MIN) ? ACC_MIN : x;
        x = x & ((64'sd1 <<< ACC_W) - 1);                       // wrap to ACC_W bits
        return (x > ACC_MAX) ? x - (64'sd1 <<< ACC_W) : x;      // back to signed
    endfunction

    function automatic longint ref_c(input int i, input int j, input int K);
        longint s = 0;
        for (int k = 0; k < K; k++) s = fit(s + longint'(A[i][k]) * longint'(B[k][j]));
        return s;
    endfunction

    // mode: 0 = random, 1 = all IN_MIN, 2 = all IN_MAX, 3 = A = IN_MIN, B = IN_MAX
    task automatic fill(input int K, input int mode);
        for (int k = 0; k < K; k++) begin
            for (int i = 0; i < ROWS; i++)
                A[i][k] = (mode == 0) ? $urandom_range(0, 2*IN_MAX+1) + IN_MIN
                        : (mode == 2) ? IN_MAX : IN_MIN;
            for (int j = 0; j < COLS; j++)
                B[k][j] = (mode == 0) ? $urandom_range(0, 2*IN_MAX+1) + IN_MIN
                        : (mode == 1) ? IN_MIN : IN_MAX;
        end
    endtask

    // drive one matrix starting at the current negedge; returns when done was checked
    task automatic run(input int K, input bit bubbles);
        int k = 0, wait_cnt;
        while (k < K) begin
            if (bubbles && $urandom_range(0, 3) == 0) begin
                in_valid = 0; in_first = 1'($urandom); in_last = 1'($urandom);   // must be ignored
                a_flat = {ROWS{IN_W'($urandom)}}; b_flat = {COLS{IN_W'($urandom)}};
            end else begin
                in_valid = 1; in_first = (k == 0); in_last = (k == K - 1);
                for (int i = 0; i < ROWS; i++) a_flat[i*IN_W +: IN_W] = IN_W'(A[i][k]);
                for (int j = 0; j < COLS; j++) b_flat[j*IN_W +: IN_W] = IN_W'(B[k][j]);
                k++;
            end
            @(posedge clk); #1;
            if (done) begin
                errors++;
                $display("[FAIL] done during streaming (mat %0d)", mats);
            end
            @(negedge clk);
        end
        in_valid = 0; in_first = 0; in_last = 0;

        // the last k was sampled on the previous posedge; count edges until done
        wait_cnt = 1;
        @(posedge clk); #1;
        while (!done && wait_cnt < LAT + 5) begin
            @(posedge clk); #1;
            wait_cnt++;
        end
        if (wait_cnt != LAT) begin
            errors++;
            $display("[FAIL] mat %0d: done after %0d edges, expected %0d", mats, wait_cnt, LAT);
        end

        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++) begin
                longint exp_c = ref_c(i, j, K);
                logic signed [ACC_W-1:0] got = c_flat[(i*COLS + j)*ACC_W +: ACC_W];
                checks++;
                if (got !== ACC_W'(exp_c)) begin
                    errors++;
                    if (errors <= 10)
                        $display("[FAIL] mat %0d K=%0d C[%0d][%0d] = %0d, expected %0d",
                                 mats, K, i, j, got, exp_c);
                end
            end
        mats++;
        @(negedge clk);   // next matrix is sampled on the edge right after done
    endtask

    initial begin
        $display("== systolic %0dx%0d  IN_W=%0d ACC_W=%0d SAT=%0d ==", ROWS, COLS, IN_W, ACC_W, SAT);
        rst_n = 0; in_valid = 0; in_first = 0; in_last = 0; a_flat = '0; b_flat = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        // corner cases
        fill(1, 0);     run(1, 0);          // K = 1: clr and last on the same k
        fill(K_MAX, 1); run(K_MAX, 0);      // (-128)(-128) * K: largest positive sum
        fill(K_MAX, 2); run(K_MAX, 0);      // 127 * 127 * K
        fill(K_MAX, 3); run(K_MAX, 1);      // (-128)(127) * K: most negative sum
        // random
        repeat (N_RAND) begin
            int K = $urandom_range(1, K_MAX);
            fill(K, 0);
            run(K, 1'($urandom_range(0, 1)));
        end

        if (errors == 0) $display(" PASS  %0dx%0d (%0d matrices, %0d checks)", ROWS, COLS, mats, checks);
        else             $display(" FAIL  %0dx%0d (%0d errors / %0d checks)", ROWS, COLS, errors, checks);
        $finish;
    end
endmodule
