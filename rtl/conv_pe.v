`timescale 1ns / 1ps
//==============================================================================
// conv_pe : one output value of a convolution = bias + sum(pix[i] * w[i])
//
//   NTAPS = 9  -> conv1 (1 input channel  x 3x3)
//   NTAPS = 36 -> conv2 (4 input channels x 3x3)
//
// Tap order (must match the weight ROM layout in quantize_export.py):
//   conv1 : tap = ky*3 + kx                  (weight addr = f*9  + tap)
//   conv2 : tap = ch*9 + ky*3 + kx           (weight addr = f*36 + tap)
//   pix_flat[8*tap +: 8] = unsigned pixel / activation (uint8, 0..255)
//   w_flat  [8*tap +: 8] = signed weight (int8, two's complement)
//
// Pipeline (fully parallel, 1 result per clock, no stall needed):
//   cycle k   : in_valid=1 with pix_flat / w_flat / bias
//   cycle k+2 : out_valid=1 with acc (signed 32-bit, bias included)
//   stage 1 = NTAPS multipliers (registered), stage 2 = adder + bias (registered)
// rst only clears the valid bits; acc is meaningful only while out_valid = 1.
//==============================================================================
module conv_pe #(
    parameter NTAPS = 9
)(
    input                      clk,
    input                      rst,          // synchronous, active high
    input                      in_valid,
    input      [8*NTAPS-1:0]   pix_flat,
    input      [8*NTAPS-1:0]   w_flat,
    input  signed [31:0]       bias,
    output reg                 out_valid,
    output reg signed [31:0]   acc
);
    reg signed [16:0] prod [0:NTAPS-1];     // uint8 * int8 fits in 17-bit signed
    reg signed [31:0] bias_q;
    reg               v1;

    integer i1, i2;
    reg signed [31:0] s;

    // ---------------- stage 1 : multiply
    always @(posedge clk) begin
        for (i1 = 0; i1 < NTAPS; i1 = i1 + 1)
            prod[i1] <= $signed({1'b0, pix_flat[8*i1 +: 8]}) * $signed(w_flat[8*i1 +: 8]);
        bias_q <= bias;
        v1     <= rst ? 1'b0 : in_valid;
    end

    // ---------------- stage 2 : accumulate + bias
    always @(posedge clk) begin
        s = bias_q;
        for (i2 = 0; i2 < NTAPS; i2 = i2 + 1)
            s = s + prod[i2];
        acc       <= s;
        out_valid <= rst ? 1'b0 : v1;
    end
endmodule
