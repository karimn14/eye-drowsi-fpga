# Status and known issues

_State of the material handed over on 2026-10-30. "Verified" means I re-ran it for this repo; everything else is as reported in the original files._

## Verified (Icarus Verilog + numpy, `./run_sim.sh`)
- The sequential one-MAC implementation in `rtl/cnn_top.v` reproduces all
  **16/16** golden logit pairs of `ml/export/expected.txt` (14/16 correct
  classes; images 0 and 1 are the deliberately included model misses).
- Original `rtl/legacy/cnn_top_original_buggy.v` reproduces the failure in `docs/reports/xsim_simulate_ORIGINAL_buggy_rtl.log`.
- Unit tests of `conv_pe`, `relu_requant` and conv+ReLU+pool vs. `expected_a1/a2`: 0 errors.
- int8 accuracy re-computed from the exported weights: train 97.23 % (758), valid 94.44 % (216), test 98.15 % (108).
- `examples/digits-demo-basys3`: its `tb_cnn_core` passes under Icarus (0/16 bit mismatches, 15/16 correct).

## Not verified / open
1. **The restored one-MAC RTL has not been synthesised or implemented in the
   current project.** Re-run synthesis and implementation to confirm resource
   usage, timing, and memory inference.
2. **Historical timing:** the previous critical path was loop counters →
   `a1_idx` arithmetic → 484-entry `a1_mem` read mux → multiply/add → `acc2`
   (27 logic levels, 17.26 ns). The one-MAC organization reduces parallel
   arithmetic, but its timing still needs a fresh Vivado report.
3. **No evidence of an on-board test** in the provided files (bitstream was generated in the team's Vivado project, but no photo/log of the board running). The bitstream is not in this repo because it was built from the buggy RTL.
4. `vivado/create_project.tcl` has not been run in Vivado.
5. **Dataset / evaluation caveat.** All 756 train and 108 test label files come from the same subject (`s0001_*`) and their frame numbers interleave (train 4–3240, test 69–3221), so neighbouring near-identical frames likely sit on both sides of the split. The 98 % test figure therefore says little about unseen people; the validation set is 216 crops. A subject-wise split (or another dataset) is needed before claiming real-world accuracy. Also, the class counts in the `.npz` files differ slightly from the eye-state flag in the file names (e.g. train 328 open in npz vs 309 in file names) — worth a label check (my reading of the file-name convention is an assumption).
6. Raw dataset copy handed over was incomplete (train: 11 of 756 images present, valid: none), most likely a partial download. The crops (`ml/*.npz`) are complete, so training/export is reproducible; `prepare_data.py` is not without re-downloading the dataset.
7. Minor: comment in `basys3_wrapper.v` lists `W15` for `sw[3]`; the XDC (correct for Basys 3) uses `W17`. `ml/export/` and the Verilog sources use Windows (CRLF) line endings; `.gitattributes` normalises them.
8. The CNN classifies a stored 24×24 eye crop. Camera input, face/eye localisation and the "ADAS" decision logic (e.g. PERCLOS / eyes-closed duration) are outside this repo.

## Suggested next steps
1. Run synthesis and implementation for the one-MAC RTL, regenerate reports,
   build a bitstream, and record a board test (photo/video + which `SW` values
   give which result).
2. Redo the split by subject / use more subjects; report precision/recall for *closed* eyes (the safety-relevant class).
3. Optionally replace the sequential datapath by the unit-tested `conv_pe` + `relu_requant`.
4. Add a `LICENSE`, fill in the team roles, tag a release containing the bitstream.
