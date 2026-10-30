import cv2, glob, os, numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SIZE = 24

def crop_split(split):
    X, y = [], []
    for p in glob.glob(os.path.join(ROOT, split, "images", "*")):
        lbl = os.path.join(ROOT, split, "labels",
                        os.path.splitext(os.path.basename(p))[0] + ".txt")
        if not os.path.exists(lbl):
            continue
        img = cv2.imread(p, cv2.IMREAD_GRAYSCALE)
        H, W = img.shape
        for line in open(lbl):
            c, xc, yc, w, h = line.split()[:5]
            xc, yc, w, h = float(xc)*W, float(yc)*H, float(w)*W, float(h)*H
            x1, x2 = int(max(xc-w/2, 0)), int(min(xc+w/2, W))
            y1, y2 = int(max(yc-h/2, 0)), int(min(yc+h/2, H))
            crop = img[y1:y2, x1:x2]
            if crop.size == 0:
                continue
            X.append(cv2.resize(crop, (SIZE, SIZE), interpolation=cv2.INTER_AREA))
            y.append(int(c))
    return np.array(X, np.uint8), np.array(y, np.int64)

for s in ["train", "valid", "test"]:
    X, y = crop_split(s)
    np.savez(f"{s}.npz", X=X, y=y)
    print(s, X.shape, np.bincount(y))