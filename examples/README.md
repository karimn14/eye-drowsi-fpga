# examples/

`digits-demo-basys3/` is a **separate reference project** that was in the training folder (`Demo FPGA/cnn_basys3`): an 8×8 handwritten-digit CNN (Conv3×3×4 → ReLU → MaxPool → FC 36→10) for Basys 3, with its own RTL, Python generator, testbench and Vivado Tcl.
It is not part of the eye-drowsiness design; it is kept as a working example of a time-multiplexed CNN FSM with bit-exact verification.
Its own README says its author could not run a simulator; I ran `sim/tb_cnn_core.v` with Icarus Verilog (`iverilog -g2005 -I rtl rtl/cnn_core.v rtl/rom_*.v sim/golden_rom.v sim/tb_cnn_core.v`): 0/16 bit-exact mismatches, 15/16 correct, 3657 cycles latency. Vivado synthesis was not run.
