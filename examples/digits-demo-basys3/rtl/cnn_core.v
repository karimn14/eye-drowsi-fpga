`timescale 1ns / 1ps
`include "cnn_params.vh"
//==============================================================================
// cnn_core : 8x8 uint4 image -> Conv3x3(x4) -> ReLU -> MaxPool2x2 -> FC(36x10) -> argmax
//
// One shared time-multiplexed MAC (1 DSP48 each for conv and FC datapath).
// Every MAC takes 2 clock cycles: FETCH (ROM synchronous read) + ACC (multiply-accumulate).
//
// Arithmetic (must match python/train_and_export.py bit-exactly):
//   conv acc   : int18  = bias + sum(w_int8 * pix_uint4)
//   pooled     : max over the 2x2 window of conv acc, started from 0  (== ReLU then max-pool)
//   feature    : uint7  = min(127, (pooled + 2^(S1-1)) >> S1)
//   logit      : int24  = fc_bias + sum(fc_w_int8 * feature_uint7)
//   prediction : argmax(logit), lowest index wins ties
//
// Layouts : image index = row*8+col | conv_w = f*9+ky*3+kx | feature = f*9+py*3+px
//           fc_w = class*36 + feature
// Latency : 36*(4*20+1) + 10*74 + few  ~= 3.66k clock cycles
//==============================================================================
module cnn_core (
    input              clk,
    input              rst,          // synchronous, active high
    input              start,        // 1-cycle pulse, ignored while busy
    input      [3:0]   img_sel,      // which stored image (latched at start)
    output reg         busy,
    output reg         done,         // level, cleared by next start
    output     [3:0]   pred,
    output reg [15:0]  cycles,       // latency of last/ongoing inference in clock cycles
    output     [239:0] logits_flat   // logits_flat[24*c +: 24] (signed), for verification
);
    localparam [3:0] S_IDLE   = 4'd0,
                     S_C_INIT = 4'd1,
                     S_C_FETCH= 4'd2,
                     S_C_ACC  = 4'd3,
                     S_C_WEND = 4'd4,
                     S_C_STORE= 4'd5,
                     S_F_INIT = 4'd6,
                     S_F_FETCH= 4'd7,
                     S_F_ACC  = 4'd8,
                     S_F_END  = 4'd9,
                     S_DONE   = 4'd10;

    reg [3:0] state;

    // ---------------------------------------------------------------- loop counters
    reg [1:0] f, py, px, ky, kx;       // filter, pooled row/col, kernel row/col
    reg       dy, dx;                  // position inside the 2x2 pool window
    reg [3:0] c;                       // FC class
    reg [5:0] i;                       // FC feature index
    reg [8:0] fw_addr;                 // running FC weight address (class*36+i)
    reg [3:0] sel_q;

    // ---------------------------------------------------------------- datapath registers
    reg signed [17:0] acc_c;
    reg signed [17:0] maxv;
    reg signed [23:0] acc_f;
    reg signed [23:0] best_val;
    reg        [3:0]  best_idx;
    reg        [6:0]  feat [0:35];
    reg        [6:0]  feat_q;
    reg signed [23:0] logit [0:9];

    // ---------------------------------------------------------------- ROMs
    wire [2:0] row = {py, 1'b0} + dy + ky;            // 0..7
    wire [2:0] col = {px, 1'b0} + dx + kx;            // 0..7
    wire [5:0] w_addr_c = {f, 3'b000} + f + {ky, 1'b0} + ky + kx;   // f*9 + ky*3 + kx (0..35)

    wire        [3:0]  pix;
    wire signed [7:0]  w_c;
    wire signed [17:0] b_c;
    wire signed [7:0]  w_f;
    wire signed [23:0] b_f;

    rom_img    u_img (.clk(clk), .addr({sel_q, row, col}), .dout(pix));
    rom_conv_w u_cw  (.clk(clk), .addr(w_addr_c),          .dout(w_c));
    rom_conv_b u_cb  (.addr(f),                            .dout(b_c));
    rom_fc_w   u_fw  (.clk(clk), .addr(fw_addr),           .dout(w_f));
    rom_fc_b   u_fb  (.addr(c),                            .dout(b_f));

    always @(posedge clk) feat_q <= feat[i];          // synchronous feature read (6-bit i, i<=35 when used)

    // ---------------------------------------------------------------- MACs
    wire signed [17:0] prod_c = w_c * $signed({1'b0, pix});
    wire signed [23:0] prod_f = w_f * $signed({1'b0, feat_q});

    // requantisation of pooled value (maxv >= 0)
    wire        [18:0] rnd     = {1'b0, maxv} + (19'd1 << (`CNN_S1 - 1));
    wire        [18:0] shifted = rnd >> `CNN_S1;
    wire        [6:0]  feat_n  = (shifted > 19'd127) ? 7'd127 : shifted[6:0];
    wire        [5:0]  f_idx   = {f, 3'b000} + f + {py, 1'b0} + py + px;   // f*9 + py*3 + px

    assign pred = best_idx;

    genvar g;
    generate for (g = 0; g < 10; g = g + 1) begin : G_LOG
        assign logits_flat[24*g +: 24] = logit[g];
    end endgenerate

    // ---------------------------------------------------------------- FSM
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0; cycles <= 16'd0;
            f <= 0; py <= 0; px <= 0; ky <= 0; kx <= 0; dy <= 0; dx <= 0;
            c <= 0; i <= 0; fw_addr <= 0; sel_q <= 0;
            acc_c <= 0; maxv <= 0; acc_f <= 0; best_val <= 0; best_idx <= 0;
        end else begin
            if (busy) cycles <= cycles + 16'd1;

            case (state)
            //------------------------------------------------------------
            S_IDLE: if (start) begin
                sel_q <= img_sel;
                busy <= 1'b1; done <= 1'b0; cycles <= 16'd0;
                f <= 0; py <= 0; px <= 0; dy <= 0; dx <= 0; ky <= 0; kx <= 0;
                maxv <= 18'sd0;
                best_val <= 24'sh800000; best_idx <= 4'd0;
                state <= S_C_INIT;
            end
            //------------------------------------------------------------ convolution
            S_C_INIT: begin                       // start a new 3x3 window
                acc_c <= b_c;
                ky <= 0; kx <= 0;
                state <= S_C_FETCH;
            end
            S_C_FETCH: state <= S_C_ACC;          // ROM latency
            S_C_ACC: begin
                acc_c <= acc_c + prod_c;
                if (kx == 2'd2) begin
                    kx <= 0;
                    if (ky == 2'd2) state <= S_C_WEND;
                    else begin ky <= ky + 2'd1; state <= S_C_FETCH; end
                end else begin
                    kx <= kx + 2'd1; state <= S_C_FETCH;
                end
            end
            S_C_WEND: begin                       // ReLU + max-pool (maxv starts at 0)
                if (acc_c > maxv) maxv <= acc_c;
                if (dx == 1'b0) begin
                    dx <= 1'b1; state <= S_C_INIT;
                end else begin
                    dx <= 1'b0;
                    if (dy == 1'b0) begin dy <= 1'b1; state <= S_C_INIT; end
                    else            begin dy <= 1'b0; state <= S_C_STORE; end
                end
            end
            S_C_STORE: begin                      // write pooled feature, advance
                feat[f_idx] <= feat_n;
                maxv <= 18'sd0;
                if (px == 2'd2) begin
                    px <= 0;
                    if (py == 2'd2) begin
                        py <= 0;
                        if (f == 2'd3) begin
                            f <= 0; c <= 0; i <= 0; fw_addr <= 0;
                            state <= S_F_INIT;
                        end else begin f <= f + 2'd1; state <= S_C_INIT; end
                    end else begin py <= py + 2'd1; state <= S_C_INIT; end
                end else begin px <= px + 2'd1; state <= S_C_INIT; end
            end
            //------------------------------------------------------------ fully connected
            S_F_INIT: begin
                acc_f <= b_f;
                i <= 0;
                state <= S_F_FETCH;
            end
            S_F_FETCH: state <= S_F_ACC;
            S_F_ACC: begin
                acc_f   <= acc_f + prod_f;
                fw_addr <= fw_addr + 9'd1;
                if (i == 6'd35) state <= S_F_END;
                else begin i <= i + 6'd1; state <= S_F_FETCH; end
            end
            S_F_END: begin
                logit[c] <= acc_f;
                if (acc_f > best_val) begin best_val <= acc_f; best_idx <= c; end
                if (c == 4'd9) state <= S_DONE;
                else begin c <= c + 4'd1; state <= S_F_INIT; end
            end
            //------------------------------------------------------------
            S_DONE: begin
                busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
