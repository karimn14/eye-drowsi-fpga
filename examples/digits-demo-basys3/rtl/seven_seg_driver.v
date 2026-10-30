`timescale 1ns / 1ps
// 4-digit multiplexed 7-segment driver for Basys3 (common anode, active-low segments and anodes).
// d3 = leftmost digit (an[3]), d0 = rightmost (an[0]). Hex digits 0-F supported.
module seven_seg_driver (
    input             clk,
    input      [3:0]  d3, d2, d1, d0,
    input      [3:0]  blank,       // 1 = digit off
    input      [3:0]  dp_in,       // 1 = decimal point on
    output reg [6:0]  seg,         // {g,f,e,d,c,b,a}, active low
    output            dp,          // active low
    output reg [3:0]  an           // active low
);
    reg [17:0] scan = 18'd0;
    always @(posedge clk) scan <= scan + 18'd1;
    wire [1:0] s = scan[17:16];

    reg [3:0] val;
    reg       blk, pt;
    always @* begin
        case (s)
            2'd0: begin val = d0; blk = blank[0]; pt = dp_in[0]; an = 4'b1110; end
            2'd1: begin val = d1; blk = blank[1]; pt = dp_in[1]; an = 4'b1101; end
            2'd2: begin val = d2; blk = blank[2]; pt = dp_in[2]; an = 4'b1011; end
            default: begin val = d3; blk = blank[3]; pt = dp_in[3]; an = 4'b0111; end
        endcase
        if (blk) an = 4'b1111;
    end

    always @* begin
        case (val)                        // gfedcba, active low
            4'h0: seg = ~7'b0111111;
            4'h1: seg = ~7'b0000110;
            4'h2: seg = ~7'b1011011;
            4'h3: seg = ~7'b1001111;
            4'h4: seg = ~7'b1100110;
            4'h5: seg = ~7'b1101101;
            4'h6: seg = ~7'b1111101;
            4'h7: seg = ~7'b0000111;
            4'h8: seg = ~7'b1111111;
            4'h9: seg = ~7'b1101111;
            4'hA: seg = ~7'b1110111;
            4'hB: seg = ~7'b1111100;
            4'hC: seg = ~7'b0111001;
            4'hD: seg = ~7'b1011110;
            4'hE: seg = ~7'b1111001;
            default: seg = ~7'b1110001;   // F
        endcase
    end
    assign dp = ~pt;
endmodule
