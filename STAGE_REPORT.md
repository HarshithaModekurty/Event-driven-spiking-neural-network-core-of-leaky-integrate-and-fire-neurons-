# RTL project stage report

Report date: 2026-11-10. Authoritative specification:
`Screenshot 2026-10-28 143938.png`.

## Current milestone

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

- **11 unit/directed RTL tests passed**, including pipeline commit/reset behavior, last-pixel/bias/output address
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

| Screenshot requirement | Current status / evidence |
|---|---|
| 256 time-multiplexed LIF states, 16-bit membrane, leak, threshold, reset, refractory | Implemented; full-population stress and integrated state comparisons |
| 256x256 1-bit or 4-bit synapse memory in BRAM | Four-bit table implemented and mapped to 8 RAMB36E1 blocks in full-core synthesis |
| AER input/output queues and handshake | Not implemented in RTL; current parallel spike bitmap is a test interface |
| Time-step accumulate, leak/fire, emit controller | Core implemented; host/frame protocol still required |
| Round-robin AER arbiter as ESPRESSO/BDD block | Python reference only; RTL and required representation/optimization remain |
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
| CTL eventual AER acknowledgment (fairness) | Not proven; needs implemented AER/arbiter and formal model |
| CTL no firing when refractory | Directed simulation exists; CTL proof not completed |
| Complete pattern-to-class UART/LED demonstration | Not completed on FPGA |

## Next required milestone

Build AER input/output queues and the request/acknowledge protocol around the
fixed-size core. Implement and verify round-robin arbitration, including the
specified ESPRESSO/BDD work and fairness assumptions, then add hardware input
encoding/frame sequencing. Continue with RV32/AXI4-Lite, DMA, interrupt and
UART integration. Add the formal proofs and research optimization comparison;
measure the complete implementation and demonstrate it on the target board.
Do not claim these requirements from the present core simulation results.

## Reproduce

```powershell
cd D:\RTL_PROJECT
python -m tools.run_mnist_rtl_check
python -m tools.run_mnist_rtl_check --simulator xsim
python -m unittest discover -s tests -v
```

For GUI simulation and evidence formats, read `MNIST_RTL_VERIFICATION.md`.
The `.xpr` synthesis top is now the full default `lif_snn_core`, and its saved
simulation top is the 256-state `lif_mnist_tb`. The dedicated implementation
script instantiates that full default core in a timing-only fixture with
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
