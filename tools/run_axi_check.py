"""Exercise the AXI4-Lite endpoint and actual 256-state SNN peripheral."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from tools.run_rate_snn_check import RTL as RATE_RTL

ROOT=Path(__file__).resolve().parents[1]
RTL=[n for n in RATE_RTL if not n.startswith('tb/')]+[
    'axi_lite_endpoint.v','lif_host_registers.v','lif_axi_lite.v','tb/lif_axi_lite_tb.v']


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator',choices=('iverilog','xsim'),default='iverilog')
    args=parser.parse_args()
    folder=ROOT/'build/axi_protocol';folder.mkdir(parents=True,exist_ok=True)
    receipt=folder/f'{args.simulator}_verification.json';receipt.unlink(missing_ok=True)
    sources=[ROOT/'rtl'/n for n in RTL]
    if args.simulator=='iverilog':
        exe=folder/'axi.vvp'
        subprocess.run(['iverilog','-g2005','-s','lif_axi_lite_tb','-o',str(exe),*map(str,sources)],check=True,timeout=120)
        command=['vvp',str(exe)];cwd=ROOT
    else:
        cwd=folder/'xsim';cwd.mkdir(exist_ok=True);binary=Path('F:/Xilinx/Vivado/2023.2/bin')
        subprocess.run([str(binary/'xvlog.bat'),*map(str,sources)],cwd=cwd,check=True,timeout=120)
        subprocess.run([str(binary/'xelab.bat'),'work.lif_axi_lite_tb','-s','axi','--timescale','1ns/1ps'],cwd=cwd,check=True,timeout=180)
        command=[str(binary/'xsim.bat'),'axi','--runall','--log','xsim.log']
    log_path=folder/f'{args.simulator}.log'
    with log_path.open('w') as stream:
        subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=600)
    log=log_path.read_text();print(log,end='')
    if 'PASS: independent AXI' not in log or any(s in log for s in ('FAIL:','FATAL:','ERROR:')):
        raise RuntimeError('AXI peripheral verification failed')
    receipt.write_text(json.dumps({'simulator':args.simulator,'source_sha256':{
        p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__)]}},indent=2)+'\n')


if __name__=='__main__': main()
