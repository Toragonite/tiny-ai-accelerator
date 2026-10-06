// =============================================================================
// delay_line.sv — D-cycle register delay (D = 0 is a wire)
// -----------------------------------------------------------------------------
// Used for the systolic input skew: row i / column j is delayed by i / j cycles.
// =============================================================================
module delay_line #(
    parameter int W = 8,
    parameter int D = 1
) (
    /* verilator lint_off UNUSEDSIGNAL */   // clk / rst_n are unused when D = 0
    input  logic         clk,
    input  logic         rst_n,   // async active-low reset
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);
    if (D == 0) begin : g_wire
        assign q = d;
    end else begin : g_reg
        logic [D*W-1:0] r;   // r[n*W +: W] = d delayed by n+1 cycles
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) r <= '0;
            else        r <= (r << W) | (D*W)'(d);
        assign q = r[(D-1)*W +: W];
    end
endmodule
