`timescale 1ns / 1ps
// Synchroniser + debouncer + rising-edge one-shot pulse for a push button.
module btn_debounce #(
    parameter DEBOUNCE_CYCLES = 1_000_000          // 10 ms @ 100 MHz
)(
    input  clk,
    input  btn_in,
    output pulse                                    // 1 clk wide on a debounced press
);
    reg s1 = 1'b0, s2 = 1'b0, stable = 1'b0, prev = 1'b0;
    reg [31:0] cnt = 32'd0;

    always @(posedge clk) begin
        s1 <= btn_in;
        s2 <= s1;
        if (s2 != stable) begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                stable <= s2;
                cnt    <= 32'd0;
            end else cnt <= cnt + 32'd1;
        end else cnt <= 32'd0;
        prev <= stable;
    end
    assign pulse = stable & ~prev;
endmodule
