import unittest

from golden_model import (
    AERRequest,
    LIFConfig,
    LIFNeuron,
    RateEncoder,
    RoundRobinAERArbiter,
    SNNGoldenModel,
    format_spike_raster,
)


class LIFNeuronTests(unittest.TestCase):
    def test_leak_threshold_reset_and_refractory(self) -> None:
        neuron = LIFNeuron(LIFConfig(threshold=10, leak_shift=1, refractory_period=2))
        self.assertFalse(neuron.step(6).spike)
        self.assertEqual(neuron.membrane, 6)
        self.assertTrue(neuron.step(7).spike)
        self.assertEqual(neuron.membrane, 0)
        self.assertFalse(neuron.step(100).spike)
        self.assertEqual(neuron.refractory_remaining, 1)
        self.assertFalse(neuron.step(100).spike)
        self.assertEqual(neuron.refractory_remaining, 0)
        self.assertFalse(neuron.step(4).spike)

    def test_saturates_to_unsigned_16_bit_state(self) -> None:
        neuron = LIFNeuron(LIFConfig(threshold=0xFFFF, leak_shift=None))
        self.assertTrue(neuron.step(100_000).spike)


class NetworkTests(unittest.TestCase):
    def test_input_spike_updates_targets_on_same_tick(self) -> None:
        model = SNNGoldenModel(3, LIFConfig(threshold=5, leak_shift=None), weight_bits=4)
        model.set_weight(0, 1, 5)
        model.set_weight(0, 2, 5)
        self.assertEqual(model.step([0]), [1, 2])
        self.assertEqual(model.step(), [])
        self.assertEqual(model.synaptic_events, 2)

    def test_signed_weight_and_bit_width_validation(self) -> None:
        model = SNNGoldenModel(2, weight_bits=4)
        model.set_weight(0, 1, -8)
        with self.assertRaises(ValueError):
            model.set_weight(0, 1, 8)

        binary = SNNGoldenModel(2, weight_bits=1)
        with self.assertRaises(ValueError):
            binary.set_weight(0, 1, -1)

    def test_signed_synapse_current_routing(self) -> None:
        model = SNNGoldenModel(4, weight_bits=4)
        model.set_weight(0, 0, 3)
        model.set_weight(0, 2, -2)
        model.set_weight(3, 0, -1)
        model.set_weight(3, 1, 5)
        self.assertEqual(model.route_currents([0, 3]), [2, 5, -2, 0])


class EncodingAndArbitrationTests(unittest.TestCase):
    def test_rate_encoder_emits_full_intensity_each_tick(self) -> None:
        encoder = RateEncoder(3)
        self.assertEqual(encoder.encode([255, 0, 128], 2), [[0], [0, 2]])

    def test_round_robin_and_held_request(self) -> None:
        arbiter = RoundRobinAERArbiter(2)
        arbiter.enqueue_many(0, [10, 11])
        arbiter.enqueue(1, 20)
        self.assertEqual(arbiter.cycle(), AERRequest(0, 10))
        self.assertEqual(arbiter.cycle(), AERRequest(0, 10))
        arbiter.cycle(acknowledge=True)
        self.assertEqual(arbiter.cycle(), AERRequest(1, 20))
        arbiter.cycle(acknowledge=True)
        self.assertEqual(arbiter.cycle(), AERRequest(0, 11))

    def test_uart_spike_raster_format(self) -> None:
        self.assertEqual(format_spike_raster([[], [3, 1], [2]]), "1,1\n1,3\n2,2\n")


if __name__ == "__main__":
    unittest.main()