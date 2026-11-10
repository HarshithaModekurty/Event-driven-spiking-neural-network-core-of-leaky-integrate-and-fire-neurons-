"""Directed RTL checks for the new address mapping and hardware class selector."""
import shutil
import subprocess
import unittest
from pathlib import Path
from examples import mnist256_demo as mnist

ROOT = Path(__file__).resolve().parents[1]


class PSClassifierMappingTests(unittest.TestCase):
    def test_last_pixel_bias_and_output_states_fit_the_ps_population(self):
        features = mnist.features_from_image(bytes([255]) * (28 * 28))
        self.assertEqual(len(features), 225)
        self.assertEqual(mnist.encode(features)[0], list(range(226)))
        weights = [[0] * 226 for _ in range(10)]
        weights[0][224] = 7
        weights[9][225] = -8
        model = mnist.make_model(weights)
        self.assertEqual(len(model.neurons), 256)
        self.assertEqual(sum(map(len, model.weights)), 65536)
        self.assertEqual(model.weights[224][246], 7)
        self.assertEqual(model.weights[225][255], -8)
        for events in mnist.encode(features):
            model.step(events)
        self.assertEqual(model.neurons[246].membrane, 56)
        self.assertEqual(model.neurons[255].membrane, 0)
        self.assertTrue(all(n.membrane == 0 for n in model.neurons[:246]))


@unittest.skipUnless(shutil.which("iverilog") and shutil.which("vvp"), "requires Icarus Verilog")
class ClassifierRTLTests(unittest.TestCase):
    def test_population_registered_read_and_reset(self):
        build = ROOT / "build" / "pipeline_regression"
        build.mkdir(parents=True, exist_ok=True)
        executable = build / "pipeline.vvp"
        sources = [ROOT / "rtl" / name for name in (
            "lif_transition.v", "lif_population_stepper.v", "tb/lif_population_pipeline_tb.v")]
        subprocess.run(["iverilog", "-g2005", "-s", "lif_population_pipeline_tb", "-o", str(executable),
                        *map(str, sources)], cwd=ROOT, check=True, capture_output=True, text=True, timeout=60)
        result = subprocess.run(["vvp", str(executable)], cwd=ROOT, check=True,
                                capture_output=True, text=True, timeout=60)
        self.assertNotIn("FAIL:", result.stdout)
        self.assertIn("PASS: registered population read", result.stdout)

    def test_mapped_feedback_and_readout_boundaries(self):
        build = ROOT / "build" / "mapping_regression"
        build.mkdir(parents=True, exist_ok=True)
        executable = build / "mapping.vvp"
        sources = ["lif_transition.v", "lif_population_stepper.v", "lif_synapse_router.v",
                   "lif_snn_core.v", "lif_class_readout.v", "tb/lif_source_mapping_tb.v"]
        subprocess.run(["iverilog", "-g2005", "-s", "lif_source_mapping_tb", "-o", str(executable),
                        *[str(ROOT / "rtl" / source) for source in sources]],
                       cwd=ROOT, check=True, capture_output=True, text=True, timeout=60)
        result = subprocess.run(["vvp", str(executable)], cwd=ROOT,
                                check=True, capture_output=True, text=True, timeout=60)
        self.assertNotIn("FAIL:", result.stdout)
        self.assertIn("PASS: offset recurrent source mapping", result.stdout)
