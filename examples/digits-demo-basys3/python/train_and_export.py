#!/usr/bin/env python3
"""
Offline training + fixed-point golden model + Verilog ROM generator.

Network : 8x8 gray (4-bit) -> Conv3x3 x4 (valid) -> ReLU -> MaxPool2x2 -> FC 36->10 -> argmax
Dataset : scikit-learn 'digits' (8x8 MNIST-like, ships inside scikit-learn, no download)
Outputs : ../rtl/rom_*.v, ../rtl/cnn_params.vh, ../sim/golden_rom.v, golden_report.txt

Run:  python3 train_and_export.py
"""
import numpy as np, os
from numpy.lib.stride_tricks import sliding_window_view as swv
from sklearn.datasets import load_digits

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "rtl")
SIM = os.path.join(HERE, "..", "sim")
N_DEMO = 16                      # images selectable with SW[3:0]
rng = np.random.default_rng(1)

# ------------------------------------------------------------------ data
d = load_digits()
X_all = np.clip(np.rint(d.images * 15.0 / 16.0), 0, 15).astype(np.int64)   # uint4 pixels 0..15
y_all = d.target.astype(np.int64)
perm = rng.permutation(len(y_all))
n_tr = int(0.7 * len(perm))
tr, te = perm[:n_tr], perm[n_tr:]
Xtr, ytr, Xte, yte = X_all[tr], y_all[tr], X_all[te], y_all[te]


# ------------------------------------------------------------------ float model
def forward(Xi, Wc, bc, Wf, bf, keep=False):
    x = Xi / 15.0
    p = swv(x, (3, 3), axis=(1, 2))                       # N,6,6,3,3
    c = np.einsum('nyxij,fij->nfyx', p, Wc) + bc[None, :, None, None]
    r = np.maximum(c, 0)
    q = r.reshape(-1, 4, 3, 2, 3, 2)                      # N,f,py,dy,px,dx
    pool = q.max(axis=(3, 5))                             # N,4,3,3
    feat = pool.reshape(len(Xi), 36)
    logit = feat @ Wf.T + bf
    return (logit, feat, p, c, r, q, pool) if keep else logit


Wc = rng.normal(0, 0.4, (4, 3, 3)); bc = np.zeros(4)
Wf = rng.normal(0, 0.2, (10, 36)); bf = np.zeros(10)
params = [Wc, bc, Wf, bf]
m = [np.zeros_like(p) for p in params]
v = [np.zeros_like(p) for p in params]
lr, B, EPOCHS, t = 0.01, 64, 300, 0
for ep in range(EPOCHS):
    idx = rng.permutation(len(ytr))
    for s_ in range(0, len(idx), B):
        b = idx[s_:s_ + B]; n = len(b)
        logit, feat, p, c, r, q, pool = forward(Xtr[b], *params, keep=True)
        e = np.exp(logit - logit.max(1, keepdims=True)); sm = e / e.sum(1, keepdims=True)
        dl = sm.copy(); dl[np.arange(n), ytr[b]] -= 1; dl /= n
        gWf = dl.T @ feat; gbf = dl.sum(0)
        dfeat = (dl @ params[2]).reshape(n, 4, 3, 3)
        mask = (q == pool[:, :, :, None, :, None]) & (q > 0)
        mask = mask / np.maximum(mask.sum(axis=(3, 5), keepdims=True), 1)
        dr = (mask * dfeat[:, :, :, None, :, None]).reshape(n, 4, 6, 6)
        dc = dr * (c > 0)
        gWc = np.einsum('nfyx,nyxij->fij', dc, p); gbc = dc.sum(axis=(0, 2, 3))
        grads = [gWc, gbc, gWf + 1e-4 * params[2], gbf]
        t += 1
        for i, g in enumerate(grads):
            m[i] = 0.9 * m[i] + 0.1 * g
            v[i] = 0.999 * v[i] + 0.001 * g * g
            params[i] -= lr * (m[i] / (1 - 0.9 ** t)) / (np.sqrt(v[i] / (1 - 0.999 ** t)) + 1e-8)
    if ep % 50 == 0 or ep == EPOCHS - 1:
        acc = (forward(Xte, *params).argmax(1) == yte).mean()
        print(f"epoch {ep:3d}  float test acc {acc * 100:.2f}%")
Wc, bc, Wf, bf = params
float_acc = (forward(Xte, *params).argmax(1) == yte).mean()

