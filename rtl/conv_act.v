`timescale 1ns / 1ps

module conv_act #(
    parameter SHIFT = 10
)(
    input  signed [31:0] acc,
    output        [7:0]  act_out
);
    wire signed [31:0] shifted = acc >>> SHIFT;

    assign act_out = (shifted < 32'sd0)   ? 8'd0 :
                     (shifted > 32'sd127) ? 8'd127 :
                     shifted[7:0];
endmodule