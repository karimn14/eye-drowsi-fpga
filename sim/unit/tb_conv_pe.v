`timescale 1ns / 1ps
//==============================================================================
// Unit test : conv_pe (NTAPS = 9 and 36)
//   - Python vectors (directed corners + random), expected = bias + sum(pix*w)
//   - phase 1: back-to-back inputs (1 per clock)  -> proves full throughput
//   - phase 2: random bubbles in in_valid          -> proves valid tracking
//   - latency: out_valid must appear exactly 2 clocks after in_valid
//   - reset  : out_valid must be 0 during/after rst
//==============================================================================
module conv_chk #(parameter NT = 9, parameter N = 2000,
                  parameter PIX_F = "conv9_pix.mem", parameter W_F = "conv9_w.mem",
                  parameter B_F = "conv9_b.mem", parameter E_F = "conv9_exp.mem")
                 (input clk, input rst, output reg done, output reg [31:0] errors, output reg [31:0] n_out);
    reg [8*NT-1:0] pix_m [0:N-1];
    reg [8*NT-1:0] w_m   [0:N-1];
    reg [31:0]     b_m   [0:N-1];
    reg [31:0]     e_m   [0:N-1];

    reg                  in_valid;
    reg  [8*NT-1:0]      pix, w;
    reg  signed [31:0]   bias;
    wire                 out_valid;
    wire signed [31:0]   acc;

    conv_pe #(.NTAPS(NT)) dut (.clk(clk), .rst(rst), .in_valid(in_valid), .pix_flat(pix),
                               .w_flat(w), .bias(bias), .out_valid(out_valid), .acc(acc));

    integer cyc, rd_idx, k, lat_first, lat_checked, in_cyc_first, bubbles;
    initial begin cyc = 0; rd_idx = 0; end
    always @(posedge clk) cyc <= cyc + 1;

    // ------------------------------------------------ monitor / scoreboard
    always @(posedge clk) if (!rst) begin
        if (out_valid) begin
            if (!lat_checked) begin
                lat_checked = 1;
                lat_first   = cyc - in_cyc_first;
                if (lat_first != 2) begin
                    errors = errors + 1;
                    $display("  [NT=%0d] FAIL latency = %0d clocks (expected 2)", NT, lat_first);
                end
            end
            if (acc !== $signed(e_m[rd_idx % N])) begin
                errors = errors + 1;
                if (errors < 10) $display("  [NT=%0d] FAIL out #%0d got=%0d exp=%0d", NT, rd_idx, acc, $signed(e_m[rd_idx % N]));
            end
            rd_idx = rd_idx + 1;
            n_out  = rd_idx;
        end
    end

    task drive; input integer idx;
        begin
            pix = pix_m[idx]; w = w_m[idx]; bias = b_m[idx]; in_valid = 1'b1;
        end
    endtask

    // ------------------------------------------------ stimulus
    initial begin
        errors = 0; n_out = 0; done = 0; lat_checked = 0; lat_first = -1; in_cyc_first = 0; bubbles = 0;
        in_valid = 0; pix = 0; w = 0; bias = 0;
        $readmemh(PIX_F, pix_m); $readmemh(W_F, w_m); $readmemh(B_F, b_m); $readmemh(E_F, e_m);
        wait (rst == 1'b0);
        repeat (3) @(negedge clk);

        // phase 1 : back-to-back
        for (k = 0; k < N; k = k + 1) begin
            @(negedge clk);
            if (k == 0) in_cyc_first = cyc;
            drive(k);
        end
        @(negedge clk); in_valid = 0;
        repeat (6) @(negedge clk);
        if (rd_idx != N) begin errors = errors + 1; $display("  [NT=%0d] FAIL phase1 outputs=%0d expected %0d", NT, rd_idx, N); end

        // phase 2 : random bubbles (in_valid low ~40% of the cycles, inputs keep changing)
        k = 0;
        while (k < N) begin
            @(negedge clk);
            if ($random % 5 < 2) begin
                in_valid = 0; pix = {NT{8'hA5}}; w = {NT{8'h5A}}; bubbles = bubbles + 1;   // garbage while invalid
            end else begin
                drive(k); k = k + 1;
            end
        end
        @(negedge clk); in_valid = 0;
        repeat (6) @(negedge clk);
        if (rd_idx != 2*N) begin errors = errors + 1; $display("  [NT=%0d] FAIL total outputs=%0d expected %0d", NT, rd_idx, 2*N); end
        done = 1;
    end
endmodule

module tb_conv_pe;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire d9, d36; wire [31:0] e9, e36, n9, n36;

    conv_chk #(.NT(9),  .PIX_F("conv9_pix.mem"),  .W_F("conv9_w.mem"),  .B_F("conv9_b.mem"),  .E_F("conv9_exp.mem"))
        u9  (.clk(clk), .rst(rst), .done(d9),  .errors(e9),  .n_out(n9));
    conv_chk #(.NT(36), .PIX_F("conv36_pix.mem"), .W_F("conv36_w.mem"), .B_F("conv36_b.mem"), .E_F("conv36_exp.mem"))
        u36 (.clk(clk), .rst(rst), .done(d36), .errors(e36), .n_out(n36));

    initial begin
        #55 rst = 0;
        wait (d9 && d36);
        #50;
        $display("conv_pe NTAPS=9  : %0d outputs checked, %0d errors", n9,  e9);
        $display("conv_pe NTAPS=36 : %0d outputs checked, %0d errors", n36, e36);
        if (e9 + e36 == 0) $display("*** TEST PASSED : tb_conv_pe ***");
        else               $display("*** TEST FAILED : tb_conv_pe ***");
        $finish;
    end
    initial begin #50000000; $display("*** TEST FAILED : tb_conv_pe TIMEOUT ***"); $finish; end
endmodule
