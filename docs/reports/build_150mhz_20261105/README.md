# Independent 150 MHz build/review — 2026-11-05

Source: team main 97f91aed0d2e197a827da8278ff548113e3726db (PR #15).
Build command: vivado -mode batch -source integration/scripts/build_uart.tcl
-tclargs <new-output-directory> 1000000 150. Tool: Vivado v2025.2 build 6299465.
Top drowsiness_top, part xc7a35tcpg236-1. Clock 100 MHz *9 /6 = 150 MHz.

- System CNN latency: 712 cycles /150 MHz = 4.7466667 us; telemetry us=4 truncates.
- Routed setup +0.158 ns, hold +0.015 ns; zero failing internal endpoints.
- 9,249 LUT / 8,390 FF / 18.5 BRAM / 80 of 90 DSP.
- DRC retains 20 RAMB18 async-control warnings and report-limit notice; no errors.
  External IO delay warnings remain; no unconstrained internal endpoints/clocks.
- Bitstream SHA256: e327981c67786954b8c9674487047f4af6e009505c32d620f8bb7980cb7d6e7c.
  Generated binary is not committed; build output is local build/review_150mhz_20261105/.

source_sha256.json fingerprints reviewed RTL/model/XDC/build-script files
(including unused reference RTL), not just the synthesis-selected sources.
The build used the unmodified isolated 97f91ae checkout. No programming or
physical measurement occurred during this review. The operator subsequently
reports programming this bitstream and obtaining good external-webcam results
with --norm none. No broader-subject accuracy claim follows from this report.

## Verification scope and known failures

- 34 Python host tests passed; GUI Release build/mock bridge smoke passed.
- core_stress.txt: 83 boundary/random external frames with stale RAM and
  reset-mid-execution recovery, exact integer logits PASS. Direct-core test
  counts 711 cycles due to its sampling boundary; system counter measures 712.
- integrated_scaled.txt: 16 slots, 64 temporal frames and 16 scan frames PASS;
  only the idle STEP interval was shortened from 80000 to 4000 cycles.
- UART PHY, command, formatting, 50/100/150 MHz conversion and 87-result stub
  system PASS in the focused run.
- focused_regression.json deliberately retains three FAIL records: old
  standalone conv1/conv2/FC harnesses do not match the new lane/bank interfaces.
  Full-core success does not make those harnesses pass. They remain open work.
- The original full regression was stopped during idle-heavy tb_top_real;
  this is NOT a full-suite PASS or a new physical real-UART fault campaign.

Original selected report/log bytes are retained; archive_manifest.json hashes
all original payloads. This README describes scope rather than modifying raw
results. The 4 Nov [100 MHz archive](../current_build_20261104/README.md) remains
historical and must not be mixed with these resource/timing values.
