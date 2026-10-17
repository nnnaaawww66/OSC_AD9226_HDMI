"""Exercise real Qt controls and SerialWorker against the connected board.
Renders only the application's own offscreen window; never reads the desktop.
"""
import os,sys,time,json,zlib
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
r=Path(__file__).resolve().parents[2];sys.path.insert(0,str(r/'host'))
import numpy as np
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFontDatabase,QFont
from app import Window,STYLE
out=r/'results/2026-10-17/dac_v4';out.mkdir(parents=True,exist_ok=True)
app=QApplication([]);QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont('Microsoft YaHei',10));app.setStyleSheet(STYLE.replace('Microsoft YaHei UI','Microsoft YaHei'))
w=Window();w.timer.stop();w.show();errors=[];w.worker.failed.connect(errors.append)
def wait(condition,timeout=30):
    end=time.monotonic()+timeout
    while not condition():
        app.processEvents();time.sleep(.01)
        if time.monotonic()>end:raise TimeoutError('Qt/serial operation timed out')
    app.processEvents()
def idle():wait(lambda:w.worker.jobs.unfinished_tasks==0)
try:
    w.ports.setCurrentIndex(w.ports.findData('COM27'));assert w.ports.currentData()=='COM27'
    w.toggle_connection();wait(lambda:w.online);idle()
    w.adc_mode.setCurrentIndex(w.adc_mode.findData('fft'));w.adc_rate.setCurrentIndex(w.adc_rate.findData(25));w.adc_apply();idle()
    w.span.setValue(2048);w.gain.setCurrentIndex(1);w.view_apply();idle();w.refresh_controls();idle()
    assert w.adc_mode.currentData()=='fft' and w.adc_rate.currentData()==25 and w.span.value()==2048
    w.tabs.setCurrentIndex(0);app.processEvents();w.grab().save(str(out/'host_adc_actual.png'))
    w.tabs.setCurrentIndex(1);w.shape.setCurrentIndex(w.shape.findData('expression'));w.freq.setValue(4321);w.amp.setValue(20);w.dc.setValue(50);w.formula.setText('0.8*sin(2*pi*t)+0.2*sin(6*pi*t)');w.enabled.setChecked(False)
    w.upload();idle();wait(lambda:w.confirmed_table is not None)
    np.testing.assert_array_equal(w.confirmed_table,w.current_table)
    assert w.progress.value()==100 and w.plot.ack
    w.grab().save(str(out/'host_dac_actual.png'))
    assert not errors,errors
    result=dict(passed=True,crc32=f'{zlib.crc32(w.confirmed_table.tobytes()):08x}',qt_serial_worker=True,real_port='COM27',errors=errors)
finally:
    if w.online:
        for cmd in ['dac enable 0','page adc','adc source real','adc rate 10','mode dso','view span 4096','view gain 0','view zero 2047.5','view auto 0','run 1']:w.send(cmd)
        idle()
    w.close();app.processEvents()
(out/'host_ui_hil.json').write_text(json.dumps(result,indent=2));print('PASS real Qt controls, confirmed waveform preview and SerialWorker COM27')
