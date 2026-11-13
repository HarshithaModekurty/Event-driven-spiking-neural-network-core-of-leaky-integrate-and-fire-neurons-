# Zybo Z7-10 learned-demo implementation

Vivado 2023.2 implements the complete `zybo_z710_top` on
`xc7z010clg400-1`, including all 256 LIF states, RV32/AXI, boot/weight RAM,
the 8192-record UART raster buffer and 1024-sample ILA. This is an
implementation snapshot, not a physical-board measurement.

| Check | Result |
| --- | --- |
| Core clock | 100 MHz, derived from K17's 125 MHz input |
| Setup / hold slack | +0.017 ns / +0.028 ns |
| Pulse-width slack | +2.000 ns |
| Failing setup/hold endpoints | 0 / 0 |
| Unclocked / unconstrained internal endpoints / combinational loops | 0 / 0 / 0 |
| LUT / FF / DSP | 11,089 / 16,101 / 0 |
| RAMB36E1 / RAMB18E1 | 33 / 1; eight RAMB36E1 are synapses |
| Occupied slices | 4,394 / 4,400 (99.86%) |
| Debug bus-skew constraints | All four pass; minimum slack +8.741 ns |
| DRC | 0 errors, 5 warnings retained |

The warnings concern three unused LUT inputs in AMD's debug hub, unloaded
debug signals, and the absent PS7 cell in this PL-only design. Their original
severities remain in `drc.rpt`. Clocked CDC crossings reported here are safe;
the asynchronous input synchronizers and their exact exceptions are also
described in `BOARD_WRAPPER.md`. No CPU/neuron setup or hold path is removed
by an exception.

`baseline/` preserves the earlier -0.368 ns setup failure before the AXI
sample-clear command was registered. Its copied host RTL and build script
match its historical input hashes. `ExploreWithRemap` subsequently resolves
packing of the registered-clear design. The optional encoder-enable remap
request changed zero cells in this run; `control_sets.rpt` reports 986 sets.

`build_manifest.json` binds current sources and the `.bit`/`.ltx` hashes.
`synthesis_manifest.json` also binds the reused synthesis checkpoint and
its complete synthesis/IP recipe. The original cold-synthesis script is
preserved as `synthesis_build_script.tcl`; its synthesis recipe matches the
current builder. Implementation-only settings changed after that boundary.
`release_checks.json` records artifact/source checks, the CPU-tested ROM
match, and inspection of the actual ILA names and 160-bit score ordering.
Configuration text files are copied here; the large bitstream/checkpoints
remain under `build/zybo_demo/mnist/`.

The ROM is the same 20-image learned ROM exercised by the full CPU/RTL
regression. Its input, class and all neuron-state comparisons pass. The
separate stress RTL regression passes, but a stress board bitstream was not
built in this run. Further DMA/IRQ integration needs fresh packing/timing
validation; spare aggregate LUT/FF totals alone are insufficient fit evidence.
