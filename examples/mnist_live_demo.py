"""Train a quantized LIF digit classifier and show official MNIST test images live."""

from __future__ import annotations

import argparse
import csv
import gzip
import random
import struct
import time
import zlib
from pathlib import Path

from golden_model import LIFConfig, RateEncoder, SNNGoldenModel


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "mnist"
PROOF_DIR = ROOT / "proof_images" / "mnist"
SOURCE_SIZE = 28
MODEL_SIZE = 16
MODEL_PIXELS = MODEL_SIZE * MODEL_SIZE
BIAS_ADDRESS = MODEL_PIXELS
OUTPUT_START = MODEL_PIXELS + 1
OUTPUT_COUNT = 10
NUM_NEURONS = OUTPUT_START + OUTPUT_COUNT
TICKS_PER_IMAGE = 8
MNIST_FILES = (
    "train-images-idx3-ubyte.gz",
    "train-labels-idx1-ubyte.gz",
    "t10k-images-idx3-ubyte.gz",
    "t10k-labels-idx1-ubyte.gz",
)


def load_images(path: Path) -> tuple[list[bytes], int, int]:
    with gzip.open(path, "rb") as stream:
        data = stream.read()
    if len(data) < 16:
        raise ValueError(f"truncated MNIST image file: {path}")
    magic, count, rows, columns = struct.unpack_from(">IIII", data)
    if magic != 2051 or len(data) != 16 + count * rows * columns:
        raise ValueError(f"invalid MNIST image file: {path}")
    size = rows * columns
    return [data[16 + i * size : 16 + (i + 1) * size] for i in range(count)], rows, columns


def load_labels(path: Path) -> list[int]:
    with gzip.open(path, "rb") as stream:
        data = stream.read()
    if len(data) < 8:
        raise ValueError(f"truncated MNIST label file: {path}")
    magic, count = struct.unpack_from(">II", data)
    if magic != 2049 or len(data) != 8 + count:
        raise ValueError(f"invalid MNIST label file: {path}")
    return list(data[8:])


def features_from_image(image: bytes, rows: int = SOURCE_SIZE, columns: int = SOURCE_SIZE,
                        model_size: int = MODEL_SIZE) -> list[int]:
    """Reduce a grayscale image to a square binary feature grid."""
    features = []
    for out_y in range(model_size):
        y0 = out_y * rows // model_size
        y1 = (out_y + 1) * rows // model_size
        for out_x in range(model_size):
            x0 = out_x * columns // model_size
            x1 = (out_x + 1) * columns // model_size
            pixels = [image[y * columns + x] for y in range(y0, y1) for x in range(x0, x1)]
            features.append(int(sum(pixels) / len(pixels) >= 80))
    return features


def train_perceptron(
    training_features: list[list[int]], labels: list[int], epochs: int, seed: int
) -> list[list[int]]:
    """Train a multiclass perceptron offline using only the MNIST train split."""
    weights = [[0] * (len(training_features[0]) + 1) for _ in range(OUTPUT_COUNT)]
    order = list(range(len(labels)))
    rng = random.Random(seed)
    for epoch in range(epochs):
        rng.shuffle(order)
        mistakes = 0
        for sample_index in order:
            active = [index for index, value in enumerate(training_features[sample_index]) if value]
            label = labels[sample_index]
            scores = [weights[digit][-1] for digit in range(OUTPUT_COUNT)]
            for digit in range(OUTPUT_COUNT):
                row = weights[digit]
                scores[digit] += sum(row[pixel] for pixel in active)
            prediction = max(range(OUTPUT_COUNT), key=scores.__getitem__)
            if prediction != label:
                mistakes += 1
                true_row = weights[label]
                predicted_row = weights[prediction]
                for pixel in active:
                    true_row[pixel] += 1
                    predicted_row[pixel] -= 1
                true_row[-1] += 1
                predicted_row[-1] -= 1
        print(f"Training epoch {epoch + 1}/{epochs}: {mistakes} mistakes", flush=True)
        if mistakes == 0:
            break
    return weights


