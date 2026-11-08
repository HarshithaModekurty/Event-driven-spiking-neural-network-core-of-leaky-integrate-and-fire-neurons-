"""Train offline, then stream fresh random patterns through the LIF model."""

from __future__ import annotations

import argparse
import random
import time

from golden_model import LIFConfig, RateEncoder, SNNGoldenModel


WIDTH = 5
HEIGHT = 5
NUM_PIXELS = WIDTH * HEIGHT
BIAS_ADDRESS = NUM_PIXELS
CLASS_0_NEURON = NUM_PIXELS + 1
CLASS_1_NEURON = NUM_PIXELS + 2
NUM_NEURONS = NUM_PIXELS + 3
CLASS_NAMES = {1: "left vertical", -1: "lower horizontal"}


def make_random_pattern(rng: random.Random, label: int) -> list[int]:
    """Make a bar image with a few class-preserving random noise pixels."""
    if label == 1:
        bar_column = rng.choice((0, 1))
        pixels = [int(column == bar_column) for row in range(HEIGHT) for column in range(WIDTH)]
        noise_candidates = [row * WIDTH + column for row in range(HEIGHT) for column in range(2, WIDTH)]
    elif label == -1:
        bar_row = rng.choice((3, 4))
        pixels = [int(row == bar_row) for row in range(HEIGHT) for column in range(WIDTH)]
        noise_candidates = [row * WIDTH + column for row in range(3) for column in range(WIDTH)]
    else:
        raise ValueError("label must be +1 or -1")

    for pixel in rng.sample(noise_candidates, rng.randint(1, 3)):
        pixels[pixel] = 1
    return pixels


def make_training_set(seed: int, count: int) -> list[tuple[list[int], int]]:
    """Generate labeled training images; live images use a separate RNG."""
    rng = random.Random(seed)
    samples = []
    for index in range(count):
        label = 1 if index % 2 == 0 else -1
        samples.append((make_random_pattern(rng, label), label))
    return samples


def train_perceptron(patterns: list[tuple[list[int], int]], seed: int) -> list[int]:
    """Train a linear separator offline; return pixel weights plus bias."""
    training = [(features + [1], label) for features, label in patterns]
    weights = [0] * (NUM_PIXELS + 1)
    rng = random.Random(seed)
    for _ in range(50):
        rng.shuffle(training)
        errors = 0
        for features, label in training:
            score = sum(weight * feature for weight, feature in zip(weights, features))
            if label * score <= 0:
                weights = [weight + label * feature for weight, feature in zip(weights, features)]
                errors += 1
        if errors == 0:
            break
    return weights


def quantize(weights: list[int]) -> list[int]:
    peak = max(abs(weight) for weight in weights) or 1
    return [max(-7, min(7, round(weight * 7 / peak))) for weight in weights]


def classify(pattern: list[int], quantized_weights: list[int]) -> tuple[int, int, int]:
    """Run one image through rate encoding and the integer LIF network."""
    model = SNNGoldenModel(
        num_neurons=NUM_NEURONS,
        neuron_config=LIFConfig(threshold=4, leak_shift=None),
        weight_bits=4,
    )
    for pixel, bit in enumerate(pattern):
        if bit:
            model.set_weight(pixel, CLASS_0_NEURON, quantized_weights[pixel])
            model.set_weight(pixel, CLASS_1_NEURON, -quantized_weights[pixel])
    model.set_weight(BIAS_ADDRESS, CLASS_0_NEURON, quantized_weights[-1])
    model.set_weight(BIAS_ADDRESS, CLASS_1_NEURON, -quantized_weights[-1])

    features = [255 * bit for bit in pattern] + [255]
    encoder = RateEncoder(NUM_NEURONS)
    output_counts = [0, 0]
    for events in encoder.encode(features + [0, 0], ticks=8):
        fired = model.step(events)
        output_counts[0] += CLASS_0_NEURON in fired
        output_counts[1] += CLASS_1_NEURON in fired

    prediction = 1 if output_counts[0] > output_counts[1] else -1
    return prediction, output_counts[0], output_counts[1]


def render(pattern: list[int]) -> str:
    return "\n".join(
        "".join("#" if pattern[row * WIDTH + column] else "." for column in range(WIDTH))
        for row in range(HEIGHT)
    )


def live_evaluation(
    weights: list[int], training_patterns: list[tuple[list[int], int]], sample_count: int, seed: int, delay: float
) -> tuple[int, int]:
    """Print each newly generated holdout image and its actual model result."""
    rng = random.Random(seed)
    training_images = {tuple(pattern) for pattern, _ in training_patterns}
    seen_live_images: set[tuple[int, ...]] = set()
    correct = 0

    print("\nLive holdout predictions (not used for training):", flush=True)
    for sample_index in range(1, sample_count + 1):
        while True:
            label = rng.choice((1, -1))
            pattern = make_random_pattern(rng, label)
            image_key = tuple(pattern)
            if image_key not in training_images and image_key not in seen_live_images:
                seen_live_images.add(image_key)
                break

        prediction, left_spikes, horizontal_spikes = classify(pattern, weights)
        passed = prediction == label
        correct += passed
        status = "CORRECT" if passed else "WRONG"
        print(
            f"\nSample {sample_index:02d} | expected: {CLASS_NAMES[label]} ({label:+d})"
            f" | predicted: {CLASS_NAMES[prediction]} ({prediction:+d}) | {status}",
            flush=True,
        )
        print(render(pattern), flush=True)
        print(f"output spikes: left-vertical={left_spikes}, lower-horizontal={horizontal_spikes}", flush=True)
        if delay:
            time.sleep(delay)

    return correct, sample_count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=10, help="number of fresh live test images (default: 10)")
    parser.add_argument("--seed", type=int, default=2026, help="reproducible random seed (default: 2026)")
    parser.add_argument("--delay", type=float, default=0.25, help="seconds between displayed samples (default: 0.25)")
    args = parser.parse_args()
    if args.samples <= 0:
        parser.error("--samples must be positive")
    if args.delay < 0:
        parser.error("--delay must be non-negative")

    training_patterns = make_training_set(args.seed, count=400)
    trained_weights = train_perceptron(training_patterns, seed=args.seed + 1)
    quantized_weights = quantize(trained_weights)
    print(f"Offline training complete: {len(training_patterns)} generated images; weights quantized to signed 4-bit.")
    print("Classes: +1 = left vertical bar; -1 = lower horizontal bar.")

    correct, total = live_evaluation(
        quantized_weights,
        training_patterns,
        sample_count=args.samples,
        seed=args.seed + 2,
        delay=args.delay,
    )
    print(f"\nLive holdout result: {correct}/{total} correct ({100 * correct / total:.1f}%).")
    print("This result is for the generated toy task, not a real digit dataset.")


if __name__ == "__main__":
    main()