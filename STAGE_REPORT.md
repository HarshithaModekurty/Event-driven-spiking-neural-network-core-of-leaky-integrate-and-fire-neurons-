# RTL project stage report

Report date: 2026-11-10. Authoritative specification:
`Screenshot 2026-10-28 143938.png`.

## Current milestone

The integrated top is now `lif_aer_snn_core`: four clocked AER input queues,
a round-robin BDD arbiter, per-port end-of-step markers, and a backpressured
output queue wrap the existing 256-state core. See `AER_PROTOCOL.md` for
the transfer contract, framing, test commands and remaining formal work.

Icarus and Vivado XSim both passed the AER stress run: eight steps, 410
output tokens (402 spikes plus eight end markers), and all 2,048 state
updates. It exercises full output queues, input/output stalls, address 255,
partial-frame reset and repeated/external-recurrent source overlaps. Both
also passed the trained 20-image MNIST path through AER: 160 framed steps,
40,960 state updates and matching final class scores. The same learned
weights still score 17/20 (85%) on that fixed subset. Source and vector
hashes are recorded separately for each simulator/scenario.

The primary classifier is corrected to **256 actual time-multiplexed LIF
states and a 256x256 signed four-bit synapse table**. Ten output neurons are
included within those 256. A single shared LIF transition unit uses separate
read, calculate and write clocks per state. The router reads one weight synchronously and accumulates
serially, with a BRAM inference attribute and no memory reset loop.

The classifier uses 15x15 downsampled MNIST: state/source IDs 0..224 are pixel
sources, 225 is bias, 226..245 are reserved, 246..255 are the ten outputs.
All states exist and are visited even when a task gives them zero current.
This feedforward baseline has no hidden layer. The PS specifies the state
count and synapse organization, not a mandatory hidden-layer topology.

Weights were retrained using the existing offline algorithm for 225 features.
The earlier 16x16, 267-source/10-state diagnostic was not a requirement-compliant
classifier; its 95% selected-subset result is historical and is not the current
accuracy claim. Its evidence remains in `build/mnist_rtl/`. Current evidence
is in **`build/mnist256/`** and the canonical Python mapping is
`examples/mnist256_demo.py`.

Persistent instructions in `AGENTS.md` require consulting the screenshot for
architectural changes and uncertain requirements.

## Verification completed for the correction

- **15 unit/directed RTL tests passed**, including queue wrap/full/reset,
  BDD truth-table equivalence, Python arbiter traces, duplicate-source semantics,
  pipeline commit/reset behavior, last-pixel/bias/output address
  boundaries, square matrix dimensions, signed currents, offset recurrence,
  readout tie handling, all-zero and maximum scores.
- Icarus classifier: **20/20 Python/RTL predictions matched**, **160 ticks**,
  **40,960 state updates checked**. Every membrane, refractory counter and
  spike bit for all 256 states is compared each tick. The testbench also
  checks that the datapath visits states 0..255 exactly once per tick.
- Vivado 2023.2 XSim: the same **20 images, 160 ticks, 40,960 updates passed**.
- Accuracy: **17/20 (85%) on the selected held-out subset** in both. Images
  are selected from the official test split; 12,000 official training images
  train the weights for five epochs using seed 91. Test labels never drive RTL.
- Population stress: **64 steps x 256 states passed**, exercising different
  signed currents, leak, firing and refractory behavior throughout the population.
- Signed synchronous router: **8 transactions x 256 destinations passed**.
- Integrated recurrent ring: **4 steps x 256 neurons passed** and **24 steps
  x 4 neurons passed**. The 256-state ring stimulates a moving spike.
- Hardware class readout scans actual state addresses 246..255. This MNIST
  baseline uses high thresholds and membrane scores; spike-based output
  readout and the output-spike interrupt remain system work.
- Negative control: an isolated bias-to-state-254 weight change from -4 to -3
  was rejected on the first image/tick (membrane 4 instead of 3).

The historical default-core synthesis passed on `xc7z020clg400-1` in out-of-context mode.
The mapped table used **8 RAMB36E1 blocks**,
verified by primitive enumeration and Vivado's final mapping report. Total
core resources were **8,607 LUTs, 17,431 flip-flops, 8 block RAM tiles and
0 DSPs**. These counts cover `lif_snn_core`, not the future full SoC/peripherals.
Reports and checkpoint are under `build/ps256_synthesis/`.

The trial 10 ns / 100 MHz post-synthesis timing report has **WNS -1.804 ns**
and **TNS -14,091.305 ns**. That baseline did not close timing. It was area
synthesized then analyzed with the trial clock; there is no placement/routing,
host I/O delay constraints or on-board measurement. The PS specifies no
particular clock frequency.

The current RTL registers the state read and the calculation result, with
three clocks per neuron (768 processing clocks for the full population).
`tools/synth_ps256.tcl` now constrains before synthesis and runs placement
and routing of the complete default core inside a registered timing fixture.
It checks setup and hold without false-path or multicycle exceptions.
See `TIMING_CLOSURE.md` and `build/ps256_timing/` for current physical evidence;
the historical resource counts above do not describe the new implementation.

