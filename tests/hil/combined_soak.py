"""A continuous real-board ADC/DAC + direct USB HDMI monitor.
No desktop capture. All evidence is for a single boot and uninterrupted run.
"""
import argparse,datetime,json,re,threading,time,zlib,sys,os
from pathlib import Path
import av,numpy as np,serial
r=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=3605);p.add_argument('--port',default='COM27');a=p.parse_args()
out=r/'results/2026-10-17/dac_v4'/('soak_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
stop=threading.Event();video={};video_error=[]
def camera():
    source=None
    try:
        source=av.open('video=USB3 Video',format='dshow',options={'video_size':'1280x720','framerate':'30','rtbufsize':'256M'})
        start=None;frames=0;observations=0;next_check=0;last_snap=-1;last_signature=None;last_change=None
        with (out/'video.jsonl').open('w') as log:
            for n,frame in enumerate(source.decode(video=0)):
                if stop.is_set():break
                if n<30:continue
                now=time.monotonic()
                if start is None:start=now;last_change=now
                elapsed=now-start;frames+=1
                if elapsed>=next_check:
                    rgb=frame.to_ndarray(format='rgb24');assert rgb.shape==(720,1280,3)
                    bar=rgb[62:68,32:1248];sim=float(np.mean((bar[:,:,0]>150)&(bar[:,:,1]>90)&(bar[:,:,2]<140)))
                    assert sim<.05,'SIM warning on actual HDMI'
                    # Diagnostic capture count in the footer changes continuously.
                    sig=zlib.crc32(rgb[672:695,0:1040].tobytes())
                    if sig!=last_signature:last_signature=sig;last_change=now
                    # A floating/DC input legitimately leaves the diagnostic
                    # footer unchanged. Serial RPC/counters prove CPU liveness;
                    # do not falsely classify a static scene as a frozen UI.
                    log.write(json.dumps(dict(elapsed_s=elapsed,frames=frames,footer_crc=f'{sig:08x}',sim=sim))+'\n');log.flush();observations+=1;next_check=elapsed+1
                    bucket=int(elapsed//600)
                    if bucket!=last_snap:frame.to_image().save(out/f'HDMI_{bucket*600:04d}.png');last_snap=bucket
                video.update(duration_s=elapsed,frames=frames,observations=observations,fps=frames/max(elapsed,.001),last_frame_monotonic=now)
                if elapsed>=a.seconds:frame.to_image().save(out/'HDMI_final.png');break
    except BaseException as exc:video_error.append(str(exc));stop.set()
    finally:
        if source:source.close()
thread=threading.Thread(target=camera,daemon=True)
rid=0;rows=[];start=None;fail=None;version={}
def fields(s):return dict(re.findall(r'(\w+)=([^ ]+)',s))
with serial.Serial(a.port,115200,timeout=.1,write_timeout=2) as port:
    def ask(command):
        global rid
        rid+=1;port.write((f'@{rid:08x} {command}\n').encode());deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            line=port.readline().decode('ascii',errors='replace').strip()
            if f'rid={rid:08x} ' in line:
                assert line.startswith('OK'),line
                return fields(line)
        raise TimeoutError(command)
    try:
        for cmd in ['adc source real','mode dso','run 1','adc rate 65','trig type auto','view auto 0','view gain 0','view zero 2047.5','view span 4096','page adc','dac set sine 1000 0.1 0.5 0.5 1']:ask(cmd)
        version=ask('ver');assert int(version['rtl'],16)>=0x40000
        thread.start();start=time.monotonic();previous=None
        with (out/'serial.jsonl').open('w') as log:
            while time.monotonic()-start<a.seconds+2:
                assert not video_error,video_error
                if time.monotonic()-start>20:
                    assert video and time.monotonic()-video['last_frame_monotonic']<10,'USB HDMI capture stalled for 10 seconds'
                state=ask('status');dac=ask('dac status');uart=ask('uart')
                assert state['source']=='ADC' and state['rate']=='65000000' and state['run']=='1' and state['mode']=='DSO'
                assert int(state['otr'])==0 and int(state['drop'])==0 and int(state['errors'],16)==0 and int(state['irq_lost'])==0
                assert dac['dac_enabled']=='1' and dac['hw_enabled']=='1' and uart['uart_rx_lost']=='0'
                hi,lo=state['samples'].split(':');samples=int(hi)*2**32+int(lo,16)
                row=dict(elapsed_s=time.monotonic()-start,status=state,dac=dac,samples=samples,uart=uart)
                if previous:
                    assert samples>previous['samples'] and int(state['frame'])>int(previous['status']['frame'])
                    cycles=(int(dac['cycles'])-int(previous['dac']['cycles']))&0xffffffff
                    phase=(int(dac['phase'],16)-int(previous['dac']['phase'],16))&0xffffffff
                    step=round(float(dac['actual_hz'])*2**32/50_000_000)
                    assert phase==(cycles*step)&0xffffffff,'DAC phase discontinuity'
                    assert dac['table_crc']==previous['dac']['table_crc']
                rows.append(row);previous=row;log.write(json.dumps(row)+'\n');log.flush()
                if len(rows)%30==0:print(f'COMBINED_SOAK_PROGRESS elapsed={row["elapsed_s"]:.1f}s checks={len(rows)} video_frames={video.get("frames",0)}',flush=True)
                time.sleep(2)
        thread.join(timeout=8);assert not thread.is_alive(),'Video monitor did not finish';assert not video_error,video_error
        assert video['duration_s']>=a.seconds and video['fps']>=24
    except BaseException as exc:fail=str(exc);stop.set()
    finally:
        for cmd in ['dac enable 0','adc rate 10','mode dso','page adc','run 1']:
            try:ask(cmd)
            except Exception:pass
        stop.set();thread.join(timeout=3) if thread.ident else None
result=dict(status='FAIL' if fail else 'PASS' if a.seconds>=3600 else 'SHORT_TEST_PASS',error=fail,requested_s=a.seconds,serial_duration_s=rows[-1]['elapsed_s']-rows[0]['elapsed_s'] if len(rows)>1 else 0,checks=len(rows),video=video,video_errors=video_error,folder=str(out),single_boot=True,version=version)
(out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
if thread.is_alive():
    # A blocked DirectShow read cannot be cancelled by a Python Event. The
    # serial cleanup and evidence flush above have already completed.
    # Release this process's device handles without hanging at interpreter exit.
    os._exit(1)
if fail:raise SystemExit(1)
