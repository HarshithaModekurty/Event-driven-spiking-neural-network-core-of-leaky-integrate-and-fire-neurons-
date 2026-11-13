"""Exercise real RV32 inference with per-image pauses and wire-decoded UART."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from tools.board_demo import prepare, verify_uart
from tools.run_rv32_check import RTL, ROOT


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario',choices=['mnist','stress'],default='stress')
    parser.add_argument('--samples',type=int,default=20)
    parser.add_argument('--vivado-bin',default='F:/Xilinx/Vivado/2023.2/bin')
    args=parser.parse_args()
    if not 1<=args.samples<=20: parser.error('--samples must be 1..20')
    folder=prepare(args.scenario,args.samples)
    meta=json.loads((folder/'vectors.json').read_text())
    params=dict(IMAGES=meta['images'],FRAMES=meta['frames'],INPUT_WORDS=meta['encoder_packets'],OUTPUT_WORDS=meta['output_packets'])
    sources=[ROOT/'rtl'/name for name in RTL if not name.startswith('tb/')]
    sources += [ROOT/'rtl'/name for name in ['board/uart_tx.v','board/snn_demo_reporter.v','tb/lif_board_demo_tb.v']]
    refs=sources+[Path(__file__),ROOT/'tools/board_demo.py',ROOT/'tools/run_rv32_check.py',ROOT/'tools/run_rate_snn_check.py',ROOT/'tools/rv32_assemble.py',ROOT/'firmware/snn_boot.S']
    source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in refs}
    receipt=folder/'xsim_verification.json'; receipt.unlink(missing_ok=True)
    binary=Path(args.vivado_bin); cwd=folder/'xsim'; cwd.mkdir(exist_ok=True)
    subprocess.run([str(binary/'xvlog.bat'),*map(str,sources)],cwd=cwd,check=True,timeout=120)
    command=subprocess.list2cmdline([str(binary/'xelab.bat'),'work.lif_board_demo_tb','-s','board_soc','--timescale','1ns/1ps'])
    command+=''.join(f' --generic_top "{k}={v}"' for k,v in params.items())
    subprocess.run(command,cwd=cwd,check=True,timeout=180)
    command=subprocess.list2cmdline([str(binary/'xsim.bat'),'board_soc','--runall','--log','xsim.log'])
    command+=f' --testplusarg "DATA_DIR={folder.as_posix()}"'
    with (folder/'xsim.log').open('w') as stream:
        subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=3600)
    log=(folder/'xsim.log').read_text(); print(log,end='')
    if 'PASS: board UART/LED/ILA snapshot flow' not in log or any(x in log for x in ['FAIL:','FATAL:','ERROR:']):
        raise RuntimeError('Board simulation failed; inspect log')
    verify_uart(json.loads((folder/'reference.json').read_text()),folder/'uart_capture.txt')
    if source_hashes!={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in refs}:
        raise RuntimeError('Sources changed during simulation; rerun before recording evidence')
    report=dict(scenario=args.scenario,parameters=params,simulator='xsim',uart_clocks_per_bit=4,
                physical_board_tested=False,source_sha256=source_hashes,
                artifact_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.hex')})
    receipt.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
