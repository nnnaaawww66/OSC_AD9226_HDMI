from pathlib import Path
import subprocess,json,sys,time
root=Path(__file__).resolve().parents[1]
bin=Path(r'D:/Xilinx/Vivado/2018.3/bin')
out=root/'results/2026-10-17/simulation';out.mkdir(exist_ok=True)
tests={'capture':['scope_capture.v'],'mailbox':['reset_sync.v'],'video':['scope_video_timing.v'],'vga':['scope_video_timing.v'],'keys':['scope_keys.v'],'tmds':['../vendor/encode.v'],'histogram':['scope_histogram.v'],'roll':['scope_roll.v'],'raster':['scope_raster.v'],'axi':['reset_sync.v','scope_capture.v','scope_keys.v','scope_video_timing.v','scope_display.v','scope_dma_stream.v','scope_histogram.v','scope_raster.v','scope_roll.v','scope_dac.v','scope_peripheral.v'],'dma':['reset_sync.v','scope_dma_stream.v']}
tests['fallback']=tests['axi']
tests['adc']=tests['axi']
tests['clocks']=['scope_clocks.v']
tests['adc_latency']=[]
tests['dac']=['reset_sync.v','scope_dac.v']
results={}
for name,rtl in tests.items():
    if len(sys.argv)>1 and name not in sys.argv[1:]:continue
    d=out/(name+'_'+str(time.time_ns()));d.mkdir(exist_ok=True)
    extra=[]
    if name in ['axi','dma','fallback','adc']:
        xp=Path(r'D:/Xilinx/Vivado/2018.3/data/ip/xpm')
        extra=[str(xp/f'{p}/hdl/{p}.sv') for p in ['xpm_cdc','xpm_memory','xpm_fifo']]
        extra += [r'D:/Xilinx/Vivado/2018.3/data/verilog/src/glbl.v']
    if name=='clocks':extra=[r'D:/Xilinx/Vivado/2018.3/data/verilog/src/glbl.v']
    if name=='tmds':
        import shutil
        for f in ['tmds_input.mem','tmds_expected.mem']:shutil.copy2(root/'tests/golden_vectors'/f,d/f)
    if name in ['axi','fallback','adc']:
        import shutil
        for f in ['font_hi.mem','font_mid.mem','font_lo.mem','screen.mem']:shutil.copy2(root/'hw/rtl'/f,d/f)
    commands=[['xvlog.bat','-sv',*extra,*[str(root/'hw/rtl'/f) for f in rtl],str(root/'sim'/f'tb_{name}.sv')],
              ['xelab.bat',f'tb_{name}',*(['glbl'] if extra else []),'-s',f'test_{name}','-debug','typical','-L','unisims_ver','-mt','4'],
              ['xsim.bat',f'test_{name}','-R']]
    log=''
    for cmd in commands:
        p=subprocess.run([str(bin/cmd[0]),*cmd[1:]],cwd=d,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=180)
        log+=p.stdout
        if 'Failed to launch child process' in p.stdout:
            p=subprocess.run([str(bin/cmd[0]),*cmd[1:]],cwd=d,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=180)
            log+='\nRETRY transient XSim launch failure\n'+p.stdout
        if p.returncode:break
    (d/'run.log').write_text(log,encoding='utf-8')
    results[name]=bool(p.returncode==0 and f'PASS {name}' in log and 'Fatal:' not in log)
    print(name, 'PASS' if results[name] else 'FAIL',flush=True)
    if not results[name]:print(log[-6000:],flush=True)
(out/'summary.json').write_text(json.dumps(results,indent=2))
sys.exit(0 if all(results.values()) else 1)
