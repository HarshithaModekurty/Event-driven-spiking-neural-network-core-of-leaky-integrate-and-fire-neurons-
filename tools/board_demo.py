"""Prepare FPGA demo images/references; verify real UART or ILA captures."""
import argparse
import csv
import hashlib
import html
import json
from pathlib import Path
from tools.run_rv32_check import export, ROOT


def packet_frames(path):
    frames, current = [], []
    for word in path.read_text().split():
        value = int(word, 16)
        current.append(value)
        if value == 256:
            frames.append(current)
            current = []
    if current:
        raise ValueError('Reference stream has an unterminated frame')
    return frames


def prepare(scenario, samples):
    folder = ROOT / 'build' / 'board_demo' / scenario
    meta, _ = export(folder, scenario, samples)
    states = [int(word, 16) for word in (folder / 'states.hex').read_text().split()]
    ins = packet_frames(folder / 'encoder_packets.hex')
    outs = packet_frames(folder / 'output_packets.hex')
    records = []
    originals = None
    if scenario == 'mnist':
        from examples import mnist_live_demo as images
        originals, _, _ = images.load_images(images.DATA_DIR / images.MNIST_FILES[2])
    cards = []
    for i in range(meta['images']):
        scores = [(states[8*i+7] >> (256+16*n)) & 65535 for n in range(246, 256)]
        record = dict(sample=i, python_prediction=meta['cpu_predictions'][i], scores=scores,
                      input_packets=ins[8*i:8*i+8], output_packets=outs[8*i:8*i+8])
        if originals is not None:
            record.update(test_index=meta['records'][i]['test_index'],
                          actual_digit=meta['records'][i]['true_digit'])
            pixels = originals[record['test_index']]
            # Original held-out digit, not an AI-generated drawing.
            svg = '<svg viewBox="0 0 28 28" width="140" height="140" aria-label="Actual MNIST digit">'
            svg += '<rect width="28" height="28" fill="black"/>'
            svg += ''.join(f'<rect x="{p%28}" y="{p//28}" width="1" height="1" fill="rgb({v},{v},{v})"/>'
                           for p, v in enumerate(pixels) if v)
            svg += '</svg>'
        else:
            svg = '<p>256-state signed-ring stress pattern; no digit label.</p>'
        records.append(record)
        cards.append(f'<article><h2>Sample {i:02X} (decimal {i})</h2>{svg}'
                     f'<p>Actual digit: {record.get("actual_digit", "not applicable")}; '
                     f'Python prediction: <b>{record["python_prediction"]}</b></p>'
                     f'<p>Scores for digits 0–9: {html.escape(str(scores))}</p>'
                     '<p>FPGA: read LEDs/ILA or verify a UART capture. No FPGA result is prefilled.</p></article>')
    reference = dict(scenario=scenario, neuron_states=256, samples=records,
                     firmware_sha256=hashlib.sha256((folder/'firmware.hex').read_bytes()).hexdigest(),
                     weights_sha256=meta['weights_sha256'])
    (folder/'reference.json').write_text(json.dumps(reference, indent=2)+'\n')
    (folder/'sample_count.txt').write_text(str(meta['images'])+'\n')
    (folder/'images.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8">'
        '<title>SNN FPGA demonstration images</title><style>body{font:18px system-ui;margin:2em;max-width:1000px}'
        'article{border:1px solid #bbb;padding:1em;margin:1em 0;break-inside:avoid}svg{image-rendering:pixelated}'
        '</style><h1>Actual images and Python reference</h1>'
        '<p>256 LIF states; outputs are states 246–255. Press BTN1 once per sample. '
        'Sample indices in UART/ILA are zero based and hexadecimal.</p>'+''.join(cards)+'</html>', encoding='utf-8')
    print(f'Prepared {meta["images"]} samples in {folder}')
    if scenario == 'mnist':
        print(f'Python accuracy: {meta["correct"]}/{meta["images"]}; hardware agreement is checked separately.')
    return folder


