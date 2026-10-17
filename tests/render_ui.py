from pathlib import Path
import subprocess,json,shutil
r=Path(__file__).resolve().parents[1];out=r/'results/2026-10-17/ui_sim';out.mkdir(exist_ok=True)
subprocess.run(['gcc','-std=c99','-O2','-Wall','-Wextra','-I'+str(r/'tests/host'),'-I'+str(r/'sw/include'),str(r/'tests/host/render_ui.c'),str(r/'sw/src/scope_analysis.c'),'-lm','-o',str(out/'render_ui.exe')],check=True)
p=subprocess.run([str(out/'render_ui.exe')],cwd=out,text=True,stdout=subprocess.PIPE,check=True);(out/'host_test.log').write_text(p.stdout);print(p.stdout)
for f in ['font_hi.mem','font_mid.mem','font_lo.mem','screen.mem']:shutil.copy2(r/'hw/rtl'/f,out/f)
bin=Path(r'D:/Xilinx/Vivado/2018.3/bin');commands=[['xvlog.bat','-sv',str(r/'hw/rtl/scope_video_timing.v'),str(r/'hw/rtl/scope_display.v'),str(r/'sim/tb_display.sv')],['xelab.bat','tb_display','-s','display_render','-mt','4'],['xsim.bat','display_render','-R']]
log=''
for cmd in commands:
 p=subprocess.run([str(bin/cmd[0]),*cmd[1:]],cwd=out,text=True,encoding='utf-8',errors='replace',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180);log+=p.stdout
 if p.returncode:break
(out/'rtl_display.log').write_text(log);assert 'PASS display' in log,log[-4000:]
import re,zlib
raw=(out/'ui_rtl.ppm').read_bytes().split(b'\n',3)[3]
expected=zlib.crc32(raw)
actual=int(re.search(r'PIXEL_CRC32=([0-9a-fA-F]+)',log).group(1),16)
assert expected==actual, f'pixel CRC mismatch: Python {expected:08x}, RTL {actual:08x}'
print(f'PASS independent RGB frame CRC32 {actual:08x}')
from PIL import Image
Image.open(out/'ui_rtl.ppm').save(out/'ui_rtl.png')
print('PASS actual RTL image:',out/'ui_rtl.png')
