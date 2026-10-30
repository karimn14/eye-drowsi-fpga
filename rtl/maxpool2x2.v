`timescale 1ns / 1ps

module maxpool2x2 (
    input  [7:0] p0, p1, p2, p3,
    output [7:0] max_val
);
    wire [7:0] m0 = (p0 > p1) ? p0 : p1;
    wire [7:0] m1 = (p2 > p3) ? p2 : p3;
    assign max_val = (m0 > m1) ? m0 : m1;
endmodule