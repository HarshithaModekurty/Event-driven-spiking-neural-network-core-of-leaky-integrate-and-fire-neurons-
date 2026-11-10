# MNIST verification with the required 256-state core

The authoritative requirement is `Screenshot 2026-10-28 143938.png`.
The classifier now instantiates **256 actual LIF states**, a single shared
LIF transition datapath, and **256x256 signed four-bit synapse entries**.
The ten digit outputs are states inside that population, not extra neurons.

The earlier ten-state/267-source diagnostic did not meet this architecture.
Its generated evidence remains in `build/mnist_rtl/` as historical evidence;
it is not the current implementation or the current accuracy result.

## Exact address map

| State/source addresses | Classifier use |
|---|---|
| 0..224 | 225 features from a 15x15 downsampled image |
| 225 | Constant bias event |
| 226..245 | Reserved states, initialized and updated, with zero weights in this task |
| 246..255 | Output neurons for digits 0..9 |

All 256 membrane/refractory states are physically stored and visited during
every population step. Each neuron now has separate registered read,
calculation and write clocks; see `TIMING_CLOSURE.md`. The testbench verifies
that addresses 0..255 are visited exactly once, and compares every state's
membrane, refractory counter and spike bit against the 256-neuron Python
model after each tick. The pixel/bias/reserved states have no incoming
connections in this simple classifier, so their states remain zero. They
are not deleted from the RTL population. There is no hidden layer in this
baseline; the screenshot does not prescribe a classifier layer topology.

The full 65,536-entry matrix is programmed through the write port, including
all zero entries. For source s in 0..225 and digit d, the learned weight
is placed at matrix[s][246+d]. All other weights are zero for this task.
Recurrent ring/population regressions separately exercise active states
throughout the full population rather than relying only on this classifier.

## Shared training and image handling

`examples/mnist256_demo.py` defines the canonical 256-state mapping and Python
classifier. It reuses the existing MNIST loader, perceptron trainer and signed
four-bit quantizer, with the feature count passed through correctly.

To fit pixels, bias and outputs inside the required 256-address matrix, the
new model uses 15x15 features. Its weights were retrained on the first 12,000
official training images, for five epochs using seed 91. The default 20 test
indices are selected from the separate official test partition using seed 92.
The original 16x16 model's weights and 95% subset result are not reused or
claimed for this changed preprocessing. The earlier example file
`examples/mnist_live_demo.py` is retained as historical software code.

Pixel intensities are region-averaged and binarized at 80. Active pixels
have encoder intensity 255, inactive pixels 0, and bias intensity 255.
Thus active pixel/bias events repeat on each of eight ticks for an image.
Python saves the original untouched 28x28 image as a PNG as well.

The output neuron settings match in both implementations: threshold 65535,
reset zero, leak disabled, refractory zero. Classification selects the
largest output membrane after eight ticks. Output spikes are normally absent
with this high-threshold score readout; the general LIF core's firing/leak/
refractory functions are covered by separate regressions. A spike-based task
readout and output-spike interrupt are still system requirements to complete.

`rtl/lif_class_readout.v` scans actual state addresses 246..255 in hardware,
choosing the lowest digit on a tie. Expected predictions/true labels only
feed testbench checks and never drive the core or selector. Neuron states
are reset between images; programmed synapse weights survive those resets.

## Synchronous synapse storage

`rtl/lif_synapse_router.v` now has a registered weight read suitable for BRAM
inference. For each destination it scans source addresses. An active source
issues one synchronous read, then adds the sign-extended four-bit weight on
the following clock. Inactive sources skip the read. Destination currents
are returned with `current_valid`, with variable spacing between results.
No matrix-wide combinational weight sum remains.

This saves read ports at the cost of more clocks per network tick. Eight
input encoding ticks are not eight FPGA clocks. A 256-neuron recurrent ring
step takes about 66,000 routing clocks for one active source, plus state
updates/control. No real-time throughput claim is made.

Run `tools/synth_ps256.tcl` to synthesize, place and route the full default
core on `xc7z020clg400-1` inside a registered timing fixture. It loads timing
constraints before synthesis, checks setup and hold at 100 MHz, and requires
eight inferred RAMB primitives. Current evidence is in `build/ps256_timing/`;
see `TIMING_CLOSURE.md` for the exact context and reproduction command.
The older `build/ps256_synthesis/` report (-1.804 ns estimated setup slack)
is the historical baseline before state-path pipelining. Core implementation
inside a timing fixture does not establish full-system or board timing closure.

## Reproduce the comparison

From PowerShell in `D:\RTL_PROJECT`:

```powershell
python -m tools.run_mnist_rtl_check
```

