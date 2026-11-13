# RV32 / AXI4-Lite host control

The host path consists of a real PicoRV32 RV32I processor, an AXI4-Lite
endpoint, a 64 KiB synchronous boot RAM and the existing rate/AER/256-state
SNN. `lif_rv32_soc` is the integrated top. `lif_axi_lite` exposes the same
SNN registers as a standalone peripheral for an external AXI master.

The target board is the **Zybo Z7-10**, FPGA `xc7z010clg400-1`, confirmed by
the user. Earlier Z7-20-part reports do not establish fit/timing on this
smaller device. The 256 stored LIF states and 256x256 synapse table are
preserved. This document describes processor-driven loading and inference.
The subsequent board wrapper adds clock/reset/pins, image stepping, LEDs,
ILA snapshots and a Pmod UART raster; see `BOARD_WRAPPER.md` and
`ZYBO_Z7_10_DEMO_TUTORIAL.html`. DMA and output interrupt integration remain.

The Z7-10 placement trial exposed slice-packing pressure from independently
enabled registers, even though aggregate LUT/FF counts were below capacity.
The temporary 256x32-bit synaptic-current buffer now uses synchronous RAM
with resettable valid bits. Invalid entries read as zero, including after
reset, without resetting the RAM. All 256 membrane/refractory states remain
present, and READ/CALCULATE/WRITE still takes three clocks per neuron.

## Bus contract and register map

One outstanding read and one outstanding write can coexist. AW and W are
buffered independently: address-first, data-first and simultaneous arrivals
work. B/R responses and payloads are registered and held until accepted.
The backend accepts each write/read once and publishes one response. Sample
clear is a registered command: its B response acknowledges acceptance, and
BUSY covers the following clock in which the network is cleared. Wait for
BUSY=0 before configuring or starting a new image. A synchronous active-low
reset cancels partial requests and held
responses. All signals use one clock; AWPROT/ARPROT have no protection effect.

The peripheral occupies `0x40000000..0x400fffff`. Every register/window entry
is a **four-byte aligned 32-bit word**. Unsupported addresses return DECERR
(3), misaligned accesses and rejected busy commands return SLVERR (2).
Reads and writes may progress concurrently; no ordering is guaranteed
between the two directions. Read a write's result after accepting its B
response. CPU firmware does so naturally with its serialized memory interface.

| Offset | Access | Meaning |
|---|---|---|
| `0x000` | R | ID `0x534e4e32` |
| `0x004` | W | Command: 1=start one tick; 2=clear one image; 0=no operation |
| `0x008` | R | Status: busy[0], tick-ready[1], clear-ready[2], output-valid[3], sticky tick-done[4], sticky frame-done[5] |
| `0x00c` | RW | Sticky completion flags: tick[0], frame[1]; write one to clear |
| `0x010` | RW | Threshold[15:0] |
| `0x014` | RW | Reset membrane value[15:0] |
| `0x018` | RW | Leak enable[8], shift[4:0] |
| `0x01c` | RW | Refractory period[15:0] |
| `0x020` | RW | State-read address[7:0] |
| `0x024` | R | Selected state's `{refractory[15:0], membrane[15:0]}`; idle only |
| `0x028` | R | Pop one output packet: valid[31], END[8], address[7:0]; zero if empty |
| `0x02c` | R | Peek at that packet without removing it |
| `0x030` | R | Completed calculation count |
| `0x034` | R | Drained output-frame count |
| `0x038` | R | Accepted weight-write count |
| `0x03c` | R | Accepted intensity-write count |
| `0x040` | R | Consumed output-spike count, excluding END markers |
| `0x044` | RW | Software result mailbox |
| `0x01000..0x40ffc` | W | Weight `[source][destination]`, address=`0x1000+4*(source*256+destination)` |
| `0x80000..0x803fc` | W | Source intensity, address=`0x80000+4*source` |

