# Current status and known issues

Reviewed 2026-11-05 against team main `97f91ae` (150 MHz integration PR #15),
with the operator-approved host default changed back to --norm none.
This page is the current index. [STUDY_PROGRESS.md](STUDY_PROGRESS.md) is a
dated journal; pending/uncommitted statements describe their original sessions.
The [previous status snapshot](archive/STATUS_20261103.md) remains historical.

## Implemented

- Basys 3 integer CNN: 24x24 grayscale, Conv 1->4, Conv 4->8, FC 128->2;
  int8 weights, signed int32 logits, S1=10/S2=6. Banked/overlapped datapath with 48/64/8 MAC operations in parallel;
  default implementation uses 80 DSP with additional LUT multipliers.
  Inference: **712 cycles = 4.75 us at 150 MHz** (5 Nov `cnn150` core; 100 MHz core 702 cycles = 7.02 us).
- ROM slots, board sequence controls, observation-count drowsiness FSM,
  LED/display and JA1 buzzer.
- 1 Mbaud 8N1 UART (115200 before 5 Nov) telemetry and CRC-checked 576-byte external image uploads.
- Host webcam preprocessing and persistent UART, integrated into Windows GUI.
  Live defaults: left eye, Reyn eye+brow, pad 0.15, contrast 60..235,
  vertical offset +0.10, target 10 Hz. MediaPipe/crop run on the laptop;
  CNN classification and warning decisions run on FPGA.
  Additional normalization defaults to --norm none following the operator's
  successful external-webcam retest; --norm train remains an explicit option.

## Evidence and scope

| Area | Evidence | Limit |
|---|---|---|
| CNN numerical behavior | Recorded RTL regressions match 16 exported logit pairs; two demo images are known model misses (14/16 labels correct) | Numerical agreement is not unseen-subject accuracy |
| UART faults/recovery | [CRC, timeout, reset and operator logs](../integration/docs/IMAGE_UPLOAD_VERIFICATION.md) | 3 Nov archive uses older 37,290-cycle core |
| Current implementation | [97f91ae independent build](reports/build_150mhz_20261105/README.md): setup +0.158 ns, hold +0.015 ns; 9,249 LUT / 8,390 FF / 18.5 BRAM / 80 DSP | Exact routed build; narrow positive margin, DRC warnings retained |
| Host and GUI | 34 host tests, Release GUI/mock smoke PASS; [review scope](reports/build_150mhz_20261105/README.md) | Mock test does not measure physical camera/board |
| Physical live | Operator reports new bitstream programmed and good classification with norm none; preceding norm train session has 375/375 golden matches | Golden agreement establishes arithmetic, not visual accuracy; no independent physical readback |
| Historical 4 Nov CPU comparison | [NumPy integer baseline](../integration/docs/INFERENCE_BENCHMARK.md): 152.8 us median vs 79.96 us FPGA, 1.911x | Specific CPU/backend/power configuration; prior FPGA telemetry |

The team repository is the implementation source of truth. The separate local
FPGA_Final_Project assignment workspace is learning material and historical
audits, not another deployed source tree.

## Verification regressions (open)

- sim/tb_conv1_layer.v fails compilation against changed ports; conv2/FC
  standalone harnesses produce unknown logits with outdated bank/lane wiring.
  The maintained portable runner still includes these three tests; its full
  run must not be called PASS. Dedicated cnn150 layer harnesses remain needed.
- Independent cnn150 stress (83 external boundary/random images, reset recovery)
  and top-level golden/temporal/scan checks passed; the latter shortened only
  long idle spacing for simulation. See the archived review for exact scope.
- The original idle-heavy full regression was intentionally stopped; real
  UART/upload testing on the new physical build remains a separate acceptance
  task. Older fault-test archives are not new 150 MHz measurements.
- Upstream removed .github/workflows/checks.yml. No automatic CI is currently
  configured; documentation/host/build checks must be run explicitly.

## Open limitations

1. Live client stops after frame ID 65535. Stop, reset btnU and restart with
   a new ID range; automatic rollover and diagnostic filename handling remain future work.
2. Temporal thresholds count observations, not measured closure time. Missing
   or late observations pause the host. Reset with UART idle before resuming;
   stopping the host does not clear a latched board alarm.
3. Accuracy 98.15% (108 test images) is from a small single-subject dataset,
   with possible neighbouring-frame leakage. Subject-disjoint evaluation and
   more people/lighting/pose/camera tests remain needed.
4. Slots 0/1 are known model misses. Confidence margin 1024 is uncalibrated;
   SW13 can hold the previous eye state. Keep it down for the live demo.
5. Standalone basys3_wrapper is separate from the tested integration top.
   Use integration/ for UART, webcam and buzzer demonstrations.
6. ML dependency versions and training seed were not frozen. Retraining is
   possible from committed crops but is not guaranteed to reproduce identical
   weights; raw Roboflow folders require a separate download.
7. Code license remains a team decision. Dataset attribution is separate:
   [ml/README.md](../ml/README.md).
8. No public release package/video is claimed here. Bitstreams stay outside
   Git; publish source-identified release assets deliberately.

## Start here

- [Setup and demo](GETTING_STARTED.md)
- [Architecture](ARCHITECTURE.md) and [active interface](../integration/docs/INTERFACE.md)
- [Evidence index](reports/README.md)
- [Repository and artifact policy](REPOSITORY_POLICY.md)
