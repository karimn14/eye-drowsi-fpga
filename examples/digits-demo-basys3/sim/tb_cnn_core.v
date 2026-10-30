`timescale 1ns / 1ps
// Self-checking testbench: runs all 16 stored images and compares the prediction AND all
// 10 int24 logits bit-exactly against the Python golden model (golden_rom.v).
module tb_cnn_core;
    reg         clk = 0, rst = 1, start = 0;
    reg  [3:0]  img_sel = 0;
    wire        busy, done;
    wire [3:0]  pred;
    wire [15:0] cycles;
    wire [239:0] logits;

    cnn_core dut (.clk(clk), .rst(rst), .start(start), .img_sel(img_sel),
                  .busy(busy), .done(done), .pred(pred), .cycles(cycles), .logits_flat(logits));

    wire [3:0]   g_pred, g_label;
    wire [239:0] g_logits;
    golden_rom gold (.idx(img_sel), .pred(g_pred), .label(g_label), .logits(g_logits));

    always #5 clk = ~clk;                       // 100 MHz

    integer n, errors, correct, timeout;
    initial begin
        errors = 0; correct = 0;
        repeat (5) @(posedge clk);
        rst <= 0;
        repeat (3) @(posedge clk);

        for (n = 0; n < 16; n = n + 1) begin
            img_sel <= n[3:0];
            @(posedge clk);
            start <= 1; @(posedge clk); start <= 0;
            timeout = 0;
            @(posedge clk);
            while (!done && timeout < 20000) begin @(posedge clk); timeout = timeout + 1; end
            #1;
            if (!done) begin
                $display("[FAIL] img %0d : timeout", n); errors = errors + 1;
            end else begin
                if (pred !== g_pred || logits !== g_logits) begin
                    $display("[FAIL] img %0d : pred=%0d golden=%0d  logits_match=%0d", n, pred, g_pred, (logits === g_logits));
                    errors = errors + 1;
                end else
                    $display("[ OK ] img %2d : label=%0d pred=%0d  latency=%0d cycles (%0d ns)", n, g_label, pred, cycles, cycles*10);
                if (pred == g_label) correct = correct + 1;
            end
            repeat (3) @(posedge clk);
        end
        $display("----------------------------------------------");
        $display("Bit-exact mismatches vs golden : %0d / 16", errors);
        $display("Correct classifications        : %0d / 16", correct);
        if (errors == 0) $display("*** TEST PASSED ***"); else $display("*** TEST FAILED ***");
        $finish;
    end
endmodule
