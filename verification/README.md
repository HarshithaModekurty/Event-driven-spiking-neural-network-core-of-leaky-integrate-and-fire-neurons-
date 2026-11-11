# Verification snapshots

Each receipt records the source/vector hashes used for that run. Historical
snapshots describe their recorded sources, rather than every later revision.

Current RV32 integration evidence is in `axi_protocol/`, `rv32_network/`,
`rv32_mnist/` and `rv32_z710_timing/`. `RV32_AXI_CONTROL.md` states which
simulator/scenario combinations and implementation scopes were checked.
`rv32_z710_timing/packing_baseline.*` separately records the failed
pre-RAM placement baseline; its earlier source hashes are intentional.

`rate_network/`, `rate_mnist/`, `rate256_timing/` and earlier standalone
core/AER results predate the Z7-10 scratch-current RAM change. The rate
milestone is commit `40c3d6e`; AER milestone is `52fdc50`. Their timing
fixtures targeted xc7z020 and are not Z7-10 board measurements.

`formal/` proves the production selector, arbiter, depth-16 queues and LIF
transition components named by its hashes. Those proofs do not cover the
new AXI/CPU integration or complete stored-state/controller composition.
See `FORMAL_VERIFICATION.md` for assumptions and negative controls.

Large vectors, checkpoints, simulator caches and MNIST archives remain
untracked under `build/` and `data/`; snapshots are copied after a verified
run and are not automatically refreshed. Earlier reproduction commands are
in `TIMING_CLOSURE.md` and `MNIST_RTL_VERIFICATION.md`. To reuse the saved
learned checkpoint in a new workspace, copy
`verification/mnist256/trained_weights.json` to
`build/mnist256/trained_weights.json` before exporting vectors. Never treat
a historical snapshot as proof that subsequently modified RTL has passed.
