"""Independent direct-USB video/UI endurance monitor; never touches JTAG or UART.

This observes the captured 30fps stream, not the physical 60Hz TMDS clock.
The JTAG test independently checks the actual ADC/video hardware counters.
"""
from pathlib import Path
import argparse
import datetime
import json
import time
import zlib

import av
import numpy as np
from PIL import Image

root=Path(__file__).resolve().parents[2]
folder=root/'results/2026-10-17/prd_completion'
parser=argparse.ArgumentParser()
parser.add_argument('--seconds',type=float,default=3605)
parser.add_argument('--check-fixtures',action='store_true')
args=parser.parse_args()


def sim_fraction(rgb):
    bar=rgb[62:68,32:1248]
    return float(np.mean((bar[:,:,0]>150)&(bar[:,:,1]>90)&(bar[:,:,2]<140)))


if args.check_fixtures:
    assert sim_fraction(np.asarray(Image.open(folder/'HDMI_SIM_warning.png').convert('RGB')))>0.95
    assert sim_fraction(np.asarray(Image.open(folder/'HDMI_REAL_final.png').convert('RGB')))<0.05
    print('HDMI_SOURCE_FIXTURE_TEST_PASS')
    raise SystemExit(0)

run=folder/('hdmi_endurance_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
run.mkdir(parents=True,exist_ok=False)
log=(run/'observations.jsonl').open('w',encoding='utf-8')
start=None;frames=0;observations=0;last_signature=None;last_change=None;last_snapshot=-1
next_observation=0;source=None
try:
    source=av.open('video=USB3 Video',format='dshow',options={'video_size':'1280x720','framerate':'30'})
    for decoded,frame in enumerate(source.decode(video=0)):
        if decoded<30:continue
        now=time.monotonic()
        if start is None:start=now;last_change=now
        elapsed=now-start;frames+=1
        if elapsed>=next_observation:
            rgb=frame.to_ndarray(format='rgb24')
            assert rgb.shape==(720,1280,3)
            warning=sim_fraction(rgb)
            assert warning<0.05,f'SIM warning appeared: fraction={warning}'
            # The firmware updates VIDEO/TRIG numbers here; frozen UI fails.
            signature=zlib.crc32(rgb[24:48,240:912].tobytes())
            if signature!=last_signature:last_signature=signature;last_change=now
            assert now-last_change<5,'Firmware header stopped changing for five seconds'
            row={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 'elapsed_s':elapsed,'decoded_frames':frames,'header_crc32':f'{signature:08x}',
                 'sim_warning_fraction':warning,'header_stale_s':now-last_change}
            log.write(json.dumps(row)+'\n');log.flush();observations+=1
            bucket=int(elapsed//600)
            if bucket!=last_snapshot:
                Image.fromarray(rgb).save(run/f'HDMI_endurance_{bucket*600:04d}.png')
                last_snapshot=bucket
            next_observation=elapsed+1
            if observations%60==0:print(f'HDMI_ENDURANCE_PROGRESS seconds={elapsed:.1f} observations={observations}',flush=True)
        if elapsed>=args.seconds:
            Image.fromarray(frame.to_ndarray(format='rgb24')).save(run/'HDMI_endurance_final.png')
            fps=frames/elapsed
            assert fps>=24,f'Capture throughput too low: {fps}'
            result={'status':'PASS' if elapsed>=3600 else 'SHORT_TEST_PASS',
                    'duration_s':elapsed,'decoded_frames':frames,'capture_fps':fps,
                    'observations':observations,'folder':run.relative_to(root).as_posix(),
                    'SIM_warning_observations':0,'maximum_header_stall_s':'<5',
                    'scope':'Direct USB HDMI stream and changing ARM UI header; does not replace ADC bit accuracy or continuous DDR qualification.'}
            (folder/'hdmi_endurance_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
            print('HDMI_ENDURANCE_'+result['status'],json.dumps(result),flush=True)
            break
    else:raise RuntimeError('HDMI source ended before the requested duration')
except BaseException as exc:
    result={'status':'FAIL','reason':str(exc),'folder':run.relative_to(root).as_posix()}
    (folder/'hdmi_endurance_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    raise
finally:
    if source is not None:source.close()
    log.close()
