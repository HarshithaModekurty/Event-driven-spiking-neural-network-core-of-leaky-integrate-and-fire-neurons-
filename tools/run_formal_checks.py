"""Source-bound CTL and SAT checks; no change to production RTL or constraints.

Portable tools: python -m tools.setup_formal_tools
Run: python -m tools.run_formal_checks
"""
from pathlib import Path
import hashlib
import importlib.metadata
import json
import os
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/formal_checks'
TOOLS=ROOT/'build/formal_tools'


def yosys(script,name):
    (BUILD/f'{name}.ys').write_text(script+'\n')
    env=os.environ.copy()
    env['PYTHONPATH']=str(TOOLS/'python')
    env['YOWASP_CACHE_DIR']=str(TOOLS/'cache')
    native=Path(os.environ['LOCALAPPDATA'])/'Programs/Python/Python311/python.exe'
    result=subprocess.run([str(native),'-c',
        'import sys,yowasp_yosys; sys.exit(yowasp_yosys.run_yosys(sys.argv[1:]))',
        '-Q','-T','-s',f'build/formal_checks/{name}.ys'],cwd=ROOT,env=env,
        capture_output=True,text=True,timeout=180)
    log=result.stdout+result.stderr
    (BUILD/f'{name}_yosys.log').write_text(log)
    if result.returncode:
        raise RuntimeError(f'Yosys failed: {name}; inspect {BUILD}')
    return log


def ctl(source,top,name,properties,fair=False,abstract_ge=False,expect_false=False):
    model=source.read_text().replace(f'MODULE _{top}','MODULE main').replace('  IVAR','  VAR')
    # Unconstrained input words become state variables free to change every step.
    # The clock is abstracted to one rising edge per transition by the SMV backend.
    if abstract_ge:
        # The arithmetic threshold result may take EITHER value independently
        # every step. This is a safety overapproximation, not an assumption
        # suppressing a failing spike. The refractory guard remains actual RTL.
        model,count=re.subn(r'(?m)^    (\S*\$ge\S*) := [^\n]+;\n',
            r'    \1 := _arbitrary_threshold_crossing;\n',model)
        if count!=1:
            raise RuntimeError('Expected exactly one LIF threshold comparator')
        model=model.replace('  VAR\n','  VAR\n    _arbitrary_threshold_crossing : unsigned word[1];\n',1)
    if fair:
        model+='\nFAIRNESS bool(_acknowledge)\n'
    model+='\n'+'\n'.join('CTLSPEC '+p for p in properties)+'\n'
    path=BUILD/f'{name}.smv'; path.write_text(model)
    exe=next(TOOLS.rglob('NuSMV.exe'))
    result=subprocess.run([str(exe),'-dynamic','-coi',str(path)],cwd=ROOT,
                          capture_output=True,text=True,timeout=300)
    log=result.stdout+result.stderr
    (BUILD/f'{name}_nusmv.log').write_text(log)
    outcomes=re.findall(r'-- specification .*? is (true|false)',log)
    if result.returncode or len(outcomes)!=len(properties):
        raise RuntimeError(f'NuSMV failed/incomplete: {name}; inspect {BUILD}')
    if expect_false:
        if 'false' not in outcomes:
            raise RuntimeError(f'Negative control was not detected: {name}')
    elif 'false' in outcomes:
        raise RuntimeError(f'CTL property failed: {name}')
    print(f'{name}: {outcomes.count("true")} true, {outcomes.count("false")} false',flush=True)
    return {'model':str(path.relative_to(ROOT)),'properties':properties,'outcomes':outcomes,
            'fair_receiver':fair,'threshold_result_overapproximation':abstract_ge}


