"""Boot real RV32I firmware and compare AXI-loaded 256-state inference to Python."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
from tools.run_rate_snn_check import RTL as RATE_RTL, export as export_rate
from tools.rv32_assemble import assemble

ROOT=Path(__file__).resolve().parents[1]
RTL=[n for n in RATE_RTL if not n.startswith('tb/')]+[
    'vendor/picorv32.v','axi_lite_endpoint.v','lif_host_registers.v','lif_rv32_soc.v','tb/lif_rv32_soc_tb.v']


def export(folder,scenario,samples):
    metadata,params=export_rate(folder,scenario,samples)
    if metadata['images']>20: raise ValueError('Boot RAM layout supports at most 20 test images')
    weights=[int(x,16) for x in (folder/'weights.hex').read_text().split()]
    intensities=bytes(int(x,16) for x in (folder/'intensities.hex').read_text().split())
    states=[int(x,16) for x in (folder/'states.hex').read_text().split()]
    predictions=[]
    for i in range(metadata['images']):
        last=states[i*8+7]
        scores=[(last>>(256+16*n))&65535 for n in range(246,256)]
        predictions.append(max(range(10),key=lambda n:scores[n]))
    constants={**params,'LEAK_CONFIG':(params['LEAK_ENABLE']<<8)|2}
    code=assemble((ROOT/'firmware/snn_boot.S').read_text(),constants)
    assert len(code)*4<=0x1000
    memory=bytearray(65536)
    for i,word in enumerate(code): memory[4*i:4*i+4]=word.to_bytes(4,'little')
    memory[0x1000:0x9000]=bytes(weights[i]|weights[i+1]<<4 for i in range(0,65536,2))
    memory[0x9000:0x9000+len(intensities)]=intensities
    for i,pred in enumerate(predictions): memory[0xb000+4*i:0xb004+4*i]=pred.to_bytes(4,'little')
    (folder/'firmware.hex').write_text(''.join(f'{int.from_bytes(memory[i:i+4],"little"):08X}\n' for i in range(0,65536,4)))
    (folder/'predictions.hex').write_text(''.join(f'{n:08X}\n' for n in predictions))
    params={k:params[k] for k in ('IMAGES','FRAMES','INPUT_WORDS','OUTPUT_WORDS')}
    metadata['firmware_instructions']=len(code)
    metadata['cpu_predictions']=predictions
    generics=' '.join(f'{k}={v}' for k,v in params.items())
    (folder/'configure_vivado.tcl').write_text(
        'set_property top lif_rv32_soc_tb [get_filesets sim_1]\n'
        f'set_property generic {{{generics}}} [get_filesets sim_1]\n'
        f'set_property -dict [list xsim.simulate.xsim.more_options {{-testplusarg "DATA_DIR={folder.as_posix()}"}}] [get_filesets sim_1]\n'
        'update_compile_order -fileset sim_1\n')
    (folder/'vectors.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata,params


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario',choices=('stress','mnist'),default='stress')
    parser.add_argument('--simulator',choices=('iverilog','xsim'),default='iverilog')
    parser.add_argument('--samples',type=int,default=20)
    parser.add_argument('--generate-only',action='store_true')
    parser.add_argument('--vivado-bin',default='F:/Xilinx/Vivado/2023.2/bin')
    args=parser.parse_args()
    if not 1<=args.samples<=20: parser.error('--samples must be 1..20')
    folder=ROOT/'build'/('rv32_mnist' if args.scenario=='mnist' else 'rv32_network')
    meta,params=export(folder,args.scenario,args.samples)
    if args.generate_only: print('Generated RV32 boot image:',folder); return
    receipt=folder/f'{args.simulator}_verification.json';receipt.unlink(missing_ok=True)
    sources=[ROOT/'rtl'/n for n in RTL]
    if args.simulator=='iverilog':
        exe=folder/'soc.vvp';command=['iverilog','-g2005','-s','lif_rv32_soc_tb','-o',str(exe)]
        for k,v in params.items(): command+=['-P',f'lif_rv32_soc_tb.{k}={v}']
        subprocess.run(command+list(map(str,sources)),check=True,cwd=ROOT,timeout=120)
        command=['vvp',str(exe),f'+DATA_DIR={folder.as_posix()}'];cwd=ROOT
    else:
        cwd=folder/'xsim';cwd.mkdir(exist_ok=True);binary=Path(args.vivado_bin)
        subprocess.run([str(binary/'xvlog.bat'),*map(str,sources)],cwd=cwd,check=True,timeout=120)
        command=subprocess.list2cmdline([str(binary/'xelab.bat'),'work.lif_rv32_soc_tb','-s','rv32_soc','--timescale','1ns/1ps'])
        command+=''.join(f' --generic_top "{k}={v}"' for k,v in params.items())
        subprocess.run(command,cwd=cwd,check=True,timeout=180)
        command=subprocess.list2cmdline([str(binary/'xsim.bat'),'rv32_soc','--runall','--log','xsim.log'])
        command+=f' --testplusarg "DATA_DIR={folder.as_posix()}"'
    log_path=folder/f'{args.simulator}.log'
    with log_path.open('w') as stream:
        subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=3600)
    log=log_path.read_text();print(log,end='')
    if 'PASS: real RV32/AXI boot' not in log or any(s in log for s in ('FAIL:','FATAL:','ERROR:')):
        raise RuntimeError('CPU/AXI comparison failed; inspect log')
    refs=[ROOT/'firmware/snn_boot.S',Path(__file__),ROOT/'tools/rv32_assemble.py',ROOT/'tools/run_rate_snn_check.py']
    refs += [ROOT/'golden_model'/n for n in ('encoding.py','lif.py','network.py')]
    report={k:v for k,v in meta.items() if k!='records'}
    report.update(simulator=args.simulator,parameters=params,
        source_sha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+refs},
        artifact_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.hex')})
    receipt.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
