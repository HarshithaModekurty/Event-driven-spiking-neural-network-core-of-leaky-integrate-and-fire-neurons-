# LIF Spiking Core Golden Model

See [STAGE_REPORT.md](STAGE_REPORT.md) for completed work, verification results,
remaining project stages, and the next recommended milestone.

This folder contains a dependency-free Python behavioral reference for the
RTL project in `Screenshot 2026-10-28 143938.png`.

## Included

- 16-bit saturating LIF neurons with configurable threshold, reset, leak shift,
  and refractory period.
- Time-step network with 256 neurons by default and a `weights[source][destination]`
  synapse table.
- 1-bit excitatory (0/+1) and signed 4-bit (-8..+7) synapse modes.
- Deterministic 8-bit rate encoder and a round-robin AER request/acknowledge
  arbiter whose request stays stable until acknowledged.
- UART-friendly spike-raster text formatter (`tick,address` records).
- Small offline-trained vertical-versus-horizontal pattern demo.
- Real-image MNIST digit classification demo using official train/test splits.
- Unit tests covering neuron behavior, time-step routing, encoding, and AER
  arbitration.

## Run

From this directory in PowerShell:

```powershell
.venv\bin\python.exe -m unittest discover -s tests -v
.venv\bin\python.exe -m examples.train_toy_classifier
```

The demo trains a perceptron offline on 400 generated 5x5 bar images, quantizes
its weights to signed 4-bit values, and then streams fresh random noisy images
through the LIF model. Each image is rendered in the terminal beside its
expected class, predicted class, and output spike counts. Holdout images are
rejected if they exactly duplicate a training image. The labels come from the
synthetic image-generation rule; this demonstrates the workflow, not real digit
recognition or generalization to MNIST.

To stream more samples, use for example:

```powershell
.venv\bin\python.exe -m examples.train_toy_classifier --samples 20 --seed 91
```

## Real MNIST Image Proof

The live bar demo above uses generated toy images. For real handwritten digits,
run:

```powershell
.venv\bin\python.exe -m examples.mnist_live_demo --samples 20 --train-count 12000 --seed 91
```

This uses the official MNIST training partition for offline training and
selects images only from the separate official test partition for evaluation.
It prints each original 28x28 image as grayscale ASCII, its true digit, the
predicted digit, and the ten output-neuron membrane scores. The 28x28 image is
area-averaged and binarized to 16x16 for the 256 input neurons, then passed
through the signed 4-bit LIF network. Output digit is the neuron with the
highest membrane potential after eight rate-coded ticks.

The script saves each original grayscale MNIST test image as a PNG and appends
the per-image results to `proof_images/mnist/predictions.csv`. You can open the
PNG files individually in Windows Photos/Paint and show them in sample order;
the CSV maps each image filename to its true and predicted digit. The selected
test image indices do not overlap the training partition.

