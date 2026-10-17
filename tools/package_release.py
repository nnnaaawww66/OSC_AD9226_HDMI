"""Package the qualified live release; no hardware access or source mutation."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
result = root/'results/2026-10-17'
hil = result/'prd_completion'
p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
output = a.output.resolve()
output.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(root/'tests/verify_release.py'), '--require-soak'], check=True)
acceptance = json.loads((root/'docs/Acceptance.json').read_text(encoding='utf-8'))
assert acceptance['overall']=='DIGITAL_IMPLEMENTATION_AND_HIL_PASS_ANALOG_LIMITED'
assert acceptance['verification']['soak']['status']=='PASS'
revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip(), 'Commit reviewed source changes before packaging'
tag = 'prd-digital-2026-10-17'
assert subprocess.check_output(['git','rev-list','-n','1',tag],cwd=root,text=True).strip()==revision

files = {}
def add(path, name=None):
    assert path.is_file(), path
    files[name or path.relative_to(root).as_posix()] = path

for name in subprocess.check_output(['git','ls-files','-z'],cwd=root).decode('utf-8').split('\0'):
    if name:
        add(root/name)
add(root/'docs/Acceptance.json')
for name in ('scope_top.bit','scope_top.hdf','scope_top.ltx','scope_design.hwdef',
             'scope_routed.dcp','scope.elf','scope_diag.elf','ps7_init.tcl',
             'build_revision.txt','hardware_build.ok','sdk_build.ok','release_artifacts.json',
             'analysis_tests.json','ip_inventory.json','machine_info.json','tool_probe.txt',
             'reset_gate_test.log','scope_elf_segments.txt','diag_elf_segments.txt'):
    add(result/name)
for path in result.glob('*.rpt'):
    add(path)
for path in (result/'simulation').rglob('*'):
    if path.is_file() and (path.name=='run.log' or path.name=='summary.json'):
        add(path)
for name in ('ui_rtl.png','ui_vga.png','host_test.log','rtl_display.log','vga_display.log'):
    add(result/'ui_sim'/name)
excluded = {'package_release_console.log','HDMI_REAL_baseline.png','release_7378052_console.log',
            'release_console.log','release_final_console.log','release_export_console.log',
            'sdk_7378052.log','sdk_build.log','sdk_release.log','functional_hil_console.log',
            'ila_analysis.log','ila_capture_console.log','ila_capture.log',
            'ila_active_capture_console.log','ila_active_capture.log'}
for path in hil.rglob('*'):
    if path.is_file() and path.name not in excluded and path.suffix in {'.png','.json','.jsonl','.log','.rpt','.txt','.csv','.ila','.tcl'}:
        add(path)
add(result/'hil/jtag_acceptance.log')
for path in (root/'sw/sdk2018/scope_bsp').rglob('*'):
    rel = path.relative_to(root/'sw/sdk2018/scope_bsp')
    if path.is_file() and path.suffix not in {'.o','.d'} and not any(part.startswith('.') for part in rel.parts):
        add(path,'sw/bsp_export/'+rel.as_posix())

entries=[]
for name,path in sorted(files.items()):
    data=path.read_bytes()
    entries.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
manifest={'date':'2026-10-17','delivery_commit':revision,'release_tag':tag,
          'rtl_bit_revision':acceptance['profile']['rtl_build_revision'],
          'firmware_revision':acceptance['profile']['firmware_build_revision'],
          'profile':'1280x720@60; default REAL ADC 10MSa/s; digital 10/25/50/65MSa/s',
          'qualification':'Digital implementation and HIL PASS; analog reference/calibration LIMITED',
          'working_project':str(root),'source_archive_opening':'Run build.ps1 -Recreate in a new short path; generated XPR/cache are not included',
          'flash_written':False,'entries':entries}
manifest_path=output/'Release_Manifest.json'
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
archive=output/'Z7_Scope_PRD_digital_release.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
    for name,path in sorted(files.items()):
        z.write(path,name)
    z.write(manifest_path,'Release_Manifest.json')
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(entries)+1
    for entry in entries:
        assert hashlib.sha256(z.read(entry['path'])).hexdigest()==entry['sha256'],entry['path']
for name in ('Z7_Scope_boardfix_JTAG_UI.zip','Z7_Scope_source_and_outputs.zip'):
    shutil.copy2(archive,output/name)
for name in ('Delivery_Report.md','User_Manual.md','Acceptance.json','Release_Notes.md'):
    shutil.copy2(root/'docs'/name,output/name)
for path in hil.glob('HDMI_*.png'):
    if path.name!='HDMI_REAL_baseline.png':
        shutil.copy2(path,output/path.name)
for old,new in {'HDMI_DSO_live.png':'HDMI_DSO_real.png','HDMI_FFT_live.png':'HDMI_FFT_real.png',
                'HDMI_DPX_live.png':'HDMI_DPX_real.png','HDMI_EYE_live.png':'HDMI_EYE_real.png',
                'HDMI_ADC_live.png':'HDMI_REAL_final.png'}.items():
    shutil.copy2(hil/new,output/old)
for src,dst in ((result/'ui_sim/ui_rtl.png','ui_720p_rtl.png'),
                (result/'ui_sim/ui_vga.png','ui_vga_rtl.png')):
    shutil.copy2(src,output/dst)
integrity={'status':'PASS','archive':str(archive),'entries_verified':len(entries),
           'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
           'delivery_commit':revision,'qualification':manifest['qualification']}
(output/'Package_Verification.json').write_text(json.dumps(integrity,indent=2),encoding='utf-8')
checksums=[]
for path in sorted(output.iterdir()):
    if path.is_file() and path.name!='SHA256SUMS.txt':
        checksums.append(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.name)
(output/'SHA256SUMS.txt').write_text('\n'.join(checksums)+'\n',encoding='utf-8')
print(json.dumps(integrity,indent=2))
