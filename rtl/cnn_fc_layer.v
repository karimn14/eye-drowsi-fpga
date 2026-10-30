`timescale 1ns / 1ps

// Behavioral fully-connected layer and argmax decision.
module cnn_fc_layer (
    input              clk,
    input              rst,
    input              start,
    input      [1023:0] a2_flat,
    output reg signed [31:0] logit0,
    output reg signed [31:0] logit1,
    output reg         prediction,
    output reg         done
);
    reg signed [7:0] weights [0:255];
    reg signed [31:0] biases [0:1];
    integer cls, i, acc, pixel, weight_index;
    integer calculated_logit0, calculated_logit1;

    initial begin
        $readmemh("fc_w.mem", weights);
        $readmemh("fc_b.mem", biases);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            logit0 <= 0;
            logit1 <= 0;
            prediction <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                calculated_logit0 = 0;
                calculated_logit1 = 0;
                for (cls = 0; cls < 2; cls = cls + 1) begin
                    acc = biases[cls];
                    for (i = 0; i < 128; i = i + 1) begin
                        pixel = a2_flat[i*8 +: 8];
                        weight_index = cls*128 + i;
                        acc = acc + pixel * $signed(weights[weight_index]);
                    end
                    if (cls == 0) begin
                        calculated_logit0 = acc;
                        logit0 <= acc;
                    end else begin
                        calculated_logit1 = acc;
                        logit1 <= acc;
                    end
                end
                prediction <= (calculated_logit1 > calculated_logit0);
                done <= 1'b1;
            end
        end
    end
endmodule
