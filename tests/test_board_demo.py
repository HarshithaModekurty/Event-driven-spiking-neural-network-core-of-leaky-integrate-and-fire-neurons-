from pathlib import Path
import subprocess
import tempfile
import unittest
from tools.board_demo import ROOT, verify_uart, verify_ila


class BoardDemoTests(unittest.TestCase):
    def test_uart_production_baud_and_reset(self):
        folder=ROOT/'build'/'board_unit'; folder.mkdir(parents=True,exist_ok=True)
        subprocess.run(['iverilog','-g2005','-s','uart_tx_tb','-o',str(folder/'uart.vvp'),
                        'rtl/board/uart_tx.v','rtl/tb/uart_tx_tb.v'],cwd=ROOT,check=True)
        result=subprocess.run(['vvp',str(folder/'uart.vvp')],cwd=ROOT,check=True,capture_output=True,text=True)
        self.assertIn('PASS: UART production divisor 868',result.stdout)

    def test_reporter_dual_port_pause_overflow_and_serial(self):
        folder=ROOT/'build'/'board_unit'; folder.mkdir(parents=True,exist_ok=True)
        output=folder/'capture.txt'
        subprocess.run(['iverilog','-g2005','-s','demo_reporter_tb','-o',str(folder/'reporter.vvp'),
                        'rtl/board/uart_tx.v','rtl/board/snn_demo_reporter.v','rtl/tb/demo_reporter_tb.v'],cwd=ROOT,check=True)
        result=subprocess.run(['vvp',str(folder/'reporter.vvp'),f'+OUTPUT={output.as_posix()}'],cwd=ROOT,check=True,capture_output=True,text=True)
        self.assertIn('PASS:',result.stdout)
        expected='C,00,9'+''.join(f',{0x1230+n:04X}' for n in range(10))+'\n'
        expected+='I,00,0,005\nO,00,0,0FA\nI,00,0,100\nO,00,0,100\nI,00,1,006\nO,00,1,0FB\n'
        self.assertEqual(output.read_text(),expected)

    def test_capture_checker_rejects_wrong_class_score_or_packet(self):
        record=dict(python_prediction=3,scores=list(range(10)),
                    input_packets=[[256] for _ in range(8)],output_packets=[[256] for _ in range(8)])
        reference=dict(samples=[record])
        text='C,00,3'+''.join(f',{n:04X}' for n in range(10))+'\n'
        text+=''.join(f'{kind},00,{tick},100\n' for tick in range(8) for kind in ['I','O'])
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'capture.txt'; path.write_text(text)
            self.assertEqual(verify_uart(reference,path),1)
            for bad in [text.replace('C,00,3','C,00,2'),text.replace(',0009',',000A'),text.replace('I,00,7,100\n','')]:
                path.write_text(bad)
                with self.assertRaises(ValueError): verify_uart(reference,path)

    def test_ila_csv_little_endian_score_bank(self):
        reference=dict(samples=[dict(python_prediction=9,scores=list(range(10)))])
        packed=sum(n<<(16*n) for n in range(10))
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'ila.csv'
            path.write_text('Sample in Buffer,snapshot_pulse,sample_index[7:0],predicted_digit[3:0],scores[159:0],error\n'
                            f'0,1,00,9,{packed:040X},0\n')
            self.assertEqual(verify_ila(reference,path),1)
            path.write_text(path.read_text().replace(',9,',',8,'))
            with self.assertRaises(ValueError): verify_ila(reference,path)


if __name__=='__main__': unittest.main()