The dataset archives are stored in `data/mnist/`. They are the standard MNIST
IDX gzip files, also available from the [MNIST dataset page](http://yann.lecun.com/exdb/mnist/)
and the [Google-hosted mirror](https://storage.googleapis.com/cvdf-datasets/mnist/).
The reported subset accuracy is only an evaluation sample, not the full MNIST
benchmark accuracy. This is a software golden-model demonstration; RTL proof
still requires comparing RTL outputs against these same image inputs and
weights.

## First RTL Block: LIF Neuron

The first synthesizable RTL block is `rtl/lif_neuron.v`. It implements one
16-bit LIF neuron with signed 32-bit input current, optional shift-based leak,
threshold/reset, refractory counter, synchronous reset, and clock enable.
Configuration inputs are sampled each enabled clock, so a future time-multiplexed
controller can drive neuron-specific settings.

Install Icarus Verilog and make sure `iverilog` and `vvp` are on `PATH`. Then
run this from the project root in PowerShell:

```powershell
.venv\bin\python.exe -m tools.run_lif_rtl_check
```

The Python runner generates test vectors by stepping `golden_model/lif.py`,
including its default configuration (`threshold=32`, `reset_value=0`,
`leak_shift=4`, `refractory_period=0`) and additional stress configurations.
It compiles the RTL and self-checking testbench, then compares spike, membrane,
and refractory state after every clock. The runner reports the current cycle
count. It also writes `build/lif_rtl/lif_neuron.vcd`, which contains the DUT
inputs/outputs and the testbench expected values for waveform inspection.
Vector, VCD, and compiled simulation files are written under `build/lif_rtl/`.

For Vivado simulation, add `rtl/lif_neuron.v` and `rtl/tb/lif_neuron_tb.v` to
the project and set `lif_neuron_tb` as the simulation top. First regenerate
`build/lif_rtl/lif_vectors.txt` with the Python command above. The testbench
opens `D:/RTL_PROJECT/build/lif_rtl/lif_vectors.txt` directly, so no XSim runtime
plusarg is needed. Change that string in `rtl/tb/lif_neuron_tb.v` if the project
is located elsewhere, and keep the Vivado imported copy synchronized. The
testbench prints an `INFO` line with the opened path, then prints
`PASS: matched Python golden model for 518 LIF cycles` when the entire file has
been processed. If it prints `FAIL: could not open ...`, check that the vectors
exist at the hardcoded path. The generated GUI Tcl script may say
`run 1000ns`; type `run all` in Vivado's Tcl console to run through all 518
cycles (about 5180 ns). Add `dut.membrane`, `dut.spike`,
`dut.refractory_remaining`, `expected_membrane`, `expected_spike`, and
`expected_refractory` to the waveform to compare actual and expected values.
The testbench uses a 1 ns timescale. Vivado records its waveform in its WDB;
`$dumpfile/$dumpvars` are enabled only for Icarus, which creates the VCD.

## Behavioral contract for RTL comparison

1. Membrane state is an unsigned 16-bit value. Addition saturates to 65535 and
negative current clamps at zero.
2. With `leak_shift=k`, leak is applied before input current as
   `v_leaked = v - (v >> k)`. `leak_shift=None` disables leak.
3. The neuron fires when the post-current membrane is greater than or equal to
   threshold. It immediately loads its reset value.
4. The next `refractory_period` ticks ignore current and cannot fire. The
   refractory counter decrements once per blocked tick.
5. Network inputs are source neuron addresses. AER events delivered in one
   tick update target membrane states in that tick; neurons that fire produce
   events processed on the following tick.
6. Every nonzero traversed synapse increments `synaptic_events`, including
   inhibitory connections. This is an event-count proxy, not a power estimate.
7. Four-bit weights are signed two's complement (-8 through +7). The one-bit
   mode uses 0 for no connection and 1 for an excitatory connection.

For bit-exact comparison, use the same order of operations and parameter
interpretation in RTL. The Python model uses unbounded integer accumulation
for per-tick synaptic current; if the RTL uses a narrower accumulator, add the
same explicit saturation/wrap rule to both implementations.

## Package map

- `golden_model/lif.py`: LIF configuration and neuron transition.
- `golden_model/network.py`: synapse matrix and synchronous network step.
- `golden_model/encoding.py`: input feature rate encoding.
- `golden_model/aer.py`: queued AER arbiter.
- `golden_model/raster.py`: UART spike-raster formatter.
- `examples/train_toy_classifier.py`: self-contained offline-training example.
- `examples/mnist_live_demo.py`: real MNIST image training and live holdout proof.
- `rtl/lif_neuron.v`: first synthesizable Verilog neuron datapath.
- `rtl/tb/lif_neuron_tb.v`: vector-driven Verilog self-checking testbench.
- `tools/run_lif_rtl_check.py`: Python golden-vector generator and Icarus runner.
- `tests/test_golden_model.py`: executable model checks.