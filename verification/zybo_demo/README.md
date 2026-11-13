# Zybo Z7-10 demo evidence

These are simulation/implementation snapshots, not physical FPGA captures.
The primary model still contains 256 LIF states; outputs occupy 246–255.

- `mnist/`: actual RV32 boot, 65,536 AXI weight writes, 20 learned images,
  160 ticks and 40,960 membrane/refractory state readbacks; all encoded and
  output packets match Python. The real simulated UART wire is decoded and
  checked for the actual class and all ten scores per image. Accuracy is
  17/20 against ground truth; Python/RTL agreement is 20/20.
- `stress/`: the same architecture with deterministic signed-ring test
  weights, 3 images, 24 ticks and 6,144 readbacks, including nonzero output
  spikes. It does not measure digit recognition accuracy.
- `board_io/`: Xsim with the actual AMD MMCM model, 125-to-100 MHz clock,
  startup reset, button bounce rejection, start and BTN0 restart.
- `host_regression/`: standalone AXI protocol tests in Icarus and Xsim,
  plus the original CPU stress test with demo backpressure disabled in Xsim.
- `unit/`: 25 unit tests, including simultaneous dual-port event capture,
  formatting, pause/next/reset/overflow, capture mismatch detection and
  every clock of UART bits at the production divisor of 868, and rejection
  of changed hardware/ROM/recipes/checkpoints or stale synthesis artifacts.
- `board_timing/`: the learned 20-image board bitstream's routed 100 MHz
  implementation, setup +0.017 ns, hold +0.028 ns, resource/constraint/DRC/CDC
  and bus-skew reports, bit/probes hashes and synthesis provenance. Its
  `baseline/` records the earlier failing clear-command path separately.

`uart_capture.txt` in these folders is decoded simulation output, not a
USB capture from a board. `reference.json` holds Python expectations, not
measured FPGA results. Integrated simulation accelerates UART to four
clocks per bit; hardware uses 868. No clock is stopped for image pauses.

Each integrated receipt binds actual HDL, export/assembly/test code and
vector/firmware artifact bytes by SHA-256. The golden model modules remain
unchanged from the preceding `3d19e6b` milestone; Git history and the separate
source manifest bind those additional dependencies. Preserve raw evidence
bytes across checkouts; `.gitattributes` disables newline conversion here.

For physical measurements follow `ZYBO_Z7_10_DEMO_TUTORIAL.html`, save new
UART/ILA captures under `build/board_demo/mnist/` and run the capture checker.
Do not rename these simulation logs as physical captures. The snapshot
does not complete DMA, output IRQ, full formal composition or the paper
optimization comparison; see `STAGE_REPORT.md`.