Configuration registers implement byte strobes; reserved bits read zero.
Weights use the low nibble of byte 0, preserving signed two's-complement
four-bit values. Intensities use byte 0. Their upper byte lanes are ignored;
without WSTRB[0], these writes have no effect. Commands and flag clearing
also require WSTRB[0]; reserved command bits in the low byte are rejected.
Start+clear together is an error. Configuration/weight/intensity/state-address
writes and sample clear/start are rejected while busy. The mailbox and
completion-flag clearing remain accessible. Zero-strobe writes to writable
registers do nothing. Unsupported registers still return an error.

A packet is removed when the read backend executes, and its complete value
is retained in the AXI R register while RREADY is low. Repeated reads of an
empty queue return zero. A stalled R response cannot remove multiple packets.
If reset interrupts a response, that transaction is canceled along with the
network's in-flight state. Sample clear preserves weights and intensities,
resets the image's encoder phases and LIF/recurrence state, and does not
reset the host's cumulative counters. A new completion wins over simultaneous
write-one-to-clear of its flag. Thirty-two-bit counters wrap naturally.

## Processor and boot program

The vendored processor is [PicoRV32](https://github.com/YosysHQ/picorv32),
pinned to commit `ef203c2b0a3fb793280f5114941416c425c5b461` with its original
license notice. It is a third-party host CPU; the LIF datapath remains our
existing RTL. This configuration disables M, compressed instructions and
interrupts. The upstream CPU adapter has no response-code inputs; our SoC
latches any non-OKAY AXI response as `bus_fault` and holds the CPU in reset.
Successful firmware ends with EBREAK after writing its success mailbox.

`firmware/snn_boot.S` is readable RV32I assembly. The small, dependency-free
assembler in `tools/rv32_assemble.py` supports its explicit instruction subset;
it is not a general C toolchain. The resulting words execute on the actual
vendored RTL processor. Firmware performs every SNN load and command:

1. Check the device ID, unpack and write all 65,536 signed-nibble weights.
2. Configure LIF parameters; clear each image and load all 256 intensities.
3. Start eight ticks per image, draining every output packet through AXI reads.
4. Read all 256 membrane/refractory states after every tick. Compute the class
   from states 246..255 with the existing largest-membrane / first-tie rule.
5. Store each computed class in RAM, compare it with the Python self-test
   prediction, write `0x600d600d` on success, then stop with EBREAK.

Expected predictions are used only for the final self-test comparison; they
do not select the inferred class. An error writes `0xdead0001`. The testbench
independently checks every state and packet, so a false software success
marker is insufficient to pass.

| Boot RAM region | Content |
|---|---|
| `0x0000..0x0fff` | RV32I program |
| `0x1000..0x8fff` | Two weights per byte, lower-addressed weight in low nibble |
| `0x9000..0xa3ff` | Up to 20 images, 256 intensity bytes per image |
| `0xb000...` | Python self-test predictions, one word per image |
| `0xc000...` | Classes computed by firmware, one word per image |

RAM uses synchronous reads and byte-write enables without a reset loop.
Reset preserves the RAM and learned weight/intensity memories; firmware
restarts and reloads the entire SNN table. The boot image embeds the saved
learned checkpoint for the MNIST scenario; it is not retrained by the CPU.

## Reproduce

```powershell
python -m tools.run_axi_check
python -m tools.run_axi_check --simulator xsim
python -m tools.run_rv32_check
python -m tools.run_rv32_check --simulator xsim
python -m tools.run_rv32_check --scenario mnist
python -m tools.run_rv32_check --scenario mnist --simulator xsim
```

`--generate-only` produces the boot RAM image and reference files without
running a simulator. The stress case uses three grayscale images and
signed recurrent weights; MNIST reuses the trained 20-image subset, exact
preprocessing and 256-state mapping. Accuracy remains a selected-subset
measurement, not full-test-set or board accuracy. See `RATE_ENCODER.md`.

AXI protocol checks also exercise full output queues and 258 exactly-once
packet pops. RV32 integration compares all CPU weight/intensity writes,
encoded packets, emitted packets, state readbacks and final predictions.
Only boot RAM is initialized by the testbench; there are no direct SNN
weight/configuration/input writes bypassing the processor.

| Completed check on the current RAM-buffer revision | Result |
|---|---|
| Existing unit suite, including reset invalidation of unwritten currents | 17 passed |
| AXI peripheral protocol/inference checks, Icarus and Vivado XSim | Both passed |
| Real CPU stress, Icarus and Vivado XSim | Both passed: 24 ticks, 6,144 state reads |
| Real CPU trained MNIST, Vivado XSim | Passed: 20 images, 160 ticks, 40,960 state reads, all predictions equal to Python |
| Generated-project Vivado GUI flow, CPU stress | Passed |

The learned subset remains 17/20 correct (85%). Matching Python predictions
does not mean that all 20 predictions match the ground-truth labels.

Evidence is generated under `build/axi_protocol/`, `build/rv32_network/`
and `build/rv32_mnist/`. Receipts bind RTL, firmware, generation code and
reference/vector hashes. CPU simulation takes longer than direct RTL tests
because it includes instruction fetches and all loading/polling instructions.

For the GUI, generate both the learned and stress vectors, then create a
dedicated project in a new Vivado session using the script below. This avoids depending on the
simulation selection saved in an existing GUI session:

```tcl
source tools/create_rv32_project.tcl
launch_simulation
run all
```

Inspect `dut.cpu`, `dut.endpoint`, `dut.registers`, `dut.software_result`,
`dut.bus_fault` and `dut.registers.core`. The CPU trap after success is
intentional; an earlier trap or bus fault fails the regression.

The generated project is `build/rv32_vivado/lif_rv32.xpr`, targets the Z7-10,
and selects the learned boot image for synthesis. Set environment variable
`SNN_SCENARIO=stress` before creating it to select stress simulation instead.
`tools/check_rv32_project.tcl` checks that generated project and runs the
stress simulation through Vivado's `launch_simulation` flow. The root
`RTL_PROJECT.xpr` includes the new sources, but an open GUI may retain an
older selected testbench; use the matching generated configuration script
when selecting a scenario there.

## Implementation scope

The measurements below record the preceding `3d19e6b` host milestone.
The board wrapper and its registered sample-clear command have separate
implementation evidence in `verification/zybo_demo/`; see `BOARD_WRAPPER.md`.

`tools/synth_rv32_z710.tcl` implements the full processor/RAM/AXI/SNN in
a registered timing fixture on **xc7z010clg400-1**, with a 100 MHz clock,
0.100 ns uncertainty, and no false-path or multicycle exceptions. It uses
the generated learned `build/rv32_mnist/firmware.hex` image. Setup, hold,
coverage, combinational loops, resource use and synapse BRAM mapping must
pass before claiming closure. Results are under `build/rv32_z710_timing/`.
This fixture has a real BUFG and registered reset/observation context;
it does not supply the Zybo's physical clock/reset/pin wrapper or a bitstream.
Historical xc7z020 timing numbers are retained under their original labels.

The completed routed run passes **setup +0.299 ns, hold +0.024 ns** with
zero failing endpoints, zero unconstrained internal endpoints, zero
combinational loops and no timing exceptions. All 18,255 routable nets are
fully routed. The SoC uses **9,582 LUTs, 13,550 flip-flops, 24 RAMB36E1
plus one RAMB18E1 and zero DSPs**. The fixture adds one LUT, 45 flip-flops
and one BUFG. Eight RAMB36E1 blocks are the unchanged synapse table,
16 are boot RAM, and the RAMB18E1 stores temporary currents. DRC has two
context warnings: no PS7 instance and virtual observation outputs without
external routed loads. These results establish registered-context closure
on the Z7-10 part, not physical-board validation.

The current spike transport is processor polling. The PS-required DMA,
output-spike interrupt, physical UART demonstration, composed system formal proofs and
paper optimization comparison remain outstanding. The next hardware step
is the first programmed-board comparison using the wrapper/tutorial now
provided in `BOARD_WRAPPER.md` and `ZYBO_Z7_10_DEMO_TUTORIAL.html`.

References: [Arm AXI specification](https://documentation-service.arm.com/static/67ab5a186dbc975ccea91734),
[Digilent Zybo Z7 reference manual](https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf).
