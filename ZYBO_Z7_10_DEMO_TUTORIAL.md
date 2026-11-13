# Deploy and demonstrate the SNN on a Zybo Z7-10

This guide takes you from Python reference results to RTL simulation and then
to a real FPGA demonstration. You can start with **the board, a USB data cable,
LEDs and Vivado ILA**. An extra UART adapter is optional for this first test.

The target is **Zybo Z7-10, xc7z010clg400-1**, using Vivado **2023.2**. The
physical-board test is something you will perform; simulation and a generated
bitstream alone do not establish that your board has run correctly. See the
latest validation evidence in `verification/zybo_demo/` when available.

## 1. What you will show your professor

Put these four things side by side:

| Evidence | Where you see it | What it means |
| --- | --- | --- |
| Actual handwritten image and label | Generated `images.html` on your laptop | The digit the dataset says is correct |
| Python prediction and ten scores | Same page and `reference.json` | What the saved trained model calculates |
| RTL simulation result | XSim log and decoded simulated UART capture | What the actual CPU and SNN RTL calculate in simulation |
| Physical FPGA prediction and scores | Four LEDs and ILA, optionally UART | What the programmed device calculates |

Compare Python with RTL/FPGA to check **implementation agreement**. Compare
the predicted digit with the dataset label to measure **classification accuracy**.
The selected 20-image set currently scores **17/20 (85%)** in Python. Three
images are misclassified; matching those same predictions in hardware is still
the expected behavior. This small fixed subset is not a full MNIST test-set score.

## 2. What is inside the FPGA

The design still has **256 stored LIF neuron states**, each with 16-bit membrane
and refractory values. A shared calculation unit visits them one at a time,
using read, calculate and write phases. The ten output neurons are states
**246–255**, included within the 256.

The saved offline-trained weights are loaded by a real RV32 processor through
AXI4-Lite into the 256×256 signed four-bit synapse memory. Python and RTL use
the same image preprocessing, weights, eight time steps and arithmetic. This
board wrapper adds observation and controls; it does not retrain the network.

The image is not a JPEG file sent into a neuron. Python converts the original
28×28 image into the existing trained 15×15 binary features: addresses 0–224.
Address 225 supplies a bias; remaining intensities are zero. These 256 byte
values are included in the boot image. The CPU writes them into the hardware
rate encoder, which produces address events for the SNN. In this first demo,
the images are **preloaded when building the bitstream**. There is no live
camera, handwritten drawing input or UART image upload yet.

The predicted class is the index of the largest final membrane value among
states 246–255; a tie chooses the lowest digit. The CPU computes it from RTL
state readbacks and writes its result into RAM. The wrapper observes that
actual write and the actual scores. The expected Python classes in boot RAM
are used afterward for a self-check, not to choose the displayed class.

## 3. What to have ready

- Zybo Z7-10 and a data-capable micro-USB cable for the board's **J12 USB
  JTAG/UART connector**. A charge-only cable cannot program the board.
- Vivado 2023.2 with Zynq-7000 device support and cable drivers installed.
- Python 3.10 or newer, the repository and the saved trained checkpoint/data used by the
  existing MNIST scripts. `prepare` reuses the checkpoint; it does not request
  retraining. On a fresh checkout, follow the dataset/checkpoint setup in
  `MNIST_RTL_VERIFICATION.md` first.
- Optional later: a **3.3 V TTL USB-to-UART adapter**, or a correctly wired
  Pmod USBUART and jumper wires.

The board's built-in USB UART is wired to the **ARM processor's MIO pins**.
Our RV32 processor is implemented in the FPGA fabric. Its UART output therefore
uses **Pmod JC pin 1**, not that built-in COM port. J12 still provides JTAG
programming and ILA without an extra adapter. The ARM does not need Vitis,
Linux or an ARM application for this PL-only demonstration.

Board power, jumper positions and connector numbering below follow the
[Digilent Zybo Z7 reference manual](https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf).
Use the labels on your board and check that manual if your revision differs.

## 4. Generate the images and Python reference

Open PowerShell in the folder containing `rtl`, `tools`, `firmware` and
`golden_model`. In the current workspace that is `D:\RTL_PROJECT`:

```powershell
Set-Location D:\RTL_PROJECT
if (!(Test-Path build/mnist256/trained_weights.json)) {
    New-Item -ItemType Directory -Force build/mnist256 | Out-Null
    Copy-Item verification/mnist256/trained_weights.json build/mnist256/trained_weights.json
}
python -m tools.board_demo prepare --scenario mnist
```

