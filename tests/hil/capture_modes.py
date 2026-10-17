"""Sequence the live board by JTAG, then read USB HDMI directly; no desktop UI."""
from pathlib import Path
import subprocess,time
r=Path(__file__).resolve().parents[2];out=r/'results/2026-10-17/prd_completion';xsct=r'D:/Xilinx/SDK/2018.3/bin/xsct.bat'
def command(*words):
 p=subprocess.run([xsct,str(r/'hw/scripts/jtag_console.tcl'),*words],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=80)
 with (out/'hdmi_commands.log').open('a',encoding='utf-8') as f:f.write(p.stdout)
 assert p.returncode==0 and 'JTAG_COMMAND_PASS' in p.stdout,p.stdout
command('selftest');command('adc','source','real');command('memory','capture')
for mode in ['dso','dpx','eye','fft','roll','mem','seg']:
 command('mode',mode);time.sleep(1.2 if mode=='seg' else .5)
 subprocess.run([r'D:/Anaconda/python.exe',str(r/'tests/hil/capture_hdmi.py'),'--output',str(out/f'HDMI_{mode.upper()}_real.png')],check=True,timeout=30)
command('mode','dso');command('adc','source','sim');time.sleep(.3)
subprocess.run([r'D:/Anaconda/python.exe',str(r/'tests/hil/capture_hdmi.py'),'--output',str(out/'HDMI_SIM_warning.png')],check=True,timeout=30)
command('adc','source','real');time.sleep(.3)
subprocess.run([r'D:/Anaconda/python.exe',str(r/'tests/hil/capture_hdmi.py'),'--output',str(out/'HDMI_REAL_final.png')],check=True,timeout=30)
print('LIVE_HDMI_MODES_PASS')
