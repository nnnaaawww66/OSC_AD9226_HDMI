"""Check the released artifacts and evidence without connecting to the board.

Use --require-soak for release packaging. A pending/interrupted soak is never PASS.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results/2026-10-17'
HIL = OUT / 'prd_completion'
parser = argparse.ArgumentParser()
parser.add_argument('--require-soak', action='store_true')
args = parser.parse_args()


def read(path):
    return path.read_text(encoding='utf-8-sig', errors='replace')


def marker(path, value):
    assert value in read(path), f'Missing {value}: {path}'


seal = json.loads(read(OUT / 'release_artifacts.json'))
required = {'scope_top.bit', 'scope_top.hdf', 'scope_top.ltx', 'scope.elf',
            'scope_diag.elf', 'ps7_init.tcl', 'build_revision.txt',
            'hardware_build.ok', 'sdk_build.ok'}
assert len(seal['files']) == len(required)
assert {item['name'] for item in seal['files']} == required
for item in seal['files']:
    data = (OUT / item['name']).read_bytes()
    assert len(data) == item['bytes']
    assert hashlib.sha256(data).hexdigest() == item['sha256'], item['name']
assert (OUT / 'build_revision.txt').read_text().strip() == seal['rtl_revision']
with zipfile.ZipFile(OUT / 'scope_top.hdf') as handoff:
    for name in ('scope_top.bit', 'ps7_init.tcl'):
        assert handoff.read(name) == (OUT / name).read_bytes(), f'HDF mismatch: {name}'
elf_ranges = {}
for name, lower, upper in (('scope.elf', 0x00100000, 0x08000000),
                           ('scope_diag.elf', 0, 0x0002f000)):
    data = (OUT / name).read_bytes()
    assert data[:7] == b'\x7fELF\x01\x01\x01' and struct.unpack_from('<H', data, 18)[0] == 40
    entry, offset = struct.unpack_from('<II', data, 24)
    size, count = struct.unpack_from('<HH', data, 42)
    assert lower <= entry < upper
    loads = []
    for i in range(count):
        kind, file_offset, va, pa, file_size, memory_size, flags, align = struct.unpack_from('<IIIIIIII', data, offset+i*size)
        if kind == 1:
            assert lower <= pa == va and pa+memory_size <= upper, (name, hex(pa), hex(memory_size))
            assert file_offset+file_size <= len(data) and file_size <= memory_size
            loads.append({'address': hex(pa), 'bytes': memory_size})
    assert loads
    elf_ranges[name] = loads

sim = json.loads(read(OUT / 'simulation/summary.json'))
expected_sim = {'capture', 'mailbox', 'video', 'vga', 'keys', 'tmds',
                'histogram', 'roll', 'raster', 'axi', 'dma', 'fallback',
                'adc', 'clocks', 'adc_latency'}
assert set(sim) == expected_sim and all(v is True for v in sim.values())
analysis = json.loads(read(OUT / 'analysis_tests.json'))
for name in ('envelope', 'measure', 'no_signal', 'DMA_DDS_PHASE',
             'EYE_PHASE', 'NOISE_FREQUENCY'):
    assert analysis[name].startswith('PASS'), name
assert len([key for key in analysis if re.fullmatch(r'fft_\d+_[01]', key)]) == 6

timing = read(OUT / 'timing_summary.rpt')
assert 'All user specified timing constraints are met.' in timing
timing_row = re.search(r'WNS\(ns\).*?\n\s*[- ]+\n\s*([\d.-]+)\s+([\d.-]+)\s+(\d+)\s+(\d+)\s+([\d.-]+)', timing)
assert timing_row, 'No timing summary row'
wns, tns, failing, endpoints, whs = timing_row.groups()
assert float(wns) >= 0 and float(whs) >= 0 and float(tns) == 0 and int(failing) == 0
for rate in (10, 25, 50, 65):
    for delay in ('max', 'min'):
        report = read(OUT / f'adc_{rate}_{delay}.rpt')
        assert len(re.findall(r'^Slack \(MET\)', report, re.M)) == 13, (rate, delay)
        assert len(set(re.findall(r'Source:\s+(adc_(?:data\[\d+\]|otr))', report))) == 13
marker(OUT / 'cdc_review.txt', 'reviewed_critical_rows=159 unreviewed_critical_rows=0')
drc = read(OUT / 'drc.rpt')
assert not re.search(r'\|\s*\S+\s*\|\s*(?:Error|Critical Warning)\s*\|', drc)
marker(HIL / 'cdc_gate_test.log', 'CDC_GATE_TEST_PASS')
marker(HIL / 'unsigned_counter_test.log', 'UNSIGNED_COUNTER_TEST_PASS')
marker(HIL / 'hil_cleanup_test.log', 'HIL_CLEANUP_TEST_PASS')
marker(HIL / 'functional_hil.log', 'PRD_FUNCTIONAL_HIL_PASS rates=4 mode_transitions=1000 final_source=ADC')
observed = re.search(r'source_sha=([0-9a-f]{8}) fw_sha=([0-9a-f]{8})', read(HIL / 'functional_hil.log'))
assert observed and observed[1] == seal['rtl_revision'], 'HIL evidence belongs to a different RTL build'
marker(HIL / 'recovery_program.log', 'SCOPE_READY real_ADC=1 DDR_selftest=PASS MEM_source=ADC')
marker(HIL / 'clean_rebuild_console.log', 'RELEASE_SEAL_PASS')
marker(HIL / 'warm_boots.log', 'BOOT_VERIFIED')
boots = read(HIL / 'warm_boots.log').count('BOOT_VERIFIED stage=00000006')
assert boots == 5
ila = json.loads(read(HIL / 'ila/analysis.json'))
assert ila['ADC']['counter_steps'] == 'all +1'
assert ila['ADC']['otr'] == 0
assert ila['ila_sys_last.csv']['TLAST_count'] == 1
for key, value in ila.items():
    if key.startswith('ila_video'):
        assert value['clock_lock'] == 'all locked'
        assert value['HS_VS_DE_alignment'].startswith('PASS')
for mode in ('DSO', 'DPX', 'EYE', 'FFT', 'ROLL', 'MEM', 'SEG'):
    assert (HIL / f'HDMI_{mode}_real.png').stat().st_size > 10000

soak = {'status': 'PENDING'}
if (HIL / 'soak_analysis.json').exists():
    # Re-parse the current raw log; never trust a stale analysis from an earlier boot.
    subprocess.run([__import__('sys').executable, str(ROOT / 'tests/hil/analyze_soak.py')], check=True)
    soak = json.loads(read(HIL / 'soak_analysis.json'))
if args.require_soak:
    assert soak['status'] == 'PASS', 'One-hour soak has not completed'
hdmi = {'status': 'PENDING'}
if (HIL / 'hdmi_endurance_result.json').exists():
    if json.loads(read(HIL / 'hdmi_endurance_result.json'))['status'] == 'PASS':
        subprocess.run([__import__('sys').executable, str(ROOT / 'tests/hil/analyze_hdmi_endurance.py')], check=True)
        hdmi = json.loads(read(HIL / 'hdmi_endurance_analysis.json'))
if args.require_soak:
    assert hdmi['status'] == 'PASS', 'Independent HDMI endurance has not completed'
    assert hdmi['first_observation_epoch_ms'] >= soak['first_observation_epoch_ms'], 'HDMI evidence predates this board run'
    marker(HIL / 'final_board_state.log', 'FINAL_BOARD_STATE_PASS source=ADC rate=10000000 real_segments=8 flash_written=0')

result = {'status': 'PASS' if soak['status'] == hdmi['status'] == 'PASS' else 'PENDING_SOAK',
          'artifact_hashes': 'PASS', 'rtl_revision': seal['rtl_revision'],
          'firmware_revision': observed[2],
          'HDF_bit_and_PS7_match': True, 'ELF_load_ranges': elf_ranges,
          'RTL_tests': len(sim), 'C_NumPy': 'PASS', 'WNS_ns': float(wns),
          'WHS_ns': float(whs), 'ADC_input_paths_per_rate_and_delay': 13,
          'reviewed_CDC_Critical_rows': 159, 'unreviewed_CDC_Critical_rows': 0,
          'mode_transitions_on_board': 1000, 'warm_boots': boots,
          'ILA': 'PASS', 'clean_reconstruction': 'PASS', 'soak': soak, 'HDMI_endurance': hdmi,
          'analog_qualification': 'LIMITED: floating input, no calibrated reference',
          'UART': 'User requested JTAG only; physical UART not exercised'}
(HIL / 'release_verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
