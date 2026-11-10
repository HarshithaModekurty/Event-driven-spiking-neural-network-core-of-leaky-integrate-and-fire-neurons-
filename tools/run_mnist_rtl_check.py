"""Export trained MNIST weights and compare held-out inference with real RTL."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import shutil
import subprocess
from pathlib import Path

from examples import mnist_live_demo as images
from examples import mnist256_demo as mnist
from golden_model import SNNGoldenModel

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "mnist256"
CONFIG = mnist.CONFIG
SOURCES = mnist.NUM_NEURONS  # exactly 256 states and 256 source addresses
OUTPUTS = mnist.OUTPUT_COUNT
INPUT_WORDS = (SOURCES + 31) // 32
VECTOR_FIELDS = 4 + 2 * INPUT_WORDS + 2 * SOURCES + 1


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_reference(weights: list[list[int]]) -> SNNGoldenModel:
    """Canonical 256-state Python reference, with outputs at 246..255."""
    return mnist.make_model(weights)


def export(args: argparse.Namespace) -> dict:
    BUILD.mkdir(parents=True, exist_ok=True)
    dataset_paths = [images.DATA_DIR / name for name in images.MNIST_FILES]
    train_images, rows, columns = images.load_images(dataset_paths[0])
    train_labels = images.load_labels(dataset_paths[1])
    test_images, test_rows, test_columns = images.load_images(dataset_paths[2])
    test_labels = images.load_labels(dataset_paths[3])
    if (rows, columns, test_rows, test_columns) != (28, 28, 28, 28):
        raise ValueError("expected original 28x28 MNIST images")
    if len(train_images) != len(train_labels) or len(test_images) != len(test_labels):
        raise ValueError("image/label counts differ")
    if args.train_count > len(train_images) or args.samples > len(test_images):
        raise ValueError("requested count exceeds the official dataset split")
    provenance = {
        "train_count": args.train_count, "epochs": args.epochs, "seed": args.seed,
        "preprocessing": "PS mapping: 15x15 binary grid at 80; bias 225; outputs 246..255; 256 states",
        "dataset_sha256": {p.name: sha256(p) for p in dataset_paths},
    }
    checkpoint_path = BUILD / "trained_weights.json"
    if checkpoint_path.exists() and not args.retrain:
        checkpoint = json.loads(checkpoint_path.read_text(encoding="utf-8"))
        if checkpoint["provenance"] != provenance:
            raise ValueError("cached training configuration differs; pass --retrain explicitly")
        weights = checkpoint["quantized_weights"]
        print("Reusing saved offline-trained weights.", flush=True)
    else:
        features = [mnist.features_from_image(image) for image in train_images[:args.train_count]]
        raw = images.train_perceptron(features, train_labels[:args.train_count], args.epochs, args.seed)
        weights = images.quantize_centered(raw)
        checkpoint = {"provenance": provenance, "raw_weights": raw, "quantized_weights": weights}
        checkpoint_path.write_text(json.dumps(checkpoint, indent=2) + "\n", encoding="utf-8")
    if len(weights) != OUTPUTS or any(len(row) != mnist.MODEL_PIXELS + 1 for row in weights):
        raise ValueError("invalid checkpoint dimensions")
    if any(not isinstance(w, int) or not -8 <= w <= 7 for row in weights for w in row):
        raise ValueError("checkpoint contains a weight outside signed four-bit range")

    model = make_reference(weights)
    weight_path = BUILD / "synapse_weights.hex"
    with weight_path.open("w", encoding="ascii") as stream:
        for row in model.weights:
            for weight in row:
                stream.write(f"{weight & 15:X}\n")

    selected = random.Random(args.seed + 1).sample(range(len(test_images)), args.samples)
    records = []
    with (BUILD / "mnist_vectors.hex").open("w", encoding="ascii") as hex_file, \
         (BUILD / "mnist_vectors.txt").open("w", encoding="ascii") as text_file:
        text_file.write("# sample test_index label tick input_words[0:7] spike_words[0:7] membranes[0:255] refractory[0:255] python_prediction\n")
        for sample, test_index in enumerate(selected, 1):
            model.reset()
            features = mnist.features_from_image(test_images[test_index])
            for tick, events in enumerate(mnist.encode(features), 1):
                fired = model.step(events)
                if any(n.membrane or n.refractory_remaining for n in model.neurons[:mnist.OUTPUT_START]):
                    raise AssertionError("input-only neuron state is not inert; mapping is invalid")
                if any(neuron < mnist.OUTPUT_START for neuron in fired):
                    raise AssertionError("an input-only neuron fired")
                mask = sum(1 << source for source in events)
                scores = [n.membrane for n in model.neurons[mnist.OUTPUT_START:]]
                prediction = max(range(OUTPUTS), key=scores.__getitem__)
                row = [sample, test_index, test_labels[test_index], tick]
                row += [(mask >> (32 * word)) & 0xFFFFFFFF for word in range(INPUT_WORDS)]
                spike_mask = sum(1 << neuron for neuron in fired)
                row += [(spike_mask >> (32 * word)) & 0xFFFFFFFF for word in range(INPUT_WORDS)]
                row += [n.membrane for n in model.neurons]
                row += [n.refractory_remaining for n in model.neurons]
                row += [prediction]
                assert len(row) == VECTOR_FIELDS
                packed = sum((value & 0xFFFFFFFF) << (32 * index) for index, value in enumerate(row))
                hex_file.write(f"{packed:0{8 * VECTOR_FIELDS}X}\n")
                text_file.write(" ".join(map(str, row)) + "\n")
            # Independently rerun the canonical 256-state classify entrypoint.
            if mnist.classify(features, weights) != (prediction, scores):
                raise AssertionError("export differs from the canonical 256-state classifier")
            image_name = f"sample_{sample:03d}_test_{test_index:05d}_label_{test_labels[test_index]}.png"
            images.save_png(BUILD / image_name, test_images[test_index])
            record = {"sample": sample, "test_index": test_index, "true_digit": test_labels[test_index],
                      "python_prediction": prediction, "scores": scores, "image": image_name,
                      "synaptic_events": model.synaptic_events}
            records.append(record)
            print(f"Sample {sample:02d}: test index {test_index}, true={test_labels[test_index]}, Python={prediction}, scores={scores}", flush=True)
            if args.show_images:
                print(images.ascii_image(test_images[test_index]), flush=True)
    with (BUILD / "python_predictions.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    manifest = {
        "provenance": provenance, "checkpoint_sha256": sha256(checkpoint_path),
        "weights_sha256": sha256(weight_path), "vectors_sha256": sha256(BUILD / "mnist_vectors.hex"),
        "num_sources": SOURCES, "num_stored_neurons": SOURCES, "synapse_entries": SOURCES * SOURCES, "output_start": mnist.OUTPUT_START, "ticks_per_image": mnist.TICKS_PER_IMAGE,
        "samples": records, "correct": sum(r["true_digit"] == r["python_prediction"] for r in records),
    }
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (BUILD / "configure_vivado.tcl").write_text(
        f'set_property top lif_mnist_tb [get_filesets sim_1]\n'
        f'set_property generic {{NUM_SAMPLES={args.samples}}} [get_filesets sim_1]\n'
        'update_compile_order -fileset sim_1\n', encoding="ascii")
    return manifest


def run_simulation(args: argparse.Namespace, manifest: dict) -> None:
    sources = [ROOT / "rtl" / name for name in (
        "lif_transition.v", "lif_population_stepper.v", "lif_synapse_router.v", "lif_snn_core.v", "lif_class_readout.v")]
    sources.append(ROOT / "rtl" / "tb" / "lif_mnist_tb.v")
    if args.simulator == "iverilog":
        executable = BUILD / "lif_mnist_tb.vvp"
        compile_command = ["iverilog", "-g2005", "-DIVERILOG", "-s", "lif_mnist_tb",
                           "-P", f"lif_mnist_tb.NUM_SAMPLES={args.samples}", "-o", str(executable)]
        subprocess.run(compile_command + list(map(str, sources)), cwd=ROOT, check=True, timeout=600)
        command = ["vvp", str(executable)]
        sim_cwd = ROOT
    else:
        sim_cwd = BUILD / "xsim"
        sim_cwd.mkdir(exist_ok=True)
        bin_dir = Path(args.vivado_bin)
        subprocess.run([str(bin_dir / "xvlog.bat"), "--work", "work", *map(str, sources)],
                       cwd=sim_cwd, check=True, timeout=120)
        # Quote the generic explicitly: cmd.exe otherwise splits the '=' in
        # arguments passed through Vivado's Windows batch launcher.
        elaborate = subprocess.list2cmdline([
            str(bin_dir / "xelab.bat"), "work.lif_mnist_tb", "-s", "mnist_trained_tb",
            "--timescale", "1ns/1ps", "--debug", "typical"])
        elaborate += f' --generic_top "NUM_SAMPLES={args.samples}"'
        subprocess.run(elaborate, cwd=sim_cwd, check=True, timeout=120)
        command = [str(bin_dir / "xsim.bat"), "mnist_trained_tb", "--runall", "--log", "xsim.log"]
    actual_path = BUILD / "rtl_predictions.csv"
    verification_path = BUILD / f"{args.simulator}_verification.json"
    if verification_path.exists():
        verification_path.unlink()
    if actual_path.exists():
        actual_path.unlink()  # exact generated file only; prevent accepting stale results
    simulation = subprocess.run(command, cwd=sim_cwd, capture_output=True, text=True, timeout=600)
    log = simulation.stdout + simulation.stderr
    (BUILD / f"{args.simulator}.log").write_text(log, encoding="utf-8")
    print(log, end="", flush=True)
    if simulation.returncode or "FAIL:" in log or "PASS: MNIST" not in log or "ERROR:" in log:
        raise RuntimeError("MNIST RTL comparison did not pass; see simulator log")
    with actual_path.open(newline="", encoding="ascii") as stream:
        actual = list(csv.DictReader(stream))
    if len(actual) != len(manifest["samples"]):
        raise AssertionError("RTL result count does not match selected images")
    for rtl, reference in zip(actual, manifest["samples"]):
        for key in ("sample", "test_index", "true_digit", "python_prediction"):
            if int(rtl[key]) != reference[key]:
                raise AssertionError(f"RTL metadata mismatch: {key}")
        if int(rtl["rtl_prediction"]) != reference["python_prediction"]:
            raise AssertionError("RTL digit differs from Python")
        if [int(rtl[f"score_{digit}"]) for digit in range(OUTPUTS)] != reference["scores"]:
            raise AssertionError("RTL output scores differ from Python")
    correct = manifest["correct"]
    report = {"simulator": args.simulator, "images_matched": len(actual),
              "ticks_matched": len(actual) * mnist.TICKS_PER_IMAGE,
              "state_updates_checked": len(actual) * mnist.TICKS_PER_IMAGE * SOURCES,
              "neuron_states": SOURCES, "synapse_entries": SOURCES * SOURCES, "correct": correct,
              "accuracy_percent": 100 * correct / len(actual), "weights_sha256": manifest["weights_sha256"],
              "vectors_sha256": manifest["vectors_sha256"], "rtl_predictions_sha256": sha256(actual_path),
              "source_sha256": {str(path.relative_to(ROOT)): sha256(path) for path in sources}}
    shutil.copyfile(actual_path, BUILD / f"{args.simulator}_predictions.csv")
    verification_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(actual)}/{len(actual)} RTL/Python predictions and scores; held-out accuracy {correct}/{len(actual)} ({report['accuracy_percent']:.1f}%).")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--train-count", type=int, default=12000)
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--seed", type=int, default=91)
    parser.add_argument("--retrain", action="store_true", help="regenerate the saved training checkpoint")
    parser.add_argument("--generate-only", action="store_true", help="prepare files for Vivado without running a simulator")
    parser.add_argument("--show-images", action="store_true", help="print each original image as ASCII")
    parser.add_argument("--simulator", choices=("iverilog", "xsim"), default="iverilog")
    parser.add_argument("--vivado-bin", default="F:/Xilinx/Vivado/2023.2/bin")
    args = parser.parse_args()
    if min(args.samples, args.train_count, args.epochs) <= 0:
        parser.error("sample count, training count and epochs must be positive")
    manifest = export(args)
    if not args.generate_only:
        run_simulation(args, manifest)


if __name__ == "__main__":
    main()