def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    receipt=BUILD/'verification.json'; receipt.unlink(missing_ok=True)
    if not (TOOLS/'tool_versions.json').exists():
        raise SystemExit('Run python -m tools.setup_formal_tools first')
    common='rtl/aer_rr_select.v rtl/aer_rr_arbiter.v'
    yosys(f'read_verilog {common} formal/aer_scheduler.v; prep -top aer_scheduler -flatten; '
          'opt_clean; write_smv build/formal_checks/scheduler_raw.smv','scheduler')
    scheduler=[f'AG (bool(_pending[{p}:{p}]) -> AF bool(_served[{p}:{p}]))' for p in range(4)]
    scheduler+=['EF bool(_pending[3:3])','EF bool(_served[3:3])']
    checks=[ctl(BUILD/'scheduler_raw.smv','aer_scheduler','scheduler_fair',scheduler,fair=True)]
    checks.append(ctl(BUILD/'scheduler_raw.smv','aer_scheduler','scheduler_unfair',scheduler,expect_false=True))
    yosys(f'read_verilog rtl/aer_event_fifo.v {common} formal/aer_queues.v; '
          'prep -top aer_queues -flatten; memory_map; opt_clean; '
          'write_smv build/formal_checks/queues_raw.smv','queues')
    queue_props=[f'AG (bool(_pending[{p}:{p}]) -> AF bool(_accepted[{p}:{p}]))' for p in range(4)]
    queue_props += [f'AG (bool(_nonempty[{p}:{p}]) -> AF bool(_served[{p}:{p}]))' for p in range(4)]
    queue_props+=['EF bool(_pending[3:3])','EF bool(_served[3:3])']
    checks.append(ctl(BUILD/'queues_raw.smv','aer_queues','queues_fair',queue_props,fair=True))
    sat=yosys('read_verilog rtl/lif_transition.v formal/lif_refractory.v; '
              'prep -top lif_refractory -flatten; '
              'sat -verify -prove safe 1 -prove countdown_safe 1 -show-inputs -show-outputs; '
              'write_smv build/formal_checks/refractory_raw.smv','refractory')
    if 'no model found: SUCCESS!' not in sat:
        raise RuntimeError('Missing full-width refractory SAT proof')
    checks.append(ctl(BUILD/'refractory_raw.smv','lif_refractory','refractory_ctl',
                      ['AG bool(_safe)','EF (_refractory != 0ud16_0)','EF bool(_spike)'],abstract_ge=True))
    mutant=BUILD/'priority_mutant.v'
    mutant.write_text('module aer_rr_select(input wire [3:0] requests, input wire [1:0] next_port, '
        "output wire [3:0] grant); assign grant=requests[0]?4'b0001:requests[1]?4'b0010:"
        "requests[2]?4'b0100:requests[3]?4'b1000:4'b0; endmodule\n")
    yosys('read_verilog build/formal_checks/priority_mutant.v rtl/aer_rr_arbiter.v formal/aer_scheduler.v; '
          'prep -top aer_scheduler -flatten; opt_clean; '
          'write_smv build/formal_checks/priority_raw.smv','priority_mutant')
    checks.append(ctl(BUILD/'priority_raw.smv','aer_scheduler','priority_mutant',scheduler,
                      fair=True,expect_false=True))
    # Removing the actual refractory guard must invalidate the safety property.
    text=(ROOT/'rtl/lif_transition.v').read_text()
    old="if (refractory_in != 16'd0)"
    if text.count(old)!=1:
        raise RuntimeError('Refractory mutation site changed')
    (BUILD/'lif_mutant.v').write_text(text.replace(old,"if (1'b0)"))
    yosys('read_verilog build/formal_checks/lif_mutant.v formal/lif_refractory.v; '
          'prep -top lif_refractory -flatten; '
          'sat -falsify -prove safe 1 -show-inputs -show-outputs '
          '-dump_json build/formal_checks/lif_mutant_counterexample.json; '
          'write_smv build/formal_checks/lif_mutant_raw.smv','lif_mutant')
    checks.append(ctl(BUILD/'lif_mutant_raw.smv','lif_refractory','lif_mutant',
                      ['AG bool(_safe)'],abstract_ge=True,expect_false=True))
    files=[ROOT/'rtl'/name for name in ('aer_event_fifo.v','aer_rr_select.v','aer_rr_arbiter.v','lif_transition.v')]
    files+=list((ROOT/'formal').glob('*.v'))+[Path(__file__),ROOT/'tools/setup_formal_tools.py',ROOT/'requirements-formal.txt']
    tool_record=json.loads((TOOLS/'tool_versions.json').read_text())
    tool_record['python_packages']={dist.metadata['Name']:dist.version for dist in
                                   importlib.metadata.distributions(path=[str(TOOLS/'python')])}
    nusmv=next(TOOLS.rglob('NuSMV.exe'))
    tool_record['nusmv_executable_sha256']=hashlib.sha256(nusmv.read_bytes()).hexdigest()
    report={'tool_setup':tool_record,'checks':checks,
            'refractory_uncut_sat':'proved for all full-width inputs',
            'scope':'four depth-16 queues and scheduler under fair consumption; LIF update safety; not the complete SoC',
            'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    receipt.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: source-bound CTL/SAT proofs and expected negative controls',flush=True)


if __name__=='__main__':
    main()
