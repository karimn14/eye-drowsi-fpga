`timescale 1ns / 1ps

module basys3_wrapper (
    input clk,               // 100MHz clock (W5)
    input btnC,              // Reset button (U18)
    input btnR,              // Start button (T17)
    input [3:0] sw,          // Image index selection (V17, V16, W16, W15)
    output [15:0] led,       // LEDs
    output [6:0] seg,        // 7-segment cathodes
    output [3:0] an          // 7-segment anodes
);

    reg btnR_d1, btnR_d2;
    wire start_pulse;

    always @(posedge clk or posedge btnC) begin
        if (btnC) begin
            btnR_d1 <= 0;
            btnR_d2 <= 0;
        end else begin
            btnR_d1 <= btnR;
            btnR_d2 <= btnR_d1;
        end
    end

    assign start_pulse = btnR_d1 & ~btnR_d2;

    wire done;
    wire prediction;
    wire signed [31:0] logit0, logit1;

    cnn_top cnn_inst (
        .clk(clk),
        .rst(btnC),
        .start(start_pulse),
        .img_base_addr({sw, 10'b0}), // sw * 1024
        .done(done),
        .prediction(prediction),
        .logit0(logit0),
        .logit1(logit1)
    );

    seven_seg_drive seg_inst (
        .clk(clk),
        .rst(btnC),
        .prediction(prediction),
        .done(done),
        .an(an),
        .seg(seg)
    );

    assign led[0]    = prediction; // 1: Open, 0: Closed
    assign led[14]   = start_pulse;
    assign led[15]   = done;
    assign led[13:1] = 13'b0;

endmodule