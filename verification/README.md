# Core and AER verification snapshots

These are copies of the small evidence files produced for the 256-state,
256x256 four-bit SNN core on 2026-11-10. They preserve results in Git while
`build/`, Vivado checkpoints/caches, generated vectors and MNIST archives
remain untracked. The snapshot is not automatically updated by a new run.

- `ps256_timing/`: Vivado 2023.2 synthesis, placement and routed timing,
  constraint coverage, route status, DRC, utilization and source hashes.
  The registered timing fixture passed at 100 MHz: setup +0.508 ns,
  hold +0.032 ns. It is not a board or full-SoC implementation. The DRC
  warning about the missing PS7 block is retained in the original report.
- `mnist256/`: the actual offline-trained weights, dataset/vector hashes,
  per-image predictions and both simulator verification records. Python,
  Icarus and XSim agreed for 20 images / 160 ticks / 40,960 state updates;
  accuracy on that selected test subset was 17/20 (85%).

The subsequent AER milestone adds `aer256_timing/`, `aer_network/` and
`aer_mnist/`. These preserve the new wrapper's routed timing reports and the
source/vector-bound simulator results separately from the original core
milestone. See `AER_PROTOCOL.md`; neither snapshot establishes board timing
or the outstanding CTL proofs.

Reproduction commands and the original Windows paths are documented in
`TIMING_CLOSURE.md` and `MNIST_RTL_VERIFICATION.md`. The testbench defaults
use `D:/RTL_PROJECT/build/`; use that documented workspace or adjust the
testbench data paths when running a checkout elsewhere. Snapshot source
hashes identify the exact bytes used on the recorded Windows run; Git line
ending conversion on another platform can change byte hashes.

Generated simulator vectors can be recreated from the documented training
configuration and official MNIST archives. To reuse this exact saved
checkpoint, copy `mnist256/trained_weights.json` into `build/mnist256/`
before running the classifier exporter. Never treat a saved snapshot as
evidence that subsequently modified RTL has passed.
