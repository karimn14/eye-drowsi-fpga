import numpy as np, torch, torch.nn as nn

tr, va, te = [np.load(f"{s}.npz") for s in ["train", "valid", "test"]]
def prep(d):
    return (torch.tensor(d["X"], dtype=torch.float32).unsqueeze(1) / 255.0,
            torch.tensor(d["y"]))
Xtr, ytr = prep(tr); Xva, yva = prep(va); Xte, yte = prep(te)
SIZE = Xtr.shape[-1]

class Net(nn.Module):
    def __init__(self, f1=4, f2=8):
        super().__init__()
        self.conv1 = nn.Conv2d(1, f1, 3)     # 24 -> 22
        self.conv2 = nn.Conv2d(f1, f2, 3)    # 11 -> 9
        self.pool = nn.MaxPool2d(2)          # 22 -> 11, 9 -> 4
        with torch.no_grad():
            n = self.features(torch.zeros(1, 1, SIZE, SIZE)).numel()
        self.fc = nn.Linear(n, 2)
        print("FC input size:", n)

    def features(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = self.pool(torch.relu(self.conv2(x)))
        return x

    def forward(self, x):
        return self.fc(self.features(x).flatten(1))

net = Net(f1=4, f2=8)
opt = torch.optim.Adam(net.parameters(), 5e-3)
lossf = nn.CrossEntropyLoss()

for ep in range(80):
    net.train()
    perm = torch.randperm(len(Xtr))
    for i in range(0, len(perm), 64):
        idx = perm[i:i+64]
        xb = Xtr[idx]
        flip = torch.rand(len(idx)) < 0.5
        xb[flip] = xb[flip].flip(-1)
        opt.zero_grad()
        lossf(net(xb), ytr[idx]).backward()
        opt.step()
    net.eval()
    with torch.no_grad():
        acc = (net(Xva).argmax(1) == yva).float().mean().item()
    if ep % 10 == 9:
        print(ep + 1, "val acc", round(acc, 3))

with torch.no_grad():
    print("test acc (float):", (net(Xte).argmax(1) == yte).float().mean().item())
torch.save(net.state_dict(), "net_float.pt")