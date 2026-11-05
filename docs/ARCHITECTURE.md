# Architecture

## 1. Model

| Stage | Op | Output shape | Notes |
|---|---|---|---|
| input | grayscale crop, `uint8` | 1×24×24 | 576 px, no normalisation in RTL (scale 1/255 is folded into the quantised bias) |
| conv1 | 4 filters 3×3, `int8` weights, `int32` bias, valid | 4×22×22 | accumulate in 32 bit |
| act1 | `clip(acc >>> 10, 0, 127)` | 4×22×22 | ReLU + requantise (shift **S1 = 10**) |
| pool1 | 2×2 max | 4×11×11 | |
| conv2 | 8 filters 3×3×4 | 8×9×9 | |
| act2 | `clip(acc >>> 6, 0, 127)` | 8×9×9 | shift **S2 = 6** |
| pool2 | 2×2 max, floor | 8×4×4 | last row/col dropped (9 → 4) |
| fc | 128 → 2, `int8` weights | 2 logits (`int32`) | flatten order `ch*16 + row*4 + col` |
| decision | `logit1 > logit0` → **open (1)**, else **closed (0)** | | ties → closed |

Classes (from `ml/data.yaml`): `0 = eye_closed`, `1 = eye_open`.
Float model: `ml/train.py` (Conv 1→4, Conv 4→8, FC 128→2; Adam 5e-3, 80 epochs, random horizontal flip).
Quantisation: `ml/quantize_export.py` — per-tensor symmetric int8 weights; shifts S1/S2 chosen so the 99.9th percentile of positive accumulators fits in 7 bits; the Python integer model there is the *golden model* the RTL must match bit-exactly.

## 2. ROM / memory contents (`ml/export/`)

| File | Content | Layout |
|---|---|---|
| `conv1_w.mem` / `conv1_b.mem` | 36 × int8 / 4 × int32 | `[filter][row][col]` |
| `conv2_w.mem` / `conv2_b.mem` | 288 × int8 / 8 × int32 | `[f2][f1][row][col]` |
| `fc_w.mem` / `fc_b.mem` | 256 × int8 / 2 × int32 | `[class][ch*16+row*4+col]` |
| `images.mem` | 16 test images × 1024 bytes (576 used, rest `00`) | selected by `SW[3:0] × 1024` |
| `expected_a1.mem`, `expected_a2.mem` | golden intermediate maps for the 16 images (4×11×11, 8×4×4) | used by unit tests |
| `expected.txt` | golden label / prediction / both logits for the 16 images | used by `run_sim.sh` |
| `params.txt` | `S1=10`, `S2=6` | |

The 16 demo images are chosen by `quantize_export.py`: the first two are the model's misclassified test images (so **demo images 0 and 1 are expected to be wrong**), the remaining 14 alternate closed/open.

## 3. Active 150 MHz system (5 Nov)

integration/rtl/drowsiness_top.v defaults to CLK_MHZ=150 and selects
rtl/cnn150/cnn_top_150.v. MMCM multiplies the board 100 MHz clock by 9
and divides by 6. The integrated build explicitly sets UART_BAUD=1000000;
the bare module parameter still defaults to 115200, so do not omit the build
generics when creating a custom project. [Active interface](../integration/docs/INTERFACE.md).

The default hardware has 48 conv1, 64 conv2 and 8 FC MAC operations in
parallel, mapped to 80 DSP plus LUT multipliers. Image RAM has eight copies;
activation/weight banks supply parallel reads. Loading overlaps conv1 and
conv1 overlaps conv2, with source thresholds LOAD_AHEAD=224 and
L2_AHEAD_WR=66. The cnn150 path adds RAM-read/MAC/address/pooling pipeline
registers for the shorter clock period. Arithmetic, tensor order and golden
logits remain unchanged; additional parallelism changes memory interfaces.

The default integrated system counter measures 712 cycles, 4.7466667 us.
The separate new 100 MHz rtl/cnn_top.v takes about 702 cycles, 7.02 us.
The former 4 Nov 14-DSP design took 7996 cycles/79.96 us; it is historical.

Current independent routed build at 97f91ae: 9,249 LUT, 8,390 FF, 18.5 BRAM,
80 DSP; setup +0.158 ns / hold +0.015 ns. [Raw evidence](reports/build_150mhz_20261105/README.md).
These values apply to this exact top/build; old 3/14-DSP reports remain archives.

## 4. Boundaries and verification

Host MediaPipe performs localization, then Reyn eye+brow crop, Y +0.10,
grayscale/INTER_AREA 24x24 and contrast 60..235. Default norm none leaves
those bytes intact; optional norm train adds per-crop training-statistic
matching. UART carries 576 bytes with CRC; synchronous staging supplies one
pixel per requested address. Internal cnn150 RAM reads have two register
stages, while the external pixel memory contract remains one clock.

Core ports: clk, asynchronous active-high rst, start, img_base_addr[13:0],
external_image, external_addr[9:0], external_data[7:0], done, prediction and
signed 32-bit logit0/1. EXTERNAL_INPUT enables upload support. Completion is
a pulse; prediction=1 means OPEN. System eye_state=1 means CLOSED.

ROM control, temporal counters, LEDs/display and buzzer are in integration/.
Root basys3_wrapper is a separate 100 MHz demonstration with different buttons;
use the integrated top for current UART/webcam tests. Recorder EAR status is
a host heuristic and never replaces the FPGA CNN/temporal result.

Core golden, 83 random/boundary external frames and a shortened-idle board-top
sequence passed review. Three old standalone layer harnesses have outdated
ports/bank wiring and fail; no full-suite PASS is claimed. [Current status](STATUS_AND_ISSUES.md).
Original buggy RTL and previous reports stay in legacy/archive directories.
