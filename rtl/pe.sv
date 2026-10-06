// =============================================================================
// pe.sv — Processing Element for an output-stationary systolic array
// -----------------------------------------------------------------------------
//            b_in
//             |
//   a_in --> [PE] --> a_out        a, en, clr : left -> right (1 cycle per PE)
//   en_in     |  acc               b          : top  -> bottom (1 cycle per PE)
//   clr_in   b_out
//
// The PE keeps its output C[i][j] in place (output-stationary) and accumulates
//   acc <= acc + a_in * b_in   (the verified mac: same en / clr semantics)
// while forwarding its operands to the neighbours through registers. en / clr
// travel with a, so a bubble (en = 0) or a restart (clr = 1) reaches every PE
// in the same time slot as the data it belongs to.
// =============================================================================
module pe #(
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0
) (
    input  logic                    clk,
    input  logic                    rst_n,   // async active-low reset
    input  logic signed [IN_W-1:0]  a_in,    // from the left neighbour
    input  logic signed [IN_W-1:0]  b_in,    // from the top neighbour
    input  logic                    en_in,   // a_in / b_in valid -> accumulate
    input  logic                    clr_in,  // first term of a new dot product
    output logic signed [IN_W-1:0]  a_out,   // to the right neighbour
    output logic signed [IN_W-1:0]  b_out,   // to the bottom neighbour
    output logic                    en_out,
    output logic                    clr_out,
    output logic signed [ACC_W-1:0] acc      // C[i][j]
);
    mac #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT)) u_mac (
        .clk, .rst_n, .en(en_in), .clr(clr_in), .a(a_in), .b(b_in), .acc
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out   <= '0;
            b_out   <= '0;
            en_out  <= 1'b0;
            clr_out <= 1'b0;
        end else begin
            a_out   <= a_in;
            b_out   <= b_in;
            en_out  <= en_in;
            clr_out <= clr_in;
        end
    end
endmodule
