"""
Generate unit-test vectors for conv_pe and relu_requant.
Run from the project root:  python3 python/gen_vectors.py
Output goes to mem/ (hex files read by the testbenches with $readmemh).

Step 0 re-derives a1/a2 from the repo's own .mem files and checks them against
expected_a1.mem / expected_a2.mem, so the golden model used here is proven to be
the same one the rest of the team uses.
"""
import numpy as np, os

MEM = "mem"
rng = np.random.default_rng(1234)

def rd(name, nbits, signed=True):
    v = np.array([int(x, 16) for x in open(f"{MEM}/{name}").read().split()], dtype=np.int64)
    if signed:
        v = np.where(v >= 1 << (nbits - 1), v - (1 << nbits), v)
    return v

def wr(name, arr, nbits):
    digits = nbits // 4
    with open(f"{MEM}/{name}", "w") as f:
        for v in arr:
            f.write(f"{int(v) & ((1 << nbits) - 1):0{digits}x}\n")

# ---------------------------------------------------------------- step 0: golden self-check
S = dict(l.strip().split("=") for l in open(f"{MEM}/params.txt") if "=" in l)
S1, S2 = int(S["S1"]), int(S["S2"])
w1 = rd("conv1_w.mem", 8).reshape(4, 1, 3, 3);  b1 = rd("conv1_b.mem", 32)
w2 = rd("conv2_w.mem", 8).reshape(8, 4, 3, 3);  b2 = rd("conv2_b.mem", 32)
img = rd("images.mem", 8, False).reshape(16, 1024)[:, :576].reshape(16, 24, 24)
ea1 = rd("expected_a1.mem", 8, False).reshape(16, 4, 11, 11)
ea2 = rd("expected_a2.mem", 8, False).reshape(16, 8, 4, 4)

def conv(x, w, b):
    F = w.shape[0]; H = x.shape[1] - 2
    o = np.zeros((F, H, H), dtype=np.int64)
    for f in range(F):
        for r in range(H):
            for c in range(H):
                o[f, r, c] = (x[:, r:r+3, c:c+3] * w[f]).sum() + b[f]
    return o
act  = lambda a, s: np.clip(a >> s, 0, 127)
def pool(x):
    C, H, W = x.shape
    return x[:, :H//2*2, :W//2*2].reshape(C, H//2, 2, W//2, 2).max(axis=(2, 4))

for n in range(16):
    a1 = pool(act(conv(img[n][None], w1, b1), S1))
    a2 = pool(act(conv(a1, w2, b2), S2))
    assert (a1 == ea1[n]).all() and (a2 == ea2[n]).all(), f"golden mismatch image {n}"
print(f"[0] golden self-check OK (S1={S1}, S2={S2}, 16 images match expected_a1/a2)")

# ---------------------------------------------------------------- relu_requant vectors
def relu_vectors(S, n_rand=4000):
    v = [0, 1, -1, 2**31 - 1, -2**31, (1 << S) - 1, 1 << S, -(1 << S), -(1 << S) - 1]
    for q in (0, 1, 2, 63, 126, 127, 128, 129, 255, 1000):          # around every clip boundary
        base = q << S
        v += [base - 1, base, base + 1, base + (1 << S) - 1, base + (1 << S)]
    v += [-x for x in v if x > 0]
    v += list(rng.integers(-(1 << 24), 1 << 24, n_rand // 2))        # realistic accumulator range
    v += list(rng.integers(-2**31, 2**31, n_rand // 2))              # full 32-bit range
    v = np.array(v, dtype=np.int64)
    v = np.clip(v, -2**31, 2**31 - 1)
    return v, np.clip(v >> S, 0, 127)

for s in (S1, S2):
    a, e = relu_vectors(s)
    wr(f"relu_s{s}_in.mem", a, 32); wr(f"relu_s{s}_exp.mem", e, 8)
    print(f"[1] relu S={s}: {len(a)} vectors, neg={int((a<0).sum())}, sat={int(((a>>s)>127).sum())}")

# ---------------------------------------------------------------- conv_pe vectors
def conv_vectors(nt, n=2000):
    pix = np.zeros((n, nt), dtype=np.int64); w = np.zeros((n, nt), dtype=np.int64); b = np.zeros(n, dtype=np.int64)
    k = 0
    def put(p, ww, bb):
        nonlocal k; pix[k] = p; w[k] = ww; b[k] = bb; k += 1
    put(0, 0, 0)                          # all zero
    put(0, rng.integers(-128, 128, nt), 12345)          # zero pixels -> bias only
    put(rng.integers(0, 256, nt), 0, -777)              # zero weights -> bias only
    put(255, 127, 0)                                    # max positive
    put(255, -128, 0)                                   # max negative
    put(255, -128, -2**20)                              # max negative + negative bias
    put(255, 127, 2**20)                                # max positive + positive bias
    for t in range(nt if nt <= 9 else 12):              # one-hot taps (walks tap order)
        p = np.zeros(nt, dtype=np.int64); ww = np.zeros(nt, dtype=np.int64)
        p[t] = 200; ww[t] = -3
        put(p, ww, 5)
    while k < n:
        put(rng.integers(0, 256, nt), rng.integers(-128, 128, nt), rng.integers(-2**20, 2**20))
    acc = (pix * w).sum(axis=1) + b
    assert np.abs(acc).max() < 2**31
    return pix, w, b, acc

def flat(a, nt):                                          # tap0 in the least-significant byte
    out = []
    for row in a:
        val = 0
        for t in range(nt):
            val |= (int(row[t]) & 0xFF) << (8 * t)
        out.append(f"{val:0{2*nt}x}\n")
    return out

for nt in (9, 36):
    pix, w, b, acc = conv_vectors(nt)
    open(f"{MEM}/conv{nt}_pix.mem", "w").writelines(flat(pix, nt))
    open(f"{MEM}/conv{nt}_w.mem",   "w").writelines(flat(w, nt))
    wr(f"conv{nt}_b.mem", b, 32); wr(f"conv{nt}_exp.mem", acc, 32)
    print(f"[2] conv_pe NTAPS={nt}: {len(acc)} vectors, acc range [{acc.min()}, {acc.max()}]")
