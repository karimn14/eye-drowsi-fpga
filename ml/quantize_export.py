import numpy as np, torch, os
from numpy.lib.stride_tricks import sliding_window_view as swv

os.makedirs("export", exist_ok=True)
sd = {k: v.numpy().astype(np.float64) for k, v in torch.load("net_float.pt").items()}
tr, va, te = [np.load(f"{s}.npz") for s in ["train", "valid", "test"]]
def imgs(d): return d["X"].astype(np.int64)[:, None]      # (N,1,24,24)
Xtr, Xva, Xte = imgs(tr), imgs(va), imgs(te)
ytr, yva, yte = tr["y"], va["y"], te["y"]

# ---------- integer building blocks (the RTL must match these) ----------
def conv(x, w, b):
    win = swv(x, (3, 3), axis=(2, 3))                      # (N,C,H-2,W-2,3,3)
    return np.einsum("nchwij,fcij->nfhw", win, w) + b[None, :, None, None]

def act(acc, s):                                           # ReLU + shift + saturate
    return np.clip(acc >> s, 0, 127)

def pool(x):                                               # 2x2 max, floor size
    N, C, H, W = x.shape; H2, W2 = H // 2, W // 2
    return x[:, :, :H2*2, :W2*2].reshape(N, C, H2, 2, W2, 2).max(axis=(3, 5))

def pick_shift(acc):                                       # smallest shift so 99.9th pct fits in 7 bits
    p = np.percentile(acc[acc > 0], 99.9)
    s = 0
    while (p / (1 << s)) > 127: s += 1
    return s

def qw(w):
    s = np.abs(w).max() / 127
    return np.round(w / s).astype(np.int64), s

# ---------- quantize weights, calibrate shifts on the training set ----------
sx0 = 1 / 255
w1, sw1 = qw(sd["conv1.weight"]); b1 = np.round(sd["conv1.bias"] / (sx0 * sw1)).astype(np.int64)
acc1 = conv(Xtr, w1, b1);  S1 = pick_shift(acc1)
sa1 = sx0 * sw1 * 2**S1

w2, sw2 = qw(sd["conv2.weight"]); b2 = np.round(sd["conv2.bias"] / (sa1 * sw2)).astype(np.int64)
a1p = pool(act(acc1, S1))
acc2 = conv(a1p, w2, b2);  S2 = pick_shift(acc2)
sa2 = sa1 * sw2 * 2**S2

wf, swf = qw(sd["fc.weight"]); bf = np.round(sd["fc.bias"] / (sa2 * swf)).astype(np.int64)
print("S1 =", S1, " S2 =", S2)

def forward(x):
    a1 = pool(act(conv(x, w1, b1), S1))
    a2 = pool(act(conv(a1, w2, b2), S2))
    logits = a2.reshape(len(x), -1) @ wf.T + bf            # flatten order: ch, row, col
    return a1, a2, logits

# ---------- accuracy + required bit widths ----------
for name, X, y in [("train", Xtr, ytr), ("valid", Xva, yva), ("test", Xte, yte)]:
    _, _, lg = forward(X)
    print(f"int8 {name} acc: {(lg.argmax(1) == y).mean():.4f}")

def bits(a): return int(np.ceil(np.log2(np.abs(a).max() + 1))) + 1
_, _, lg_tr = forward(Xtr)
print("signed bits needed -> acc1:", bits(acc1), " acc2:", bits(acc2), " logits:", bits(lg_tr))

# ---------- export ----------
def write_mem(path, arr, nbits):
    with open(path, "w") as f:
        for v in np.asarray(arr).flatten():
            f.write(f"{int(v) & ((1 << nbits) - 1):0{nbits // 4}x}\n")

write_mem("export/conv1_w.mem", w1, 8);  write_mem("export/conv1_b.mem", b1, 32)   # [f][r][c]
write_mem("export/conv2_w.mem", w2, 8);  write_mem("export/conv2_b.mem", b2, 32)   # [f2][f1][r][c]
write_mem("export/fc_w.mem", wf, 8);     write_mem("export/fc_b.mem", bf, 32)      # [class][ch*16+r*4+c]

# 16 test images: misclassified ones first (if any), then alternate closed/open
_, _, lg_te = forward(Xte)
wrong = list(np.where(lg_te.argmax(1) != yte)[0][:2])
pools = [[i for i in np.where(yte == c)[0] if i not in wrong] for c in (0, 1)]
idx = list(wrong); k = 0
while len(idx) < 16:
    idx.append(pools[k % 2].pop(0)); k += 1

with open("export/images.mem", "w") as f:                  # each image padded to 1024 words
    for i in idx:
        pix = Xte[i, 0].flatten()
        for v in pix: f.write(f"{int(v):02x}\n")
        for _ in range(1024 - len(pix)): f.write("00\n")

a1s, a2s, lgs = forward(Xte[idx])
write_mem("export/expected_a1.mem", a1s, 8)                # 4x11x11 per image
write_mem("export/expected_a2.mem", a2s, 8)                # 8x4x4 per image
with open("export/expected.txt", "w") as f:
    f.write("sw label pred logit0 logit1\n")
    for n, i in enumerate(idx):
        f.write(f"{n} {yte[i]} {lgs[n].argmax()} {lgs[n][0]} {lgs[n][1]}\n")
with open("export/params.txt", "w") as f:
    f.write(f"S1={S1}\nS2={S2}\n")
print("exported 16 images:", idx)