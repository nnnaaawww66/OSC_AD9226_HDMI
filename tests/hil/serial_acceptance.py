"""Actual-board smoke/soak harness. No hardware results are fabricated when no CH340 is connected."""
import argparse,time,sys,json,datetime
from pathlib import Path
import serial
from serial.tools.list_ports import comports
p=argparse.ArgumentParser();p.add_argument('--port');p.add_argument('--mode-cycles',type=int,default=7);p.add_argument('--soak-seconds',type=int,default=0);a=p.parse_args()
ports=[x.device for x in comports() if x.vid==0x1a86]
if not a.port:
 if len(ports)!=1:sys.exit('BLOCKED: connect the intended CH340E UART, or specify --port explicitly.')
 a.port=ports[0]
root=Path(__file__).resolve().parents[2];out=root/'results/2026-10-17/hil';out.mkdir(exist_ok=True)
raw=(out/'uart.bin').open('ab');log=(out/'uart.log').open('a',encoding='utf-8')
s=serial.Serial(a.port,115200,timeout=.1);results=[]
def command(text,expect,timeout=8):
 s.write((text+'\r\n').encode());start=time.monotonic();seen=[]
 while time.monotonic()-start<timeout:
  data=s.readline()
  if not data:continue
  raw.write(data);raw.flush();line=data.decode('ascii','replace').strip();seen.append(line)
  log.write(datetime.datetime.now(datetime.timezone.utc).isoformat()+' '+line+'\n');log.flush()
  if line.startswith('ERR'):raise RuntimeError(text+': '+line)
  if line.startswith('OK ') and expect in line:
   results.append({'command':text,'response':line,'elapsed_s':time.monotonic()-start});return line
 raise TimeoutError(text+': '+repr(seen))
try:
 command('ver','product=Z7_SCOPE');command('adc source sim','source=SIM');command('selftest','selftest=PASS',30)
 for mode in ['dso','dpx','eye','fft','roll','mem','seg']:
  command('mode '+mode,'mode='+mode.upper());command('status','mode='+mode.upper())
 for i in range(max(0,a.mode_cycles-7)):
  mode=['dso','dpx','eye','fft','roll'][i%5];command('mode '+mode,'mode='+mode.upper())
 deadline=time.monotonic()+a.soak_seconds
 while time.monotonic()<deadline:
  command('status','errors=00000000');time.sleep(1)
 (out/'result.json').write_text(json.dumps({'status':'PASS','port':a.port,'mode_cycles':a.mode_cycles,'soak_seconds':a.soak_seconds,'responses':results},indent=2))
 print('PASS hardware serial checks; HDMI and analog-instrument observations remain separate evidence.')
finally:s.close();raw.close();log.close()
