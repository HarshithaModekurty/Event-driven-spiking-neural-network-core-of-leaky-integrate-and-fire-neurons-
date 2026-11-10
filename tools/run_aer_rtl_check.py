"""Exercise the complete 256-state AER wrapper against the Python network."""
from pathlib import Path
import argparse
import hashlib
import json
import random
import subprocess

from golden_model import LIFConfig, SNNGoldenModel

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/aer_network'
RTL = ['aer_event_fifo.v', 'aer_rr_select.v', 'aer_rr_arbiter.v',
       'lif_transition.v', 'lif_population_stepper.v', 'lif_synapse_router.v',
       'lif_snn_core.v', 'lif_aer_snn_core.v', 'tb/lif_aer_snn_core_tb.v']


def write_vectors(weights, inputs, states, fired_steps, records, extra=None):
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / 'weights.hex').write_text(weights, encoding='ascii')
    streams = [[] for _ in range(4)]
    for frame, events in enumerate(inputs):
        for number, source in enumerate(events):
            streams[(number + frame) % 4].append(source)
        for stream in streams:
            stream.append(256)
    output_packets = [packet for fired in fired_steps for packet in fired+[256]]
    stride = max(map(len, streams))
    (BUILD / 'input_counts.hex').write_text(''.join(f'{len(s):08X}\n' for s in streams))
    (BUILD / 'input_packets.hex').write_text(''.join(
        f'{value:03X}\n' for stream in streams for value in stream+[0]*(stride-len(stream))))
    (BUILD / 'output_packets.hex').write_text(''.join(f'{value:03X}\n' for value in output_packets))
    (BUILD / 'states.hex').write_text(''.join(f'{packed:02112X}\n' for packed in states))
    metadata = {'frames': len(inputs), 'neuron_states': 256, 'synapse_entries': 65536,
                'state_updates_checked': len(inputs)*256, 'input_packet_stride': stride,
                'output_packets': len(output_packets), 'output_spikes': len(output_packets)-len(inputs),
                'records': records, **(extra or {})}
    (BUILD / 'vectors.json').write_text(json.dumps(metadata, indent=2)+'\n')
    return metadata


def export():
    BUILD.mkdir(parents=True, exist_ok=True)
    model = SNNGoldenModel(256, LIFConfig(threshold=8, reset_value=3,
                                        leak_shift=2, refractory_period=2))
    for source in range(256):
        model.set_weight(source, (source + 1) % 256, 7)
        model.set_weight(source, source, -2)
    # At frame four, a single source-255 contribution leaves neuron 128 at
    # six; counting external/recurrent source 255 twice would falsely fire it.
    model.set_weight(255, 128, 3)
    weights = ''.join(f'{weight & 15:X}\n' for row in model.weights for weight in row)
    rng = random.Random(20261110)
    # All 256 simultaneous output spikes, silent ticks, boundary wrap,
    # duplicate packets, and external/recurrent source overlap.
    inputs = [list(range(256)), [], [], [254, 254], [255, 2, 2], [],
              rng.sample(range(256), 60), rng.sample(range(256), 45)]
    states = []
    fired_steps = []
    records = []
    for frame, events in enumerate(inputs):
        fired = model.step(events)
        if frame == 4 and (model.neurons[128].membrane != 6 or 128 in fired):
            raise AssertionError('external/recurrent source-overlap witness failed')
        packed = sum(1 << source for source in fired)
        for neuron, state in enumerate(model.neurons):
            packed |= state.membrane << (256 + 16*neuron)
            packed |= state.refractory_remaining << (4352 + 16*neuron)
        states.append(packed)
        fired_steps.append(fired)
        records.append({'frame': frame, 'input_packets': len(events),
                        'unique_sources': len(set(events)), 'fired': fired})
    return write_vectors(weights, inputs, states, fired_steps, records)


def export_mnist(samples):
    from tools import run_mnist_rtl_check as classifier
    # Reuse the canonical exporter, saved learned weights and selected test split.
    args = argparse.Namespace(train_count=12000, epochs=5, seed=91,
                              samples=samples, retrain=False, show_images=False)
    manifest = classifier.export(args)
    inputs, states, fired_steps = [], [], []
    for line in (classifier.BUILD/'mnist_vectors.txt').read_text().splitlines():
        if line.startswith('#'):
            continue
        row = list(map(int, line.split()))
        mask = sum(row[4+i] << (32*i) for i in range(8))
        spike_mask = sum(row[12+i] << (32*i) for i in range(8))
        inputs.append([source for source in range(256) if mask & (1 << source)])
        fired_steps.append([source for source in range(256) if spike_mask & (1 << source)])
        packed = spike_mask
        for neuron in range(256):
            packed |= row[20+neuron] << (256+16*neuron)
            packed |= row[276+neuron] << (4352+16*neuron)
        states.append(packed)
    return write_vectors((classifier.BUILD/'synapse_weights.hex').read_text(), inputs,
                         states, fired_steps, manifest['samples'],
                         {'images': samples, 'correct': manifest['correct'],
                          'accuracy_percent': 100*manifest['correct']/samples,
                          'classifier_weights_sha256': manifest['weights_sha256']})


