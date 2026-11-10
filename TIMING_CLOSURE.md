# 100 MHz timing closure of the 256-state core

The requirement source remains `Screenshot 2026-10-28 143938.png`. This change
retains 256 stored LIF states, one shared update datapath, and the 256x256
signed four-bit synapse table. It changes the update schedule, not neuron
arithmetic, training, input images or network connectivity.

## Why the old path failed

The previous post-synthesis report in `build/ps256_synthesis/` measured
-1.804 ns setup slack against a trial 10 ns clock. The critical path selected
one membrane from a 256-state array, performed leak/add/threshold logic, and
wrote a neuron state without an intervening register.

That report was an unplaced estimate, with the clock added after synthesis.
It did not establish board timing closure.

## RTL correction

`rtl/lif_population_stepper.v` now uses three clock phases per neuron:

1. Read phase: register the selected membrane, refractory state, current and
   configuration. This isolates the large state-selection mux from arithmetic.
2. Calculate phase: run the unchanged `lif_transition` calculation and
   register its membrane/refractory/spike results.
3. Write phase: commit those registered results to that neuron's state.

Registering only the input read improved the synthesis estimate, but placement
still showed negative slack through calculation and the broadcast state write.
The result register separates those paths. That exploratory attempt is saved
under `build/ps256_read_only_attempt/`; it is not the final implementation.

The neuron address advances only after a commit. `update_commit` identifies
the write cycle. `busy` spans all three phases; it must not be used as a commit
count. `done` occurs after the 256th commit. Configuration is captured with
each neuron's read; the controller must hold its intended step settings
stable while the population is processing.

The population scan now takes 768 processing clocks instead of 256, plus the
start/control overhead. Synapse routing is unchanged. No multicycle exception
is needed: each register-to-register path must meet one 10 ns clock period.
Reset cancels an in-flight read and clears the state as before.

Useful waveform signals inside `dut.population_stepper` are `neuron_index`,
`update_phase` (0 read, 1 calculate, 2 write), `selected_membrane`,
`selected_current`, `result_membrane` and `update_commit`.
The classifier testbench counts 256 commit cycles per tick and compares all
256 neuron states after completion.

## Constraint and implementation flow

The production Vivado project loads `constraints/core_100mhz.xdc` for
synthesis and implementation. It specifies:

- 100 MHz / 10 ns `core_clk`.
- 0.100 ns clock uncertainty for implementation.
- Synchronous input arrival budget: 0.500 ns minimum, 2.000 ns maximum.
- Synchronous output delay budget: 0.500 ns minimum, 2.000 ns maximum.

These are internal-IP integration assumptions, not measured board delays.
Reset is synchronous and included in the input timing budget. No false-path
or multicycle exceptions are added. The XDC is also registered in the
Vivado project's constraints set for synthesis and implementation.

The first raw-core implementation met routed setup (+0.358 ns), but reported
-0.911 ns hold slack on unplaced input-port paths. Vivado warned that those
ports had no `HD.PARTPIN_LOCS` and could not be routed accurately. The raw
attempt is retained in `build/ps256_raw_boundary_attempt/`; it is not a
passing hold result. `constraints/core_ooc_context.xdc` describes its assumed
external clock buffer, and is not the final physical verification context.

The final flow uses `tools/fixtures/lif_core_timing_harness.v` to give every
core data input and output a real launch/capture register. It instantiates
the unmodified default core, 341 launch bits, 290 capture bits and an actual
BUFG at BUFGCTRL_X0Y0. The launch shift register keeps the core inputs live
for static timing; it is only a timing fixture, not classifier stimulus or
a replacement for the production interface. All core interfaces are routed
between placed registers, so the router can analyze and repair their hold
paths. This adds verification context without relaxing a failing path.

`constraints/timing_harness_100mhz.xdc` supplies the same 10 ns clock and
0.100 ns uncertainty **before synthesis**, with 2.000 ns maximum / 0.500 ns
minimum delay on observation outputs. There are no external data inputs in
this fixture. `constraints/timing_harness_context.xdc` locates its real BUFG.
Observation output ports are virtual, not board pins. The parent SoC must
be implemented and timed again with its actual clock and interfaces.

`tools/synth_ps256.tcl` performs constrained synthesis, optimization, placement,
physical optimization and routing on the project part `xc7z020clg400-1`.
It checks the worst routed setup and hold paths in this fixture and requires eight RAMB
primitives. Reports/checkpoints are written to `build/ps256_timing/`.

From PowerShell in `D:\RTL_PROJECT`:

```powershell
& 'F:\Xilinx\Vivado\2023.2\bin\vivado.bat' -mode batch -source tools/synth_ps256.tcl -log build/ps256_timing.log -journal build/ps256_timing.jou
```