def quantize_centered(weights: list[list[int]]) -> list[list[int]]:
    """Center each input's class weights, then quantize to signed 4-bit."""
    feature_count = len(weights[0])
    centered = [[0.0] * feature_count for _ in range(OUTPUT_COUNT)]
    peak = 0.0
    for feature in range(feature_count):
        mean = sum(weights[digit][feature] for digit in range(OUTPUT_COUNT)) / OUTPUT_COUNT
        for digit in range(OUTPUT_COUNT):
            centered[digit][feature] = weights[digit][feature] - mean
            peak = max(peak, abs(centered[digit][feature]))

    scale = 7.0 / peak if peak else 1.0
    quantized = [
        [max(-7, min(7, round(centered[digit][feature] * scale))) for feature in range(feature_count)]
        for digit in range(OUTPUT_COUNT)
    ]

    # Keep each feature's class weights zero-sum, so some output has positive
    # evidence and clamping negative membrane current does not erase every score.
    for feature in range(feature_count):
        imbalance = sum(quantized[digit][feature] for digit in range(OUTPUT_COUNT))
        if imbalance > 0:
            for digit in sorted(range(OUTPUT_COUNT), key=lambda item: quantized[item][feature], reverse=True):
                change = min(imbalance, quantized[digit][feature] + 7)
                quantized[digit][feature] -= change
                imbalance -= change
                if imbalance == 0:
                    break
        elif imbalance < 0:
            imbalance = -imbalance
            for digit in sorted(range(OUTPUT_COUNT), key=lambda item: quantized[item][feature]):
                change = min(imbalance, 7 - quantized[digit][feature])
                quantized[digit][feature] += change
                imbalance -= change
                if imbalance == 0:
                    break
    return quantized


def classify(features: list[int], weights: list[list[int]]) -> tuple[int, list[int]]:
    """Encode pixels and return the winning LIF output membrane and all scores."""
    model = SNNGoldenModel(
        num_neurons=NUM_NEURONS,
        neuron_config=LIFConfig(threshold=0xFFFF, leak_shift=None),
        weight_bits=4,
    )
    for pixel in range(MODEL_PIXELS + 1):
        for digit in range(OUTPUT_COUNT):
            model.set_weight(pixel, OUTPUT_START + digit, weights[digit][pixel])

    encoder = RateEncoder(NUM_NEURONS)
    input_values = [255 * value for value in features] + [255] + [0] * OUTPUT_COUNT
    for events in encoder.encode(input_values, ticks=TICKS_PER_IMAGE):
        model.step(events)

    # Output thresholds are set above the maximum possible frame accumulation;
    # the class result is read from the 10 output neurons' membrane potentials.
    scores = [model.neurons[OUTPUT_START + digit].membrane for digit in range(OUTPUT_COUNT)]
    return max(range(OUTPUT_COUNT), key=scores.__getitem__), scores