The new routed 100 MHz run passed: **setup WNS +0.508 ns, hold WHS
+0.032 ns**, with zero failing endpoints and zero TNS/THS. Production core
utilization inside the fixture is **8,462 LUTs, 17,623 flip-flops, eight
RAMB36E1 blocks and zero DSPs**. The fixture adds one LUT, 631 flip-flops and
one BUFG. These are core implementation results in a registered context;
they do not establish board timing or future complete-system resources.

`tools/synth_synapse_bram.tcl` is an optional faster, isolated memory/router
check using RuntimeOptimized synthesis. Its separate resources do not replace
the full-core baseline above.

## Traceability to every screenshot requirement

The new AER wrapper also completed 100 MHz implementation in a registered
timing fixture: **setup +0.300 ns, hold +0.024 ns**, zero failing endpoints.
The AER-wrapped core uses **9,350 LUTs, 18,337 flip-flops, eight RAMB36E1
blocks and zero DSPs** in this run. Fixture overhead is one LUT, 431
flip-flops and one BUFG. Reports are under `build/aer256_timing/`.
This measurement includes the queues and scheduler, and remains distinct
from full-SoC or board timing closure.

| Screenshot requirement | Current status / evidence |
|---|---|
| 256 time-multiplexed LIF states, 16-bit membrane, leak, threshold, reset, refractory | Implemented; full-population stress and integrated state comparisons |
| 256x256 1-bit or 4-bit synapse memory in BRAM | Four-bit table implemented and mapped to 8 RAMB36E1 blocks in full-core synthesis |
| AER input/output queues and handshake | Clocked request/acknowledge, bounded queues, backpressure and explicit end markers implemented and simulated |
| Time-step accumulate, leak/fire, emit controller | Framed collect/compute/emit/drain controller implemented; future DMA/host integration remains |
| Round-robin AER arbiter as ESPRESSO/BDD block | Four-port RTL arbiter with generated 38-node reduced ordered BDD; all 64 grant combinations and stateful Python traces checked |
| Input rate encoder | Python reference; hardware encoder/integration remains |
| RV32 weight loading over AXI4-Lite | Not implemented |
| DMA spike delivery | Not implemented |
| Output-spike interrupt | Not implemented |
| UART spike-raster dump / LEDs | Python text formatter only; RTL peripherals/demo remain |
| Offline-trained small-task golden model | Canonical 256-state model and saved learned checkpoint |
| Spike-for-spike agreement | Checked for the recurrent ring/population and all 256 classifier spike bits each tick |
| Classification accuracy | 17/20 for the selected held-out simulation subset; full-test-set/on-board measurements remain |
| Synaptic events per inference | Python counts saved per image; hardware counter and comparison remain |
| Resource table / baseline vs paper design | Full-core baseline resource table measured; paper implementation/comparison still required |
| CTL eventual AER acknowledgment (fairness) | RTL/BDD implemented; CTL model, explicit environment assumptions and proof still required |
| CTL no firing when refractory | Directed simulation exists; CTL proof not completed |
| Complete pattern-to-class UART/LED demonstration | Not completed on FPGA |

## Next required milestone

Develop the CTL fairness/refractory model for the implemented scheduler/core,
with receiver and end-of-step progress assumptions made explicit. Add the
hardware rate encoder and connect it to the framed input interface.
Continue with RV32/AXI4-Lite, DMA, interrupt and
UART integration. Add the formal proofs and research optimization comparison;
measure the complete implementation and demonstrate it on the target board.
Do not claim these requirements from the present core simulation results.

## Reproduce

```powershell
cd D:\RTL_PROJECT
python -m tools.run_mnist_rtl_check
python -m tools.run_mnist_rtl_check --simulator xsim
python -m unittest discover -s tests -v
python -m tools.run_aer_rtl_check
python -m tools.run_aer_rtl_check --scenario mnist --simulator xsim
```

For GUI simulation and evidence formats, read `MNIST_RTL_VERIFICATION.md`.
The `.xpr` synthesis top is now `lif_aer_snn_core`, and its saved simulation
top is `lif_aer_snn_core_tb`. The older bitmap classifier is selectable with
its generated configuration script. Dedicated implementation scripts
instantiate the old core or the new AER top in timing-only fixtures with
launch/capture registers and a real clock buffer. It does not modify an open
Vivado project. Core timing in that registered context does not establish
future full-system or board timing closure.

The active Vivado workspace is `D:/RTL_PROJECT`. Versioned source is mirrored
into its nested `Event-driven-spiking-neural-network-core-of-leaky-integrate-and-fire-neurons-`
Git checkout. The Vivado project references canonical `rtl/` sources directly,
so ignored imported-source copies are not required to reopen the checkout.
Small verification snapshots are retained under `verification/`; large build
outputs, datasets and Vivado caches remain ignored. Committing locally and
pushing to GitHub are separate operations.
