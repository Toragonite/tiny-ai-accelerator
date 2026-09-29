// =============================================================================
// mac_pipe.sv — 2-stage pipelined signed Multiply-Accumulate (MAC) unit
// -----------------------------------------------------------------------------
// Stage 1 : prod_r <= a * b      (en, clr are delayed together -> en_r, clr_r)
// Stage 2 : acc    <= acc + prod_r
//
// Latency   : 2 cycles (input -> acc updated)
// Throughput: 1 MAC / cycle (same as mac.sv)
// Why pipeline: splits the multiply->add critical path so Fmax can go up.
//
// Control (applied in stage 2, using the DELAYED control signals):
//   clr_r & en_r  : acc <= prod_r
//   clr_r & !en_r : acc <= 0
//   !clr_r & en_r : acc <= acc + prod_r
//   otherwise     : hold
// =============================================================================
module mac_pipe #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0
) (
    input  logic                    clk,
    input  logic                    rst_n,   // async active-low reset
    input  logic                    en,      // accumulate enable
    input  logic                    clr,     // clear / restart accumulation
    input  logic signed [IN_W-1:0]  a,       // activation
    input  logic signed [IN_W-1:0]  b,       // weight
    output logic signed [ACC_W-1:0] acc
);
    localparam int PROD_W = 2 * IN_W;

    // ---- min max values ----
    localparam logic signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};  // 0111...1
    localparam logic signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};  // 1000...0

    // =========================================================================
    // Stage 1 : multiply
    // =========================================================================
    logic signed [PROD_W-1:0] prod;
    assign prod = a * b;

    // ---- pipeline register: product + control travel TOGETHER ----
    logic signed [PROD_W-1:0] prod_r;
    logic                     en_r, clr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r <= '0;
            en_r   <= '0;
            clr_r  <= '0;
        end else begin
            prod_r <= prod;
            en_r   <= en;
            clr_r  <= clr;
        end
    end

    // =========================================================================
    // Stage 2 : accumulate
    // =========================================================================
    // ---- sign-extend the REGISTERED product to accumulator width ----
    logic signed [ACC_W-1:0] prod_ext;
    assign prod_ext = {{(ACC_W - PROD_W){prod_r[PROD_W-1]}}, prod_r};   // ⑥ 어떤 곱을 써야 할까? (두 칸 같은 답)

    // ---- overflow detection ----
    logic signed [ACC_W:0]    sum_wide;
    assign sum_wide = acc + prod_ext;

    // ---- accumulate next ----
    logic signed [ACC_W-1:0] acc_next;
    always_comb begin
        if (!SAT)                                acc_next = sum_wide[ACC_W-1:0];
        else if (sum_wide > (ACC_W+1)'(ACC_MAX)) acc_next = ACC_MAX;
        else if (sum_wide < (ACC_W+1)'(ACC_MIN)) acc_next = ACC_MIN;
        else                                     acc_next = sum_wide[ACC_W-1:0];
    end

    // ---- accumulator register (uses DELAYED control) ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          acc <= '0;
        else if (clr_r)     acc <= en_r ? prod_ext : '0;
        else if (en_r)     acc <= acc_next;
    end

`ifndef SYNTHESIS
    initial begin
        if (ACC_W < PROD_W) $fatal(1, "ACC_W (%0d) must be >= 2*IN_W (%0d)", ACC_W, PROD_W);
    end
`endif
endmodule