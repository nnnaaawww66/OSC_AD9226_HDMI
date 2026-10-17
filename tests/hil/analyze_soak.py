"""Validate raw one-hour board log without inferring tests that were not run."""
from pathlib import Path
import json,re,numpy as np
root=Path(__file__).resolve().parents[2];folder=root/'results/2026-10-17/prd_completion'
text=(folder/'soak.log').read_text(encoding='utf-8')
rows=[]
for line in text.splitlines():
 m=re.search(r'^(\d+) heartbeat=(\d+) locks=(\d+).*source=ADC rate=(\d+).*frame=(\d+) samples=(\d+):([0-9a-f]+).*otr=(\d+) drop=(\d+) errors=([0-9a-f]+)',line)
 if m:
  ts,h,locks,rate,frame,hi,lo,otr,drop,errors=m.groups()
  rows.append((int(ts),int(h),int(locks),int(rate),int(frame),(int(hi)<<32)|int(lo,16),int(otr),int(drop),int(errors,16)))
assert len(rows)>100,'insufficient continuity observations'
assert re.search(r'^PASS duration_ms=([0-9]+)',text,re.M),'missing test completion marker'
duration=int(re.search(r'^PASS duration_ms=([0-9]+)',text,re.M).group(1));assert duration>=3600000
v=np.array(rows,dtype=np.int64)
assert np.all(v[:,3]==65000000)
assert np.all(v[:,2]&0xc00==0xc00)
assert np.all(np.diff(v[:,0])>0) and np.all(np.diff(v[:,4])>0) and np.all(np.diff(v[:,5])>0)
assert np.all(np.diff(v[:,1])!=0) and np.all(v[:,7:9]==0)
t=(v[:,0]-v[0,0])/1000
adc_rate=float(np.polyfit(t,v[:,5]-v[0,5],1)[0]);fps=float(np.polyfit(t,v[:,4]-v[0,4],1)[0])
assert abs(adc_rate/65000000-1)<.01 and abs(fps-60)<.5
result={'status':'PASS','duration_ms':duration,'observations':len(rows),'configured_rate_sps':65000000,'measured_counter_slope_sps':adc_rate,'measured_video_fps':fps,'maximum_observation_gap_ms':int(np.diff(v[:,0]).max()),'samples_observed':int(v[-1,5]-v[0,5]),'video_frames_observed':int(v[-1,4]-v[0,4]),'OTR_first_last':[int(v[0,6]),int(v[-1,6])],'DMA_drop':0,'error_flags':0,'input':'User-confirmed floating analog input','scope':'Digital clocks, real ADC selected, firmware continuity and video; no calibrated analog reference'}
(folder/'soak_analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