def main():
    global BUILD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', choices=('iverilog', 'xsim'), default='iverilog')
    parser.add_argument('--generate-only', action='store_true')
    parser.add_argument('--scenario', choices=('stress', 'mnist'), default='stress')
    parser.add_argument('--samples', type=int, default=20)
    parser.add_argument('--vivado-bin', default='F:/Xilinx/Vivado/2023.2/bin')
    args = parser.parse_args()
    if not 1 <= args.samples <= 10000:
        parser.error('--samples must be 1..10000')
    if args.scenario == 'mnist':
        BUILD = ROOT/'build/aer_mnist'
        metadata = export_mnist(args.samples)
    else:
        metadata = export()
    params = {'FRAMES': metadata['frames'], 'PORT_WORDS': metadata['input_packet_stride'],
              'OUTPUT_WORDS': metadata['output_packets']}
    if args.scenario == 'mnist':
        params.update(THRESHOLD=65535, RESET_VALUE=0, LEAK_ENABLE=0,
                      REFRACTORY_PERIOD=0, RESET_EVERY=8, REQUIRE_FULL_OUTPUT=0)
    generic = ' '.join(f'{name}={value}' for name, value in params.items())
    (BUILD/'configure_vivado.tcl').write_text(
        'set_property top lif_aer_snn_core_tb [get_filesets sim_1]\n'
        f'set_property generic {{{generic}}} [get_filesets sim_1]\n'
        f'set_property -dict [list xsim.simulate.xsim.more_options {{-testplusarg "DATA_DIR={BUILD.as_posix()}"}}] [get_filesets sim_1]\n'
        'update_compile_order -fileset sim_1\n')
    if args.generate_only:
        print(f'Generated {metadata["frames"]} framed AER network steps in {BUILD}')
        return
    sources = [ROOT/'rtl'/name for name in RTL]
    if args.simulator == 'iverilog':
        executable = BUILD/'aer_network.vvp'
        command = ['iverilog', '-g2005', '-s', 'lif_aer_snn_core_tb', '-o', str(executable)]
        for name, value in params.items():
            command += ['-P', f'lif_aer_snn_core_tb.{name}={value}']
        subprocess.run(command+list(map(str, sources)), cwd=ROOT, check=True, timeout=120)
        command = ['vvp', str(executable), f'+DATA_DIR={BUILD.as_posix()}']
        cwd = ROOT
    else:
        cwd = BUILD/'xsim'; cwd.mkdir(exist_ok=True)
        binary = Path(args.vivado_bin)
        subprocess.run([str(binary/'xvlog.bat'), *map(str, sources)], cwd=cwd, check=True, timeout=120)
        elaborate = subprocess.list2cmdline([str(binary/'xelab.bat'), 'work.lif_aer_snn_core_tb',
                                            '-s', 'aer_network', '--timescale', '1ns/1ps'])
        for name, value in params.items():
            elaborate += f' --generic_top "{name}={value}"'
        subprocess.run(elaborate, cwd=cwd, check=True, timeout=120)
        command = subprocess.list2cmdline([str(binary/'xsim.bat'), 'aer_network',
                                           '--runall', '--log', 'xsim.log'])
        # cmd.exe splits '=' in batch arguments unless this value is quoted.
        command += f' --testplusarg "DATA_DIR={BUILD.as_posix()}"'
    evidence = BUILD/f'{args.simulator}_verification.json'
    evidence.unlink(missing_ok=True)
    simulation = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=1200)
    log = simulation.stdout+simulation.stderr
    (BUILD/f'{args.simulator}.log').write_text(log, encoding='utf-8')
    print(log, end='')
    if simulation.returncode or 'PASS: AER network' not in log or 'FAIL:' in log or 'FATAL:' in log or 'ERROR:' in log:
        raise RuntimeError('AER end-to-end comparison failed; inspect simulator log')
    report = {k: v for k, v in metadata.items() if k != 'records'}
    report['simulator'] = args.simulator
    report['scenario'] = args.scenario
    report['parameters'] = params
    report['artifact_sha256'] = {name: hashlib.sha256((BUILD/name).read_bytes()).hexdigest()
                                 for name in ('weights.hex', 'input_packets.hex', 'input_counts.hex',
                                              'output_packets.hex', 'states.hex')}
    report['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [*sources, ROOT/'golden_model/network.py', ROOT/'golden_model/lif.py']}
    evidence.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
