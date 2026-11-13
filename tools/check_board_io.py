"""Simulate the actual vendor MMCM and board reset/button wrapper with Xsim."""
from pathlib import Path
import hashlib
import json
import subprocess
from tools.run_rv32_check import ROOT, RTL


def main():
    binary=Path('F:/Xilinx/Vivado/2023.2/bin')
    folder=ROOT/'build'/'board_io'; folder.mkdir(parents=True,exist_ok=True)
    sources=[ROOT/'rtl'/name for name in RTL if not name.startswith('tb/')]
    sources+=list((ROOT/'rtl'/'board').glob('*.v'))+[ROOT/'rtl'/'tb'/'board_io_tb.v']
    sources+=[binary.parent/'data'/'verilog'/'src'/'glbl.v']
    refs=[p for p in sources if p.is_relative_to(ROOT)]+[Path(__file__)]
    source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in refs}
    subprocess.run([str(binary/'xvlog.bat'),*map(str,sources)],cwd=folder,check=True,timeout=120)
    subprocess.run([str(binary/'xelab.bat'),'work.board_io_tb','work.glbl','-L','unisims_ver','-L','secureip',
                    '-s','board_io','--timescale','1ns/1ps'],cwd=folder,check=True,timeout=180)
    subprocess.run([str(binary/'xsim.bat'),'board_io','--runall','--log','board_io.log'],cwd=folder,check=True,timeout=120)
    log=(folder/'board_io.log').read_text()
    if 'PASS: actual MMCM' not in log or any(x in log for x in ['FAIL:','FATAL:','ERROR:']):
        raise RuntimeError('Board IO simulation failed')
    if source_hashes!={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in refs}:
        raise RuntimeError('Sources changed during board IO simulation')
    (folder/'verification.json').write_text(json.dumps(dict(simulator='xsim',physical_board_tested=False,
         source_sha256=source_hashes,log_sha256=hashlib.sha256((folder/'board_io.log').read_bytes()).hexdigest()),indent=2)+'\n')


if __name__=='__main__': main()
