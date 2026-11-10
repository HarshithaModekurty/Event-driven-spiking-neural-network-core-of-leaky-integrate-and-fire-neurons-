"""Compare a time-multiplexed LIF population RTL step against Python neurons."""

from __future__ import annotations

import random
import subprocess
import argparse
from pathlib import Path

from golden_model import LIFConfig, LIFNeuron


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "lif_population"
VECTOR_PATH = BUILD_DIR / "lif_population_vectors.txt"
VECTOR_HEX_PATH = BUILD_DIR / "lif_population_vectors.hex"
CONFIG = LIFConfig(threshold=64, reset_value=3, leak_shift=2, refractory_period=2)


def build_vectors(num_neurons: int, time_steps: int = 64) -> int:
    rng = random.Random(20261108)
    neurons = [LIFNeuron(CONFIG) for _ in range(num_neurons)]
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    with (
        VECTOR_PATH.open("w", encoding="ascii", newline="\n") as vector_file,
        VECTOR_HEX_PATH.open("w", encoding="ascii", newline="\n") as hex_file,
    ):
        for tick in range(time_steps):
            currents = []
            for neuron_id in range(num_neurons):
                if neuron_id % 4 == 0:
                    current = 40 if tick % 7 in (0, 1, 2, 3) else rng.randint(-12, 72)
                elif neuron_id % 4 == 1:
                    current = -48 if tick % 3 == 0 else rng.randint(-32, 24)
                elif neuron_id % 4 == 2:
                    current = 82 if tick % 9 == 4 else rng.randint(-24, 50)
                else:
                    current = rng.randint(-28, 76)
                currents.append(current)
            results = [neuron.step(current) for neuron, current in zip(neurons, currents)]
            spike_mask = sum(int(result.spike) << index for index, result in enumerate(results))
            spike_words = [
                (spike_mask >> (32 * word_index)) & 0xFFFFFFFF
                for word_index in range((num_neurons + 31) // 32)
            ]
            row = [
                CONFIG.threshold,
                CONFIG.reset_value,
                int(CONFIG.leak_shift is not None),
                CONFIG.leak_shift or 0,
                CONFIG.refractory_period,
            ]
            row += currents + spike_words
            row += [result.membrane for result in results]
            row += [result.refractory_remaining for result in results]
            vector_file.write(" ".join(map(str, row)) + "\n")
            packed = sum((value & 0xFFFFFFFF) << (32 * index) for index, value in enumerate(row))
            hex_digits = (32 * len(row) + 3) // 4
            hex_file.write(f"{packed:0{hex_digits}X}\n")
    return time_steps


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--neurons", type=int, default=4, help="population size to compare (default: 4)")
    parser.add_argument("--steps", type=int, default=64, help="number of persistent time steps (default: 64)")
    args = parser.parse_args()
    if args.neurons <= 0 or args.neurons > 256 or args.steps <= 0 or args.steps > 64:
        parser.error("--neurons must be 1..256 and --steps must be 1..64")

    num_neurons = args.neurons
    time_steps = build_vectors(num_neurons, args.steps)
    executable = BUILD_DIR / "lif_population_stepper_tb.vvp"
    addr_width = max(1, (num_neurons - 1).bit_length())
    subprocess.run(
        [
            "iverilog",
            "-g2005",
            "-DIVERILOG",
            "-s",
            "lif_population_stepper_tb",
            "-P",
            f"lif_population_stepper_tb.NUM_NEURONS={num_neurons}",
            "-P",
            f"lif_population_stepper_tb.ADDR_WIDTH={addr_width}",
            "-P",
            f"lif_population_stepper_tb.NUM_TIME_STEPS={time_steps}",
            "-o",
            str(executable),
            str(ROOT / "rtl" / "lif_transition.v"),
            str(ROOT / "rtl" / "lif_population_stepper.v"),
            str(ROOT / "rtl" / "tb" / "lif_population_stepper_tb.v"),
        ],
        cwd=ROOT,
        check=True,
    )
    simulation = subprocess.run(
        ["vvp", str(executable)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    print(simulation.stdout, end="")
    if "PASS:" not in simulation.stdout or "FAIL:" in simulation.stdout:
        raise RuntimeError("Population RTL did not report a passing Python comparison")
    print(f"Python generated {time_steps} time steps for {num_neurons} neurons in {VECTOR_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()