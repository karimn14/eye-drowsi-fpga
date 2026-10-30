`timescale 1ns / 1ps
// Top-level smoke test with a shortened debounce time: press btnC for each image and check
// that LED one-hot output equals the golden prediction.
module tb_cnn_top;
    reg clk = 0;
    reg [15:0] sw = 0;
    reg btnC = 0, btnU = 0;
    wire [15:0] led; wire [6:0] seg; wire dp; wire [3:0] an;

    cnn_top #(.DEBOUNCE_CYCLES(4)) dut (.clk(clk), .sw(sw), .btnC(btnC), .btnU(btnU),
                                         .led(led), .seg(seg), .dp(dp), .an(an));
    always #5 clk = ~clk;

    wire [3:0] g_pred, g_label; wire [239:0] g_logits;
    golden_rom gold (.idx(sw[3:0]), .pred(g_pred), .label(g_label), .logits(g_logits));

    integer n, errors;
    initial begin
        errors = 0;
        btnU = 1; repeat (10) @(posedge clk); btnU = 0; repeat (10) @(posedge clk);
        for (n = 0; n < 16; n = n + 1) begin
            sw[3:0] = n; repeat (10) @(posedge clk);
            btnC = 1; repeat (20) @(posedge clk); btnC = 0;
            repeat (5000) @(posedge clk);
            if (led[14] !== 1'b1 || led[9:0] !== (10'd1 << g_pred)) begin
                $display("[FAIL] img %0d led=%b expected pred %0d", n, led, g_pred); errors = errors + 1;
            end else $display("[ OK ] img %2d pred=%0d match_led=%b", n, g_pred, led[13]);
        end
        if (errors == 0) $display("*** TOP TEST PASSED ***"); else $display("*** TOP TEST FAILED ***");
        $finish;
    end
endmodule
