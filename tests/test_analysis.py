from pathlib import Path
import ctypes as c,subprocess,numpy as np,json,zlib
r=Path(__file__).resolve().parents[1];out=r/'results/2026-10-17';dll=out/'scope_analysis.dll'
subprocess.run(['gcc','-std=c99','-O2','-shared','-Wall','-Wextra','-Werror','-I'+str(r/'sw/include'),str(r/'sw/src/scope_analysis.c'),'-o',str(dll),'-lm'],check=True)
lib=c.CDLL(str(dll));p16=np.ctypeslib.ndpointer(np.uint16,flags='C_CONTIGUOUS');p32=np.ctypeslib.ndpointer(np.uint32,flags='C_CONTIGUOUS');pf=np.ctypeslib.ndpointer(np.float32,flags='C_CONTIGUOUS')
lib.scope_fft.argtypes=[p16,c.c_uint,c.c_uint,c.c_int,c.c_double,pf,pf,pf,c.POINTER(c.c_double),c.POINTER(c.c_double)]
lib.scope_envelope.argtypes=[p16,c.c_uint,c.c_uint,c.c_uint,p32]
class Measures(c.Structure):_fields_=[('mean',c.c_double),('rms',c.c_double),('frequency',c.c_double),('min',c.c_uint16),('max',c.c_uint16),('crossings',c.c_uint32),('overrange',c.c_uint32),('frequency_valid',c.c_int)]
lib.scope_measure.argtypes=[p16,c.c_uint,c.c_double,c.POINTER(Measures)]
results={};rng=np.random.default_rng(7010)
for n in [1024,2048,4096]:
 for hann in [0,1]:
  fs=64000.;t=np.arange(n)/fs;data=np.rint(2048+900*np.sin(2*np.pi*1000*t)+150*np.sin(2*np.pi*3500*t)).astype(np.uint16)
  re=np.zeros(n,np.float32);im=re.copy();db=np.zeros(n//2,np.float32);hz=c.c_double();amp=c.c_double()
  lib.scope_fft(data,n,1,hann,fs,re,im,db,c.byref(hz),c.byref(amp))
  win=np.hanning(n) if hann else np.ones(n);ref=np.fft.fft((data.astype(float)-data.mean())*win)
  relative=np.max(np.abs(re+1j*im-ref))/np.max(np.abs(ref))
  assert relative<8e-5,(n,hann,relative)
  assert abs(hz.value-1000)<fs/n*0.05,(n,hann,hz.value)
  refdb=20*np.log10(np.maximum(2*np.abs(ref[:n//2])/(win.sum()*2048),1e-6));refdb[0]=max(-120,refdb[0]-6.0206)
  assert abs(amp.value-refdb[n//64])<0.003,(amp.value,refdb[n//64])
  results[f'fft_{n}_{hann}']={'relative_complex_error':float(relative),'peak_hz':hz.value,'peak_dbfs':amp.value}
  np.savez(r/'tests/golden_vectors'/f'fft_{n}_{hann}.npz',data=data,re=ref.real,im=ref.imag,fs=fs)
data=rng.integers(0,4096,16384,dtype=np.uint16);data[17]=4095;wave=np.zeros(960,np.uint32);lib.scope_envelope(data,len(data),0,len(data),wave)
for x,w in enumerate(wave):
 a=x*len(data)//960;b=(x+1)*len(data)//960
 assert (w&1023)==609-int(data[a:b].max())*539//4095
 assert (w>>10)==609-int(data[a:b].min())*539//4095
results['envelope']='PASS all 960 columns including narrow peaks'
t=np.arange(16384)/10000000;data=np.rint(2048+1000*np.sin(2*np.pi*10000*t)).astype(np.uint16);m=Measures();lib.scope_measure(data,len(data),1e7,c.byref(m));assert m.frequency_valid and abs(m.frequency-10000)<1
assert abs(m.mean-data.mean())<1e-9 and abs(m.rms-np.sqrt(np.mean(data.astype(float)**2)))<1e-9
results['measure']='PASS frequency, code RMS, min/max'
data[:]=2048;lib.scope_measure(data,len(data),1e7,c.byref(m));assert not m.frequency_valid;results['no_signal']='PASS invalid frequency on DC'

for kind,n,stride in [('DC',4096,1),('NOISE',2048,1),('BOXCAR',1024,16)]:
 data=(np.full(n*stride,2048,dtype=np.uint16) if kind=='DC' else rng.integers(1000,3000,n*stride,dtype=np.uint16))
 re=np.zeros(n,np.float32);im=re.copy();db=np.zeros(n//2,np.float32);hz=c.c_double();amp=c.c_double()
 lib.scope_fft(data,n,stride,1,10000000.,re,im,db,c.byref(hz),c.byref(amp))
 averaged=data.astype(float).reshape(n,stride).mean(axis=1);ref=np.fft.fft((averaged-averaged.mean())*np.hanning(n))
 err=np.max(np.abs(re+1j*im-ref))/max(1,np.max(np.abs(ref)))
 assert err<8e-5,(kind,err)
 results['fft_'+kind]={'relative_complex_error':float(err),'stride':stride}
(out/'analysis_tests.json').write_text(json.dumps(results,indent=2));print('PASS portable C analysis against NumPy; seed=7010')
