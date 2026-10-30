`timescale 1ns / 1ps
//==============================================================================
// cnn_top : Basys3 wrapper for the lightweight CNN digit classifier
//
//   SW[3:0]  select one of 16 pre-stored 8x8 test images
//   btnC     start inference on the selected image
//   btnU     reset
//   SW[15]   0: show  [true digit] . . [predicted digit]
//            1: show inference latency in clock cycles (hex)
//   LED[9:0] one-hot predicted class, LED13 = match with true label,
//   LED14    = result valid, LED15 = busy
//==============================================================================
module cnn_top #(
    parameter DEBOUNCE_CYCLES = 1_000_000
)(
    input         clk,
    input  [15:0] sw,
    input         btnC,
    input         btnU,
    output [15:0] led,
    output [6:0]  seg,
    output        dp,
    output [3:0]  an
);
    // reset: synchronised level from btnU
    reg r1 = 1'b0, r2 = 1'b0;
    always @(posedge clk) begin r1 <= btnU; r2 <= r1; end
    wire rst = r2;

    wire start;
    btn_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_db (.clk(clk), .btn_in(btnC), .pulse(start));

    // synchronise slide switches
    reg [15:0] sw_s1 = 16'd0, sw_s2 = 16'd0;
    always @(posedge clk) begin sw_s1 <= sw; sw_s2 <= sw_s1; end
    wire [3:0] img_sel = sw_s2[3:0];
    wire       show_cyc = sw_s2[15];

    wire        busy, done;
    wire [3:0]  pred;
    wire [15:0] cycles;
    wire [239:0] logits_unused;

    cnn_core u_core (
        .clk(clk), .rst(rst), .start(start), .img_sel(img_sel),
        .busy(busy), .done(done), .pred(pred), .cycles(cycles), .logits_flat(logits_unused)
    );

    // remember which image the displayed result belongs to
    reg [3:0] sel_run = 4'd0;
    always @(posedge clk) if (start && !busy) sel_run <= img_sel;
    wire valid = done && (sel_run == img_sel);

    wire [3:0] label;
    rom_label u_lbl (.addr(img_sel), .dout(label));

    wire match = valid && (pred == label);

    // display
    wire [3:0] d3 = show_cyc ? cycles[15:12] : label;
    wire [3:0] d2 = show_cyc ? cycles[11:8]  : 4'd0;
    wire [3:0] d1 = show_cyc ? cycles[7:4]   : 4'd0;
    wire [3:0] d0 = show_cyc ? cycles[3:0]   : pred;
    wire [3:0] blank = show_cyc ? {4{~valid}} : {1'b0, 1'b1, 1'b1, ~valid};

    seven_seg_driver u_seg (
        .clk(clk), .d3(d3), .d2(d2), .d1(d1), .d0(d0),
        .blank(blank), .dp_in({1'b0, 1'b0, 1'b0, match}),
        .seg(seg), .dp(dp), .an(an)
    );

    // LEDs
    reg [9:0] onehot;
    always @* begin
        onehot = 10'd0;
        if (valid && pred <= 4'd9) onehot[pred] = 1'b1;
    end
    assign led = {busy, valid, match, 3'b000, onehot};
endmodule
