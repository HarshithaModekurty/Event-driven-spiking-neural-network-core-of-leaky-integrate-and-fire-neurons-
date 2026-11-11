# LIF Spiking Core Golden Model

See [STAGE_REPORT.md](STAGE_REPORT.md) for completed work, verification results,
remaining project stages, and the next recommended milestone.

The integrated core now has framed AER input/output queues and a four-port
round-robin BDD arbiter. See [AER_PROTOCOL.md](AER_PROTOCOL.md) for the
request/acknowledge contract, time-step boundaries and verification commands.

The hardware rate encoder now feeds that AER interface. See
[RATE_ENCODER.md](RATE_ENCODER.md) for intensity loading, image/tick control,
Python comparisons and Vivado GUI commands. The integrated top remains a
256-state design. Source-bound scheduler/queue CTL and full-width refractory
SAT checks, assumptions and remaining composition work are described in
[FORMAL_VERIFICATION.md](FORMAL_VERIFICATION.md).

See [TIMING_CLOSURE.md](TIMING_CLOSURE.md) for the registered neuron-read
schedule, constraints applied before synthesis, and routed setup/hold checks.

Trained MNIST inference now has an RTL comparison. See
[MNIST_RTL_VERIFICATION.md](MNIST_RTL_VERIFICATION.md) for the address mapping,
saved trained weights, per-image results, and Vivado instructions. Run
`python -m tools.run_mnist_rtl_check` or add `--simulator xsim` for Vivado XSim.

See [CORE_WALKTHROUGH.md](CORE_WALKTHROUGH.md) for a plain-English explanation
of the connected core, the actual four-neuron ring example, and Vivado signals
to inspect.

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

## Trained MNIST proof within the PS limits

The primary classifier uses exactly 256 stored LIF states and a 256x256
signed four-bit synapse matrix. Inputs are 15x15 downsampled images at
addresses 0..224, bias is 225, 226..245 are reserved states, and output
digits occupy states 246..255. All 256 states are visited and checked each tick.
The input-source states have no incoming connections in this baseline;
they remain zero but are physically present and processed.

```powershell
python -m tools.run_mnist_rtl_check
python -m tools.run_mnist_rtl_check --simulator xsim
```

Both simulators matched all 20 held-out predictions and all 256 states over
160 ticks (40,960 neuron updates). The retrained 15x15 model scored 17/20
(85%) on that selected test subset; this is not full-test-set accuracy.
Original images, learned weights, per-image results, vectors and hashes
are saved in `build/mnist256/`.

For a Python-only live demonstration with ASCII images:

```powershell
python -m examples.mnist256_demo
```

See [MNIST_RTL_VERIFICATION.md](MNIST_RTL_VERIFICATION.md) for Vivado GUI
commands and the exact mapping. The screenshot is the authoritative PS;
[STAGE_REPORT.md](STAGE_REPORT.md) tracks all remaining requirements.
The older `examples.mnist_live_demo` and `build/mnist_rtl/` results used
a different diagnostic mapping; their 95% subset result does not apply
to this corrected classifier. The synapse router now uses scheduled
synchronous reads; full-core synthesis is provided by `tools/synth_ps256.tcl`.

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

## Population, Synapse, and Core RTL

`rtl/lif_population_stepper.v` stores each neuron's membrane and refractory
state in arrays and uses separate read, calculation and write clocks
for each neuron, using the shared combinational
`rtl/lif_transition.v` datapath. The default parameter is 256 neurons; its
current simulation config uses 4 neurons so cycle-by-cycle state can be checked
easily. Before each population step, software/testbench writes one signed
current per neuron. The controller returns a spike bitmap and has a debug state
read port.

The population stepper has been checked at both 4 and 256 neurons. Signed-4-bit
synapse storage and source-spike current routing are implemented in
`rtl/lif_synapse_router.v`. The integrated `rtl/lif_snn_core.v` routes source
spikes, loads the resulting current for each destination, updates the
population, then feeds the output spikes into the following time step.

Run the Python-generated four-neuron comparison from PowerShell:

```powershell
.venv\bin\python.exe -m tools.run_population_rtl_check
```

The runner compares 64 population time steps against four persistent Python
`LIFNeuron` instances and reports each run's result. It writes
`build/lif_population/lif_population_vectors.txt` and, under Icarus,
`build/lif_population/lif_population_stepper.vcd`. Vivado uses
`lif_population_stepper_tb` as its simulation top and reads the same vector
file by its absolute path; change the path in
`rtl/tb/lif_population_stepper_tb.v` if this workspace is moved.

Python's `CONFIG` is the source of the population test parameters. Every vector
row begins with `threshold reset_value leak_enable leak_shift refractory_period`,
followed by four input currents, the expected spike bitmap, four expected
membrane values, and four expected refractory counters. The testbench loads the
first row's configuration before reset, then loads the configuration from every
row before its step, so the RTL is not relying on a separate copy of the
population parameters.

Run the 256-neuron population check and standalone synapse-router check:

```powershell
.venv\bin\python.exe -m tools.run_population_rtl_check --neurons 256 --steps 64
.venv\bin\python.exe -m tools.run_synapse_router_check --neurons 256 --transactions 32
```

Run the integrated router-to-population core against `SNNGoldenModel`:

```powershell
.venv\bin\python.exe -m tools.run_snn_core_check --neurons 4 --transactions 24
.venv\bin\python.exe -m tools.run_snn_core_check --neurons 256 --transactions 4
```

The standalone router test checks signed accumulated destination currents.
The integrated example uses a deterministic excitatory ring: neuron `n` has a
weight of `+7` to neuron `(n + 1) mod N`, the threshold is `8`, and the first
input event is at neuron 0. Its first output spike is neuron 1, the next is
neuron 2, and the spike continues around the ring. The test compares each
transaction's spike vector, membrane, and refractory states with
`SNNGoldenModel`. Python generates deterministic weight/event files under
`build/lif_router/` and `build/lif_snn_core/`; generate these before running the
corresponding Vivado simulation.

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
- `examples/mnist256_demo.py`: primary PS-aligned 256-state classifier.
- `examples/mnist_live_demo.py`: historical model and shared data/training helpers.
- `rtl/lif_neuron.v`: first synthesizable Verilog neuron datapath.
- `rtl/lif_transition.v`: shared combinational LIF state transition.
- `rtl/lif_population_stepper.v`: parameterized time-multiplexed neuron state engine.
- `rtl/lif_synapse_router.v`: signed-4-bit synapse storage and serial current router.
- `rtl/lif_snn_core.v`: router/population sequencing and recurrent spike feedback.
- `rtl/lif_class_readout.v`: synthesizable largest-membrane digit selector.
- `rtl/tb/lif_neuron_tb.v`: vector-driven Verilog self-checking testbench.
- `rtl/tb/lif_population_stepper_tb.v`: population vector testbench.
- `rtl/tb/lif_synapse_router_tb.v`: standalone router comparison testbench.
- `rtl/tb/lif_snn_core_tb.v`: integrated SNN comparison testbench.
- `rtl/tb/lif_mnist_tb.v`: trained-image state and hardware digit comparison.
- `tools/run_lif_rtl_check.py`: Python golden-vector generator and Icarus runner.
- `tools/run_population_rtl_check.py`: Python-driven population RTL comparison.
- `tools/run_synapse_router_check.py`: Python-driven signed synapse routing check.
- `tools/run_snn_core_check.py`: integrated recurrent SNN/Python comparison.
- `tools/run_mnist_rtl_check.py`: trained-weight export and Icarus/Vivado MNIST verification.
- `tests/test_golden_model.py`: executable model checks.
