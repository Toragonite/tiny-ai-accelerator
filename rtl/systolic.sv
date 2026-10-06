// =============================================================================
// systolic.sv — ROWS x COLS output-stationary systolic array: C = A x B
// -----------------------------------------------------------------------------
// One k per cycle (in_valid = 1):
//   a_col[i*IN_W +: IN_W]           = A[i][k]     (column k of A)
//   b_row[j*IN_W +: IN_W]           = B[k][j]     (row k of B)
//   c[(i*COLS + j)*ACC_W +: ACC_W]  = C[i][j]
//   in_first marks k = 0 (clears every PE as it passes), in_last marks k = K-1.
//   in_valid = 0 cycles (bubbles) are allowed anywhere inside a matrix.
// Ports and mesh wires are flat vectors because Yosys 0.33 cannot read
// multi-dimensional packed ports.
//
// Input skew: row i of A is delayed by i cycles and column j of B by j cycles,
// so A[i][k] (i skew + j hops right) and B[k][j] (j skew + i hops down) meet in
// PE(i,j) in the same cycle.
//
// Timing, counted in clock edges after the edge that samples a k on the ports:
//   PE(i,j) accumulates that k on edge +(i+j)
//   the last k reaches PE(ROWS-1, COLS-1) on edge +(ROWS+COLS-2)
//   done rises on that same edge, is high for one cycle, and every c[i][j] is final then
//
// The next matrix may start (in_first sampled) at the clock edge right after
// done at the earliest, since its first k clears PE(0,0) on that edge.
// =============================================================================
module systolic #(
    parameter int ROWS  = 4,
    parameter int COLS  = 4,
    parameter int IN_W  = 8,
    parameter int ACC_W = 32,
    parameter bit SAT   = 0
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        in_valid,
    input  logic                        in_first,
    input  logic                        in_last,
    input  logic [ROWS*IN_W-1:0]        a_col,   // column k of A
    input  logic [COLS*IN_W-1:0]        b_row,   // row k of B
    output logic [ROWS*COLS*ACC_W-1:0]  c,       // C, row-major
    output logic                        done
);
    // ---- PE mesh wires ----
    // horizontal {en, clr, a}: node (i, j), j = 0..COLS  (PE(i,j) input = j, output = j+1)
    // vertical   b           : node (i, j), i = 0..ROWS  (PE(i,j) input = i, output = i+1)
    localparam int HW = IN_W + 2;
    /* verilator lint_off UNUSED */                  // outputs of the last column / row
    logic [ROWS*(COLS+1)*HW-1:0]   h;
    logic [(ROWS+1)*COLS*IN_W-1:0] v;
    /* verilator lint_on UNUSED */

    // =========================================================================
    // Input skew: row i -> i registers, column j -> j registers
    // =========================================================================
    for (genvar i = 0; i < ROWS; i++) begin : g_skew_a
        delay_line #(.W(HW), .D(i)) u_dly (
            .clk, .rst_n,
            .d({in_valid, in_valid & in_first, a_col[i*IN_W +: IN_W]}),
            .q(h[i*(COLS+1)*HW +: HW])
        );
    end

    for (genvar j = 0; j < COLS; j++) begin : g_skew_b
        delay_line #(.W(IN_W), .D(j)) u_dly (
            .clk, .rst_n, .d(b_row[j*IN_W +: IN_W]), .q(v[j*IN_W +: IN_W])
        );
    end

    // =========================================================================
    // PE mesh
    // =========================================================================
    for (genvar i = 0; i < ROWS; i++) begin : g_row
        for (genvar j = 0; j < COLS; j++) begin : g_col
            localparam int HI = (i*(COLS+1) + j) * HW;    // h node (i, j)
            localparam int HO = HI + HW;                   // h node (i, j+1)
            localparam int VI = (i*COLS + j) * IN_W;       // v node (i, j)
            localparam int VO = VI + COLS*IN_W;            // v node (i+1, j)

            pe #(.IN_W(IN_W), .ACC_W(ACC_W), .SAT(SAT)) u_pe (
                .clk, .rst_n,
                .en_in  (h[HI+HW-1]), .clr_in (h[HI+HW-2]), .a_in (h[HI +: IN_W]),
                .b_in   (v[VI +: IN_W]),
                .en_out (h[HO+HW-1]), .clr_out(h[HO+HW-2]), .a_out(h[HO +: IN_W]),
                .b_out  (v[VO +: IN_W]),
                .acc    (c[(i*COLS + j)*ACC_W +: ACC_W])
            );
        end
    end

    // =========================================================================
    // done: in_last delayed by ROWS+COLS-1 registers (stage 0 on edge +0, last stage on
    //       edge +(ROWS+COLS-2)) -> rises together with PE(ROWS-1, COLS-1)'s last update
    // =========================================================================
    localparam int DONE_D = ROWS + COLS - 1;
    logic [DONE_D-1:0] last_sr;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) last_sr <= '0;
        else        last_sr <= {last_sr[DONE_D-2:0], in_valid & in_last};

    assign done = last_sr[DONE_D-1];

`ifndef SYNTHESIS
    initial begin
        if (ROWS < 2 || COLS < 2) $fatal(1, "ROWS (%0d) and COLS (%0d) must be >= 2", ROWS, COLS);
    end
`endif
endmodule