def verify_uart(reference, capture, allow_partial=False):
    observed, events = {}, {}
    for line_number, raw in enumerate(capture.read_text(encoding='ascii').splitlines(), 1):
        if not raw.strip():
            continue
        parts = raw.split(',')
        try:
            kind, sample = parts[0], int(parts[1], 16)
            if sample >= len(reference['samples']):
                raise ValueError('Sample index outside reference')
            if kind == 'C' and len(parts) == 13:
                if sample in observed:
                    raise ValueError('Duplicate sample (reset? use a new capture file)')
                observed[sample] = (int(parts[2], 16), [int(s, 16) for s in parts[3:]])
            elif kind in ('I', 'O') and len(parts) == 4:
                tick, packet = int(parts[2], 16), int(parts[3], 16)
                if not 0 <= tick < 8 or not 0 <= packet <= 256 or sample not in observed:
                    raise ValueError('Invalid tick, packet or missing class record')
                events.setdefault((sample, kind, tick), []).append(packet)
            else:
                raise ValueError('Unexpected record format')
        except (ValueError, IndexError) as exc:
            raise ValueError(f'UART line {line_number}: {raw!r}: {exc}') from exc
    if not observed:
        raise ValueError('No class records received')
    wanted = set(range(len(reference['samples'])))
    if not allow_partial and set(observed) != wanted:
        raise ValueError(f'Missing samples: {sorted(wanted-set(observed))}')
    for sample, (digit, scores) in sorted(observed.items()):
        ref = reference['samples'][sample]
        if digit != ref['python_prediction'] or scores != ref['scores']:
            raise ValueError(f'Sample {sample}: FPGA class/scores differ from Python')
        for kind, key in [('I', 'input_packets'), ('O', 'output_packets')]:
            for tick in range(8):
                if events.get((sample, kind, tick), []) != ref[key][tick]:
                    raise ValueError(f'Sample {sample}, tick {tick}, {kind}: spike/END stream differs from Python')
        print(f'PASS sample {sample:02X}: class={digit}, ten scores and all input/output packets match Python; '
              f'actual digit={ref.get("actual_digit", "N/A")}')
    return len(observed)


def verify_ila(reference, capture):
    # Vivado write_hw_ila_data CSV: signal headings may include hierarchy and bit ranges.
    with capture.open(newline='', encoding='utf-8-sig') as stream:
        rows = list(csv.reader(stream))
    required = ['snapshot_pulse', 'sample_index', 'predicted_digit', 'scores', 'error']
    heading = next((i for i, row in enumerate(rows) if all(any(name in col for col in row) for name in required)), None)
    if heading is None:
        raise ValueError('CSV must contain snapshot_pulse, sample_index, predicted_digit, scores and error probes')
    columns = {name: next(j for j, col in enumerate(rows[heading]) if name in col) for name in required}
    matched = set()
    for row in rows[heading+1:]:
        try:
            values = {name: int(row[j].strip().removeprefix('0x'), 16) for name, j in columns.items()}
        except (ValueError, IndexError):
            continue  # Vivado's optional radix row is not sample data.
        if not values['snapshot_pulse']:
            continue
        sample = values['sample_index']
        if sample >= len(reference['samples']):
            raise ValueError('ILA sample index outside reference')
        ref = reference['samples'][sample]
        scores = [(values['scores'] >> (16*n)) & 65535 for n in range(10)]
        if values['error'] or values['predicted_digit'] != ref['python_prediction'] or scores != ref['scores']:
            raise ValueError(f'ILA sample {sample}: hardware error or class/scores mismatch')
        matched.add(sample)
        print(f'PASS ILA sample {sample:02X}: actual FPGA class and all ten scores match Python')
    if not matched:
        raise ValueError('No valid snapshot_pulse=1 sample found; export probes with hexadecimal radix')
    return len(matched)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    prep = sub.add_parser('prepare')
    prep.add_argument('--scenario', choices=['mnist', 'stress'], default='mnist')
    prep.add_argument('--samples', type=int, default=20)
    check = sub.add_parser('verify')
    check.add_argument('--scenario', choices=['mnist', 'stress'], default='mnist')
    check.add_argument('--capture', type=Path, required=True)
    check.add_argument('--format', choices=['uart', 'ila'], default='uart')
    check.add_argument('--allow-partial', action='store_true', help='Accept complete individual UART samples')
    args = parser.parse_args()
    if args.command == 'prepare':
        if not 1 <= args.samples <= 20:
            parser.error('--samples must be 1..20')
        prepare(args.scenario, args.samples)
    else:
        folder = ROOT/'build'/'board_demo'/args.scenario
        reference = json.loads((folder/'reference.json').read_text())
        count = (verify_uart(reference, args.capture, args.allow_partial) if args.format == 'uart'
                 else verify_ila(reference, args.capture))
        print(f'PASS: verified {count} captured FPGA sample(s); these are observations, not prefilled results.')


if __name__ == '__main__':
    main()
