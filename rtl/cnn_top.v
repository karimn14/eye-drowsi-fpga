`timescale 1ns / 1ps

// Top-level layer scheduler. Numerical work lives in one module per layer.
module cnn_top (
    input clk,
    input rst,
    input start,
    input [13:0] img_base_addr,
    output reg done,
    output reg prediction,
    output reg signed [31:0] logit0,
    output reg signed [31:0] logit1
);
    localparam ST_IDLE = 3'd0,
               ST_LOAD = 3'd1,
               ST_CONV1 = 3'd2,
               ST_CONV2 = 3'd3,
               ST_FC = 3'd4,
               ST_DONE = 3'd5;

    reg [2:0] state;
    reg load_start, conv1_start, conv2_start, fc_start;
    wire load_done, conv1_done, conv2_done, fc_done;
    wire [4607:0] image_flat;
    wire [3871:0] a1_flat;
    wire [1023:0] a2_flat;
    wire signed [31:0] fc_logit0, fc_logit1;
    wire fc_prediction;

    cnn_image_loader image_loader (
        .clk(clk), .rst(rst), .start(load_start),
        .base_addr(img_base_addr), .image_flat(image_flat), .done(load_done)
    );

    cnn_conv1_layer conv1 (
        .clk(clk), .rst(rst), .start(conv1_start),
        .image_flat(image_flat), .a1_flat(a1_flat), .done(conv1_done)
    );

    cnn_conv2_layer conv2 (
        .clk(clk), .rst(rst), .start(conv2_start),
        .a1_flat(a1_flat), .a2_flat(a2_flat), .done(conv2_done)
    );

    cnn_fc_layer fc (
        .clk(clk), .rst(rst), .start(fc_start),
        .a2_flat(a2_flat), .logit0(fc_logit0), .logit1(fc_logit1),
        .prediction(fc_prediction), .done(fc_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            done <= 1'b0;
            prediction <= 1'b0;
            logit0 <= 0;
            logit1 <= 0;
            load_start <= 1'b0;
            conv1_start <= 1'b0;
            conv2_start <= 1'b0;
            fc_start <= 1'b0;
        end else begin
            done <= 1'b0;
            load_start <= 1'b0;
            conv1_start <= 1'b0;
            conv2_start <= 1'b0;
            fc_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        load_start <= 1'b1;
                        state <= ST_LOAD;
                    end
                end
                ST_LOAD: begin
                    if (load_done) begin
                        conv1_start <= 1'b1;
                        state <= ST_CONV1;
                    end
                end
                ST_CONV1: begin
                    if (conv1_done) begin
                        conv2_start <= 1'b1;
                        state <= ST_CONV2;
                    end
                end
                ST_CONV2: begin
                    if (conv2_done) begin
                        fc_start <= 1'b1;
                        state <= ST_FC;
                    end
                end
                ST_FC: begin
                    if (fc_done) begin
                        logit0 <= fc_logit0;
                        logit1 <= fc_logit1;
                        prediction <= fc_prediction;
                        done <= 1'b1;
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    if (!start)
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