The conditional copy restores the committed trained checkpoint on a fresh
checkout and leaves an existing checkpoint intact. Keep this step: the older
exporter trains a model automatically if no checkpoint exists. With the saved
checkpoint present, the log must say `Reusing saved offline-trained weights.`

It prints the Python predictions and makes:

| File under `build/board_demo/mnist/` | Purpose |
| --- | --- |
| `images.html` | Actual original digits, labels and Python predictions/scores |
| `reference.json` | Python scores and exact input/output event packets |
| `firmware.hex` | RV32 instructions, packed learned weights and input intensities |
| `states.hex` | Every Python neuron state after each tick |
| `predictions.hex` | Expected final classes used by the CPU self-check |

Open `images.html` in a browser. It intentionally leaves the FPGA result for
you to observe. UART/ILA sample indices start at **00** and are hexadecimal;
sample 0A means the eleventh image. The original MNIST dataset index is shown
in `reference.json`, which is different from this demonstration sequence number.

For the first sample, the actual label is **8**, but Python predicts **5**.
The expected score vector is:

```text
digit:    0  1  2  3   4   5  6  7   8   9
score:    0  0  8  0  16  72  0  0  24  40
```

Do not change a label or replace a result to make these agree.

## 5. Run the RTL comparison before programming

```powershell
python -m tools.run_board_demo_check --scenario mnist
```

This invokes Vivado XSim through `F:/Xilinx/Vivado/2023.2/bin` by default.
If Vivado is elsewhere, add `--vivado-bin "C:/your/path/Vivado/2023.2/bin"`.
This full CPU simulation can take several to tens of minutes; its log may
stay at `run -all` while it works. It runs the real RV32 instructions, checks all
65,536 AXI weight writes, 160 ticks, 40,960 membrane/refractory state readbacks
and the input/output event streams. It also pauses between images and decodes
the actual UART TX waveform. The UART is accelerated to four clocks per bit
in simulation; the bitstream uses 868 clocks per bit at 100 MHz, about 115200 baud.

Look for both:

```text
PASS: board UART/LED/ILA snapshot flow, real RV32/AXI boot ...
PASS sample 00: class=5, ten scores and all input/output packets match Python ...
```

The decoded **simulated** serial output is `build/board_demo/mnist/uart_capture.txt`.
It is not a physical FPGA capture. You can recheck it with:

```powershell
python -m tools.board_demo verify --scenario mnist --capture build/board_demo/mnist/uart_capture.txt
```

For lower-level checks:

```powershell
python -m unittest discover -s tests -v
python -m tools.check_board_io
```

The second command uses the actual AMD MMCM simulation model to check
125-to-100 MHz conversion, startup reset, button debounce and reset/restart.
Its Vivado installation path is currently set in `tools/check_board_io.py`.
The optional unit suite also needs Icarus Verilog (`iverilog` and `vvp`) on
PATH. The main board-demo comparison uses Vivado XSim.

## 6. Build a board bitstream with ILA

Run this from PowerShell, changing the Vivado path if needed:

```powershell
$env:SNN_PYTHON=(Get-Command python).Source
& 'F:/Xilinx/Vivado/2023.2/bin/vivado.bat' -mode batch -source tools/build_zybo_demo.tcl -log build/zybo_demo_build.log -journal build/zybo_demo_build.jou
```

Alternatively, in the Vivado Tcl Console:

```tcl
cd D:/RTL_PROJECT
set ::env(SNN_PYTHON) C:/msys64/mingw64/bin/python.exe
source tools/build_zybo_demo.tcl
```

The Tcl example gives this computer's Python path. Replace it with your own
Python 3.10+ executable if using another computer. The PowerShell command above
selects it automatically before Vivado changes its process environment.

The script creates a separate board project under `build/zybo_demo/mnist/`.
You do not need to change the top or simulation settings in the older open
`RTL_PROJECT.xpr`. The top is `zybo_z710_top`; ILA is enabled by default.
Each build creates a new project directory so an open older project does not
need to be overwritten. Allow tens of minutes for synthesis and routing on
this computer; wait for the final PASS message.

The design uses the board's 125 MHz PHY clock at K17 and an MMCM to make
100 MHz. The wrapper holds PHY reset at E17 high so that reference clock is
available. The board-authored CDC exceptions cover asynchronous button/lock
synchronizer inputs; AMD's ILA also supplies its own debug/JTAG constraints.
LED/UART propagation is bounded separately. No false path or multicycle
exception removes a CPU or neuron calculation from timing checks.

The build must finish with `PASS: board bitstream ...` and produce:

