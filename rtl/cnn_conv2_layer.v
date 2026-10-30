`timescale 1ns / 1ps

// Behavioral Conv2 + ReLU/requantisation + 2x2 max-pooling.
module cnn_conv2_layer (
    input              clk,
    input              rst,
    input              start,
    input      [3871:0] a1_flat,
    output reg [1023:0] a2_flat,
    output reg         done
);
    reg signed [7:0] weights [0:287];
    reg signed [31:0] biases [0:7];
    integer f, orow, ocol, prow, pcol, ch, kr, kc;
    integer acc, value, max_value, pixel;
    integer weight_index, pixel_index, output_index;

    initial begin
        $readmemh("conv2_w.mem", weights);
        $readmemh("conv2_b.mem", biases);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a2_flat <= 0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (f = 0; f < 8; f = f + 1) begin
                    for (orow = 0; orow < 4; orow = orow + 1) begin
                        for (ocol = 0; ocol < 4; ocol = ocol + 1) begin
                            max_value = 0;
                            for (prow = 0; prow < 2; prow = prow + 1) begin
                                for (pcol = 0; pcol < 2; pcol = pcol + 1) begin
                                    acc = biases[f];
                                    for (ch = 0; ch < 4; ch = ch + 1) begin
                                        for (kr = 0; kr < 3; kr = kr + 1) begin
                                            for (kc = 0; kc < 3; kc = kc + 1) begin
                                                pixel_index = ch*121
                                                    + (orow*2 + prow + kr)*11
                                                    + (ocol*2 + pcol + kc);
                                                weight_index = f*36 + ch*9 + kr*3 + kc;
                                                pixel = a1_flat[pixel_index*8 +: 8];
                                                acc = acc + pixel * $signed(weights[weight_index]);
                                            end
                                        end
                                    end
                                    value = acc >>> 7;
                                    if (value < 0)
                                        value = 0;
                                    else if (value > 127)
                                        value = 127;
                                    if (value > max_value)
                                        max_value = value;
                                end
                            end
                            output_index = f*16 + orow*4 + ocol;
                            a2_flat[output_index*8 +: 8] = max_value[7:0];
                        end
                    end
                end
                done <= 1'b1;
            end
        end
    end
endmodule
