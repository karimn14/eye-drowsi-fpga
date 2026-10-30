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
    integer correct_count;
    reg expected_label [0:15];
    reg expected_prediction;

    initial begin
        // Labels from ml/export/expected.txt: 0 = CLOSED, 1 = OPEN.
        expected_label[0]  = 1;
        expected_label[1]  = 0;
        expected_label[2]  = 0;
        expected_label[3]  = 1;
        expected_label[4]  = 0;
        expected_label[5]  = 1;
        expected_label[6]  = 0;
        expected_label[7]  = 1;
        expected_label[8]  = 0;
        expected_label[9]  = 1;
        expected_label[10] = 0;
        expected_label[11] = 1;
        expected_label[12] = 0;
        expected_label[13] = 1;
        expected_label[14] = 0;
        expected_label[15] = 1;
    end

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        img_base_addr = 0;
        correct_count = 0;

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

            expected_prediction = expected_label[img_i];
            if (prediction == expected_prediction) begin
                correct_count = correct_count + 1;
                $display("Image %2d | Expected: %s | Pred: %s | CORRECT | Logit0: %d | Logit1: %d",
                         img_i, expected_prediction ? "OPEN  " : "CLOSED",
                         prediction ? "OPEN  " : "CLOSED", logit0, logit1);
            end else begin
                $display("Image %2d | Expected: %s | Pred: %s | WRONG   | Logit0: %d | Logit1: %d",
                         img_i, expected_prediction ? "OPEN  " : "CLOSED",
                         prediction ? "OPEN  " : "CLOSED", logit0, logit1);
            end
        end

        $display("====================================================");
        $display("   Classification accuracy: %0d / 16", correct_count);
        $display("====================================================");
        $display("   Simulation Complete!");
        $display("====================================================");
        $finish;
    end
endmodule