```text
build/zybo_demo/mnist/zybo_demo.bit
build/zybo_demo/mnist/zybo_demo.ltx
build/zybo_demo/mnist/result.json
build/zybo_demo/mnist/timing.rpt
build/zybo_demo/mnist/utilization.rpt
build/zybo_demo/mnist/drc.rpt
```

Check that `result.json` is from your successful run, identifies `xc7z010clg400-1`,
and has nonnegative setup and hold slack. An old bitstream left after a failed
build is not evidence that the new build passed. Keep `.bit` and `.ltx` together
from the same successful run. The `.ltx` tells Vivado how to interpret the ILA probes.

The saved learned-demo build from 13 November 2026 passes 100 MHz with
**+0.017 ns setup** and **+0.028 ns hold** slack. Its reports are preserved in
`verification/zybo_demo/board_timing/`. This confirms implementation timing;
your programmed-board measurements are still required.

## 7. Connect and program the board

1. With power off, set the boot jumper **JP5 to JTAG** using the board's
   printed legend. This prevents an SD-card/Linux application from starting
   and reconfiguring the chip during this demonstration.
2. Select the intended power source with **JP6**. For USB power use its USB
   position; if the board resets or power is unstable, use a suitable regulated
   supply as specified by Digilent and select WALL. Do not guess a supply voltage.
3. Connect the laptop to **J12** with the data cable. Switch **SW4 on** and
   check that the **PGOOD** LED is lit.
4. In Vivado choose **Open Hardware Manager → Open Target → Auto Connect**.
   Expand the target. You should see an `xc7z010` FPGA device; an ARM DAP entry
   may also appear. Select the FPGA.
5. Right-click it → **Program Device**. Choose `zybo_demo.bit` and the matching
   `zybo_demo.ltx`. Program it. Check the programming log and DONE indication.
6. The application should wait for BTN1. Its RGB LED6 should be blue, with
   the four digit LEDs initially off. DONE means configured; it does not mean
   all predictions have been checked.

This is volatile JTAG programming. After power off or PROGB you must program
the board again. Flash/SD boot installation is outside this first demonstration.
Use **BTN0** for application reset, not PROGB or PS-SRST.

## 8. Demonstrate the digit with LEDs

**BTN0 restarts the application. BTN1 starts the first image or advances to
the next image after the previous one is ready.** Press and release BTN1;
holding it does not repeatedly advance.

The RGB LED6 has these meanings:

| Color | Meaning |
| --- | --- |
| Blue | Waiting for the first start, calculating, or transmitting a raster |
| Green | Current image's report is finished and the next BTN1 press can be accepted; also stays green after successful completion of all images |
| Red | Bus, firmware self-check or capture error; stop and inspect/reset |

The predicted digit appears on **LD3 LD2 LD1 LD0** as a binary number.
LD0 is the least significant bit. Read LEDs by their printed numbers, not by
assuming left/right orientation.

| Digit | LD3 LD2 LD1 LD0 |
| --- | --- |
| 0 | 0000 |
| 1 | 0001 |
| 2 | 0010 |
| 3 | 0011 |
| 4 | 0100 |
| 5 | 0101 |
| 6 | 0110 |
| 7 | 0111 |
| 8 | 1000 |
| 9 | 1001 |

For the first sample expect **0101**, meaning predicted digit 5. Open the
corresponding actual image on the laptop and explain that its ground truth is 8.
After each image, wait for green before pressing BTN1 again. Raster transmission
continues even without an adapter connected; wait for it to finish. A press
during transmission is ignored. After the last sample, BTN0 restarts the set.

The second image, sample **01**, has actual digit **9** and Python prediction
**9**. Its expected LED pattern is **1001**. This gives you a correctly
classified example immediately after the first sample's misclassification.

## 9. Use ILA to prove the FPGA calculated the same scores

ILA is a small logic analyzer built into the bitstream. It observes the real
programmed logic through the same JTAG cable; it is separate from XSim.
The system clock keeps running while the CPU pauses between images.
The ILA records 1024 clocks per capture. All probes have the same one-clock
input pipeline, so the pulse and its scores remain aligned. Only
`snapshot_pulse` is a trigger probe; the other signals are recorded as data.

1. In Hardware Manager, refresh the programmed FPGA and open its `demo_ila`.
   If no probes appear, verify that the `.bit` and `.ltx` are the matching pair.
2. Add `snapshot_pulse` to Trigger Setup. Set its condition to **equal 1**.
   This pulse lasts one clock when the actual CPU class write is captured.
