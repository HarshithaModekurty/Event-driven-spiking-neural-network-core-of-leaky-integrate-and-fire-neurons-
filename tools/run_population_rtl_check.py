"""Compare a time-multiplexed LIF population RTL step against Python neurons."""

from __future__ import annotations

import random
import subprocess
from pathlib import Path

from golden_model import LIFConfig, LIFNeuron


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "lif_population"
VECTOR_PATH = BUILD_DIR / "lif_population_vectors.txt"
VECTOR_HEX_PATH = BUILD_DIR / "lif_population_vectors.hex"
NUM_NEURONS = 4
CONFIG = LIFConfig(threshold=64, reset_value=3, leak_shift=2, refractory_period=2)


def build_vectors(time_steps: int = 64) -> int:
    rng = random.Random(20261108)
    neurons = [LIFNeuron(CONFIG) for _ in range(NUM_NEURONS)]
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    with (
        VECTOR_PATH.open("w", encoding="ascii", newline="\n") as vector_file,
        VECTOR_HEX_PATH.open("w", encoding="ascii", newline="\n") as hex_file,
    ):
        for tick in range(time_steps):
            currents = [
                40 if tick % 7 in (0, 1, 2, 3) else rng.randint(-12, 72),
                -48 if tick % 3 == 0 else rng.randint(-32, 24),
                82 if tick % 9 == 4 else rng.randint(-24, 50),
                rng.randint(-28, 76),
            ]
            results = [neuron.step(current) for neuron, current in zip(neurons, currents)]
            spike_mask = sum(int(result.spike) << index for index, result in enumerate(results))
            config_values = [
                CONFIG.threshold,
                CONFIG.reset_value,
                int(CONFIG.leak_shift is not None),
                CONFIG.leak_shift or 0,
                CONFIG.refractory_period,
            ]
            row = config_values + currents + [spike_mask]
            row += [result.membrane for result in results]
            row += [result.refractory_remaining for result in results]
            vector_file.write(" ".join(map(str, row)) + "\n")
            packed = sum((value & 0xFFFFFFFF) << (32 * index) for index, value in enumerate(row))
            hex_file.write(f"{packed:0144X}\n")
    return time_steps


def main() -> None:
    time_steps = build_vectors()
    executable = BUILD_DIR / "lif_population_stepper_tb.vvp"
    subprocess.run(
        [
            "iverilog",
            "-g2005",
            "-DIVERILOG",
            "-s",
            "lif_population_stepper_tb",
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
    print(f"Python generated {time_steps} time steps for {NUM_NEURONS} neurons in {VECTOR_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()