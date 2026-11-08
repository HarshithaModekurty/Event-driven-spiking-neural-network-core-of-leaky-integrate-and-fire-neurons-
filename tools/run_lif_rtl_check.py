"""Generate vectors from the Python LIF model and compare them with Icarus RTL."""

from __future__ import annotations

import random
import subprocess
from pathlib import Path

from golden_model import LIFConfig, LIFNeuron, LIFStepResult


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "lif_rtl"
VECTOR_PATH = BUILD_DIR / "lif_vectors.txt"


def build_vectors() -> int:
    rng = random.Random(731)
    scenarios = [
        (LIFConfig(), [0, 8, 8, 8, 8, 0, 32, 0, 64, -16, 8]),
        (LIFConfig(threshold=30_000, reset_value=7, leak_shift=3, refractory_period=3),
         [0, 1000, -50, 20_000, 15_000, 65_535, 100_000, -100_000, 15_000, 0, 40_000]),
        (LIFConfig(threshold=65_535, reset_value=0, leak_shift=None, refractory_period=0),
         [65_534, 1, 100_000, 65_534, -20, 32_767, 32_768]),
        (LIFConfig(threshold=500, reset_value=19, leak_shift=0, refractory_period=0),
         [500, -100, 1, 499, 65535]),
    ]

    VECTOR_PATH.parent.mkdir(parents=True, exist_ok=True)
    vector_count = 0
    with VECTOR_PATH.open("w", encoding="ascii", newline="\n") as vector_file:
        for scenario_index, (config, currents) in enumerate(scenarios):
            neuron = LIFNeuron(config)
            vector_file.write(
                f"1 0 0 {config.threshold} {config.reset_value} "
                f"{int(config.leak_shift is not None)} {config.leak_shift or 0} "
                f"{config.refractory_period} 0 {config.reset_value} 0\n"
            )
            vector_count += 1
            neuron.reset()

            full_currents = currents + [rng.randint(-80_000, 100_000) for _ in range(120)]
            for tick, current in enumerate(full_currents):
                enabled = 0 if tick in (17, 18, 83) else 1
                result = neuron.step(current) if enabled else None
                if result is None:
                    result = LIFStepResult(False, neuron.membrane, neuron.refractory_remaining)
                vector_file.write(
                    f"0 {enabled} {current} {config.threshold} {config.reset_value} "
                    f"{int(config.leak_shift is not None)} {config.leak_shift or 0} "
                    f"{config.refractory_period} {int(result.spike)} {result.membrane} "
                    f"{result.refractory_remaining}\n"
                )
                vector_count += 1
    return vector_count


def main() -> None:
    vector_count = build_vectors()
    compile_command = [
        "iverilog",
        "-g2005",
        "-DIVERILOG",
        "-s",
        "lif_neuron_tb",
        "-o",
        str(BUILD_DIR / "lif_neuron_tb.vvp"),
        str(ROOT / "rtl" / "lif_neuron.v"),
        str(ROOT / "rtl" / "tb" / "lif_neuron_tb.v"),
    ]
    subprocess.run(compile_command, cwd=ROOT, check=True)
    simulation = subprocess.run(
        [
            "vvp",
            str(BUILD_DIR / "lif_neuron_tb.vvp"),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    print(simulation.stdout, end="")
    if "PASS:" not in simulation.stdout or "FAIL:" in simulation.stdout:
        raise RuntimeError("RTL testbench did not report a passing golden-model comparison")
    print(f"Python generated {vector_count} reference cycles in {VECTOR_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()