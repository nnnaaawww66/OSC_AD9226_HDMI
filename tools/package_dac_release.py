"""Package only sealed current outputs and explicit 4.0 evidence."""
import argparse,hashlib,json,subprocess,zipfile,sys
from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,str(r/'tests/verify_dac_release.py')],cwd=r,check=True)
subprocess.run([sys.executable,str(r/'tools/write_dac_report.py')],cwd=r,check=True)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
sealed=json.loads((r/'results/2026-10-17/release_artifacts.json').read_text(encoding='utf-8-sig'))
for f in sealed['files']:assert sha(r/'results/2026-10-17'/f['name'])==f['sha256']
boot=json.loads((r/'boot/manifest.json').read_text(encoding='utf-8-sig'))
for f in boot['files']:assert sha(r/'boot'/f['name'])==f['sha256']
tracked=subprocess.check_output(['git','ls-files','-z'],cwd=r).decode().split('\0')
files={Path(f) for f in tracked if f and (r/f).is_file()}
result=r/'results/2026-10-17'
names=['scope_top.bit','scope_top.hdf','scope_top.ltx','scope.elf','scope_diag.elf','ps7_init.tcl','hardware_build.ok','sdk_build.ok','build_revision.txt','release_artifacts.json','timing_summary.rpt','utilization.rpt','drc.rpt','io.rpt','power.rpt','check_timing.rpt','clock_interaction.rpt','cdc.rpt','cdc_details.rpt','cdc_review.txt','dac_setup.rpt','dac_hold.rpt','dac_gate.txt']
names += [f'adc_{rate}_{delay}.rpt' for rate in [10,25,50,65] for delay in ['max','min']]
for name in names:files.add((result/name).relative_to(r))
for folder in [r/'boot',r/'backup/qspi_before_dac_20261017',result/'dac_v4']:
    for f in folder.rglob('*'):
        if f.is_file() and f.suffix.lower() not in ['.dcp','.wdb','.exe']:files.add(f.relative_to(r))
for name in ['dac_v4_sim_console.log','dac_v4_ui_console.log','dac_v4_program_console.log','dac_v4_sdk_final.log','dac_v4_97d15f6_build.log','dac_v4_97d15f6_console.log','qspi_backup_console.log']:
    f=result/name
    if f.exists():files.add(f.relative_to(r))
files.add((result/'simulation/summary.json').relative_to(r))
files.add((r/'docs/Acceptance.json').relative_to(r))
manifest={'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'rtl_revision':sealed['rtl_revision'],'files':[]}
archive=out/'Z7_LAB_ADC_DAC_v4_project.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(files):
        path=r/f;assert path.is_file(),path
        z.write(path,f.as_posix());manifest['files'].append(dict(path=f.as_posix(),bytes=path.stat().st_size,sha256=sha(path)))
    z.writestr('PACKAGE_MANIFEST.json',json.dumps(manifest,indent=2,ensure_ascii=False))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
(out/'Project_Package_Manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
print('PROJECT_PACKAGE_PASS',len(files),archive.stat().st_size,sha(archive),flush=True)