After a completed run, inspect:

| File under `build/ps256_timing/` | Evidence |
|---|---|
| `timing_synth.rpt` | Constrained post-synthesis estimate |
| `timing_placed.rpt` | Placement-stage setup and hold |
| `timing_routed.rpt` | Routed setup/hold and pulse-width summary |
| `setup_paths.rpt`, `hold_paths.rpt` | Detailed worst paths |
| `check_timing.rpt` | Clock and input/output constraint coverage |
| `route_status.rpt`, `drc.rpt` | Routing completion and design rules |
| `applied_constraints.xdc` | Constraints actually written from the design |
| `timing_result.json` | Machine-readable routed slacks and BRAM count |
| `source_manifest.json` | Source hashes recorded for this implementation run |
| `utilization_routed.rpt`, `utilization_hierarchical.rpt` | Fixture total and separate core resources |
| `core_routed.dcp` | Routed core with registered timing context |

This is physical implementation of the internal core out of context. It is
not a pin-constrained board design, a bitstream, or closure of the future
RV32/AER/AXI/DMA/UART system. Other parts must not be treated as complete
because the core passes timing.

To inspect the routed result in Vivado, close the active design and enter:

```tcl
open_checkpoint D:/RTL_PROJECT/build/ps256_timing/core_routed.dcp
report_timing_summary -delay_type min_max -report_unconstrained
report_timing -delay_type max -max_paths 10
report_timing -delay_type min -max_paths 10
```

Both setup WNS and hold WHS must be nonnegative, with zero failing endpoints.
Check clock/constraint coverage and routing completion as well as the slacks.
Setup slack measures how much margin data has to arrive before the capture
edge. Hold slack measures the margin for keeping the old data stable after
that edge. TNS and THS are totals of violations and should both be zero.

## Measured implementation result (2026-11-10)

Vivado 2023.2 completed synthesis, placement and routing on
`xc7z020clg400-1` in the registered context described above:

| Stage | Setup WNS (ns) | Hold WHS (ns) |
|---|---:|---:|
| Synthesis estimate | +1.850 | +0.032 |
| Placed / physically optimized | +0.601 | -0.033 |
| Routed | **+0.508** | **+0.032** |

The routed report has zero setup and hold failing endpoints, TNS = 0 and
THS = 0. The router repaired the short hold paths through physical routing.
The target remained 10 ns with 0.100 ns uncertainty throughout; no false-path
or multicycle exceptions were applied. The routed checkpoint is
`build/ps256_timing/core_routed.dcp`.

All 21,002 routable nets are fully routed, with zero routing errors. Clock,
I/O-delay and internal-endpoint constraint coverage checks all report zero
problems. The DRC report contains no errors and one `ZPS7-1` warning because
this standalone core fixture does not instantiate the Zynq processing system.
The external clock/observation ports remain virtual boundaries; the internal
BUFG clock network and all core data interfaces are physically routed.

| Routed scope | LUTs | Flip-flops | RAMB36E1 | DSPs |
|---|---:|---:|---:|---:|
| Production `lif_snn_core` | 8,462 | 17,623 | 8 | 0 |
| Timing fixture overhead | 1 | 631 | 0 | 0 |
| Total implementation | 8,463 | 18,254 | 8 | 0 |

The fixture also contains one BUFG. Hierarchical utilization separates its
overhead from core resources; none of these counts includes future AER/SoC
peripherals or the classifier's separate class readout block.

## Functional checks

All 11 unit/directed tests passed. The 256-state population stress and both
the 256-neuron and four-neuron recurrent ring regressions passed. Icarus and
Vivado XSim each matched Python for all 20 classifier images and 40,960 state
updates. Source hashes in both simulator records match the implemented RTL.
Only FPGA clock latency changed. Reproduce with:

```powershell
python -m unittest discover -s tests -v
python -m tools.run_population_rtl_check --neurons 256 --steps 64
python -m tools.run_snn_core_check --neurons 256 --transactions 4
python -m tools.run_mnist_rtl_check
python -m tools.run_mnist_rtl_check --simulator xsim
```

The directed pipeline test checks that reads do not prematurely update a
state, each neuron commits once, and reset cancels the pending write. The
classifier compares all 256 membranes/refractory counters/spike bits over
160 ticks (40,960 state updates); its 20-image accuracy remains 17/20 (85%).

## Documentation basis

AMD's [non-project constraint flow](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Non-Project-Flows)
places timing XDC before synthesis. Its [out-of-context constraint guidance](https://docs.amd.com/r/2023.1-English/ug905-vivado-hierarchical-design/Out-of-Context-Design-Constraints)
describes the clock/context assumptions used for this core-only experiment.
