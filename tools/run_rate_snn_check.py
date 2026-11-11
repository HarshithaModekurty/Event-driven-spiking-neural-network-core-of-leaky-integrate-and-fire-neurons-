"""Compare intensity -> hardware encoder -> AER -> 256 LIF states with Python."""
from pathlib import Path
import argparse
import hashlib
import json
import random
import subprocess
from golden_model import RateEncoder,LIFConfig,SNNGoldenModel

ROOT=Path(__file__).resolve().parents[1]
RTL=['rate_encoder_transition.v','aer_rate_encoder.v','aer_event_fifo.v','aer_rr_select.v',
     'aer_rr_arbiter.v','lif_transition.v','lif_population_stepper.v','lif_synapse_router.v',
     'lif_snn_core.v','lif_aer_snn_core.v','lif_rate_aer_snn_core.v','tb/lif_rate_snn_tb.v']


def export(folder,scenario,samples):
    folder.mkdir(parents=True,exist_ok=True)
    records=[]
    if scenario=='mnist':
        from tools import run_mnist_rtl_check as classifier
        from examples import mnist256_demo as mnist
        from examples import mnist_live_demo as images
        manifest=classifier.export(argparse.Namespace(train_count=12000,epochs=5,seed=91,
                                                     samples=samples,retrain=False,show_images=False))
        checkpoint=json.loads((classifier.BUILD/'trained_weights.json').read_text())
        model=mnist.make_model(checkpoint['quantized_weights'])
        test_images,_,_=images.load_images(images.DATA_DIR/images.MNIST_FILES[2])
        values=[[255*x for x in mnist.features_from_image(test_images[s['test_index']])]+[255]+[0]*30
                for s in manifest['samples']]
        records=manifest['samples']
        config=dict(THRESHOLD=65535,RESET_VALUE=0,LEAK_ENABLE=0,REFRACTORY_PERIOD=0,REQUIRE_FULL_OUTPUT=0)
    else:
        model=SNNGoldenModel(256,LIFConfig(threshold=8,reset_value=3,leak_shift=2,refractory_period=2))
        for source in range(256):
            model.set_weight(source,(source+1)%256,7); model.set_weight(source,source,-2)
        rng=random.Random(20261111)
        values=[[255]*256,[([0,1,64,127,128,129,254,255][n%8]) for n in range(256)],
                [rng.randrange(256) for _ in range(256)]]
        config=dict(THRESHOLD=8,RESET_VALUE=3,LEAK_ENABLE=1,REFRACTORY_PERIOD=2,REQUIRE_FULL_OUTPUT=1)
    weights=''.join(f'{weight&15:X}\n' for row in model.weights for weight in row)
    (folder/'weights.hex').write_text(weights)
    (folder/'intensities.hex').write_text(''.join(f'{v:02X}\n' for image in values for v in image))
    encoder_packets=[]; output_packets=[]; states=[]
    for image_number,image in enumerate(values):
        encoder=RateEncoder(256); model.reset()
        for _ in range(8):
            events=encoder.encode_tick(image)
            fired=model.step(events)
            encoder_packets+=events+[256]; output_packets+=fired+[256]
            packed=sum(1<<n for n in fired)
            for n,neuron in enumerate(model.neurons):
                packed|=neuron.membrane<<(256+16*n)
                packed|=neuron.refractory_remaining<<(4352+16*n)
            states.append(packed)
        if scenario=='mnist':
            assert [n.membrane for n in model.neurons[246:]]==records[image_number]['scores']
    for name,packets in [('encoder_packets.hex',encoder_packets),('output_packets.hex',output_packets)]:
        (folder/name).write_text(''.join(f'{packet:03X}\n' for packet in packets))
    (folder/'states.hex').write_text(''.join(f'{state:02112X}\n' for state in states))
    metadata={'scenario':scenario,'images':len(values),'frames':len(states),'neuron_states':256,
              'synapse_entries':65536,'state_updates_checked':len(states)*256,
              'encoder_packets':len(encoder_packets),'output_packets':len(output_packets),
              'weights_sha256':hashlib.sha256((folder/'weights.hex').read_bytes()).hexdigest(),
              'records':records}
    if scenario=='mnist':
        metadata.update(correct=manifest['correct'],accuracy_percent=100*manifest['correct']/samples)
    params={'FRAMES':len(states),'IMAGES':len(values),'INPUT_WORDS':len(encoder_packets),
            'OUTPUT_WORDS':len(output_packets),**config}
    (folder/'vectors.json').write_text(json.dumps(metadata,indent=2)+'\n')
    generics=' '.join(f'{k}={v}' for k,v in params.items())
    (folder/'configure_vivado.tcl').write_text(
        'set_property top lif_rate_snn_tb [get_filesets sim_1]\n'
        f'set_property generic {{{generics}}} [get_filesets sim_1]\n'
        f'set_property -dict [list xsim.simulate.xsim.more_options {{-testplusarg "DATA_DIR={folder.as_posix()}"}}] [get_filesets sim_1]\n'
        'update_compile_order -fileset sim_1\n')
    return metadata,params


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario',choices=('stress','mnist'),default='stress')
    parser.add_argument('--simulator',choices=('iverilog','xsim'),default='iverilog')
    parser.add_argument('--samples',type=int,default=20)
    parser.add_argument('--generate-only',action='store_true')
    parser.add_argument('--vivado-bin',default='F:/Xilinx/Vivado/2023.2/bin')
    args=parser.parse_args()
    if not 1<=args.samples<=10000: parser.error('--samples must be 1..10000')
    folder=ROOT/'build'/('rate_mnist' if args.scenario=='mnist' else 'rate_network')
    metadata,params=export(folder,args.scenario,args.samples)
    if args.generate_only:
        print('Generated',metadata['frames'],'hardware-encoded network steps in',folder); return
    sources=[ROOT/'rtl'/name for name in RTL]
    receipt=folder/f'{args.simulator}_verification.json'; receipt.unlink(missing_ok=True)
    if args.simulator=='iverilog':
        exe=folder/'rate_snn.vvp'
        command=['iverilog','-g2005','-s','lif_rate_snn_tb','-o',str(exe)]
        for name,value in params.items(): command+=['-P',f'lif_rate_snn_tb.{name}={value}']
        subprocess.run(command+list(map(str,sources)),cwd=ROOT,check=True,timeout=120)
        command=['vvp',str(exe),f'+DATA_DIR={folder.as_posix()}']; cwd=ROOT
    else:
        cwd=folder/'xsim'; cwd.mkdir(exist_ok=True); binary=Path(args.vivado_bin)
        subprocess.run([str(binary/'xvlog.bat'),*map(str,sources)],cwd=cwd,check=True,timeout=120)
        command=subprocess.list2cmdline([str(binary/'xelab.bat'),'work.lif_rate_snn_tb',
                                         '-s','rate_snn','--timescale','1ns/1ps'])
        command+=''.join(f' --generic_top "{name}={value}"' for name,value in params.items())
        subprocess.run(command,cwd=cwd,check=True,timeout=120)
        command=subprocess.list2cmdline([str(binary/'xsim.bat'),'rate_snn','--runall','--log','xsim.log'])
        command+=f' --testplusarg "DATA_DIR={folder.as_posix()}"'
    # A live log distinguishes this run from previous completed evidence.
    log_path=folder/f'{args.simulator}.log'
    with log_path.open('w') as stream:
        subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,timeout=1800,check=True)
    log=log_path.read_text(); print(log,end='')
    if 'PASS: rate/AER/SNN' not in log or 'FAIL:' in log or 'FATAL:' in log or 'ERROR:' in log:
        raise RuntimeError('Hardware-encoded network comparison failed; inspect simulator log')
    report={k:v for k,v in metadata.items() if k!='records'}
    report.update(simulator=args.simulator,parameters=params)
    references=[ROOT/'golden_model'/name for name in ('encoding.py','network.py','lif.py')]
    report['source_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sources+references}
    report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.hex')}
    receipt.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
