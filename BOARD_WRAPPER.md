# Zybo Z7-10 board wrapper

For the deployment instructions use `ZYBO_Z7_10_DEMO_TUTORIAL.html` or its
Markdown source. This file describes the implementation for review.

`rtl/board/zybo_z710_top.v` instantiates the existing full-population
`lif_rv32_soc` with optional demo backpressure enabled. The default SoC
parameter `ENABLE_DEMO=0` preserves the standalone host interface behavior.
The board build sets it to one and connects the reporter's run signal.

The AXI backend registers the sample-clear command before driving the wide
network reset and readiness logic. BUSY includes that one clear cycle, so
configuration writes cannot be accepted while clear is executing. This
breaks the long AXI address-decode-to-reset-to-BRAM/probe path; it does not
change the shared neuron's read/calculate/write schedule or numerical model.

`zybo_z710_clock.v` buffers K17's external 125 MHz clock, multiplies by eight
and divides by ten with an MMCME2_BASE (1000 MHz VCO, 100 MHz output). E17
holds Ethernet PHY reset high, preserving its reference clock. No PS-generated
clock or ARM initialization is needed. Two-stage button/lock synchronizers
precede a synchronous startup/reset counter and a registered reset release.
BTN1 is debounced for 10 ms at
100 MHz; BTN0 holds application reset until released. BTN0 restarts software
without changing the boot instruction/weight/intensity image in block RAM.

`snn_demo_reporter.v` begins with the CPU backend paused. On BTN1 it admits
AXI backend reads/writes, observes actual input and output handshakes, and
records all output-state reads from addresses 246–255. It detects the CPU's
class store at RAM address `0xc000 + 4*sample`. That transaction commits
exactly once; subsequent backend transactions stall while the UART drains.
Responses already accepted by the endpoint are allowed to complete. Clocks
and the SNN state machine are not gated. A subsequent debounced press resumes
the CPU's Python self-check and next inference. After the final report the
CPU automatically resumes its last comparison, writes the success/failure
mailbox and executes EBREAK. The original RV32I program is unchanged.

The reporter's 8192×16 true dual-port RAM holds records of the form
`{3'b0, direction, tick[2:0], packet[8:0]}`. Input and output events may arrive
in the same clock; two distinct locations are written. Port A becomes a
synchronous read port only during reporting, when the CPU is paused and the
completed image cannot produce more packets. The RAM has no reset loop;
reset/next-image clears only its count and tick tags. Capacity overflow is
an explicit sticky error. A maximum eight-tick image can produce at most
4112 input-plus-output records, including end markers, below its capacity.

The serial output is 115200 8N1 (100 MHz / 868 = 115207.4 baud). It emits a
class/scores record followed by real captured input/output packets. It is a
buffered event raster, not a measurement of wall-clock arrival spacing.
Reports use sample indices 00–13 for the default twenty images. Packet 100
terminates each tick; it is never counted as a spike. No expected score is
used as the displayed score. UART output is always drained, even without an
adapter, so pause behavior and ILA snapshots do not depend on adapter presence.

ILA captures the actual predicted digit, all ten 16-bit scores, sample index,
snapshot pulse/valid, error, wait/transmit and completion flags. `scores[15:0]`
is digit zero and `scores[159:144]` is digit nine. The snapshot pulse occurs
one cycle after the accepted class store, when all corresponding data are
stable. This is an inference-result snapshot, not an ILA dump of every tick
and every neuron state. The full simulation scoreboard separately checks
all 256 membrane/refractory states on every tick. The build generates an
HDL-instantiated ILA with 1024 samples and one input pipeline stage on every
probe. Only `snapshot_pulse` is configured as a trigger; the other eight
probes are data only. This avoids wide score-comparison trigger logic.

`constraints/zybo_z710_demo.xdc` gives every board port a location and I/O
standard and defines the 125 MHz input clock. The MMCM output clock is derived
by Vivado. `tools/zybo_demo_context.tcl` applies exact first-stage CDC input
exceptions and clock-to-pin bounds for unclocked LED/UART receivers. It does
not exempt any neuron, processor, AXI, BRAM or register-to-register path.
AMD's inserted ILA/debug hub additionally carries its own debug/JTAG constraints.
The Z7-10's slice packing also requires attention to control sets. The build
uses `ExploreWithRemap` logic optimization and requests `CONTROL_SET_REMAP
ENABLE` for the encoder's 2048 phase flip-flops. That optional property can
implement enables as data feedback muxes; see
[AMD UG912](https://docs.amd.com/r/2023.2-English/ug912-vivado-properties/CONTROL_SET_REMAP).
The current run's control-set reduction pass created and removed zero cells;
its pre-placement report retains 986 control sets. The log and
`control_sets.rpt` record the actual mapping. All 256 LIF states remain intact.
The build checks routed setup/hold and clock/internal-endpoint coverage before
generating a bitstream. `opt_design` inserts the debug hub for the instantiated
ILA, following AMD UG908. Board pin
assignments follow the Digilent master XDC; links are in the tutorial.

Optional synthesis reuse checks HDL, pin/clock constraints, boot bytes,
sample/ILA configuration, the synthesis/IP recipe, and the checkpoint's
SHA-256. Implementation-only directive changes can reuse a verified netlist.
Each fresh synthesis seals that provenance after writing its checkpoint;
failed synthesis cannot bind an older checkpoint to new inputs. Final export
also checks that sources and the synthesis checkpoint stayed unchanged.

The trained demo uses preloaded MNIST inputs with the saved signed four-bit
weights and unchanged preprocessing. Its class comes from final membranes
and its output event stream contains only END markers for this subset. The
separate signed-ring stress scenario supplies nonzero output spikes on the
same 256-state architecture; it is not digit-classification accuracy evidence.

Verification includes concurrent event capture, UART framing and content,
debounce/reset/MMCM simulation, actual CPU writes/state reads with image
pauses, capture-checker mismatch detection, and real board implementation.
Receipts must distinguish these from physical FPGA captures, which require
a connected board and the user's demonstration procedure.

The learned-demo release is routed at 100 MHz with setup +0.017 ns and hold
+0.028 ns. It uses 11,089 LUTs, 16,101 FFs, 33 RAMB36E1, one RAMB18E1 and no
DSPs; 4,394/4,400 slices are occupied. DRC retains five warnings (AMD debug
LUT pins/unloaded signals and no PS7), with no errors. The reports, source
and firmware bindings are in `verification/zybo_demo/board_timing/`.
These measurements include ILA and the UART raster buffer. Physical-board
operation remains unverified, and DMA/IRQ additions require new fit/timing.
