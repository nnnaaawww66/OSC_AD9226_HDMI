"""Independently validate the saved direct-USB endurance observations."""
from pathlib import Path
import datetime
import json
import re
import numpy as np

root=Path(__file__).resolve().parents[2]
folder=root/'results/2026-10-17/prd_completion'
result=json.loads((folder/'hdmi_endurance_result.json').read_text())
assert result['status']=='PASS' and result['duration_s']>=3600
assert re.fullmatch(r'results/2026-10-17/prd_completion/hdmi_endurance_\d{8}_\d{6}',result['folder'])
run=root/result['folder']
rows=[json.loads(line) for line in (run/'observations.jsonl').read_text().splitlines()]
assert len(rows)>=3500
elapsed=np.array([row['elapsed_s'] for row in rows])
frames=np.array([row['decoded_frames'] for row in rows])
assert elapsed[-1]-elapsed[0]>=3600
gaps=np.diff(elapsed)
assert np.all(gaps>0) and np.max(gaps)<3
assert np.all(np.diff(frames)>0)
assert all(row['sim_warning_fraction']<.05 and row['header_stale_s']<5 for row in rows)
assert len({row['header_crc32'] for row in rows})>.9*len(rows)
fps=float((frames[-1]-frames[0])/(elapsed[-1]-elapsed[0]))
assert 24<=fps<=35
assert len(list(run.glob('HDMI_endurance_*.png')))>=7
assert (run/'HDMI_endurance_final.png').is_file()
first=datetime.datetime.fromisoformat(rows[0]['utc']).timestamp()*1000
last=datetime.datetime.fromisoformat(rows[-1]['utc']).timestamp()*1000
analysis={'status':'PASS','actual_observation_span_s':float(elapsed[-1]-elapsed[0]),
          'observations':len(rows),'first_observation_epoch_ms':first,
          'last_observation_epoch_ms':last,'capture_fps':fps,
          'maximum_observation_gap_s':float(gaps.max()),
          'unique_firmware_header_signatures':len({row['header_crc32'] for row in rows}),
          'SIM_warning_observations':0,'snapshots':len(list(run.glob('*.png'))),
          'folder':result['folder'],
          'scope':'Actual USB capture and changing firmware UI, independent of JTAG; capture fps is not the physical 60Hz video clock.'}
(folder/'hdmi_endurance_analysis.json').write_text(json.dumps(analysis,indent=2),encoding='utf-8')
print(json.dumps(analysis,indent=2))
