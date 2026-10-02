// =============================================================================
// fa.sv — 1-bit Full Adder
// -----------------------------------------------------------------------------
//   {cout, sum} = a + b + cin
// =============================================================================
module fa (
    input  logic a,
    input  logic b,
    input  logic cin,
    output logic sum,
    output logic cout
);
    assign sum  = a ^ b ^ cin;                 // ① 1의 개수가 홀수면 1
    assign cout = (a & b) | ((a ^ b) & cin);   // ② g | (p & cin)
endmodule
