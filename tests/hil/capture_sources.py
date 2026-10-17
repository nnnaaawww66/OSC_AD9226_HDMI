from pathlib import Path
import subprocess,av
r=Path(__file__).resolve().parents[2];out=r/'results/2026-10-17/prd_completion'
def cmd(*words):
 p=subprocess.run([r'D:/Xilinx/SDK/2018.3/bin/xsct.bat',str(r/'hw/scripts/jtag_console.tcl'),*words],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=30)
 print(p.stdout,flush=True);assert 'JTAG_COMMAND_PASS' in p.stdout
# Open the device before changing the source, then retain one stream across both snapshots.
with av.open('video=USB3 Video',format='dshow',options={'video_size':'1280x720','framerate':'30'}) as source:
 try:
  cmd('mode','dso');cmd('adc','source','sim')
  for i,frame in enumerate(source.decode(video=0)):
   if i>=60:frame.to_image().save(out/'HDMI_SIM_warning.png');break
 finally:cmd('adc','source','real')
 for i,frame in enumerate(source.decode(video=0)):
  if i>=60:frame.to_image().save(out/'HDMI_REAL_final.png');break
print('LIVE_SOURCE_CAPTURES_PASS')