def ascii_image(image: bytes) -> str:
    ramp = " .:-=+*#%@"
    return "\n".join(
        "".join(ramp[min(len(ramp) - 1, image[y * SOURCE_SIZE + x] * len(ramp) // 256)] for x in range(SOURCE_SIZE))
        for y in range(SOURCE_SIZE)
    )


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    body = chunk_type + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def save_png(path: Path, image: bytes) -> None:
    """Save the untouched 28x28 grayscale MNIST input as a PNG image."""
    scanlines = b"".join(b"\0" + image[row * SOURCE_SIZE : (row + 1) * SOURCE_SIZE] for row in range(SOURCE_SIZE))
    header = struct.pack(">IIBBBBB", SOURCE_SIZE, SOURCE_SIZE, 8, 0, 0, 0, 0)
    png_data = b"\x89PNG\r\n\x1a\n"
    png_data += _png_chunk(b"IHDR", header)
    png_data += _png_chunk(b"IDAT", zlib.compress(scanlines))
    png_data += _png_chunk(b"IEND", b"")
    path.write_bytes(png_data)


def run(args: argparse.Namespace) -> None:
    missing = [name for name in MNIST_FILES if not (DATA_DIR / name).is_file()]
    if missing:
        raise FileNotFoundError(
            f"Missing MNIST archives in {DATA_DIR}: {', '.join(missing)}. "
            "See README.md for the official MNIST download source."
        )

    train_images, rows, columns = load_images(DATA_DIR / MNIST_FILES[0])
    train_labels = load_labels(DATA_DIR / MNIST_FILES[1])
    test_images, test_rows, test_columns = load_images(DATA_DIR / MNIST_FILES[2])
    test_labels = load_labels(DATA_DIR / MNIST_FILES[3])
    if rows != SOURCE_SIZE or columns != SOURCE_SIZE or (test_rows, test_columns) != (rows, columns):
        raise ValueError("expected 28x28 MNIST images")
    if len(train_images) != len(train_labels) or len(test_images) != len(test_labels):
        raise ValueError("MNIST image and label counts do not match")
    if args.train_count > len(train_images) or args.samples > len(test_images):
        raise ValueError("requested sample count exceeds the available MNIST split")

    print(f"Loaded official MNIST split: {args.train_count} train images, {len(test_images)} held-out test images.", flush=True)
    training_features = [features_from_image(image) for image in train_images[: args.train_count]]
    training_labels = train_labels[: args.train_count]
    raw_weights = train_perceptron(training_features, training_labels, args.epochs, args.seed)
    quantized_weights = quantize_centered(raw_weights)
    print("Offline training complete; learned weights quantized to signed 4-bit.", flush=True)

    PROOF_DIR.mkdir(parents=True, exist_ok=True)
    selected = random.Random(args.seed + 1).sample(range(len(test_images)), args.samples)
    manifest_path = PROOF_DIR / "predictions.csv"
    correct = 0
    with manifest_path.open("w", newline="", encoding="utf-8") as manifest_file:
        writer = csv.writer(manifest_file)
        writer.writerow(["sample", "mnist_test_index", "image_file", "true_digit", "predicted_digit", "correct", "membrane_scores_0_to_9"])
        print("\nLive predictions on official MNIST test images:", flush=True)
        for sample_number, test_index in enumerate(selected, start=1):
            image = test_images[test_index]
            true_digit = test_labels[test_index]
            features = features_from_image(image)
            prediction, scores = classify(features, quantized_weights)
            is_correct = prediction == true_digit
            correct += is_correct
            image_name = f"sample_{sample_number:03d}_test_{test_index:05d}_label_{true_digit}.png"
            save_png(PROOF_DIR / image_name, image)

            print(
                f"\nSample {sample_number:03d}/{args.samples} | MNIST test index {test_index}"
                f" | expected: {true_digit} | predicted: {prediction} | {'CORRECT' if is_correct else 'WRONG'}",
                flush=True,
            )
            print(ascii_image(image), flush=True)
            print(f"saved original 28x28 image: {PROOF_DIR.relative_to(ROOT) / image_name}", flush=True)
            print("output membrane scores 0-9: " + " ".join(f"{digit}:{score}" for digit, score in enumerate(scores)), flush=True)
            writer.writerow([sample_number, test_index, image_name, true_digit, prediction, is_correct, " ".join(map(str, scores))])
            manifest_file.flush()
            if args.delay:
                time.sleep(args.delay)

    print(f"\nHeld-out MNIST result: {correct}/{args.samples} correct ({100 * correct / args.samples:.1f}%).")
    print(f"Presentation images and per-image manifest: {PROOF_DIR.relative_to(ROOT)}")
    print("The test images were not used during training; the reported accuracy is only for this selected subset.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=20, help="number of official MNIST test images to present")
    parser.add_argument("--train-count", type=int, default=12000, help="number of MNIST training images to use")
    parser.add_argument("--epochs", type=int, default=5, help="maximum offline perceptron training passes")
    parser.add_argument("--seed", type=int, default=91, help="seed for training order and held-out selection")
    parser.add_argument("--delay", type=float, default=0.2, help="seconds between displayed test images")
    args = parser.parse_args()
    if args.samples <= 0 or args.train_count <= 0 or args.epochs <= 0:
        parser.error("--samples, --train-count, and --epochs must be positive")
    if args.delay < 0:
        parser.error("--delay must be non-negative")
    run(args)


if __name__ == "__main__":
    main()
