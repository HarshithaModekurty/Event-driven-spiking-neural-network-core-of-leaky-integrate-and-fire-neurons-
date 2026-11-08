"""Deterministic rate encoder for unsigned 8-bit input features."""


class RateEncoder:
    """Convert feature intensities to address events with an accumulator.

    Each feature has an accumulator in [0, 254]. On every tick its intensity
    is added; an event is emitted when the sum reaches 255. Repeated calls to
    ``encode_tick`` preserve phase, while ``encode`` starts a fresh sample.
    """

    def __init__(self, num_features: int, maximum: int = 255) -> None:
        if num_features <= 0:
            raise ValueError("num_features must be positive")
        if maximum <= 0:
            raise ValueError("maximum must be positive")
        self.num_features = num_features
        self.maximum = maximum
        self.accumulators = [0] * num_features

    def reset(self) -> None:
        self.accumulators = [0] * self.num_features

    def encode_tick(self, values: list[int] | tuple[int, ...]) -> list[int]:
        if len(values) != self.num_features:
            raise ValueError("feature count does not match encoder configuration")
        events = []
        for feature, value in enumerate(values):
            if not 0 <= value <= self.maximum:
                raise ValueError(f"feature values must be in [0, {self.maximum}]")
            accumulated = self.accumulators[feature] + value
            if accumulated >= self.maximum:
                events.append(feature)
                accumulated -= self.maximum
            self.accumulators[feature] = accumulated
        return events

    def encode(self, values: list[int] | tuple[int, ...], ticks: int) -> list[list[int]]:
        if ticks < 0:
            raise ValueError("ticks must be non-negative")
        self.reset()
        return [self.encode_tick(values) for _ in range(ticks)]