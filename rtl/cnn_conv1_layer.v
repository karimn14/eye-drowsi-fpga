`timescale 1ns / 1ps

// Behavioral Conv1 + ReLU/requantisation + 2x2 max-pooling.
module cnn_conv1_layer (
    input              clk,
    input              rst,
    input              start,
    input      [4607:0] image_flat,
    output reg [3871:0] a1_flat,
    output reg         done
);
    reg signed [7:0] weights [0:35];
    reg signed [31:0] biases [0:3];
    integer f, orow, ocol, prow, pcol, kr, kc;
    integer acc, value, max_value, pixel;
    integer weight_index, pixel_index, output_index;

    initial begin
        $readmemh("conv1_w.mem", weights);
        $readmemh("conv1_b.mem", biases);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a1_flat <= 0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (f = 0; f < 4; f = f + 1) begin
                    for (orow = 0; orow < 11; orow = orow + 1) begin
                        for (ocol = 0; ocol < 11; ocol = ocol + 1) begin
                            max_value = 0;
                            for (prow = 0; prow < 2; prow = prow + 1) begin
                                for (pcol = 0; pcol < 2; pcol = pcol + 1) begin
                                    acc = biases[f];
                                    for (kr = 0; kr < 3; kr = kr + 1) begin
                                        for (kc = 0; kc < 3; kc = kc + 1) begin
                                            pixel_index = ((orow*2 + prow + kr) * 24)
                                                        + (ocol*2 + pcol + kc);
                                            weight_index = f*9 + kr*3 + kc;
                                            pixel = image_flat[pixel_index*8 +: 8];
                                            acc = acc + pixel * $signed(weights[weight_index]);
                                        end
                                    end
                                    value = acc >>> 10;
                                    if (value < 0)
                                        value = 0;
                                    else if (value > 127)
                                        value = 127;
                                    if (value > max_value)
                                        max_value = value;
                                end
                            end
                            output_index = f*121 + orow*11 + ocol;
                            a1_flat[output_index*8 +: 8] = max_value[7:0];
                        end
                    end
                end
                done <= 1'b1;
            end
        end
    end
endmodule
