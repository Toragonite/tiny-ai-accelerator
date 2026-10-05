// =============================================================================
// mac_csa.sv — 2-stage pipelined signed MAC with carry-save accumulation
// -----------------------------------------------------------------------------
// Stage 1 : prod_r <= a * b                       (same as mac_pipe)
// Stage 2 : (acc_s, acc_c) <= CSA(acc_s, acc_c, prod_ext)
// Output  : acc = acc_s + acc_c                   (combinational, OUTSIDE the loop)
//
// Why: in mac_pipe the feedback loop acc -> 32-bit adder -> acc holds the whole
//   carry chain, and a loop cannot be pipelined. Keeping acc in redundant form
//   (two vectors whose sum is the value) leaves only one full-adder level per bit
//   in the loop. The carry-propagate add moves to the output, where it is needed
//   once per dot product and can be pipelined or shared.
//
// CSA (3:2 compressor), bit-wise, no carry chain:
//   sum   = x ^ y ^ z
//   carry = ((x & y) | (x & z) | (y & z)) << 1        ->  x + y + z = sum + carry
//
// Wrap-around (mod 2^ACC_W) is identical to mac_pipe SAT=0: dropping the carry's
// MSB in the shift is a drop of 2^ACC_W. Saturation is not supported, because
// overflow cannot be detected without resolving the carries every cycle.
//
// Latency   : 2 cycles (input -> acc updated), same as mac_pipe
// Control   : same as mac_pipe (delayed en_r / clr_r applied in stage 2)
// =============================================================================
module mac_csa #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32
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

    // =========================================================================
    // Stage 1 : multiply
    // =========================================================================
    logic signed [PROD_W-1:0] prod_r;
    logic                     en_r, clr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r <= '0;
            en_r   <= '0;
            clr_r  <= '0;
        end else begin
            prod_r <= a * b;
            en_r   <= en;
            clr_r  <= clr;
        end
    end

    // =========================================================================
    // Stage 2 : carry-save accumulate
    // =========================================================================
    logic [ACC_W-1:0] prod_ext;
    assign prod_ext = {{(ACC_W - PROD_W){prod_r[PROD_W-1]}}, prod_r};

    logic [ACC_W-1:0] acc_s, acc_c;      // acc value = acc_s + acc_c (mod 2^ACC_W)
    logic [ACC_W-1:0] csa_s, csa_c;

    assign csa_s = acc_s ^ acc_c ^ prod_ext;
    assign csa_c = ((acc_s & acc_c) | (acc_s & prod_ext) | (acc_c & prod_ext)) << 1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_s <= '0;
            acc_c <= '0;
        end else if (clr_r) begin
            acc_s <= en_r ? prod_ext : '0;
            acc_c <= '0;
        end else if (en_r) begin
            acc_s <= csa_s;
            acc_c <= csa_c;
        end
    end

    // =========================================================================
    // Output : resolve the redundant form (carry-propagate add)
    // =========================================================================
    assign acc = signed'(acc_s + acc_c);

`ifndef SYNTHESIS
    initial begin
        if (ACC_W < PROD_W) $fatal(1, "ACC_W (%0d) must be >= 2*IN_W (%0d)", ACC_W, PROD_W);
    end
`endif
endmodule
