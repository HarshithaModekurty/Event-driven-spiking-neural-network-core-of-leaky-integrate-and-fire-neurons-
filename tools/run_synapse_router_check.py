"""Compare signed-4-bit RTL synapse routing against SNNGoldenModel."""

from __future__ import annotations

import argparse
import random
import subprocess
from pathlib import Path

from golden_model import LIFConfig, SNNGoldenModel


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "lif_router"
WEIGHT_PATH = BUILD_DIR / "synapse_weights.hex"
VECTOR_PATH = BUILD_DIR / "lif_router_vectors.txt"
VECTOR_HEX_PATH = BUILD_DIR / "lif_router_vectors.hex"


def build_vectors(num_neurons: int, transactions: int, seed: int) -> None:
    rng = random.Random(seed)
    model = SNNGoldenModel(
        num_neurons=num_neurons,
        neuron_config=LIFConfig(threshold=64, reset_value=3, leak_shift=2, refractory_period=2),
        weight_bits=4,
    )
    weights = []
    for source in range(num_neurons):
        row = []
        for destination in range(num_neurons):
            if source == destination or (source * 7 + destination * 11) % 13 >= 3:
                weight = 0
            else:
                weight = rng.randint(-8, 7)
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
        for transaction in range(transactions):
            if transaction == 0:
                sources = list(range(0, num_neurons, max(1, num_neurons // 8)))[:8]
            else:
                sources = [source for source in range(num_neurons) if rng.random() < 0.08]
            routed_currents = model.route_currents(sources)
            source_mask = sum(1 << source for source in sources)
            row = [
                (source_mask >> (32 * word_index)) & 0xFFFFFFFF
                for word_index in range(spike_words)
            ] + routed_currents
            vector_file.write(" ".join(map(str, [*sources, -1, *routed_currents])) + "\n")
            packed = sum((value & 0xFFFFFFFF) << (32 * index) for index, value in enumerate(row))
            hex_digits = (32 * len(row) + 3) // 4
            hex_file.write(f"{packed:0{hex_digits}X}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--neurons", type=int, default=4, help="network size, from 1 through 256")
    parser.add_argument("--transactions", type=int, default=32, help="number of source-spike vectors")
    parser.add_argument("--seed", type=int, default=20261109, help="deterministic synapse/event seed")
    args = parser.parse_args()
    if not 1 <= args.neurons <= 256 or args.transactions <= 0 or args.transactions > 32:
        parser.error("--neurons must be 1..256 and --transactions must be 1..32")

    num_neurons = args.neurons
    build_vectors(num_neurons, args.transactions, args.seed)
    addr_width = max(1, (num_neurons - 1).bit_length())
    executable = BUILD_DIR / "lif_synapse_router_tb.vvp"
    subprocess.run(
        [
            "iverilog", "-g2005", "-DIVERILOG", "-s", "lif_synapse_router_tb",
            "-P", f"lif_synapse_router_tb.NUM_NEURONS={num_neurons}",
            "-P", f"lif_synapse_router_tb.ADDR_WIDTH={addr_width}",
            "-P", f"lif_synapse_router_tb.NUM_TRANSACTIONS={args.transactions}",
            "-o", str(executable),
            str(ROOT / "rtl" / "lif_synapse_router.v"),
            str(ROOT / "rtl" / "tb" / "lif_synapse_router_tb.v"),
        ],
        cwd=ROOT,
        check=True,
    )
    simulation = subprocess.run(
        ["vvp", str(executable)], cwd=ROOT, capture_output=True, text=True, check=True
    )
    print(simulation.stdout, end="")
    if "PASS:" not in simulation.stdout or "FAIL:" in simulation.stdout:
        raise RuntimeError("Synapse router did not report a passing Python comparison")
    print(f"Python reference generated {args.transactions} routing cases for {num_neurons} neurons")


if __name__ == "__main__":
    main()
