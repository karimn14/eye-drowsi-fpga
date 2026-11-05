# Integration — drowsiness top level for Basys3

Board top level around the CNN core of this repo (`rtl/cnn_top.v` + `rtl/rom_weights.v`, used as is, not copied):
buttons/switches, the drowsiness state machine (PERCLOS window, DROWSY / MICROSLEEP alarms), 7-segment and LED
output, 150 MHz system clock from MMCM (optional 100 MHz direct/legacy 50 MHz), simulation and Vivado scripts.

```text
integration/
├── rtl/
│   ├── drowsiness_top.v    # FPGA top: 150 MHz (CLK_MHZ), input_control, drowsy_fsm, cnn_top, alert_control
│   ├── input_control.v     # btnU reset sync, btnC debounce + one-pulse, switch sync / debounce
│   ├── drowsy_fsm.v        # IDLE -> START_CNN -> WAIT_DONE -> UPDATE -> SHOW; drowsiness rules; sequence modes
│   ├── alert_control.v     # 7-segment OPEn / CLSd / tirE / SLEP / ---- / latency, LED patterns
│   ├── cnn_core_stub.v, image_rom.v, weight_bias_rom.v   # stub build (`USE_STUB`), golden logits
│   ├── cnn_control.v       # alternative 1-MAC/cycle sequencer (reference, verified, not used in the build)
│   └── model_params.vh     # generated: S1, S2, image count
├── sim/                    # Icarus testbenches + run.sh (tb_top_real = this top with the real cnn_top)
├── mem/seq.mem             # sequence-mode script (+ stub/test files)
├── scripts/                # gen_sim_data.py, drowsy_ref.py, add_sources.tcl, create_project.tcl, build.tcl
├── constraints/basys3.xdc  # pins for drowsiness_top
└── docs/                   # INTERFACE.md (contract), VIVADO_BOARD_GUIDE.md (step by step + board test)
```

## Quick start

```bash
bash integration/sim/run.sh                 # all testbenches (first run generates vectors from ml/export)
GEN=1 bash integration/sim/run.sh           # regenerate after a new ml/export
```

Expected: 14 testbenches selected by the current shell runner; `tb_top_real` (~3 min) checks all 16 images bit-exact against `ml/export/expected.txt`,
64 sequence frames against `scripts/drowsy_ref.py` and the scan mode.

Vivado (GUI): open/create a Basys3 project, then in the Tcl console
`source {<repo>/integration/scripts/add_sources.tcl}` → Generate Bitstream → program.
Batch: `cd integration && vivado -mode batch -source scripts/create_project.tcl && vivado -mode batch -source scripts/build.tcl`.
Full guide and board test table: [docs/VIVADO_BOARD_GUIDE.md](docs/VIVADO_BOARD_GUIDE.md); Vivado simulator (6 testbenches in
sim_1): [docs/VIVADO_SIM_GUIDE.md](docs/VIVADO_SIM_GUIDE.md).

## UART control and monitoring

SW9 selects board (down) or PC (up) control. UART sends results from every mode.
See [UART protocol and demo](docs/UART.md) and [executed verification](docs/UART_VERIFICATION.md).
Use `python integration/scripts/verify_uart.py` for the full working-tree simulation regression.
The real CNN also accepts new 24x24 eye crops over UART: see [image upload](docs/IMAGE_UPLOAD.md).
A buzzer on Pmod JA1 sounds the DROWSY / MICROSLEEP alarm: see [buzzer](docs/BUZZER.md).

## Board controls

| Control | Function |
|---|---|
| btnU | reset |
| btnC | run one inference (manual) / next frame (sequence step mode) |
| SW[3:0] | image slot 0–15 |
| SW9 | board control (0) / PC SLOT and RUN (1) |
| SW10 | sequence scan: slots 0, 1, …, 15 in order |
| SW11 | sequence step: btnC = next frame |
| SW12 | sequence slow: 1 frame per second |
| SW13 | low-confidence hold |
| SW14 | sequence mode (frames every 100 ms from `mem/seq.mem` + drowsiness rules) |
| SW15 | show latency in µs |

## Current results and verification limits

The default cnn150 core takes 712 system cycles = 4.7467 us at 150 MHz;
100 MHz new core takes 702 cycles = 7.02 us. Export remains S1=10/S2=6.
The independent 97f91ae UART/upload/buzzer build uses 9,249 LUT / 8,390 FF /
18.5 BRAM / 80 DSP, setup +0.158 ns and hold +0.015 ns. See
[build evidence](../docs/reports/build_150mhz_20261105/README.md).

The shell runner selects 14 tests, not proof that every maintained test
passes. The portable verify_uart.py runner additionally includes three
standalone layer harnesses that are stale/failing after the new bank/port
changes. [Current status](../docs/STATUS_AND_ISSUES.md) records this gap.

The canonical GUI setup is [setup and demo](../docs/GETTING_STARTED.md).
Use `vivado -mode batch -source integration/scripts/build_uart.tcl` from repo
root; defaults are 150 MHz and 1 Mbaud. CLI and FPGA baud must match.
