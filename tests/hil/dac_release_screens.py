"""Capture final HDMI evidence directly, using one named USB video stream.

Run after the soak and dac_final_state.tcl (REAL MEM/SEG records prepared).
"""
from pathlib import Path
import json
import re
import time
import av
import serial

root = Path(__file__).resolve().parents[2]
out = root / 'results/2026-10-17/dac_v4'
rid = 0
log = []
with serial.Serial('COM27', 115200, timeout=.15, write_timeout=2) as port:
    def ask(command):
        global rid
        rid += 1
        port.write(f'@{rid:08x} {command}\n'.encode('ascii'))
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            line = port.readline().decode('ascii', errors='replace').strip()
            if f'rid={rid:08x} ' in line:
                assert line.startswith('OK'), line
                log.append(dict(command=command, response=line, epoch=time.time()))
                return dict(re.findall(r'(\w+)=([^ ]+)', line))
        raise TimeoutError(command)
    with av.open('video=USB3 Video', format='dshow', options={'video_size':'1280x720','framerate':'30','rtbufsize':'256M'}) as source:
        stream = iter(source.decode(video=0))
        def capture(name):
            # Discard queued frames, then allow multiple PS UI refreshes.
            end = time.monotonic()+2.5
            while True:
                frame = next(stream)
                if time.monotonic() >= end:
                    frame.to_image().save(out / name)
                    print('ACTUAL_HDMI', name, flush=True)
                    return
        try:
            ask('dac enable 0');ask('adc source real');ask('page adc')
            for mode in ['dso','dpx','eye','fft','roll','mem','seg']:
                ask('mode '+mode);capture('HDMI_'+mode.upper()+'_REAL_v4.png')
            ask('mode dso');ask('menu toggle');capture('HDMI_MENU_CN_v4.png');ask('menu toggle')
            ask('page dac');capture('HDMI_DAC_preview_v4.png')
            ask('page adc');ask('adc source sim');ask('mode dso');capture('HDMI_SIM_EXPLICIT_v4.png')
        finally:
            for command in ['dac enable 0','page adc','adc source real','mode dso','view auto 0','view span 4096','view gain 0','view zero 2047.5','run 1']:
                ask(command)
            capture('HDMI_ADC_DELIVERED_v4.png')
            state=ask('status');dac=ask('dac status');uart=ask('uart')
            assert state['source']=='ADC' and state['rate']=='10000000' and state['mode']=='DSO' and state['run']=='1'
            assert state['errors']=='00000000' and state['drop']=='0' and state['otr']=='0'
            assert dac['dac_enabled']=='0' and dac['sample_code']=='8192' and uart['uart_rx_lost']=='0'
(out / 'screen_capture_log.json').write_text(json.dumps(dict(passed=True, log=log), indent=2), encoding='utf-8')
