# Hardware intensity-to-spike path

`lif_rate_aer_snn_core` connects a hardware rate encoder to AER port 0 of
the existing 256-state SNN. Ports 1..3 automatically send an empty-step
marker. The 256 LIF states, shared LIF calculator and 256x256 signed
four-bit synapse table remain unchanged. The encoder's phase storage is
input bookkeeping, not additional LIF neurons.

Load all 256 unsigned eight-bit intensities before starting an image. One
shared encoder visits sources 0..255 in three clocks per source, with
additional clocks for backpressure and the final marker. For each source:

```
sum = phase + intensity
spike = (sum >= 255)
phase_next = sum - 255 if spike else sum
```

Each phase starts at zero and stays in 0..254. Intensity 0 never emits;
255 emits every tick; 128 emits approximately every second tick. This
is the exact `golden_model.encoding.RateEncoder` rule. A stalled spike
holds its address and phase until the request/acknowledge transfer.
After source 255, an END token closes the tick, including an empty tick.

## Host contract

All transfers occur at the rising clock edge with request and ready/ack
both high. These signals use the same clock; see `AER_PROTOCOL.md`.

| Operation | Acceptance condition | Effect |
|---|---|---|
| Intensity write | `intensity_write && intensity_ready` | Write one eight-bit source intensity |
| Weight write | `weight_write && weight_ready` | Write one signed four-bit synapse |
| Begin tick | `tick_start && tick_ready` | Capture LIF configuration and start encoding |
| Begin new image | `sample_clear && clear_ready` | Clear encoder phases, neuron/recurrence state and AER queues |
| Consume output | `out_req && out_ack` | Accept `{out_end,out_addr}` |

Writes and sample clearing are accepted only while idle. Commands asserted
while busy are ignored. Do not assert a tick start and programming command
together. A sample clear takes priority over programming/start and preserves
intensities and weights. Global reset also preserves those memories, whose
contents must be explicitly loaded after power-up. `reset_value` must be
stable at the sample-clear/global-reset edge. Other LIF settings are captured
when a tick starts; later changes cannot alter that tick.

There is one tick in flight. `tick_done` means the LIF calculation has
finished; `frame_done` means the receiver has accepted the output END token.
The next tick is admitted after that drain, so output backpressure propagates
to the host. Continue asserting output acknowledgement as needed to make
progress. The core emits spike addresses followed by END in ascending order.

## Reproduce the checks

From the project directory:

```powershell
python -m unittest discover -s tests -v
python -m tools.run_rate_snn_check
python -m tools.run_rate_snn_check --simulator xsim
python -m tools.run_rate_snn_check --scenario mnist
python -m tools.run_rate_snn_check --scenario mnist --simulator xsim
```

The arithmetic unit test checks all 65,280 legal phase/intensity pairs.
The streaming unit test checks 256 sources over 32 ticks, grayscale values,
phase continuity, backpressure, reset cancellation and sample clearing.
The integrated stress run checks 24 ticks, 3,906 encoder tokens, 1,908 output
tokens (including 24 END markers) and 6,144 LIF state updates. It exercises
signed recurrence, firing/refractory behavior, full output queues, rejected
busy commands and configuration capture.

The MNIST run checks 20 images, 160 ticks, 6,048 encoder tokens and 40,960
state updates against Python, using the previously trained checkpoint.
Its 15x15 features are currently binary, represented as intensity 0 or 255;
bias 225 is 255, reserved/output input intensities are zero. Training and
preprocessing have not changed. Class scores remain the final membranes of
states 246..255; the high threshold means this task emits only END markers,
not output spikes. The stress run separately verifies actual output spikes.
The fixed held-out subset remains 17/20 correct (85%), not a full-test-set
or on-board accuracy measurement. Grayscale encoding is unit/stress tested;
grayscale classification would require matching preprocessing and retraining.

Each runner writes vectors, per-simulator logs and SHA256 receipts under
`build/rate_network/` or `build/rate_mnist/`. Small snapshots are retained
in `verification/`; generated memories and simulator binaries stay ignored.

## Vivado GUI

Generate the vectors first, then reopen `RTL_PROJECT.xpr` if it was already
open. The saved synthesis top is `lif_rate_aer_snn_core`; the simulation
top is `lif_rate_snn_tb`. In the Vivado Tcl console, from the project directory:

```tcl
source build/rate_network/configure_vivado.tcl
launch_simulation
run all
```

Use `build/rate_mnist/configure_vivado.tcl` for the trained images. These
scripts set the matching generic counts and quoted data-directory argument.
Inspect `dut.encoder`, `dut.input_ack`, `tick_done`, `frame_done`, `out_req`,
`out_ack`, `out_end`, and the network population stepper. A successful stress
simulation prints `PASS: rate/AER/SNN 3 images, 24 ticks ... 6144 state updates`.
The older AER/bitmap testbenches remain selectable with their own scripts.

## Routed implementation

```powershell
& 'F:/Xilinx/Vivado/2023.2/bin/vivado.bat' -mode batch -source tools/synth_rate256.tcl
```

Vivado 2023.2, `xc7z020clg400-1`, 10 ns clock: routed setup **+0.179 ns**,
hold **+0.024 ns**, zero failing endpoints, zero unconstrained internal
endpoints and zero combinational loops. Applied constraints contain no
false-path or multicycle exceptions. The full encoder/AER/LIF core uses
**10,307 LUTs, 20,514 flip-flops, eight RAMB36E1 blocks and zero DSPs**.
Its timing fixture adds one LUT, 409 flip-flops and one BUFG.

Reports are in `build/rate256_timing/` and `verification/rate256_timing/`.
This is a registered out-of-context implementation, not board timing or a
full SoC. DRC has two context warnings: no PS7 instance and virtual observation
outputs with no routable external loads. A combinational reset/admission
feedback found during development was corrected using registered `inflight`
state; the final run has no loop-breaking timing exception.
