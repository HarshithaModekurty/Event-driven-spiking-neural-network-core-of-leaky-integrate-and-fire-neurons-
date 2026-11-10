"""Compare integrated synapse routing and time-multiplexed LIF RTL with Python."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from golden_model import LIFConfig, SNNGoldenModel


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "lif_snn_core"
WEIGHT_PATH = BUILD_DIR / "synapse_weights.hex"
VECTOR_PATH = BUILD_DIR / "lif_snn_vectors.txt"
VECTOR_HEX_PATH = BUILD_DIR / "lif_snn_vectors.hex"
CONFIG = LIFConfig(threshold=8, reset_value=3, leak_shift=2, refractory_period=2)


def build_vectors(num_neurons: int, transactions: int) -> None:
    model = SNNGoldenModel(num_neurons=num_neurons, neuron_config=CONFIG, weight_bits=4)
    weights = []
    for source in range(num_neurons):
        row = []
        for destination in range(num_neurons):
            weight = 7 if destination == (source + 1) % num_neurons else 0
            row.append(weight)
        weights.append(row)
    model.load_weights(weights)

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    with WEIGHT_PATH.open("w", encoding="ascii", newline="\n") as weight_file:
        for row in weights:
            for weight in row:
                weight_file.write(f"{weight & 0xFFFFFFFF:08X}\n")

    spike_words = (num_neurons + 31) // 32
    with (
        VECTOR_PATH.open("w", encoding="ascii", newline="\n") as vector_file,
        VECTOR_HEX_PATH.open("w", encoding="ascii", newline="\n") as hex_file,
    ):
        for tick in range(transactions):
            if tick == 0:
                external_sources = [0]
            else:
                external_sources = []
            fired = model.step(external_sources)
            input_mask = sum(1 << source for source in external_sources)
            output_mask = sum(1 << neuron for neuron in fired)
            row = [
                CONFIG.threshold,
                CONFIG.reset_value,
                int(CONFIG.leak_shift is not None),
                CONFIG.leak_shift or 0,
                CONFIG.refractory_period,
            ]
            row += [(input_mask >> (32 * word_index)) & 0xFFFFFFFF for word_index in range(spike_words)]
            row += [(output_mask >> (32 * word_index)) & 0xFFFFFFFF for word_index in range(spike_words)]
            row += [neuron.membrane for neuron in model.neurons]
            row += [neuron.refractory_remaining for neuron in model.neurons]
            vector_file.write(" ".join(map(str, [*external_sources, -1, *row])) + "\n")
            packed = sum((value & 0xFFFFFFFF) << (32 * index) for index, value in enumerate(row))
            hex_digits = (32 * len(row) + 3) // 4
            hex_file.write(f"{packed:0{hex_digits}X}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--neurons", type=int, default=4, help="network size, from 1 through 256")
    parser.add_argument("--transactions", type=int, default=24, help="number of recurrent SNN time steps")
    args = parser.parse_args()
    if not 1 <= args.neurons <= 256 or not 1 <= args.transactions <= 24:
        parser.error("--neurons must be 1..256 and --transactions must be 1..24")

    build_vectors(args.neurons, args.transactions)
    addr_width = max(1, (args.neurons - 1).bit_length())
    executable = BUILD_DIR / "lif_snn_core_tb.vvp"
    subprocess.run(
        [
            "iverilog", "-g2005", "-DIVERILOG", "-s", "lif_snn_core_tb",
            "-P", f"lif_snn_core_tb.NUM_NEURONS={args.neurons}",
            "-P", f"lif_snn_core_tb.ADDR_WIDTH={addr_width}",
            "-P", f"lif_snn_core_tb.NUM_TRANSACTIONS={args.transactions}",
            "-o", str(executable),
            str(ROOT / "rtl" / "lif_transition.v"),
            str(ROOT / "rtl" / "lif_population_stepper.v"),
            str(ROOT / "rtl" / "lif_synapse_router.v"),
            str(ROOT / "rtl" / "lif_snn_core.v"),
            str(ROOT / "rtl" / "tb" / "lif_snn_core_tb.v"),
        ],
        cwd=ROOT,
        check=True,
    )
    simulation = subprocess.run(
        ["vvp", str(executable)], cwd=ROOT, capture_output=True, text=True, check=True
    )
    print(simulation.stdout, end="")
    if "PASS:" not in simulation.stdout or "FAIL:" in simulation.stdout:
        raise RuntimeError("Integrated SNN core did not report a passing Python comparison")
    print(f"Python reference generated {args.transactions} integrated time steps for {args.neurons} neurons")


if __name__ == "__main__":
    main()
