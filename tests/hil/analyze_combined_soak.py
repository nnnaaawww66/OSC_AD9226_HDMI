from pathlib import Path
import argparse,json,numpy as np
p=argparse.ArgumentParser();p.add_argument('folder');p.add_argument('--require-hour',action='store_true');a=p.parse_args();folder=Path(a.folder)
rows=[json.loads(x) for x in (folder/'serial.jsonl').read_text().splitlines() if x.strip()]
video=[json.loads(x) for x in (folder/'video.jsonl').read_text().splitlines() if x.strip()]
assert len(rows)>2 and len(video)>2
t=np.asarray([r['elapsed_s'] for r in rows]);samples=np.asarray([r['samples']-rows[0]['samples'] for r in rows],dtype=float)
frames=np.asarray([int(r['status']['frame'])-int(rows[0]['status']['frame']) for r in rows],dtype=float)
dac=[0]
for before,after in zip(rows,rows[1:]):dac.append(dac[-1]+((int(after['dac']['cycles'])-int(before['dac']['cycles']))&0xffffffff))
adc_rate=float(np.polyfit(t-t[0],samples,1)[0]);video_rate=float(np.polyfit(t-t[0],frames,1)[0]);dac_rate=float(np.polyfit(t-t[0],np.asarray(dac),1)[0])
assert abs(adc_rate/65e6-1)<.001 and abs(dac_rate/50e6-1)<.001 and abs(video_rate/60-1)<.001
assert all(r['status']['source']=='ADC' and r['status']['errors']=='00000000' and r['status']['drop']=='0' and r['status']['otr']=='0' and r['uart']['uart_rx_lost']=='0' for r in rows)
assert all(r['dac']['dac_enabled']=='1' and r['dac']['hw_enabled']=='1' and r['dac']['table_crc']==rows[0]['dac']['table_crc'] for r in rows)
assert len(set(r['dac']['sample_code'] for r in rows))>5
for before,after in zip(rows,rows[1:]):
    phase=(int(after['dac']['phase'],16)-int(before['dac']['phase'],16))&0xffffffff
    clocks=(int(after['dac']['cycles'])-int(before['dac']['cycles']))&0xffffffff
    step=round(float(after['dac']['actual_hz'])*2**32/50e6)
    assert phase==(clocks*step)&0xffffffff
span=float(t[-1]-t[0]);vspan=video[-1]['elapsed_s']-video[0]['elapsed_s'];fps=(video[-1]['frames']-video[0]['frames'])/vspan
assert fps>=24
if a.require_hour:
    assert span>=3600 and vspan>=3600
    summary=json.loads((folder/'summary.json').read_text());assert summary['status']=='PASS' and summary['single_boot']
result=dict(status='HOUR_PASS' if span>=3600 and vspan>=3600 else 'PROGRESS',serial_duration_s=span,hdmi_duration_s=vspan,observations=len(rows),video_observations=len(video),adc_measured_samples_per_s=adc_rate,dac_measured_updates_per_s=dac_rate,pl_video_measured_fps=video_rate,usb_capture_fps=fps,adc_sample_delta=int(rows[-1]['samples']-rows[0]['samples']),dac_clock_delta=dac[-1],video_frame_delta=int(frames[-1]),distinct_dac_codes=len(set(r['dac']['sample_code'] for r in rows)),source='REAL_ADC',dac_phase_continuity='PASS',errors=0,drop=0,otr=0,uart_rx_lost=0)
if a.require_hour:(folder/'analysis.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