# ------------------------------------------------------------------ quantisation
# pixel p_int in 0..15 (p_float = p_int/15)
Sw1 = 127.0 / np.abs(Wc).max()
Wc_q = np.clip(np.rint(Wc * Sw1), -128, 127).astype(np.int64)            # int8
bc_q = np.rint(bc * Sw1 * 15.0).astype(np.int64)                          # int18 (acc scale)


def conv_acc(img, Wq, bq):            # returns 4x6x6 int accumulators
    out = np.zeros((4, 6, 6), dtype=np.int64)
    for f in range(4):
        for y in range(6):
            for x in range(6):
                out[f, y, x] = bq[f] + (Wq[f] * img[y:y + 3, x:x + 3]).sum()
    return out


# choose requant shift S1 from training data so that ~99.9 % of activations fit in 0..127
acts = np.concatenate([np.maximum(conv_acc(im, Wc_q, bc_q), 0).ravel() for im in Xtr[:400]])
need = np.percentile(acts, 99.9) / 127.0
S1 = max(1, int(np.ceil(np.log2(max(need, 1.0)))))
Sa = Sw1 * 15.0 / (2 ** S1)                                               # feature int per float unit


def features_int(img):
    a = conv_acc(img, Wc_q, bc_q)
    feat = np.zeros(36, dtype=np.int64)
    for f in range(4):
        for py in range(3):
            for px in range(3):
                mx = max(0, a[f, 2 * py:2 * py + 2, 2 * px:2 * px + 2].max())   # ReLU(max) == max(ReLU)
                v_ = (mx + (1 << (S1 - 1))) >> S1                                # round
                feat[f * 9 + py * 3 + px] = min(v_, 127)                         # saturate uint7
    return feat


feat_tr = np.array([features_int(im) for im in Xtr])
fmax = feat_tr.max()
Sw2 = 127.0 / np.abs(Wf).max()
Wf_q = np.clip(np.rint(Wf * Sw2), -128, 127).astype(np.int64)             # int8
bf_q = np.rint(bf * Sw2 * Sa).astype(np.int64)                            # int24


def infer_int(img):
    feat = features_int(img)
    logits = bf_q + Wf_q @ feat                                           # 10 x int24
    return int(np.argmax(logits)), logits, feat                           # first max wins ties


# ------------------------------------------------------------------ bit-width checks (hardware widths)
ACC_C_BITS, ACC_F_BITS = 18, 24
mx_c = max(np.abs(conv_acc(im, Wc_q, bc_q)).max() for im in X_all)
mx_f = max(np.abs(bf_q + Wf_q @ features_int(im)).max() for im in X_all)
assert mx_c < 2 ** (ACC_C_BITS - 1), f"conv acc overflow {mx_c}"
assert mx_f < 2 ** (ACC_F_BITS - 1), f"fc acc overflow {mx_f}"
assert np.abs(bc_q).max() < 2 ** (ACC_C_BITS - 1) and np.abs(bf_q).max() < 2 ** (ACC_F_BITS - 1)

preds = np.array([infer_int(im)[0] for im in Xte])
int_acc = (preds == yte).mean()
agree = (preds == forward(Xte, *params).argmax(1)).mean()

# ------------------------------------------------------------------ demo image selection
demo = []
for dgt in range(10):                       # first occurrence of every digit in the test set
    demo.append(int(np.where(yte == dgt)[0][0]))
for i in range(len(yte)):                   # fill remaining slots
    if len(demo) == N_DEMO:
        break
    if i not in demo:
        demo.append(i)
demo_img = Xte[demo]; demo_lbl = yte[demo]
demo_res = [infer_int(im) for im in demo_img]


# ------------------------------------------------------------------ Verilog generation
def lit(v_, bits, signed):
    v_ = int(v_)
    if signed:
        return f"{bits}'sd{v_}" if v_ >= 0 else f"-{bits}'sd{-v_}"
    return f"{bits}'d{v_}"


