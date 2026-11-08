"""Integer leaky-integrate-and-fire neuron used as the RTL reference."""

from dataclasses import dataclass


@dataclass(frozen=True)
class LIFConfig:
    """Parameters shared by neurons in a model.

    ``leak_shift=None`` disables leakage. Otherwise leakage subtracts
    ``membrane >> leak_shift`` before the current for the current tick is added.
    Membrane state is unsigned 16-bit and saturates at 65535.
    """

    threshold: int = 32
    reset_value: int = 0
    leak_shift: int | None = 4
    refractory_period: int = 0

    def __post_init__(self) -> None:
        if not 1 <= self.threshold <= 0xFFFF:
            raise ValueError("threshold must be in [1, 65535]")
        if not 0 <= self.reset_value <= 0xFFFF:
            raise ValueError("reset_value must be in [0, 65535]")
        if self.leak_shift is not None and self.leak_shift < 0:
            raise ValueError("leak_shift must be non-negative or None")
        if self.refractory_period < 0:
            raise ValueError("refractory_period must be non-negative")


@dataclass(frozen=True)
class LIFStepResult:
    spike: bool
    membrane: int
    refractory_remaining: int


class LIFNeuron:
    """One saturating 16-bit LIF neuron."""

    def __init__(self, config: LIFConfig) -> None:
        self.config = config
        self.membrane = config.reset_value
        self.refractory_remaining = 0

    def reset(self) -> None:
        self.membrane = self.config.reset_value
        self.refractory_remaining = 0

    def step(self, input_current: int = 0) -> LIFStepResult:
        """Advance one tick; refractory ticks ignore input and cannot fire."""
        if self.refractory_remaining:
            self.refractory_remaining -= 1
            self.membrane = self.config.reset_value
            return LIFStepResult(False, self.membrane, self.refractory_remaining)

        membrane = self.membrane
        if self.config.leak_shift is not None:
            membrane -= membrane >> self.config.leak_shift
        membrane = min(0xFFFF, max(0, membrane + input_current))

        if membrane >= self.config.threshold:
            self.membrane = self.config.reset_value
            self.refractory_remaining = self.config.refractory_period
            return LIFStepResult(True, self.membrane, self.refractory_remaining)

        self.membrane = membrane
        return LIFStepResult(False, self.membrane, self.refractory_remaining)