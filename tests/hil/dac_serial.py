"""Real COM27 RPC, independent ADC/DAC configuration and table upload checks."""
import argparse,json,time,sys,re,zlib
from pathlib import Path
import serial,numpy as np
r=Path(__file__).resolve().parents[2];sys.path.insert(0,str(r/'host'))
from waveforms import make_table
p=argparse.ArgumentParser();p.add_argument('--port',default='COM27');p.add_argument('--output',default=str(r/'results/2026-10-17/dac_v4/serial_hil.json'));a=p.parse_args()
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
log=[];rid=0
def parse(line):return dict(re.findall(r'(\w+)=([^ ]+)',line))
with serial.Serial(a.port,115200,timeout=.1,write_timeout=2) as port:
    def ask(command,ok=True,timeout=10):
        global rid
        rid+=1;port.write((f'@{rid:08x} {command}\n').encode());port.flush();deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            line=port.readline().decode(errors='replace').strip()
            if f'rid={rid:08x} ' in line:
                log.append(dict(command=command,response=line,time=time.time()))
                assert line.startswith('OK' if ok else 'ERR'),line
                return parse(line)
        raise TimeoutError(command)
    try:
        assert ask('ver')['fw']=='4.0'
        before=ask('settings')
        ask('dac set sine 1234 0.1 0.5 0.5 0')
        dac=ask('dac status');assert dac['dac_enabled']=='0'
        unchanged=ask('settings')
        for key in ['mode','run','source','rate','span','gain','zero','level','trig','fft_n','bitrate']:assert before[key]==unchanged[key],key
        ask('page dac');assert ask('settings')['mode']==before['mode']
        # Changes in the ADC chain cannot change the DAC table or phase step.
        for cmd in ['mode fft','view span 1024','view gain 2','adc rate 25','mode dso']:
            ask(cmd)
            current=ask('dac status')
            assert current['table_crc']==dac['table_crc'] and current['actual_hz']==dac['actual_hz'],cmd
            if int(ask('ver')['rtl'],16)>=0x40000:
                step=round(float(dac['actual_hz'])*2**32/50_000_000)
                clocks=(int(current['cycles'])-int(dac['cycles']))&0xffffffff
                phase=(int(current['phase'],16)-int(dac['phase'],16))&0xffffffff
                assert phase==(clocks*step)&0xffffffff,'ADC command changed DAC phase continuity'
        table=make_table('expression',.2,.5,formula='0.8*sin(2*pi*t)+0.2*sin(6*pi*t)')
        ask('dac begin')
        ask('dac chunk 1 2000',False)
        ask('dac chunk 0 2000xxxx',False)
        for at in range(0,2048,24):
            response=ask(f'dac chunk {at} '+''.join(f'{int(x):04x}' for x in table[at:at+24]))
            assert int(response['dac_uploaded'])==min(2048,at+24)
        ask('dac commit 00000000 1000 0',False)
        crc=zlib.crc32(table.tobytes());commit=ask(f'dac commit {crc:08x} 1000 0')
        assert commit['crc']==f'{crc:08x}'
        assert ask('dac status')['table_crc']==f'{crc:08x}'
        if int(ask('ver')['rtl'],16)>=0x40000:
            ask('dac enable 1')
            observed=set()
            for _ in range(20):
                sample=ask('dac status');step=round(float(sample['actual_hz'])*2**32/50_000_000)
                index=((int(sample['phase'],16)-step)&0xffffffff)>>21
                assert sample['hw_enabled']=='1' and int(sample['sample_code'])==int(table[index]),'DAC output register differs from the committed table/DDS phase'
                observed.add(int(sample['sample_code']))
            assert len(observed)>5,'DAC output codes are not changing'
            ask('dac enable 0')
        # Invalid requests cannot change the last committed waveform.
        for cmd in ['dac set sine nan 0.1 0.5 0.5 1','dac set sine 1000 1 0.9 0.5 1','dac set sine 1000 0.1 0.5 0 1']:
            ask(cmd,False);assert ask('dac status')['table_crc']==f'{crc:08x}'
        for mode in ['dso','dpx','eye','fft','roll']:
            ask(f'mode {mode}');ask('page dac');ask('page adc')
        ask('adc source real');ask('adc rate 10');ask('mode dso');ask('view gain 0');ask('view zero 2047.5');ask('view span 4096');ask('view auto 0');ask('run 1')
        uart=ask('uart');assert uart['uart_rx_lost']=='0'
        result=dict(passed=True,port=a.port,transactions=len(log),table_crc=f'{crc:08x}',uart=uart,log=log)
    except BaseException as exc:
        result=dict(passed=False,error=str(exc),log=log);out.write_text(json.dumps(result,indent=2));raise
    finally:
        try:ask('dac enable 0');ask('page adc');ask('adc source real');ask('mode dso');ask('run 1')
        except Exception:pass
out.write_text(json.dumps(result,indent=2));print('PASS COM27 DAC RPC/CRC/readback and ADC/DAC isolation',len(log))
