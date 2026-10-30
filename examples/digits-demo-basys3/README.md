# Lightweight CNN Inference on Basys3 (8×8 digits → Conv3×3 → ReLU → MaxPool → FC → argmax)

## Pipeline
1. `python/train_and_export.py` trains offline (NumPy, scikit-learn *digits* 8×8 dataset – MNIST-like, bundled, no download),
   quantises to int8, runs the **bit-exact integer golden model**, and **generates** `rtl/rom_*.v`, `rtl/cnn_params.vh`, `sim/golden_rom.v`, `python/golden_report.txt`.
   (`pip install numpy scikit-learn`, then `python3 train_and_export.py`. Generated files are already included.)
2. RTL: `cnn_core.v` (time-multiplexed MAC FSM) + `cnn_top.v` (switches/LED/7-seg).

## Files
`rtl/cnn_top.v` (**top**), `cnn_core.v`, `seven_seg_driver.v`, `btn_debounce.v`, generated `rom_conv_w/b.v`, `rom_fc_w/b.v`, `rom_img.v`, `rom_label.v`, `cnn_params.vh`;
`sim/tb_cnn_core.v` (bit-exact vs golden, all 16 images), `sim/tb_cnn_top.v`, `sim/golden_rom.v`; `constraints/basys3_cnn.xdc`.

## Vivado
*Tools → Run Tcl Script → `create_project.tcl`* (sets part xc7a35tcpg236-1, include dir for `cnn_params.vh`, sim sources).
Manual: add `rtl/*.v`, `rtl/cnn_params.vh` (type *Verilog Header*, add `rtl` to include directories), the XDC, and for simulation `sim/*.v`.
Simulation top: `tb_cnn_core` (prints `*** TEST PASSED ***`); then `tb_cnn_top`.

## Board use
- **SW[3:0]** select one of 16 stored test images (no raw pixel entry), **btnC** = run inference, **btnU** = reset.
- 7-seg (SW15 = 0): leftmost digit = true label, rightmost = predicted digit (decimal point lights on a match).
- SW15 = 1: inference latency in clock cycles (hex). Expect ~0xE48 (3656) + a few cycles of start/done overhead ≈ 36.6 µs @100 MHz.
- LEDs: LED[9:0] one-hot prediction, LED13 match, LED14 valid, LED15 busy.

## Design summary (details in `python/golden_report.txt`)
| Item | Value |
|---|---|
| Input | 8×8, uint4 (0–15) |
| Conv | 4 filters 3×3, int8 weights, int18 accumulator, valid padding → 4×6×6 |
| Activation / pool | ReLU + 2×2 max pool → 4×3×3 = 36 features |
| Requantisation | `min(127, (x + 2^(S1-1)) >> S1)`, S1 = 6, uint7 features |
| FC | 36→10, int8 weights, int24 logits, argmax (lowest index wins ties) |
| Accuracy (540 test images) | float 97.78 %, int8 golden 97.96 % |
| Latency | 3656 cycles (2 cycles per MAC: ROM read + accumulate) |

Resource/Fmax numbers are **not** claimed here: take them from your Vivado utilisation and timing reports
(expect a handful of DSP48E1, ≤ a few BRAM/LUT-ROM, <1 % of the device).

## Verification status
- Python integer golden model: run, 97.96 % accuracy.
- A cycle-by-cycle Python transliteration of `cnn_core`'s FSM (same address formulas and loop order, reading the generated ROM files) reproduces all 16 golden logit vectors bit-exactly and the 3656-cycle count.
- The Verilog itself has **not** been compiled or simulated by me (no Vivado/simulator available). Run `tb_cnn_core` first.

## Report notes
Digit recognition is a computational proof-of-concept of the vision accelerator, not an ADAS function. Fallback demo if hardware integration fails: the simulation waveform of `tb_cnn_core` plus the board test of the 7-segment/switch front end.
