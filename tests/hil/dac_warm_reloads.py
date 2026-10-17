"""Five volatile JTAG reloads of the sealed release, plus real UART checks.

Run only after the uninterrupted soak. Does not erase or write QSPI and is
explicitly separate from the user's physical QSPI power-cycle evidence.
"""
from pathlib import Path
import json
import re
import subprocess
import time
import serial

root = Path(__file__).resolve().parents[2]
out = root / 'results/2026-10-17/dac_v4'
observations = []
for attempt in range(1, 6):
    log = out / f'warm_reload_{attempt}.log'
    with log.open('w', encoding='utf-8') as stream:
        subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'program.ps1'), '-SkipSelftest'], cwd=root, stdout=stream, stderr=subprocess.STDOUT, check=True)
    assert 'BOOT_VERIFIED stage=00000006' in log.read_text(encoding='utf-8')
    with serial.Serial('COM27', 115200, timeout=.15, write_timeout=2) as port:
        def ask(cmd, rid):
            port.write(f'@{rid:08x} {cmd}\n'.encode('ascii'))
            deadline = time.monotonic()+10
            while time.monotonic() < deadline:
                line = port.readline().decode('ascii', errors='replace').strip()
                if f'rid={rid:08x} ' in line:
                    assert line.startswith('OK'), line
                    return line, dict(re.findall(r'(\w+)=([^ ]+)', line))
            raise TimeoutError(cmd)
        ver, identity = ask('ver', 1)
        status, state = ask('status', 2)
        dac_line, dac = ask('dac status', 3)
        assert identity['source_sha'] == '97d15f6d' and identity['fw_sha'] == 'a160d300'
        assert state['source'] == 'ADC' and state['rate'] == '10000000' and state['run'] == '1' and state['mode'] == 'DSO'
        assert state['errors'] == '00000000' and state['otr'] == '0' and state['drop'] == '0'
        assert dac['dac_enabled'] == '0' and dac['hw_enabled'] == '0' and dac['sample_code'] == '8192'
        observations.append(dict(attempt=attempt, ver=ver, status=status, dac=dac_line))
    print('V4_WARM_RELOAD_PASS', attempt, flush=True)
(out / 'warm_reloads.json').write_text(json.dumps(dict(passed=True, count=5, kind='volatile JTAG reload; not physical cold boot', observations=observations), indent=2), encoding='utf-8')
