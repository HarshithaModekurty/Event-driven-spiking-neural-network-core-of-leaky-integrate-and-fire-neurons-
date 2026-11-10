"""PS mapping: 256 actual LIF states and a 256x256 weight matrix."""
from examples import mnist_live_demo as images
from golden_model import LIFConfig, RateEncoder, SNNGoldenModel

NUM_NEURONS = 256
MODEL_SIZE = 15
MODEL_PIXELS = 225
BIAS_ADDRESS = 225
OUTPUT_START = 246
OUTPUT_COUNT = 10
TICKS_PER_IMAGE = 8
CONFIG = LIFConfig(threshold=65535, reset_value=0, leak_shift=None, refractory_period=0)


def features_from_image(image: bytes) -> list[int]:
    return images.features_from_image(image, model_size=MODEL_SIZE)


def make_model(weights: list[list[int]]) -> SNNGoldenModel:
    model = SNNGoldenModel(NUM_NEURONS, CONFIG, weight_bits=4)
    for source in range(MODEL_PIXELS + 1):
        for digit in range(OUTPUT_COUNT):
            model.set_weight(source, OUTPUT_START + digit, weights[digit][source])
    return model


def encode(features: list[int]) -> list[list[int]]:
    if len(features) != MODEL_PIXELS:
        raise ValueError("expected 225 pixels for the 15x15 classifier")
    values = [255 * value for value in features] + [255] + [0] * 30
    return RateEncoder(NUM_NEURONS).encode(values, TICKS_PER_IMAGE)


def classify(features: list[int], weights: list[list[int]]) -> tuple[int, list[int]]:
    model = make_model(weights)
    for events in encode(features):
        model.step(events)
    scores = [neuron.membrane for neuron in model.neurons[OUTPUT_START:]]
    return max(range(OUTPUT_COUNT), key=scores.__getitem__), scores


if __name__ == "__main__":
    import sys
    from tools.run_mnist_rtl_check import main
    sys.argv.extend(["--generate-only", "--show-images"])
    main()
