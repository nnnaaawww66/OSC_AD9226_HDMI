from pathlib import Path
import subprocess
from PIL import Image
r=Path(__file__).resolve().parents[1];out=r/'results/2026-10-17/ui_sim';bin=Path(r'D:/Xilinx/Vivado/2018.3/bin')
commands=[['xvlog.bat','-sv',str(r/'hw/rtl/scope_video_timing.v'),str(r/'hw/rtl/scope_display.v'),str(r/'sim/tb_display.sv'),str(r/'sim/tb_display_vga.sv')],['xelab.bat','tb_display_vga','-s','display_vga','-mt','4'],['xsim.bat','display_vga','-R']]
log=''
for cmd in commands:
 p=subprocess.run([str(bin/cmd[0]),*cmd[1:]],cwd=out,text=True,encoding='utf-8',errors='replace',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180);log+=p.stdout
 if p.returncode:break
(out/'vga_display.log').write_text(log);assert 'PASS display' in log,log[-5000:]
im=Image.open(out/'ui_rtl.ppm');assert im.size==(640,480);im.save(out/'ui_vga.png');print('PASS 640x480 adaptive RTL render')
