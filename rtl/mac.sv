// =============================================================================
// mac.sv — Parameterized signed Multiply-Accumulate (MAC) unit
// -----------------------------------------------------------------------------
// acc <= acc + a * b           (a, b : signed IN_W-bit, acc : signed ACC_W-bit)
//
// Control (synchronous, active-high):
//   clr & en  : acc <= a*b        (start a new dot product with this term)
//   clr & !en : acc <= 0
//   !clr & en : acc <= acc + a*b  (accumulate)
//   otherwise : hold
//
// Why ACC_W = 32 for INT8?
//   one INT8 x INT8 product needs 16 bits (-128*-128 = 16384).
//   Summing N products needs 16 + ceil(log2(N)) bits.
//   32 bits => up to 2^16 = 65,536 terms without overflow.
// =============================================================================
module mac #(
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

    // ---- combinational multiply (synthesizes to a signed array multiplier) ----
    logic signed [PROD_W-1:0] prod;
    assign prod = a * b;

    // ---- sign-extend product to accumulator width ----
    logic signed [ACC_W-1:0] prod_ext;
    assign prod_ext = {{(ACC_W - PROD_W){prod[PROD_W-1]}}, prod};

    // ---- overflow detection ----
    logic signed [ACC_W:0]    sum_wide;
    assign sum_wide = acc + prod_ext;

    // ---- accumulate next
    logic signed [ACC_W-1:0] acc_next;
    always_comb begin
        if (!SAT)                                acc_next = sum_wide[ACC_W-1:0];
	else if (sum_wide > (ACC_W+1)'(ACC_MAX)) acc_next = ACC_MAX;
        else if (sum_wide < (ACC_W+1)'(ACC_MIN)) acc_next = ACC_MIN;
	else                                     acc_next = sum_wide[ACC_W-1:0];

    end
         

    // ---- accumulator register ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       acc <= '0;
        else if (clr)     acc <= en ? prod_ext : '0;
        else if (en)      acc <= acc_next;
    end

`ifndef SYNTHESIS
    initial begin
        if (ACC_W < PROD_W) $fatal(1, "ACC_W (%0d) must be >= 2*IN_W (%0d)", ACC_W, PROD_W);
    end
`endif
endmodule