3. In the wave window show `sample_index`, `predicted_digit`, `scores`,
   `snapshot_valid`, `error`, `waiting`, `transmitting` and `complete`.
4. Set the trigger position near the middle of the 1024 samples and click
   **Run Trigger**. Then press BTN1. For the first image, press BTN0 first
   if you already ran it; release BTN0, arm the trigger, then press BTN1.
5. At the trigger sample, `snapshot_pulse=1`, `snapshot_valid=1`,
   `sample_index=00`, `predicted_digit=5` and `error=0` should be visible.
   The ten scores should match the first sample in `reference.json`.
6. In the 160-bit `scores` bank, digit 0 is bits **15:0**, digit 1 bits
   **31:16**, continuing to digit 9 at **159:144**. Thus a displayed hex
   bank reads digit 9 at its left end and digit 0 at its right end.
7. Export each capture to CSV, retaining sample indices so you can identify
   which input image was actually measured. Arm again before the next BTN1.

These Hardware Manager Tcl commands export hexadecimal data for the checker:

```tcl
set demo [lindex [get_hw_ilas] 0]
foreach probe [get_hw_probes -of_objects $demo] {
    set_property DISPLAY_RADIX hex $probe
    set_property DISPLAY_AS_ENUM false $probe
}
write_hw_ila_data -force -csv_file D:/RTL_PROJECT/build/board_demo/mnist/fpga_00.csv [upload_hw_ila_data $demo]
```

Then in PowerShell:

```powershell
python -m tools.board_demo verify --scenario mnist --format ila --capture build/board_demo/mnist/fpga_00.csv
```