def rom(name, vals, width, signed, abits, comment, sync):
    sg = "signed " if signed else ""
    if sync:
        hdr = f"module {name} (input clk, input [{abits - 1}:0] addr, output reg {sg}[{width - 1}:0] dout);"
        tail = "    always @(posedge clk) dout <= mem[addr];"
    else:
        hdr = f"module {name} (input [{abits - 1}:0] addr, output {sg}[{width - 1}:0] dout);"
        tail = "    assign dout = mem[addr];"
    L = [f"// {comment}", "// AUTO-GENERATED by python/train_and_export.py - do not edit", hdr,
         f"    reg {sg}[{width - 1}:0] mem [0:{len(vals) - 1}];", "    initial begin"]
    for i, vv in enumerate(vals):
        L.append(f"        mem[{i}] = {lit(vv, width, signed)};")
    L += ["    end", tail, "endmodule", ""]
    return "\n".join(L)


def w(fn, txt):
    with open(os.path.join(RTL, fn), "w") as f:
        f.write(txt)


w("rom_conv_w.v", rom("rom_conv_w", Wc_q.reshape(-1), 8, True, 6, "Conv weights int8, index = f*9 + ky*3 + kx", True))
w("rom_conv_b.v", rom("rom_conv_b", bc_q, 18, True, 2, "Conv bias int18 (accumulator scale), index = f", False))
w("rom_fc_w.v", rom("rom_fc_w", Wf_q.reshape(-1), 8, True, 9, "FC weights int8, index = class*36 + feature", True))
w("rom_fc_b.v", rom("rom_fc_b", bf_q, 24, True, 4, "FC bias int24 (logit scale), index = class (0..9)", False))
w("rom_img.v", rom("rom_img", demo_img.reshape(-1), 4, False, 10,
                   f"{N_DEMO} demo test images, uint4 pixels, index = img*64 + row*8 + col", True))
w("rom_label.v", rom("rom_label", demo_lbl, 4, False, 4, "Ground-truth digit of each demo image", False))
w("cnn_params.vh", f"// AUTO-GENERATED\n`define CNN_S1 {S1}   // conv requantisation right-shift\n")

G = ["// AUTO-GENERATED golden vectors from the Python integer model (simulation only)",
     "module golden_rom (input [3:0] idx, output reg [3:0] pred, output reg [3:0] label,",
     "                   output reg [239:0] logits);   // logits[24*c +: 24] = signed logit of class c",
     "    always @* begin", "        case (idx)"]
for i, (p_, lg, ft) in enumerate(demo_res):
    packed = 0
    for c in range(10):
        packed |= (int(lg[c]) & 0xFFFFFF) << (24 * c)
    G.append(f"            4'd{i}: begin pred = 4'd{p_}; label = 4'd{int(demo_lbl[i])}; logits = 240'h{packed:060x}; end")
G += ["            default: begin pred = 4'd0; label = 4'd0; logits = 240'd0; end", "        endcase", "    end",
      "endmodule", ""]
with open(os.path.join(SIM, "golden_rom.v"), "w") as f:
    f.write("\n".join(G))

# ------------------------------------------------------------------ report
rep = f"""CNN golden-model report
=======================
Dataset            : sklearn digits 8x8 ({len(Xtr)} train / {len(Xte)} test), pixels quantised to uint4
Network            : Conv3x3x4 (valid) -> ReLU -> MaxPool2x2 -> FC 36x10 -> argmax
Tensor layouts     : image[row*8+col] uint4 | conv_w[f*9+ky*3+kx] int8 | feature[f*9+py*3+px] uint7
                     fc_w[class*36+feature] int8
Fixed point        : conv acc int18 (max |acc| seen {mx_c}), requant: (relu(max4)+2^(S1-1))>>S1, sat 127, S1={S1}
                     fc acc int24 (max |logit| seen {mx_f}), no final scaling, argmax (lowest index wins ties)
Scales             : Sw1={Sw1:.3f}  Sa={Sa:.3f}  Sw2={Sw2:.3f}   max feature value (train)={fmax}
Float test acc     : {float_acc * 100:.2f} %
Int8 golden acc    : {int_acc * 100:.2f} %   ({int(round(int_acc * len(yte)))}/{len(yte)})
Float/int agreement: {agree * 100:.2f} %

Demo images (SW[3:0] -> label / golden pred):
""" + "\n".join(
    f"  SW={i:2d}  label={int(demo_lbl[i])}  pred={demo_res[i][0]}  {'OK' if demo_res[i][0] == demo_lbl[i] else 'MISS'}"
    for i in range(N_DEMO)) + "\n"
with open(os.path.join(HERE, "golden_report.txt"), "w") as f:
    f.write(rep)
print(rep)
