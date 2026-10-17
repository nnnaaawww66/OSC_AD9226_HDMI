"""Read the named HDMI USB capture device directly; no desktop interaction."""
import argparse,time
from pathlib import Path
import av
p=argparse.ArgumentParser();p.add_argument('--device',default='USB3 Video');p.add_argument('--output',required=True);p.add_argument('--warmup',type=int,default=30);a=p.parse_args()
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
with av.open('video='+a.device,format='dshow',options={'video_size':'1280x720','framerate':'30'}) as source:
 for i,frame in enumerate(source.decode(video=0)):
  if i>=a.warmup:
   frame.to_image().save(out);print('HDMI_CAPTURE',frame.width,frame.height,out);break
 else:raise RuntimeError('HDMI capture ended before a frame arrived')
