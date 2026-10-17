"""Build the release qualification record from verified evidence, not UI text."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
out = root / 'results/2026-10-17'
hil = out / 'prd_completion'
parser = argparse.ArgumentParser()
parser.add_argument('--draft', action='store_true', help='Keep unfinished soak explicitly PENDING')
args = parser.parse_args()
subprocess.run([sys.executable, str(root / 'tests/verify_release.py')]
               + ([] if args.draft else ['--require-soak']), check=True)
v = json.loads((hil / 'release_verification.json').read_text())
raw = (hil / 'functional_hil.log').read_text(encoding='utf-8')
rates = []
for rate in (10, 25, 50, 65):
    # HIL command spelling is preserved; isolate each rate by its selftest marker.
    marker = re.search(rf'selftest=PASS rate={rate * 1000000}\b', raw)
    assert marker
    before = raw[:marker.start()]
    dds = list(re.finditer(r'bytes=2097152 .*?payload_MBps=([\d.]+).*?test_kind=1', before))[-1]
    stress = list(re.finditer(r'bytes=2097152 .*?payload_MBps=([\d.]+).*?test_kind=2', before))[-1]
    count = re.search(rf'RATE_COUNTER requested_MSa={rate} measured_Sa_s=([\d.]+)', raw)
    assert count and float(stress.group(1)) >= 143
    rates.append({'sample_rate_sps': rate * 1000000, 'status': 'PASS_DIGITAL',
                  'DDS_exact_1Mi_sample_payload_MBps': float(dds.group(1)),
                  'SYS_stress_payload_MBps': float(stress.group(1)),
                  'sample_counter_rate_sps_approximate': float(count.group(1)),
                  'input_max_paths': 13, 'input_min_paths': 13})


def feature(name, status, why, evidence):
    qualification = status
    if status.startswith('PASS_'):
        status = 'PASS'
    elif status.startswith('DISABLED_'):
        status = 'DISABLED'
    return {'feature': name, 'status': status, 'qualification': qualification,
            'reason': why, 'evidence': evidence}


e = 'results/2026-10-17/'
p = e + 'prd_completion/'
features = [
    feature('HDMI / ARM / JTAG / source indication', 'PASS',
            'Actual 720p HDMI; stage 6 heartbeat; default REAL; persistent SIM warning and invalidated stale results.',
            [p+'recovery_program.log', p+'HDMI_REAL_final.png', p+'HDMI_SIM_warning.png']),
    feature('DSO 16K / 8K pretrigger / Auto Normal Single STOP', 'PASS_DIGITAL',
            'RTL address/count assertions plus actual SIM trigger semantics; external analog reference not claimed.',
            [e+'simulation/summary.json', p+'trigger_hil_console.log']),
    feature('10 / 25 / 50 / 65MSa/s', 'PASS_DIGITAL',
            'Four clocks, 13 input setup/hold paths each, exact 1Mi DDS sequence and actual ADC counter rates.',
            [p+'functional_hil.log', e+'adc_65_max.rpt', e+'adc_65_min.rpt']),
    feature('Real AD9226 analog input', 'LIMITED',
            'User-confirmed floating input; code approximately 2037..2044, OTR=0, no valid period. No calibrated external generator or measured module gain/skew.',
            [p+'HDMI_65M_recovery.png', p+'ila/analysis.json']),
    feature('DPX', 'PASS_WITH_ALLOWED_REDUCTION',
            '160x90 density plane; bounded raster, hit FIFO, RMW forwarding, saturation, decay and snapshot; not 65M fully rasterized samples/s.',
            [e+'simulation/summary.json', p+'HDMI_DPX_real.png']),
    feature('EYE', 'LIMITED',
            'Known 1..5Mb/s, 2UI folding; four-rate and long 64bit-index golden tests. No reference lock/CDR; physical NRZ reference not measured.',
            [e+'analysis_tests.json', p+'HDMI_EYE_real.png']),
    feature('FFT', 'PASS_DIGITAL',
            'Actual C vs NumPy for all sizes/windows, DC/noise/two-tone/boxcar; units based on effective sample rate; physical analog response uncalibrated.',
            [e+'analysis_tests.json', p+'HDMI_FFT_real.png']),
    feature('ROLL', 'PASS_DIGITAL',
            'ADC Min/Max bins retain narrow pulses, carry time/sample metadata and report missed columns; actual HDMI.',
            [e+'simulation/summary.json', p+'HDMI_ROLL_real.png']),
    feature('DDR / MEM / SEG', 'PASS_WITH_DOCUMENTED_LIMITS',
            '2MiB pattern, >=143MB/s stress and exact 1Mi DDS prerequisite at each rate; finite 1Mi MEM; eight 16K segments with CRC and timestamps. Acquisition deadtime is counted.',
            [p+'functional_hil.log', p+'ila/ila_sys_last.csv']),
    feature('Two-key control / CLI', 'PASS_DIGITAL_PHYSICAL_LIMITED',
            'RTL debounce/combination tests, common firmware 21-item menu paths and JTAG commands. User confirmed physical keys produced seven-mode, RUN/STOP and ADC/SIM changes in the preserved log. Full physical menu campaign and UART cable not claimed.',
            [e+'simulation/summary.json', e+'ui_sim/host_test.log',p+'soak_manual_source_change_attempt.log']),
    feature('ILA / actual pixel CRC / errors', 'PASS',
            'Three actual ILA captures, sample +1, AXIS stable under backpressure and TLAST, video timing; independent zlib RGB CRC regression.',
            [p+'ila/analysis.json', p+'final_ui_sim.log', e+'ui_sim/rtl_display.log']),
    feature('One-hour 65MSa/s real ADC and 720p continuity', v['soak']['status'],
            'Only an uninterrupted raw run of at least 3600000ms can pass. Earlier USB disconnect and Tcl signed-counter parsing failure are preserved separately.',
            [p+'soak.log', p+'soak_analysis.json']),
    feature('1000 switches / repeated warm boots / clean rebuild', 'PASS',
            '1000 actual board mode changes, five stage-6 warm boots; fresh directory FPGA+BSP+ELF reconstruction.',
            [p+'functional_hil.log', p+'warm_boots.log', p+'clean_rebuild/reconstruction_analysis.json']),
    feature('Calibrated volts / EYE width-jitter', 'DISABLED_UNTIL_QUALIFIED',
            'N/A until external voltage calibration/reference lock. Never substitute chip supply voltage for module transfer gain.', []),
    feature('Advanced pulse/window triggers / CDR / BER', 'DISABLED_P2_DEFERRED',
            'Explicit optional P2 scope in PRD section 4; not implemented or represented as available.', []),
]
record = {
    'date': '2026-10-17', 'project': 'OSC_ad9226_hdmi',
    'overall': 'DIGITAL_IMPLEMENTATION_AND_HIL_PASS_ANALOG_LIMITED' if v['status']=='PASS' else 'PENDING_UNINTERRUPTED_SOAK',
    'profile': {'part':'xc7z010clg400-1', 'video':'1280x720@60Hz',
                'default_source':'ADC', 'default_rate_sps':10000000,
                'qualified_digital_rates_sps':[r['sample_rate_sps'] for r in rates],
                'ADC_clock':'FPGA output Y17 / JP1-16, user confirmed',
                'density':'160x90 PRD-permitted reduction',
                'rtl_build_revision':v['rtl_revision'], 'firmware_build_revision':v['firmware_revision']},
    'digital_implementation': {'status':'PASS', 'WNS_ns':v['WNS_ns'], 'WHS_ns':v['WHS_ns'],
        'TNS_ns':0, 'LUT':6997, 'FF':11441, 'RAMB36_equivalent':37.5, 'DSP':4,
        'raw_CDC_Critical_rows':159, 'reviewed_CDC_Critical_rows':159, 'unreviewed_CDC_Critical_rows':0,
        'CDC_exact_allowlist_tuples':68, 'DRC_errors':0, 'DRC_critical_warnings':0,
        'DRC_warnings':7, 'DRC_advisories':1, 'unconstrained_internal_endpoints':0,
        'ADC_unconstrained_inputs':0, 'TMDS_serial_no_output_delay_notices':4,
        'power_estimate_W':1.873, 'power_confidence':'Low; not instrument measured'},
    'rate_results':rates, 'verification':v, 'features':features,
    'milestones': {
        'G0':'LIMITED: board/vendor inventory complete, CLK and module supply confirmed by user; module gain/output-level/skew not measured',
        'G1':'PASS_DIGITAL: actual HDMI, stage6, keys RTL/firmware and user-confirmed key mode/RUN/source changes; UART disconnected, no physical cold-cycle claim',
        'G2':'PASS_DIGITAL / ANALOG_LIMITED: four rates, timing, counters, ILA; known external signal pending',
        'G3':'PASS_DIGITAL: 16K pretrigger and actual SIM trigger semantics; external analog phase/gain pending',
        'G4':'PASS: per-rate exact DMA+CRC and SYS stress >=143MB/s; finite records',
        'G5':'PASS_ALLOWED_REDUCTION: 160x90 RMW/raster/decay/drop accounting and actual video',
        'G6':'LIMITED: known-rate folding and goldens, no physical NRZ reference or CDR',
        'G7':'PASS_DIGITAL / ANALOG_LIMITED: NumPy FFT and ROLL MinMax tests, actual screens',
        'G8':'PASS_WITH_LIMITS: 1Mi MEM, eight segments, CRC and sample-index timestamps, counted deadtime',
        'G9':v['status']+': uninterrupted soak required, 1000 actual switches and five warm boots complete'},
    'hardware_probe': {'JTAG':'Digilent JTAG-HS2 201706300081 / xc7z010 IDCODE 13722093',
        'capture':'USB3 Video direct dshow/PyAV, 1280x720@30 acquisition of board 720p60 output',
        'UART':'Disconnected per user; no physical UART PASS claim', 'input':'Floating, user confirmed',
        'flash_written':False, 'physical_power_cycles_claimed':False},
    'constraints_limits':['ADI tOD 3.5..7ns plus provisional 0..3ns external allowance; external module path unmeasured',
        'Four TMDS source-synchronous serial outputs retain no_output_delay notices; no fabricated receiver setup/hold',
        'Raw CDC Critical retained; only exact vendor/UG472 tuples reviewed; unknown paths fail build'],
    'delivery_commit':'Recorded by Release_Manifest.json to avoid a self-referential commit hash',
    'release_tag':'prd-digital-2026-10-17',
    'supersedes':'boardfix-2026-10-17-jtag-ui; normal default now REAL, all four digital rates qualified',
}
(root/'docs/Acceptance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print('ACCEPTANCE_WRITTEN',record['overall'])
