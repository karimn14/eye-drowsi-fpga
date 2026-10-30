`timescale 1ns / 1ps

module seven_seg_drive (
    input clk,
    input rst,
    input prediction,        // 0: Closed, 1: Open
    input done,
    output reg [3:0] an,     // Active low anodes
    output reg [6:0] seg     // Active low segments
);

    reg [17:0] refresh_counter;
    wire [1:0] digit_select = refresh_counter[17:16];

    always @(posedge clk or posedge rst) begin
        if (rst)
            refresh_counter <= 0;
        else
            refresh_counter <= refresh_counter + 1;
    end

    // Segment encoding: active LOW
    localparam SEG_O   = 7'b1000000;
    localparam SEG_P   = 7'b0001100;
    localparam SEG_N   = 7'b0101010;
    localparam SEG_C   = 7'b1000110;
    localparam SEG_L   = 7'b1000111;
    localparam SEG_S   = 7'b0100100;
    localparam SEG_D   = 7'b0100001;
    localparam SEG_OFF = 7'b1111111;

    always @(*) begin
        if (!done) begin
            an = 4'b0000;
            seg = 7'b0111111; // Display dashes while processing
        end else if (prediction) begin
            case (digit_select)
                2'b00: begin an = 4'b0111; seg = SEG_O; end
                2'b01: begin an = 4'b1011; seg = SEG_P; end
                2'b10: begin an = 4'b1101; seg = SEG_N; end
                2'b11: begin an = 4'b1110; seg = SEG_OFF; end
            endcase
        end else begin
            case (digit_select)
                2'b00: begin an = 4'b0111; seg = SEG_C; end
                2'b01: begin an = 4'b1011; seg = SEG_L; end
                2'b10: begin an = 4'b1101; seg = SEG_S; end
                2'b11: begin an = 4'b1110; seg = SEG_D; end
            endcase
        end
    end

endmodule