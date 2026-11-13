"""Tie a successful board bitstream to unchanged source and boot-image bytes."""
import argparse
import hashlib
import json
from pathlib import Path
from tools.run_rv32_check import ROOT, RTL


def hashes(paths):
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def synthesis_inputs(values):
    return {k:v for k,v in values.items() if k.startswith(('rtl/','constraints/'))
            or k.endswith(('/firmware.hex','/sample_count.txt','/ila_mode.txt'))}


def synthesis_recipe(script=None):
    if script is None: script=(ROOT/'tools/build_zybo_demo.tcl').read_text()
    marker='source [file join $root tools zybo_demo_context.tcl]'
    if script.count(marker)!=1: raise RuntimeError('Cannot identify synthesis/implementation boundary')
    prefix=script.split(marker)[0]
    # Recording cache provenance has no effect on the synthesized circuit.
    prefix=''.join(line for line in prefix.splitlines(keepends=True)
                   if 'tools.board_build_manifest seal-synth' not in line)
    return hashlib.sha256(prefix.encode()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['start','finish','check-synth','seal-synth'])
    parser.add_argument('--scenario',choices=['mnist','stress'],required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    sources=[ROOT/'rtl'/name for name in RTL if not name.startswith('tb/')]
    sources+=list((ROOT/'rtl'/'board').glob('*.v'))
    sources+=[ROOT/name for name in ['constraints/zybo_z710_demo.xdc','tools/zybo_demo_context.tcl',
                                   'tools/build_zybo_demo.tcl','tools/board_build_manifest.py']]
    data=ROOT/'build'/'board_demo'/args.scenario
    paths=sources+[data/'firmware.hex',data/'sample_count.txt',args.out/'ila_mode.txt']
    current=hashes(paths)
    before=args.out/'source_manifest.json'
    checkpoint=args.out/'synthesized.dcp'
    cache=args.out/'synthesis_manifest.json'
    if args.action=='check-synth':
        previous=json.loads(cache.read_text())
        if previous['input_sha256']!=synthesis_inputs(current) or previous['recipe_sha256']!=synthesis_recipe():
            raise RuntimeError('Cannot reuse synthesis: HDL or boot image/sample count changed')
        if previous['checkpoint_sha256']!=hashlib.sha256(checkpoint.read_bytes()).hexdigest():
            raise RuntimeError('Synthesized checkpoint bytes changed')
    elif args.action=='seal-synth':
        previous=json.loads(before.read_text())
        if synthesis_inputs(previous)!=synthesis_inputs(current) or previous['tools/build_zybo_demo.tcl']!=current['tools/build_zybo_demo.tcl']:
            raise RuntimeError('Synthesis inputs changed before checkpoint was recorded')
        # Never bind a DCP left by a failed older synthesis to newer inputs.
        if checkpoint.stat().st_mtime_ns < before.stat().st_mtime_ns:
            raise RuntimeError('Checkpoint predates this input manifest; synthesize again')
        cache.write_text(json.dumps(dict(input_sha256=synthesis_inputs(current),
            recipe_sha256=synthesis_recipe(),checkpoint_sha256=hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
            build_script_sha256=current['tools/build_zybo_demo.tcl']),indent=2)+'\n')
    elif args.action=='start':
        (args.out/'result.json').unlink(missing_ok=True)
        (args.out/'build_manifest.json').unlink(missing_ok=True)
        before.write_text(json.dumps(current,indent=2)+'\n')
    else:
        if json.loads(before.read_text())!=current:
            raise RuntimeError('Board source/boot image changed during implementation; rerun')
        artifacts=[args.out/'zybo_demo.bit']
        # A no-ILA build must not claim an old probes file as its artifact.
        if (args.out/'ila_mode.txt').read_text().strip()=='1':
            artifacts.append(args.out/'zybo_demo.ltx')
        result=dict(scenario=args.scenario,source_sha256=current,artifact_sha256=hashes(artifacts),physical_board_tested=False)
        provenance=json.loads(cache.read_text())
        if provenance['checkpoint_sha256']!=hashlib.sha256(checkpoint.read_bytes()).hexdigest():
            raise RuntimeError('Synthesis checkpoint changed during implementation')
        result['synthesis_provenance']=provenance
        (args.out/'build_manifest.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__': main()
