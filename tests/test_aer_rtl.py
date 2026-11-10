"""Queue and scheduler checks against independent Python behavioral models."""
from collections import deque
from pathlib import Path
import random
import shutil
import subprocess
import unittest

from golden_model import LIFConfig, SNNGoldenModel
from golden_model.aer import RoundRobinAERArbiter
from tools.generate_aer_rr import generate

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/aer'


class AERReferenceTests(unittest.TestCase):
    def test_generated_bdd_matches_committed_source(self):
        source, metadata = generate()
        self.assertEqual((ROOT / 'rtl/aer_rr_select.v').read_text(), source)
        self.assertEqual(metadata['truth_table_rows'], 64)

    def test_repeated_packets_and_recurrent_overlap_assert_one_source_bit(self):
        model = SNNGoldenModel(4, LIFConfig(threshold=5, reset_value=0))
        model.set_weight(0, 1, 5)
        model.set_weight(1, 2, 5)
        self.assertEqual(model.route_currents([0, 0]), [0, 5, 0, 0])
        self.assertEqual(model.step([0, 0]), [1])
        self.assertEqual(model.step([1, 1]), [2])
        self.assertEqual(model.synaptic_events, 2)


@unittest.skipUnless(shutil.which('iverilog') and shutil.which('vvp'), 'requires Icarus')
class AERRTLTests(unittest.TestCase):
    def run_rtl(self, top, sources, vectors, parameter=None):
        BUILD.mkdir(parents=True, exist_ok=True)
        executable = BUILD / f'{top}_{parameter or "default"}.vvp'
        command = ['iverilog', '-g2005', '-s', top, '-o', str(executable)]
        if parameter is not None:
            command += ['-P', f'{top}.DEPTH={parameter}']
        subprocess.run(command + [str(ROOT / 'rtl' / name) for name in sources],
                       cwd=ROOT, capture_output=True, text=True, check=True, timeout=60)
        result = subprocess.run(['vvp', str(executable), f'+VECTORS={vectors.as_posix()}'],
                                cwd=ROOT, capture_output=True, text=True, check=True, timeout=60)
        self.assertIn('PASS:', result.stdout)
        return result.stdout

    def test_fifo_wrap_full_replacement_empty_and_reset(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        for depth in (1, 3, 16):
            with self.subTest(depth=depth):
                rng = random.Random(911 + depth)
                queue = deque()
                rows = []
                stimulus = [(1, 0, 0, 0)]
                stimulus += [(0, 1, i, 0) for i in range(depth + 3)]
                stimulus += [(0, 1, 256+i, 1) for i in range(depth + 3)]
                stimulus += [(0, 0, 0, 1)] * (depth + 3)
                stimulus += [(int(i % 173 == 0), rng.randrange(2), rng.randrange(512), rng.randrange(2))
                             for i in range(2000)]
                for reset, valid, data, ready in stimulus:
                    pop_valid = bool(queue) and not reset
                    push_ready = not reset and (len(queue) < depth or (pop_valid and ready))
                    rows.append([reset, valid, data, ready, int(push_ready), int(pop_valid),
                                 queue[0] if pop_valid else 0, len(queue)])
                    if reset:
                        queue.clear()
                    else:
                        if pop_valid and ready:
                            queue.popleft()
                        if valid and push_ready:
                            queue.append(data)
                path = BUILD / f'fifo_{depth}.txt'
                path.write_text(''.join(' '.join(map(str, row))+'\n' for row in rows))
                self.run_rtl('aer_fifo_tb', ['aer_event_fifo.v', 'tb/aer_fifo_tb.v'], path, depth)

    def test_arbiter_python_match_stalls_continuous_requests_and_reset(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        rng = random.Random(365)
        model = RoundRobinAERArbiter(4)
        rows = []
        held = None
        for cycle in range(3000):
            reset = cycle % 431 == 0
            if reset:
                model = RoundRobinAERArbiter(4)
                held = None
            # All ports remain continuously pending in the first 100 clocks.
            for port in range(4):
                if cycle < 100 or rng.randrange(3) == 0:
                    model.enqueue(port, rng.randrange(512))
            requests = sum(bool(q) << p for p, q in enumerate(model.queues))
            addresses = [q[0] if q else 0 for q in model.queues]
            ack = cycle % 17 >= 8 if cycle < 200 else bool(rng.randrange(2))
            if reset:
                # Reset clears the RTL grant; software queues start next cycle.
                model = RoundRobinAERArbiter(4)
                selected = None
            else:
                returned = model.cycle(ack)
                selected = None if held is not None and ack else returned
            rows.append([int(reset), requests, int(ack), *addresses,
                         int(selected is not None), selected.port if selected else 0,
                         selected.address if selected else 0])
            held = selected
        path = BUILD / 'arbiter.txt'
        path.write_text(''.join(' '.join(map(str, row))+'\n' for row in rows))
        self.run_rtl('aer_arbiter_tb', ['aer_rr_select.v', 'aer_rr_arbiter.v', 'tb/aer_arbiter_tb.v'], path)
