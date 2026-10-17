from pathlib import Path
import csv,json
r=Path(__file__).resolve().parents[2];p=r/'results/2026-10-17/prd_completion/ila'
def rows(name):
 with (p/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def bus(name):return [int(list(v.values())[-1],16) for v in rows(name)]
a=bus('ila_adc.csv');counts=[(v>>72)&0xffffffff for v in a]
assert len(a)==1024 and all((y-x)&0xffffffff==1 for x,y in zip(counts,counts[1:]))
assert all(((v>>12)&4095)==(v&4095) for v in a),'IOB sample and normalized offset sample differ'
assert all(((v>>24)&1)==0 for v in a),'Unexpected OTR'
result={'ADC':{'samples':len(a),'counter_steps':'all +1','code_min':min(v&4095 for v in a),'code_max':max(v&4095 for v in a),'otr':0}}
for name in ['ila_sys.csv','ila_sys_last.csv']:
 a=bus(name);accepted=[];last=[]
 for i,v in enumerate(a):
  valid=(v>>111)&1;ready=(v>>110)&1;tl=(v>>109)&1;data=(v>>112)&65535
  assert (v>>19)&255==0,'Error latch in ILA'
  if i and ((a[i-1]>>111)&1) and not((a[i-1]>>110)&1):assert valid and data==((a[i-1]>>112)&65535) and tl==((a[i-1]>>109)&1)
  if valid and ready:accepted.append(data);last.append(tl)
 assert len(accepted)>50
 assert all((y-x)&65535==1 for x,y in zip(accepted,accepted[1:])),name
 if 'last' in name:assert sum(last)==1 and accepted[last.index(1)]==65535
 else:assert not any(last)
 result[name]={'samples':len(a),'accepted_in_window':len(accepted),'ordered_counter':'PASS','TLAST_count':sum(last),'backpressure_stability':'PASS'}
for name in ['ila_video.csv','ila_video_vsync.csv','ila_video_hsync.csv']:
 a=rows(name);keys=list(a[0]);xkey=next(k for k in keys if '/x_raw[' in k);ykey=next(k for k in keys if '/y_raw[' in k);skey=next(k for k in keys if '/probe0_1[' in k);lock=next(k for k in keys if k.endswith('/video_locked'))
 sequence=[];sync=[]
 for v in a:
  x=int(v[xkey],16);y=int(v[ykey],16);s=int(v[skey],16);assert int(v[lock],16)==1
  sequence.append(y*1650+x);sync.append(s)
  old=(y*1650+x-5)%(1650*750);py,px=divmod(old,1650)
  expected=((1390<=px<1430)<<2)|((725<=py<730)<<1)|(px<1280 and py<720)
  assert s==expected,(name,x,y,s,expected)
 assert all((y-x)%(1650*750)==1 for x,y in zip(sequence,sequence[1:]))
 if 'hsync' in name:assert sum(bool(v&4) for v in sync)==40
 elif 'vsync' in name:assert any(v&2 for v in sync)
 else:assert any(v&1 for v in sync)
 result[name]={'samples':len(a),'coordinates':'all +1 / 1650x750','HS_VS_DE_alignment':'PASS 5-pixel pipeline','clock_lock':'all locked','HS_high_samples':sum(bool(v&4) for v in sync),'VS_high_samples':sum(bool(v&2) for v in sync),'DE_high_samples':sum(bool(v&1) for v in sync)}
(p/'analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));print('ILA_DATA_ANALYSIS_PASS')
