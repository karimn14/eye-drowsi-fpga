import numpy as np, cv2

d = np.load("train.npz")
X, y = d["X"], d["y"]
rows = []
for c in (0, 1):
    idx = np.where(y == c)[0][:16]
    rows.append(np.hstack([cv2.resize(X[i], (64, 64), interpolation=cv2.INTER_NEAREST) for i in idx]))
cv2.imwrite("grid.png", np.vstack(rows))