It checks the actual captured digit and all ten scores. A single capture is
evidence for the sample it contains, not for all 20 images. ILA snapshots
check classes/scores; full input/output packet comparison uses UART or the
RTL simulation described earlier. For reproducible ILA capture controls see
[AMD UG908 HDL debug flow](https://docs.amd.com/r/2023.2-English/ug908-vivado-programming-debugging/HDL-Instantiation-Debug-Probing-Flow-Overview?contentId=PvaLsgRFP80W8zKc2zfSqw)
and the [CSV export command](https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/write_hw_ila_data).

## 10. Add UART later if an adapter is available

Power off before wiring. Use **3.3 V TTL signaling**, not an RS-232 cable or
5 V TX/RX. The pin allocation follows
[Digilent's master XDC](https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Zybo-Z7-Master.xdc).

| Connection | Wire to |
| --- | --- |
| Zybo **JC pin 1** (FPGA V15), RTL TX | Adapter **RX** |
| Zybo JC ground (pin 5 or 11; confirm connector orientation) | Adapter **GND** |
| Adapter TX | Leave disconnected; this demo transmits only |
| Adapter VCC | Leave disconnected when using a separately powered USB-to-UART adapter |

A Pmod USBUART may need its own 3.3 V power connection according to its manual.
Use jumper wires to route the selected FPGA TX to the module's RX input;
plugging a module directly into JC does not guarantee its UART pins line up
with this custom JC1 assignment. Confirm the adapter/module pinout first.

Power the board, connect the adapter to USB, and find its COM number in
Windows Device Manager → Ports. Close other terminal applications using it.
Open a second PowerShell window in the repository and run, replacing COM7:

```powershell
powershell -ExecutionPolicy Bypass -File tools/capture_demo_uart.ps1 -Port COM7 -Output build/board_demo/mnist/fpga_uart.txt -Samples 20
```

It listens at **115200 baud, 8 data bits, no parity, one stop bit, no flow control**.
Start listening **before** BTN0/BTN1. Press BTN1 for every image, waiting for
green each time. The capture ends after all 20 class records and all tick-end
records arrive. Use a new output filename after a reset/retry. Ctrl+C stops
a partial capture; let the current image finish first for a complete per-image
check.

```powershell
python -m tools.board_demo verify --scenario mnist --capture build/board_demo/mnist/fpga_uart.txt
```

For a file containing only complete individual samples, add `--allow-partial`.
The verifier still requires every packet and tick-end for each reported sample.
It checks the class, ten scores, all encoded input packets and all consumed
output packets against Python. It prints the actual label separately.

The text protocol is deliberately readable:

```text
C,00,5,0000,0000,0008,0000,0010,0048,0000,0000,0018,0028
I,00,0,005
I,00,0,100
O,00,0,100
```

`C` means class followed by ten scores. `I`/`O` identify input/output events;
their fields are sample, tick, packet. Numeric fields are hexadecimal.
Packet `000`–`0FF` names a neuron/source address; `100` is **end of tick**,
not a spike. Events are buffered on actual handshakes and sent after inference,
so UART line spacing is transmission time, not neuron firing time. Reconstruct
the raster from the recorded tick/address fields.

The learned classifier has threshold 65535 and uses final membrane scores.
Its current 20 images emit **no output spikes**, just the eight end markers
per image. The input raster is active. An empty output raster is expected;
do not lower the threshold and call the result the same trained model.

## 11. Show nonzero output spikes with a separate stress demonstration

The signed-ring stress scenario exercises recurrent firing/refractory behavior
on the **same 256-state architecture**. Its weights are deterministic test
weights, not learned digit-classification weights. Its numerical class field
is a diagnostic argmax and has no digit-recognition meaning.

```powershell
python -m tools.run_board_demo_check --scenario stress
$env:SNN_SCENARIO='stress'
& 'F:/Xilinx/Vivado/2023.2/bin/vivado.bat' -mode batch -source tools/build_zybo_demo.tcl -log build/zybo_stress_build.log -journal build/zybo_stress_build.jou
Remove-Item Env:SNN_SCENARIO
```

Program the `.bit`/`.ltx` from `build/zybo_demo/stress/` together. Capture three
samples with `-Samples 3` and a new output filename; verify using
`python -m tools.board_demo verify --scenario stress --capture YOUR_CAPTURE.txt`.
To return to digit recognition, program the MNIST pair again. Clearly label
these two demonstrations when presenting them.

## 12. A short presentation sequence

1. Show the PS screenshot and explain that all 256 states are retained,
   including the ten output states. Show the synapse BRAM and routed resource report.
2. Open `images.html`. Point out the actual digit, Python prediction and scores.
3. Show the saved XSim PASS log and its exact state/packet comparison scope.
4. Program the MNIST bitstream. Arm ILA, press BTN1 and decode the four LEDs.
5. Export the ILA capture and run the checker in front of your professor.
   Advance to a correctly classified sample as well as showing the first
   misclassification honestly.
6. If UART is available, show the real capture and packet comparison. Optionally
   load the clearly labeled stress bitstream to show nonzero output spikes.
7. Keep the physical capture files, successful build report and `.bit`/`.ltx`
   together with the reference and firmware hashes as your evidence.

## 13. If something does not work

| Symptom | First checks |
| --- | --- |
| No device in Hardware Manager | SW4, PGOOD, J12, data cable, cable drivers, JP5 JTAG |
| Device is `xc7z020` | That is a different board variant; do not use this Z7-10 bitstream |
| DONE lights but no application | BTN0 then release; verify programmed file, K17 clock and PHY reset E17 high |
| BTN1 seems ignored | Wait for green; release the button before pressing again; blue can mean UART is still draining |
| LEDs show 0000 | Could mean digit 0 or no valid result yet; use snapshot_valid/sample_index in ILA |
| ILA absent or probes mismatched | Matching `.bit`/`.ltx`, refresh FPGA, ensure build had ILA enabled |
| ILA never triggers | Arm before BTN1; trigger on snapshot_pulse=1; first image may need BTN0 restart; try lowering JTAG target frequency if communication fails |
| UART is silent | Use external adapter COM port, JC1→RX, common ground, correct 3.3 V module, 115200 8N1; built-in ARM COM port is not this PL UART |
| Red RGB | Inspect actual class/scores, build/reference hashes, bus fault or overflow; restart with BTN0 and capture the first failing sample |
| Checker reports wrong scores | Do not regenerate the reference with different images/weights after building; rebuild and keep matching files |
| Timing/build fails | Inspect the new log; do not program an old file as proof of the failed revision; fix the cause and rerun |

## 14. What this milestone does and what remains in the PS

This procedure gives a path to demonstrate trained pattern classification,
the full 256-state core, RV32/AXI weight loading, LEDs, ILA score comparison
and an RTL UART raster. It is an initial board demonstration, not completion
of every requirement in the problem statement.

The CPU currently polls and pops output packets. A hardware spike DMA engine
and output-spike interrupt still need integration. Component formal proofs
must be composed with the full controller/SoC. The paper-based optimization
comparison, complete-system measurements and physical-board validation remain
tracked in `STAGE_REPORT.md`. Save your measured FPGA captures before claiming
the on-board demonstration passes.

The current demo occupies **4,394 of 4,400 slices** on the Z7-10. Further
integration needs a fresh packing and timing check while retaining all
256 states; spare LUT and flip-flop totals alone do not prove that it fits.
