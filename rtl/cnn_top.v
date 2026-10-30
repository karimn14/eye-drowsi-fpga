`timescale 1ns / 1ps

module cnn_top (
    input clk,
    input rst,
    input start,
    input [13:0] img_base_addr,
    output reg done,
    output reg prediction,      // 0: Closed, 1: Open
    output reg signed [31:0] logit0,
    output reg signed [31:0] logit1
);

    // Internal Layer Memory Buffers
    reg [7:0] img_mem [0:575]; // 24x24 uint8 input image
    reg [7:0] a1_mem  [0:483]; // 4x11x11 pooled feature map 1
    reg [7:0] a2_mem  [0:127]; // 8x4x4 pooled feature map 2

    // ROM Signals
    wire [5:0]  c1_w_addr = f1 * 9 + kr1 * 3 + kc1;
    wire signed [7:0] c1_w_data;
    reg  [1:0]  c1_b_addr;
    wire signed [31:0] c1_b_data;

    wire [8:0]  c2_w_addr = f2 * 36 + ch1 * 9 + kr2 * 3 + kc2;
    wire signed [7:0] c2_w_data;
    reg  [2:0]  c2_b_addr;
    wire signed [31:0] c2_b_data;

    wire [7:0]  fc_w_addr = cls * 128 + fc_cnt;
    wire signed [7:0] fc_w_data;
    reg         fc_b_addr;
    wire signed [31:0] fc_b_data;

    reg  [13:0] rom_img_addr;
    wire [7:0]  rom_img_data;

    rom_weights rom_inst (
        .clk(clk),
        .conv1_w_addr(c1_w_addr), .conv1_w_data(c1_w_data),
        .conv1_b_addr(c1_b_addr), .conv1_b_data(c1_b_data),
        .conv2_w_addr(c2_w_addr), .conv2_w_data(c2_w_data),
        .conv2_b_addr(c2_b_addr), .conv2_b_data(c2_b_data),
        .fc_w_addr(fc_w_addr),    .fc_w_data(fc_w_data),
        .fc_b_addr(fc_b_addr),    .fc_b_data(fc_b_data),
        .img_addr(rom_img_addr),  .img_data(rom_img_data)
    );

    // FSM States
    localparam ST_IDLE        = 4'd0,
               ST_LOAD_REQ    = 4'd1,
               ST_LOAD_RD     = 4'd2,
               ST_C1_REQ      = 4'd3,
               ST_C1_ACC      = 4'd4,
               ST_C1_STORE    = 4'd5,
               ST_C2_REQ      = 4'd6,
               ST_C2_ACC      = 4'd7,
               ST_C2_STORE    = 4'd8,
               ST_FC_REQ      = 4'd9,
               ST_FC_ACC      = 4'd10,
               ST_DONE        = 4'd11;

    reg [3:0] state;

    reg [9:0] load_cnt;

    // Conv1 Counters
    reg [1:0] f1;          // 0..3
    reg [3:0] or1, oc1;    // 0..10
    reg       pr1, pc1;    // 0..1
    reg [1:0] kr1, kc1;    // 0..2
    reg signed [31:0] acc1;
    reg [7:0] pool1_max;

    // Conv2 Counters
    reg [2:0] f2;          // 0..7
    reg [1:0] or2, oc2;    // 0..3
    reg       pr2, pc2;    // 0..1
    reg [1:0] ch1;         // 0..3
    reg [1:0] kr2, kc2;    // 0..2
    reg signed [31:0] acc2;
    reg [7:0] pool2_max;

    // FC Counters
    reg       cls;         // 0..1
    reg [6:0] fc_cnt;      // 0..127
    reg signed [31:0] acc_fc;

    // Shift & Saturated ReLU Units
    wire signed [31:0] c1_shift = (acc1 + c1_b_data) >>> 10;
    wire [7:0] c1_act = (c1_shift < 32'sd0) ? 8'd0 : ((c1_shift > 32'sd127) ? 8'd127 : c1_shift[7:0]);

    wire signed [31:0] c2_shift = (acc2 + c2_b_data) >>> 7;
    wire [7:0] c2_act = (c2_shift < 32'sd0) ? 8'd0 : ((c2_shift > 32'sd127) ? 8'd127 : c2_shift[7:0]);

    // Index Logic
    wire [4:0] img_r = (or1 << 1) + pr1 + kr1;
    wire [4:0] img_c = (oc1 << 1) + pc1 + kc1;
    wire [9:0] img_idx = img_r * 24 + img_c;

    wire [3:0] a1_r = (or2 << 1) + pr2 + kr2;
    wire [3:0] a1_c = (oc2 << 1) + pc2 + kc2;
    wire [8:0] a1_idx = ch1 * 121 + a1_r * 11 + a1_c;

    wire [7:0] new_p1_max = (pr1 == 0 && pc1 == 0) ? c1_act : ((c1_act > pool1_max) ? c1_act : pool1_max);
    wire [7:0] new_p2_max = (pr2 == 0 && pc2 == 0 && ch1 == 0) ? c2_act : ((c2_act > pool2_max) ? c2_act : pool2_max);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            done <= 0;
            prediction <= 0;
            logit0 <= 0;
            logit1 <= 0;
            load_cnt <= 0;
            f1 <= 0; or1 <= 0; oc1 <= 0; pr1 <= 0; pc1 <= 0; kr1 <= 0; kc1 <= 0;
            f2 <= 0; or2 <= 0; oc2 <= 0; pr2 <= 0; pc2 <= 0; ch1 <= 0; kr2 <= 0; kc2 <= 0;
            cls <= 0; fc_cnt <= 0;
            acc1 <= 0; acc2 <= 0; acc_fc <= 0;
            pool1_max <= 0; pool2_max <= 0;
        end else begin
            case (state)

                ST_IDLE: begin
                    done <= 0;
                    if (start) begin
                        load_cnt <= 0;
                        rom_img_addr <= img_base_addr;
                        state <= ST_LOAD_REQ;
                    end
                end

                ST_LOAD_REQ: begin
                    state <= ST_LOAD_RD;
                end

                ST_LOAD_RD: begin
                    img_mem[load_cnt] <= rom_img_data;
                    if (load_cnt == 575) begin
                        f1 <= 0; or1 <= 0; oc1 <= 0; pr1 <= 0; pc1 <= 0; kr1 <= 0; kc1 <= 0;
                        acc1 <= 0; pool1_max <= 0;
                        c1_b_addr <= 0;
                        state <= ST_C1_REQ;
                    end else begin
                        load_cnt <= load_cnt + 1;
                        rom_img_addr <= img_base_addr + (load_cnt + 1);
                        state <= ST_LOAD_REQ;
                    end
                end

                ST_C1_REQ: begin
                    
                    c1_b_addr <= f1;
                    state <= ST_C1_ACC;
                end

                ST_C1_ACC: begin
                    acc1 <= acc1 + $signed({1'b0, img_mem[img_idx]}) * c1_w_data;

                    if (kc1 == 2) begin
                        kc1 <= 0;
                        if (kr1 == 2) begin
                            kr1 <= 0;
                            state <= ST_C1_STORE;
                        end else begin
                            kr1 <= kr1 + 1;
                            state <= ST_C1_REQ;
                        end
                    end else begin
                        kc1 <= kc1 + 1;
                        state <= ST_C1_REQ;
                    end
                end

                ST_C1_STORE: begin
                    pool1_max <= new_p1_max;
                    acc1 <= 0;

                    if (pc1 == 1) begin
                        pc1 <= 0;
                        if (pr1 == 1) begin
                            pr1 <= 0;
                            a1_mem[f1 * 121 + or1 * 11 + oc1] <= new_p1_max;
                            pool1_max <= 0;

                            if (oc1 == 10) begin
                                oc1 <= 0;
                                if (or1 == 10) begin
                                    or1 <= 0;
                                    if (f1 == 3) begin
                                        f1 <= 0;
                                        f2 <= 0; or2 <= 0; oc2 <= 0; pr2 <= 0; pc2 <= 0; ch1 <= 0; kr2 <= 0; kc2 <= 0;
                                        acc2 <= 0; pool2_max <= 0;
                                        state <= ST_C2_REQ;
                                    end else begin
                                        f1 <= f1 + 1;
                                        state <= ST_C1_REQ;
                                    end
                                end else begin
                                    or1 <= or1 + 1;
                                    state <= ST_C1_REQ;
                                end
                            end else begin
                                oc1 <= oc1 + 1;
                                state <= ST_C1_REQ;
                            end
                        end else begin
                            pr1 <= 1;
                            state <= ST_C1_REQ;
                        end
                    end else begin
                        pc1 <= 1;
                        state <= ST_C1_REQ;
                    end
                end

                ST_C2_REQ: begin
                    
                    c2_b_addr <= f2;
                    state <= ST_C2_ACC;
                end

                ST_C2_ACC: begin
                    acc2 <= acc2 + $signed({1'b0, a1_mem[a1_idx]}) * c2_w_data;

                    if (kc2 == 2) begin
                        kc2 <= 0;
                        if (kr2 == 2) begin
                            kr2 <= 0;
                            if (ch1 == 3) begin
                                ch1 <= 0;
                                state <= ST_C2_STORE;
                            end else begin
                                ch1 <= ch1 + 1;
                                state <= ST_C2_REQ;
                            end
                        end else begin
                            kr2 <= kr2 + 1;
                            state <= ST_C2_REQ;
                        end
                    end else begin
                        kc2 <= kc2 + 1;
                        state <= ST_C2_REQ;
                    end
                end

                ST_C2_STORE: begin
                    pool2_max <= new_p2_max;
                    acc2 <= 0;

                    if (pc2 == 1) begin
                        pc2 <= 0;
                        if (pr2 == 1) begin
                            pr2 <= 0;
                            a2_mem[f2 * 16 + or2 * 4 + oc2] <= new_p2_max;
                            pool2_max <= 0;

                            if (oc2 == 3) begin
                                oc2 <= 0;
                                if (or2 == 3) begin
                                    or2 <= 0;
                                    if (f2 == 7) begin
                                        f2 <= 0;
                                        cls <= 0; fc_cnt <= 0; acc_fc <= 0;
                                        fc_b_addr <= 0;
                                        state <= ST_FC_REQ;
                                    end else begin
                                        f2 <= f2 + 1;
                                        state <= ST_C2_REQ;
                                    end
                                end else begin
                                    or2 <= or2 + 1;
                                    state <= ST_C2_REQ;
                                end
                            end else begin
                                oc2 <= oc2 + 1;
                                state <= ST_C2_REQ;
                            end
                        end else begin
                            pr2 <= 1;
                            state <= ST_C2_REQ;
                        end
                    end else begin
                        pc2 <= 1;
                        state <= ST_C2_REQ;
                    end
                end

                ST_FC_REQ: begin
                    
                    fc_b_addr <= cls;
                    state <= ST_FC_ACC;
                end

                ST_FC_ACC: begin
                    acc_fc <= acc_fc + $signed({1'b0, a2_mem[fc_cnt]}) * fc_w_data;

                    if (fc_cnt == 127) begin
                        fc_cnt <= 0;
                        if (cls == 0) begin
                            logit0 <= acc_fc + $signed({1'b0, a2_mem[fc_cnt]}) * fc_w_data + fc_b_data;
                            acc_fc <= 0;
                            cls <= 1;
                            state <= ST_FC_REQ;
                        end else begin
                            logit1 <= acc_fc + $signed({1'b0, a2_mem[fc_cnt]}) * fc_w_data + fc_b_data;
                            state <= ST_DONE;
                        end
                    end else begin
                        fc_cnt <= fc_cnt + 1;
                        state <= ST_FC_REQ;
                    end
                end

                ST_DONE: begin
                    done <= 1;
                    prediction <= (logit1 > logit0) ? 1'b1 : 1'b0;
                    if (!start) state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule