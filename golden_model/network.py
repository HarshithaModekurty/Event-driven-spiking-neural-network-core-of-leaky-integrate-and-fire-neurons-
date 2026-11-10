"""Synchronous time-step network with signed low-bit synapse weights."""

from collections.abc import Iterable

from .lif import LIFConfig, LIFNeuron


class SNNGoldenModel:
    """Small integer network matching a time-step RTL implementation.

    Weights are stored as ``weights[source][destination]``. One-bit synapses
    represent disconnected/connected excitatory links (0/+1); four-bit
    synapses use signed two's-complement values (-8..+7). Events emitted by
    neurons in a tick are routed on the following tick.
    """

    def __init__(
        self,
        num_neurons: int = 256,
        neuron_config: LIFConfig | None = None,
        weight_bits: int = 4,
    ) -> None:
        if num_neurons <= 0:
            raise ValueError("num_neurons must be positive")
        if weight_bits not in (1, 4):
            raise ValueError("weight_bits must be 1 or 4")

        self.num_neurons = num_neurons
        self.weight_bits = weight_bits
        self.neuron_config = neuron_config or LIFConfig()
        self.neurons = [LIFNeuron(self.neuron_config) for _ in range(num_neurons)]
        self.weights = [[0] * num_neurons for _ in range(num_neurons)]
        self.pending_spikes: list[int] = []
        self.synaptic_events = 0
        self.ticks = 0

    def set_weight(self, source: int, destination: int, weight: int) -> None:
        self._check_neuron_id(source)
        self._check_neuron_id(destination)
        low, high = (0, 1) if self.weight_bits == 1 else (-8, 7)
        if not low <= weight <= high:
            raise ValueError(f"weight must be in [{low}, {high}] for {self.weight_bits}-bit mode")
        self.weights[source][destination] = weight

    def load_weights(self, weights: Iterable[Iterable[int]]) -> None:
        rows = [list(row) for row in weights]
        if len(rows) != self.num_neurons or any(len(row) != self.num_neurons for row in rows):
            raise ValueError("weight matrix must be num_neurons by num_neurons")
        for source, row in enumerate(rows):
            for destination, weight in enumerate(row):
                self.set_weight(source, destination, weight)

    def route_currents(self, source_spikes: Iterable[int]) -> list[int]:
        """Sum signed synapse weights from spiking sources into each target."""
        currents = [0] * self.num_neurons
        for source in set(source_spikes):
            self._check_neuron_id(source)
            for destination, weight in enumerate(self.weights[source]):
                currents[destination] += weight
        return currents

    def step(self, input_spikes: Iterable[int] = ()) -> list[int]:
        """Consume source addresses and return neuron addresses that fired.

        ``input_spikes`` are current-tick AER input events. Internally generated
        spikes from the previous tick are processed in the same tick. The
        synaptic event counter increases for each traversed nonzero connection.
        """
        external = list(input_spikes)
        for source in external:
            self._check_neuron_id(source)

        # A neuron/source has one spike bit per tick, as in the RTL bitmap.
        # Repeated packets and an external/recurrent overlap assert that bit once.
        sources = sorted(set(self.pending_spikes).union(external))
        currents = [0] * self.num_neurons
        for source in sources:
            row = self.weights[source]
            for destination, weight in enumerate(row):
                if weight:
                    currents[destination] += weight
                    self.synaptic_events += 1

        fired = []
        for neuron_id, (neuron, current) in enumerate(zip(self.neurons, currents)):
            if neuron.step(current).spike:
                fired.append(neuron_id)

        self.pending_spikes = fired
        self.ticks += 1
        return fired

    def reset(self) -> None:
        for neuron in self.neurons:
            neuron.reset()
        self.pending_spikes.clear()
        self.synaptic_events = 0
        self.ticks = 0

    def _check_neuron_id(self, neuron_id: int) -> None:
        if not isinstance(neuron_id, int) or not 0 <= neuron_id < self.num_neurons:
            raise ValueError(f"neuron address must be in [0, {self.num_neurons - 1}]")
