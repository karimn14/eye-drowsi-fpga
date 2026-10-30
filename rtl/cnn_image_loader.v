`timescale 1ns / 1ps

// Behavioral image loader. The image ROM is intentionally kept behind a
// small layer interface so cnn_top does not contain ROM addressing logic.
module cnn_image_loader (
    input             clk,
    input             rst,
    input             start,
    input      [13:0] base_addr,
    output reg [4607:0] image_flat,
    output reg        done
);
    reg [7:0] images [0:16383];
    integer i;

    initial $readmemh("images.mem", images);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            image_flat <= 0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (i = 0; i < 576; i = i + 1)
                    image_flat[i*8 +: 8] = images[base_addr + i];
                done <= 1'b1;
            end
        end
    end
endmodule
