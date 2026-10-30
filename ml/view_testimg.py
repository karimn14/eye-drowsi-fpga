import numpy as np
import matplotlib.pyplot as plt

# 1. Read hex values from images.mem
with open("export/images.mem", "r") as f:
    hex_data = [line.strip() for line in f if line.strip()]

# 2. Convert hex bytes to uint8 array
raw_bytes = np.array([int(val, 16) for val in hex_data], dtype=np.uint8)

# 3. Plot all 16 images (each image is 24x24 pixels out of 1024 padded bytes)
fig, axes = plt.subplots(4, 4, figsize=(9, 9))
fig.suptitle("Basys 3 FPGA Test Images (Index 0 to 15)", fontsize=14, fontweight="bold")

for i in range(16):
    # Extract active 24x24 pixel window (576 bytes)
    img_data = raw_bytes[i * 1024 : i * 1024 + 576].reshape(24, 24)
    
    ax = axes[i // 4, i % 4]
    ax.imshow(img_data, cmap="gray", vmin=0, vmax=255)
    ax.set_title(f"Index {i}\nsw[3:0] = {i:04b}", fontsize=9)
    ax.axis("off")

plt.tight_layout()
plt.show()