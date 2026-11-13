"""Prevent stale netlists from qualifying as current board-build evidence."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from tools import board_build_manifest as manifest

ROOT=Path(__file__).resolve().parents[1]


class BoardManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='manifest_test_')
        self.root=Path(self.temporary.name).resolve()
        self.assertTrue(self.root.is_relative_to(ROOT.resolve()))
        self.addCleanup(self.temporary.cleanup)
        files={
            'rtl/unit.v':'module unit; endmodule\n',
            'rtl/board/unit_board.v':'module unit_board; endmodule\n',
            'constraints/zybo_z710_demo.xdc':'create_clock -period 8 [get_ports clk]\n',
            'tools/zybo_demo_context.tcl':'# context fixture\n',
            'tools/board_build_manifest.py':'# metadata fixture\n',
            'tools/build_zybo_demo.tcl':'set ila_depth 1024\nsynth_design -part xc7z010clg400-1\n'
                'source [file join $root tools zybo_demo_context.tcl]\nplace_design -directive Explore\n',
            'build/board_demo/mnist/firmware.hex':'00000000\n',
            'build/board_demo/mnist/sample_count.txt':'20\n',
            'build/zybo_demo/mnist/ila_mode.txt':'1\n',
        }
        for name,data in files.items():
            path=self.root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(data)
        self.out=self.root/'build/zybo_demo/mnist'
        self.checkpoint=self.out/'synthesized.dcp'
        self.start_patch=patch.multiple(manifest,ROOT=self.root,RTL=['unit.v'])
        self.start_patch.start(); self.addCleanup(self.start_patch.stop)
        self.run_action('start')
        self.checkpoint.write_bytes(b'not a real FPGA netlist; cache test fixture')
        stamp=(self.out/'source_manifest.json').stat().st_mtime_ns+1000000000
        os.utime(self.checkpoint,ns=(stamp,stamp))
        self.run_action('seal-synth')

    def run_action(self,action):
        with patch('sys.argv',['manifest',action,'--scenario','mnist','--out',str(self.out)]):
            manifest.main()

    def test_changed_hardware_recipe_or_checkpoint_is_rejected(self):
        self.run_action('check-synth')
        for name in ['build/board_demo/mnist/firmware.hex','build/zybo_demo/mnist/ila_mode.txt',
                     'rtl/unit.v','constraints/zybo_z710_demo.xdc','tools/build_zybo_demo.tcl',
                     'build/zybo_demo/mnist/synthesized.dcp']:
            with self.subTest(path=name):
                path=self.root/name; original=path.read_bytes()
                # Prefix edits affect synthesis; other fixture edits change data.
                path.write_bytes(b'# changed\n'+original)
                with self.assertRaises(RuntimeError): self.run_action('check-synth')
                path.write_bytes(original)
        self.run_action('check-synth')

    def test_implementation_only_edits_can_reuse_the_same_netlist(self):
        path=self.root/'tools/build_zybo_demo.tcl'
        path.write_text(path.read_text().replace('place_design -directive Explore','place_design -directive Quick'))
        self.run_action('check-synth')
        self.run_action('start')
        self.run_action('check-synth')

    def test_failed_new_synthesis_cannot_rebind_an_old_checkpoint(self):
        (self.root/'build/board_demo/mnist/firmware.hex').write_text('FFFFFFFF\n')
        self.run_action('start')
        stamp=(self.out/'source_manifest.json').stat().st_mtime_ns-1000000000
        os.utime(self.checkpoint,ns=(stamp,stamp))
        with self.assertRaises(RuntimeError): self.run_action('check-synth')
        with self.assertRaises(RuntimeError): self.run_action('seal-synth')

    def test_finalization_requires_unchanged_inputs_and_checkpoint(self):
        (self.out/'zybo_demo.bit').write_bytes(b'test bitstream fixture')
        (self.out/'zybo_demo.ltx').write_bytes(b'test probes fixture')
        path=self.root/'tools/zybo_demo_context.tcl'; original=path.read_bytes()
        path.write_bytes(original+b'# edited after build start\n')
        with self.assertRaises(RuntimeError): self.run_action('finish')
        path.write_bytes(original)
        original=self.checkpoint.read_bytes(); self.checkpoint.write_bytes(original+b'corrupt')
        with self.assertRaises(RuntimeError): self.run_action('finish')
        self.checkpoint.write_bytes(original)
        self.run_action('finish')
        self.assertFalse(json.loads((self.out/'build_manifest.json').read_text())['physical_board_tested'])
