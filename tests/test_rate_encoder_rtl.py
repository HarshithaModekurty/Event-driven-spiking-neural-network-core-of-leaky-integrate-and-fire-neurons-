"""Rate arithmetic and streaming phase behavior against the existing encoder."""
from pathlib import Path
import random
import shutil
import subprocess
import unittest
from golden_model import RateEncoder

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/rate_encoder'


@unittest.skipUnless(shutil.which('iverilog') and shutil.which('vvp'),'requires Icarus')
class RateEncoderRTLTests(unittest.TestCase):
    def run_rtl(self,top,sources,args,parameters=()):
        exe=BUILD/f'{top}.vvp'
        command=['iverilog','-g2005','-s',top,'-o',str(exe)]
        for name,value in parameters:
            command+=['-P',f'{top}.{name}={value}']
        subprocess.run(command+[str(ROOT/'rtl'/name) for name in sources],cwd=ROOT,
                       check=True,capture_output=True,text=True,timeout=60)
        result=subprocess.run(['vvp',str(exe),*args],cwd=ROOT,check=True,
                              capture_output=True,text=True,timeout=60)
        self.assertIn('PASS:',result.stdout)

    def test_all_legal_phase_intensity_combinations(self):
        BUILD.mkdir(parents=True,exist_ok=True)
        model=RateEncoder(1)
        path=BUILD/'arithmetic.txt'
        with path.open('w') as stream:
            for phase in range(255):
                for intensity in range(256):
                    model.accumulators[0]=phase
                    fired=model.encode_tick([intensity])
                    stream.write(f'{phase} {intensity} {int(bool(fired))} {model.accumulators[0]}\n')
        self.run_rtl('rate_encoder_transition_tb',['rate_encoder_transition.v','tb/rate_encoder_transition_tb.v'],
                     [f'+VECTORS={path.as_posix()}'])

    def test_phase_continuity_stalls_cancellation_and_sample_clear(self):
        BUILD.mkdir(parents=True,exist_ok=True)
        rng=random.Random(1110)
        values=[0,1,2,64,127,128,129,254,255]+[rng.randrange(256) for _ in range(246)]+[255]
        model=RateEncoder(256)
        packets=[]; phases=[]
        for tick in range(32):
            if tick==16:
                model.reset()
            packets+=model.encode_tick(values)+[256]
            phases.append(sum(phase<<(8*source) for source,phase in enumerate(model.accumulators)))
        (BUILD/'intensities.hex').write_text(''.join(f'{value:02X}\n' for value in values))
        (BUILD/'packets.hex').write_text(''.join(f'{packet:03X}\n' for packet in packets))
        (BUILD/'phases.hex').write_text(''.join(f'{phase:0512X}\n' for phase in phases))
        self.run_rtl('aer_rate_encoder_tb',['rate_encoder_transition.v','aer_rate_encoder.v','tb/aer_rate_encoder_tb.v'],
                     [f'+DATA_DIR={BUILD.as_posix()}'],[('TICKS',32),('PACKETS',len(packets))])
