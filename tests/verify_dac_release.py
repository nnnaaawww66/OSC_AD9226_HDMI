"""Verify the ADC/DAC 4.0 release against this build's evidence.

No board access. By default a complete uninterrupted hour is required. A
progress-only check never overwrites the final acceptance record.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
out = root / 'results/2026-10-17'
hil = out / 'dac_v4'
parser = argparse.ArgumentParser()
parser.add_argument('--progress', action='store_true')
parser.add_argument('--soak-folder', type=Path)
args = parser.parse_args()

def read(path):
    return path.read_text(encoding='utf-8-sig')

def marker(path, value):
    assert value in read(path), f'Missing {value}: {path}'

def sealed(folder, name):
    record = json.loads(read(folder / name))
    for item in record['files']:
        path = folder / item['name']
        assert path.name == item['name']
        assert path.stat().st_size == item['bytes']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], path
    return record

release = sealed(out, 'release_artifacts.json')
boot = sealed(root / 'boot', 'manifest.json')
assert len(release['files']) == 9 and len(boot['files']) == 5
with zipfile.ZipFile(out / 'scope_top.hdf') as handoff:
    for name in ('scope_top.bit', 'ps7_init.tcl'):
        assert handoff.read(name) == (out / name).read_bytes(), name
for name in ('scope_top.bit', 'scope.elf'):
    assert (root / 'boot' / name).read_bytes() == (out / name).read_bytes()
elf_ranges = {}
for name, lower, upper in [('scope.elf', 0x100000, 0x08000000), ('scope_diag.elf', 0, 0x2f000)]:
    data = (out / name).read_bytes()
    assert data[:7] == b'\x7fELF\x01\x01\x01' and struct.unpack_from('<H', data, 18)[0] == 40
    entry, offset = struct.unpack_from('<II', data, 24)
    size, count = struct.unpack_from('<HH', data, 42)
    assert lower <= entry < upper
    loads = []
    for i in range(count):
        kind, file_offset, va, pa, file_size, memory_size, flags, align = struct.unpack_from('<IIIIIIII', data, offset + i*size)
        if kind == 1:
            assert lower <= pa == va and pa + memory_size <= upper
            assert file_offset + file_size <= len(data) and file_size <= memory_size
            loads.append(dict(address=hex(pa), bytes=memory_size))
    assert loads
    elf_ranges[name] = loads

sim = json.loads(read(out / 'simulation/summary.json'))
assert set(sim) == {'capture', 'mailbox', 'video', 'vga', 'keys', 'tmds', 'histogram', 'roll', 'raster', 'axi', 'dma', 'fallback', 'adc', 'clocks', 'adc_latency', 'dac'}
assert all(value is True for value in sim.values())
analysis = json.loads(read(out / 'analysis_tests.json'))
for name in ('envelope', 'measure', 'no_signal', 'DMA_DDS_PHASE', 'EYE_PHASE', 'NOISE_FREQUENCY'):
    assert analysis[name].startswith('PASS'), name
assert len([key for key in analysis if re.fullmatch(r'fft_\d+_[01]', key)]) == 6
timing = read(out / 'timing_summary.rpt')
marker(out / 'timing_summary.rpt', 'All user specified timing constraints are met.')
row = re.search(r'WNS\(ns\).*?\n\s*[- ]+\n\s*([\d.-]+)\s+([\d.-]+)\s+(\d+)\s+(\d+)\s+([\d.-]+)', timing)
assert row
wns, tns, failing, endpoints, whs = row.groups()
assert float(wns) >= 0 and float(whs) >= 0 and float(tns) == 0 and int(failing) == 0
for rate in (10, 25, 50, 65):
    for delay in ('max', 'min'):
        report = read(out / f'adc_{rate}_{delay}.rpt')
        assert len(re.findall(r'^Slack \(MET\)', report, re.M)) == 13
for delay in ('setup', 'hold'):
    assert len(re.findall(r'^Slack \(MET\)', read(out / f'dac_{delay}.rpt'), re.M)) == 14
marker(out / 'dac_gate.txt', 'DAC_GATE_PASS 14 output pins,50MSa/s')
marker(out / 'cdc_review.txt', 'reviewed_critical_rows=159 unreviewed_critical_rows=0')
assert not re.search(r'\|\s*\S+\s*\|\s*(?:Error|Critical Warning)\s*\|', read(out / 'drc.rpt'))
marker(out / 'dac_v4_ui_console.log', 'PASS independent RGB frame CRC32 cdaac1b5')
marker(hil / 'firmware_control_test.log', 'PASS independent firmware: ADC/DAC configuration isolation')
marker(hil / 'waveform_unit_tests.log', 'Ran 4 tests')
marker(hil / 'waveform_unit_tests.log', 'OK')
marker(hil / 'font_coverage.log', 'PASS native UI font coverage')
marker(hil / 'clean_rebuild_console.log', 'BOOT_SEAL_PASS')
reconstruction=json.loads(read(hil/'clean_reconstruction/summary.json'))
assert reconstruction['status']=='PASS' and reconstruction['RTL_and_firmware_functional_sources_match_delivered']
marker(hil / 'cold_boot.txt', 'QSPI_COLD_BOOT_PASS boot_mode=1')
identity = re.search(r'source_sha=([0-9a-f]{8}) fw_sha=([0-9a-f]{8})', read(hil / 'cold_boot.txt'))
assert identity and identity[1] == release['rtl_revision']
marker(root / 'boot/flash_program.log', 'Flash Operation Successful')
marker(root / 'boot/flash_program.log', 'Verify Operation successful')
backup = root / 'backup/qspi_before_dac_20261017'
backup_record = json.loads(read(backup / 'manifest.json'))
assert hashlib.sha256((backup / 'qspi_16MiB.bin').read_bytes()).hexdigest() == backup_record['sha256']
assert (backup / 'qspi_16MiB.bin').stat().st_size == 16*1024*1024
serial = json.loads(read(hil / 'serial_hil.json'))
qt = json.loads(read(hil / 'host_ui_hil.json'))
assert serial['passed'] and serial['port'] == 'COM27' and qt['passed'] and qt['qt_serial_worker']
assert serial['uart']['uart_rx_lost'] == '0'
assert any('source_sha='+identity[1]+' fw_sha='+identity[2] in item['response'] for item in serial['log'])
raw = read(hil / 'adc_regression_hil.log')
assert 'PRD_FUNCTIONAL_HIL_PASS rates=4 mode_transitions=1000 final_source=ADC' in raw
assert f'source_sha={identity[1]} fw_sha={identity[2]}' in raw
rates = []
for rate in (10, 25, 50, 65):
    match = re.search(rf'selftest=PASS rate={rate*1000000}\b', raw)
    assert match
    before = raw[:match.start()]
    dds = list(re.finditer(r'bytes=2097152 .*?payload_MBps=([\d.]+).*?test_kind=1', before))[-1]
    stress = list(re.finditer(r'bytes=2097152 .*?payload_MBps=([\d.]+).*?test_kind=2', before))[-1]
    assert float(stress[1]) >= 143
    rates.append(dict(sample_rate_sps=rate*1000000, DDS_exact_1Mi_sample_payload_MBps=float(dds[1]), SYS_stress_payload_MBps=float(stress[1])))

soak_folder = args.soak_folder
if soak_folder is None:
    candidates=sorted(hil.glob('soak_*'),reverse=True)
    completed=[p for p in candidates if (p/'summary.json').exists() and json.loads(read(p/'summary.json'))['status']=='PASS']
    assert candidates if args.progress else completed, 'No complete uninterrupted hour has passed; acceptance not written'
    soak_folder=(candidates if args.progress else completed)[0]
subprocess.run([sys.executable, str(root / 'tests/hil/analyze_combined_soak.py'), str(soak_folder)] + ([] if args.progress else ['--require-hour']), check=True)
if args.progress:
    print('V4_ARTIFACTS_AND_COMPLETED_HIL_PASS; hour progress only, acceptance not written')
    raise SystemExit(0)
soak = json.loads(read(soak_folder / 'analysis.json'))
assert soak['status'] == 'HOUR_PASS'
soak_summary=json.loads(read(soak_folder/'summary.json'))
assert soak_summary['version']['source_sha']==identity[1] and soak_summary['version']['fw_sha']==identity[2]
reloads=json.loads(read(hil/'warm_reloads.json'))
assert reloads['passed'] and reloads['count']==5
marker(hil/'final_board_state.log', 'FINAL_BOARD_STATE_PASS source=ADC rate=10000000 real_segments=8 DAC_midcode=8192')
screens=json.loads(read(hil/'screen_capture_log.json'));assert screens['passed']
for mode in ['DSO','DPX','EYE','FFT','ROLL','MEM','SEG']:
    assert (hil/f'HDMI_{mode}_REAL_v4.png').stat().st_size>10000
result = dict(date='2026-10-17', project='OSC_ad9226_hdmi', version='4.0', overall='DIGITAL_AND_HIL_PASS_ANALOG_UNCALIBRATED',
    identity=dict(rtl_source=identity[1], firmware_source=identity[2]),
    artifacts=dict(release=release, boot=boot, HDF_embedded_bit_and_PS7_match=True, ELF_load_ranges=elf_ranges),
    implementation=dict(WNS_ns=float(wns), WHS_ns=float(whs), TNS_ns=0, LUT=7109, FF=11981, BRAM36_equivalent=46, DSP=4, raw_CDC_critical_rows=159, reviewed_CDC_critical_rows=159, unreviewed_CDC_critical_rows=0, DRC_errors=0, DRC_critical_warnings=0, DRC_warnings=7, DRC_advisories=1),
    ADC_rates=rates, RTL_tests=sim, C_NumPy=analysis,
    serial=dict(port='COM27', baud=115200, transactions=len(serial['log']), passed=True, RX_lost=0),
    host_Qt_serial_worker=qt, combined_hour=soak, warm_JTAG_reloads=reloads, clean_reconstruction=reconstruction,
    flash=dict(part='W25Q128JV', JEDEC='ef4018', bytes=16777216, offset=0, mode='qspi-x4-single', program_verify='PASS', actual_user_power_cycle='PASS', boot_mode_register=1, original_backup_sha256=backup_record['sha256']),
    features=dict(DSO='PASS_DIGITAL', DPX='PASS_160x90_PRD_ALLOWED', EYE='PASS_DIGITAL_FOLDING_NO_CDR', FFT='PASS_DIGITAL', ROLL='PASS_DIGITAL', MEM='PASS_FINITE_1Mi_SAMPLES', SEG='PASS_8x16K_WITH_TIMESTAMPS', native_Chinese_16x24='PASS', axes_all_modes='PASS_DIGITAL', independent_DAC_DDS_and_table='PASS', serial_and_custom_table='PASS', mode_changes_1000='PASS', one_hour_ADC_DAC_HDMI='PASS', QSPI_cold_boot='PASS'),
    boundaries=dict(ADC_module_nominal='user: +/-5V @50ohm; 10V/4095 code, zero2047.5; not calibrated', DAC_module_nominal='user: 5Vpp; digital %FS, actual analog offset/load/gain not measured', DAC_digital_supply='module circuit unavailable; verify VIH against actual digital supply', ADC_input='floating; no known analog reference', DAC_preview='digital configuration/readback, not analog measurement', DAC_stop='hold midcode8192, PD not wired, not HiZ', EYE='no reference lock/CDR/BER, width and jitter N/A', MEM='finite record, not dead-time-free ring', config='volatile board RAM or host JSON; Flash contains startup defaults', video='PL720p60, USB capture720p30; static floating input may yield unchanged frame/footer pixels', power='Vivado estimate1.904W Low confidence; no measured thermal result', qualification_field='ver qualification=BENCH_PENDING is a legacy constant, this evidence record is authoritative'))
(root / 'docs/Acceptance.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
(hil / 'release_verification.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print('V4_RELEASE_PASS', identity[1], identity[2], 'one_hour=PASS flash_cold_boot=PASS')