This saves/reuses a dedicated 15x15 training checkpoint and runs Icarus.
The new evidence directory is **`build/mnist256/`**. To display each original
image as ASCII, add `--show-images`. To run only the Python demonstration:

```powershell
python -m examples.mnist256_demo
```

To compile/run the same 256-state test with installed Vivado XSim:

```powershell
python -m tools.run_mnist_rtl_check --simulator xsim
```

The runner defaults to `F:/Xilinx/Vivado/2023.2/bin`; use `--vivado-bin` to
specify another installation. Both simulators have passed the default run:

```text
PASS: MNIST 20 images, 160 ticks, all 256 states and RTL predictions match Python; correct=17/20
```

That is 20/20 matching predictions and **40,960 checked neuron updates**.
Accuracy against the true digits is **17/20 (85%) on this selected subset**.
Do not confuse implementation agreement with task accuracy or a full MNIST
test-set benchmark. The mistakes are recorded, not removed from evaluation.

## Run in the Vivado GUI

1. Generate weights/vectors without requiring Icarus:

   ```powershell
   python -m tools.run_mnist_rtl_check --generate-only
   ```

2. Reopen `D:/RTL_PROJECT/RTL_PROJECT.xpr` to load the canonical `rtl/`
   source and testbench files. With simulation closed, enter:

   ```tcl
   source D:/RTL_PROJECT/build/mnist256/configure_vivado.tcl
   launch_simulation -simset sim_1 -mode behavioral
   run all
   ```

3. The testbench first programs 65,536 weights (about 655 microseconds of
   simulated time). The complete default run lasts about 121 milliseconds
   of simulated time. Use `run all`, not just the initial `1000ns`.

4. Add waveform signals and use `restart` then `run all` to record from reset:

   | Scope | Signals |
   |---|---|
   | `lif_mnist_tb` | `sample_number`, `image_test_index`, `true_digit`, `python_prediction`, `rtl_prediction` |
   | `lif_mnist_tb` | `step_start`, `input_spikes`, `busy`, `done`, `updates_in_step` |
   | `lif_mnist_tb` | `debug_addr`, `state_read_membrane`, `state_read_refractory`, `readout_done`, `winning_score` |
   | `lif_mnist_tb/dut/population_stepper` | `neuron_index` |
   | `lif_mnist_tb/dut/synapse_router` | `source_index`, `destination_index`, `read_weight`, `accumulated_current`, `current_valid` |

   Inspect complete tick states at `done` and the digit at `readout_done`.
   Use signed decimal for weights/current and unsigned decimal for state,
   address and class signals. `neuron_index` must visit all 0..255 each tick.
   The core state scan count must be 256 at completion.

The saved project now selects the full core for synthesis and the 256-state
classifier for simulation. To select the small ring regression instead,
close simulation and set:

```tcl
set_property top lif_snn_core_tb [get_filesets sim_1]
set_property generic {} [get_filesets sim_1]
```

## Evidence files

Under `build/mnist256/`:

- `trained_weights.json`: 15x15 model raw/quantized weights and dataset hashes.
- `synapse_weights.hex`: all 65,536 four-bit entries, source-major then destination-major.
- `mnist_vectors.txt`, `mnist_vectors.hex`: identical encoded inputs and full Python expected states.
- `sample_*.png`: original held-out images.
- `python_predictions.csv`, `rtl_predictions.csv`: per-image predictions/scores and event counts (Python).
- `iverilog_predictions.csv`, `xsim_predictions.csv`: retained actual output of each simulator.
- `manifest.json`: selected test indices, mapping, accuracy and input/weight hashes.
- `iverilog_verification.json`, `xsim_verification.json`: hashes plus 256 states,
  65,536 synapses, 160 ticks and 40,960 checked state updates.
- `iverilog.log`, `xsim.log`: simulation transcripts.
- `negative_control/result.json`, `negative_control/simulation.log`: the
  checker rejected an isolated bias-weight change from -4 to -3 at source
  225/destination 254; first-tick membrane changed from 3 to 4. Normal
  weights/vectors were not modified.

Every packed vector has 533 32-bit fields, numbered from zero: 0 sample,
1 test index, 2 label, 3 tick; 4..11 input words; 12..19 expected spike words;
20..275 all membrane states; 276..531 all refractory states; 532 prediction.
Words are low-word-first and field 0 occupies the least significant 32 bits.
Metadata/expected fields do not feed the DUT.

The table/state/BRAM correction is one milestone. AER queues/handshake,
ESPRESSO/BDD arbitration, hardware input/frame sequencing, RV32/AXI/DMA,
UART/interrupt integration, CTL proofs, a measured paper optimization and
full-system FPGA evaluation remain required; see `STAGE_REPORT.md`.
