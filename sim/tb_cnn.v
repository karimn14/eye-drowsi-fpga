`timescale 1ns / 1ps

module tb_cnn;
    reg clk;
    reg rst;
    reg start;
    reg [13:0] img_base_addr;

    wire done;
    wire prediction;
    wire signed [31:0] logit0, logit1;

    cnn_top uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .img_base_addr(img_base_addr),
        .done(done),
        .prediction(prediction),
        .logit0(logit0),
        .logit1(logit1)
    );

    always #5 clk = ~clk; // 100MHz clock

    integer img_i;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        img_base_addr = 0;

        #100;
        rst = 0;
        #50;

        $display("====================================================");
        $display("   Starting CNN Eye Drowsiness Detection Simulation ");
        $display("====================================================");

        for (img_i = 0; img_i < 16; img_i = img_i + 1) begin
            img_base_addr = img_i * 1024;
            #20;
            start = 1;
            #10;
            start = 0;

            wait(done);
            #20;

            $display("Image %2d | Base Addr: %5d | Pred: %s | Logit0: %d | Logit1: %d",
                     img_i, img_base_addr, prediction ? "OPEN  " : "CLOSED", logit0, logit1);
        end

        $display("====================================================");
        $display("   Simulation Complete!");
        $display("====================================================");
        $finish;
    end
endmodule