# Project requirements

The authoritative problem statement is `Screenshot 2026-10-28 143938.png`.
Read it before architectural changes and whenever a requirement is uncertain.
Do not substitute smaller demonstrations for the primary implementation.

The primary integrated design must provide 256 time-multiplexed LIF states
(16-bit membrane, leak, threshold, reset and refractory) and a 256x256
one- or four-bit synapse table in BRAM. Output neurons belong within the 256.
Smaller parameterized unit regressions are allowed, with explicit scope.

The brief also requires time-step control, AER queues/handshake, round-robin
arbitration as the ESPRESSO/BDD block, rate encoding, RV32/AXI4-Lite weight
loading, DMA spikes, output-spike interrupt, UART raster, offline training,
spike-for-spike comparison, task accuracy, synaptic event counts, a research
optimization comparison, resources, and CTL fairness/refractory proofs.
Track unfinished requirements honestly in STAGE_REPORT.md.

The previous 267-source/10-state classifier was diagnostic, not a compliant
replacement. Keep Python/RTL mapping, weights, arithmetic and inputs equal.
Retrain and remeasure if preprocessing changes. Do not claim BRAM inference,
timing, board behavior or formal proof from simulation alone.
