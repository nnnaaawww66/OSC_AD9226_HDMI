"""Z7 LAB Windows console. Launch with python app.py (Python 3.10+)."""
import sys, json, re, argparse
from pathlib import Path
import numpy as np
from PySide6.QtCore import Qt, QTimer, QPointF, QRectF
from PySide6.QtGui import QColor, QPainter, QPen, QPainterPath, QFont, QFontDatabase
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QFormLayout,QGroupBox,QLabel,QPushButton,QComboBox,QDoubleSpinBox,QSpinBox,QLineEdit,QPlainTextEdit,QTabWidget,QSplitter,QFileDialog,QMessageBox,QProgressBar,QCheckBox,QScrollArea)
from serial.tools import list_ports
from waveforms import make_table,actual_frequency,TABLE_N
from transport import SerialWorker

class Plot(QWidget):
    def __init__(self):
        super().__init__();self.setMinimumSize(520,270);self.data=None;self.frequency=1000.;self.ack=False;self.auto_range=True
    def set_data(self, values, frequency, ack=False):
        self.data=np.asarray(values);self.frequency=frequency;self.ack=ack;self.update()
    def paintEvent(self,event):
        p=QPainter(self);p.setRenderHint(QPainter.Antialiasing);p.fillRect(self.rect(),QColor('#0a1220'))
        area=QRectF(72,42,self.width()-125,self.height()-90)
        lo,hi=0.,16383.
        if self.auto_range and self.data is not None:
            margin=max(80.,(float(self.data.max())-float(self.data.min()))/8)
            lo=max(0.,float(self.data.min())-margin);hi=min(16383.,float(self.data.max())+margin)
        span=2/self.frequency
        scale,unit=(1e9,'ns') if span<1e-6 else (1e6,'us') if span<.001 else (1e3,'ms') if span<1 else (1,'s')
        p.setFont(QFont('Microsoft YaHei',9))
        for i in range(11):
            x=area.left()+area.width()*i/10;p.setPen(QColor('#243347'));p.drawLine(QPointF(x,area.top()),QPointF(x,area.bottom()))
            if i%2==0:
                p.setPen(QColor('#8da9c4'));p.drawText(QRectF(x-38,area.bottom()+9,80,24),Qt.AlignCenter,f'{2*i/10/self.frequency*scale:.2f} {unit}')
        for i in range(5):
            y=area.top()+area.height()*i/4;p.setPen(QColor('#243347'));p.drawLine(QPointF(area.left(),y),QPointF(area.right(),y));p.setPen(QColor('#8da9c4'));p.drawText(QRectF(2,y-11,55,22),Qt.AlignRight,f'{(hi-(hi-lo)*i/4)/16383*100:.1f}%')
        p.setPen(QColor('#dbe8f5'));p.drawText(15,24,'满量程 %FS');p.drawText(170,24,'已确认的数字表 / 非模拟实测' if self.ack else '待发送预览 / 非模拟实测')
        if self.data is not None:
            values=np.tile(self.data,2);path=QPainterPath()
            for i,v in enumerate(values):
                point=QPointF(area.left()+i*area.width()/(len(values)-1),area.bottom()-(float(v)-lo)/(hi-lo)*area.height())
                if i==0:path.moveTo(point)
                else:path.lineTo(point)
            p.setPen(QPen(QColor('#52dac3' if self.ack else '#f6c879'),1.5));p.drawPath(path)

class Window(QMainWindow):
    def __init__(self, offline=False):
        super().__init__();self.setWindowTitle('Z7 LAB · 示波器与信号发生器');self.resize(1330,910)
        self.worker=SerialWorker();self.offline=offline;self.online=False;self.csv_values=None;self.current_table=None;self.confirmed_table=None
        self.worker.response.connect(self.received);self.worker.failed.connect(self.error);self.worker.connected.connect(self.connection);self.worker.progress.connect(lambda v:self.progress.setValue(v));self.worker.applied.connect(self.applied)
        base=QWidget();self.setCentralWidget(base);root=QVBoxLayout(base);root.setContentsMargins(22,18,22,18);root.setSpacing(12)
        bar=QHBoxLayout();title=QLabel('Z7 LAB');title.setObjectName('brand');bar.addWidget(title);bar.addWidget(QLabel('独立 ADC / DAC'));bar.addStretch()
        bar.addWidget(self.button('HDMI: ADC',lambda:self.send('page adc')));bar.addWidget(self.button('HDMI: DAC',lambda:self.send('page dac')))
        stop_button=self.button('停止 DAC',self.worker.stop_output);stop_button.setStyleSheet('background:#8e3547;border-color:#d26579');bar.addWidget(stop_button)
        self.ports=QComboBox();self.ports.setMinimumWidth(210);self.scan_ports();bar.addWidget(self.ports);bar.addWidget(self.button('刷新串口',self.scan_ports));self.connect_btn=self.button('连接',self.toggle_connection);bar.addWidget(self.connect_btn);root.addLayout(bar)
        self.status=QLabel('离线 · 选择板卡串口后连接。所有电压均需区分标称与校准。');self.status.setObjectName('status');root.addWidget(self.status)
        self.tabs=QTabWidget();root.addWidget(self.tabs,1);self.build_adc();self.build_dac();self.build_diagnostics()
        self.log=QPlainTextEdit();self.log.setReadOnly(True);self.log.setMaximumBlockCount(1500);self.log.setMaximumHeight(120);root.addWidget(self.log)
        self.timer=QTimer(self);self.timer.timeout.connect(self.poll);self.timer.start(1800)
        self.preview()
    def button(self,label,callback):
        b=QPushButton(label);b.clicked.connect(callback);return b
    def spin(self,lo,hi,value,decimals=3,suffix=''):
        s=QDoubleSpinBox();s.setRange(lo,hi);s.setDecimals(decimals);s.setValue(value);s.setSuffix(suffix);s.setKeyboardTracking(False);return s
    def combo(self,items):
        c=QComboBox()
        for label,value in items:c.addItem(label,value)
        return c
    def group(self,title):
        box=QGroupBox(title);form=QFormLayout(box);form.setSpacing(12);return box,form
    def scan_ports(self):
        self.ports.clear()
        for port in list_ports.comports():self.ports.addItem(f'{port.device} · {port.description}',port.device)
        for i in range(self.ports.count()):
            if self.ports.itemData(i)=='COM27':self.ports.setCurrentIndex(i)
    def toggle_connection(self):
        if self.online:self.worker.close_port()
        elif self.ports.currentData():self.worker.connect_port(self.ports.currentData());self.status.setText('正在握手…')
    def connection(self,ok):
        self.online=ok;self.connect_btn.setText('断开连接' if ok else '连接');self.status.setText('已连接 · COM27 / 115200 8N1' if ok else '已断开连接')
    def send(self,text):
        if not self.online:
            self.error('尚未连接板卡；当前仅预览。');return
        self.worker.command(text)
    def build_adc(self):
        tab=QWidget();lay=QHBoxLayout(tab);left=QVBoxLayout();right=QVBoxLayout();lay.addLayout(left);lay.addLayout(right)
        box,f=self.group('ADC 采集与显示');left.addWidget(box)
        self.adc_mode=self.combo([(x,y) for x,y in [('示波器','dso'),('DPX 密度','dpx'),('EYE 眼图','eye'),('FFT 频谱','fft'),('滚动显示','roll'),('长存储','mem'),('分段存储','seg')]])
        self.adc_rate=self.combo([(f'{x} MSa/s',x) for x in [10,25,50,65]])
        self.source=self.combo([('AD9226 实际输入','real'),('SIM 内部测试','sim')]);self.encoding=self.combo([('偏移二进制','offset'),('二进制补码','twos')])
        for label,widget in [('模式',self.adc_mode),('采样率',self.adc_rate),('采样来源',self.source),('数据编码',self.encoding)]:f.addRow(label,widget)
        f.addRow(self.button('应用采集设置',self.adc_apply));f.addRow(self.button('HDMI 切换到 ADC',lambda:self.send('page adc')));f.addRow(self.button('读取板卡参数到控件',self.refresh_controls))
        row=QHBoxLayout();row.addWidget(self.button('RUN',lambda:self.send('run 1')));row.addWidget(self.button('STOP',lambda:self.send('run 0')));row.addWidget(self.button('自动缩放',lambda:self.send('autoscale')));f.addRow(row)
        box,f=self.group('时间、垂直与回放');left.addWidget(box)
        self.span=self.spin(64,16384,4096,0,' 点');self.gain=self.combo([(f'x{2**i}',i) for i in range(7)]);self.zero=self.spin(0,4095,2047.5,2,' code');self.offset=self.spin(0,1048575,0,0);self.segment=self.spin(0,7,0,0)
        for name,w in [('时间视窗',self.span),('垂直增益',self.gain),('屏幕中心电平',self.zero),('长存储起点',self.offset),('分段编号 0～7',self.segment)]:f.addRow(name,w)
        f.addRow(self.button('应用缩放与回放',self.view_apply));self.auto_scale=QCheckBox('连续自动缩放（示波器）');self.auto_scale.toggled.connect(lambda checked:self.send(f'view auto {int(checked)}'));f.addRow(self.auto_scale);left.addStretch()
        box,f=self.group('触发');right.addWidget(box)
        self.trig_type=self.combo([('自动','auto'),('普通','normal'),('单次','single')]);self.edge=self.combo([('上升沿','rise'),('下降沿','fall')]);self.level=self.spin(0,4095,2048,0);self.hyst=self.spin(0,255,8,0)
        for name,w in [('方式',self.trig_type),('边沿',self.edge),('触发电平 code',self.level),('滞回 code',self.hyst)]:f.addRow(name,w)
        f.addRow(self.button('应用触发',self.trigger_apply));f.addRow(self.button('单次重新触发',lambda:self.send('rearm')))
        box,f=self.group('FFT / EYE / 电压换算');right.addWidget(box)
        self.fft_n=self.combo([(str(x),x) for x in [1024,2048,4096]]);self.fft_n.setCurrentIndex(2);self.fft_window=self.combo([('汉宁窗','hann'),('矩形窗','rect')]);self.bitrate=self.spin(1,5,1,3,' Mb/s');self.uv=self.spin(.001,100000,10_000_000/4095,6,' uV/code');self.cal_zero=self.spin(0,4095,2047.5,3)
        for name,w in [('FFT 点数',self.fft_n),('窗函数',self.fft_window),('EYE 码率',self.bitrate),('ADC 校准增益',self.uv),('ADC 零电压码',self.cal_zero)]:f.addRow(name,w)
        f.addRow(self.button('应用 FFT / EYE',self.spectral_apply));f.addRow(self.button('写入实测校准',self.calibrate));f.addRow(QLabel('ADC 标称 ±5V @50Ω；校准按钮仅用于已测得的增益和零点。'))
        self.adc_status=QPlainTextEdit();self.adc_status.setReadOnly(True);self.adc_status.setMinimumHeight(130);right.addWidget(self.adc_status);right.addStretch()
        scroll=QScrollArea();scroll.setWidgetResizable(True);scroll.setWidget(tab);self.tabs.addTab(scroll,'ADC · 示波器')
    def build_dac(self):
        tab=QWidget();lay=QHBoxLayout(tab);control_widget=QWidget();controls=QVBoxLayout(control_widget);scroll=QScrollArea();scroll.setWidgetResizable(True);scroll.setWidget(control_widget);scroll.setMinimumWidth(360);view=QVBoxLayout();lay.addWidget(scroll,1);lay.addLayout(view,2)
        box,f=self.group('DAC904 独立发生器');controls.addWidget(box)
        self.shape=self.combo([('正弦波','sine'),('方波','square'),('三角波','triangle'),('锯齿波','saw'),('直流','dc'),('数学表达式','expression'),('CSV 任意波形','csv')]);self.freq=self.spin(.1,5_000_000,1000,6,' Hz');self.amp=self.spin(0,100,10,3,' %FS p-p');self.dc=self.spin(0,100,50,3,' %FS');self.duty=self.spin(1,99,50,3,' %');self.enabled=QCheckBox('上传成功后开启输出（默认关闭）')
        for name,w in [('波形',self.shape),('重复频率',self.freq),('满幅峰峰值',self.amp),('零值偏置',self.dc),('占空比 / 三角顶点',self.duty)]:f.addRow(name,w)
        f.addRow(self.enabled)
        self.formula=QLineEdit('0.8*sin(2*pi*t)+0.2*sin(6*pi*t)');f.addRow('归一化表达式',self.formula)
        hint=QLabel('t 为单周期 0≤t<1；结果须在 -1～+1\nsin cos abs sqrt exp log where minimum maximum\n例：where(t<0.25,1,-1)');hint.setWordWrap(True);f.addRow(hint)
        f.addRow(self.button('导入 CSV（单列归一化样本）',self.import_csv));f.addRow(self.button('预览待发送波形',self.preview));self.upload_btn=self.button('校验并上传到 DAC',self.upload);self.upload_btn.setObjectName('primary');f.addRow(self.upload_btn)
        row=QHBoxLayout();row.addWidget(self.button('停止 DAC',self.worker.stop_output));row.addWidget(self.button('HDMI → DAC',lambda:self.send('page dac')));f.addRow(row)
        self.progress=QProgressBar();self.progress.setValue(0);f.addRow(self.progress)
        controls.addStretch();self.plot=Plot();view.addWidget(self.plot,1)
        self.preview_auto=QCheckBox('预览自动纵向缩放');self.preview_auto.setChecked(True);self.preview_auto.toggled.connect(lambda checked:(setattr(self.plot,'auto_range',checked),self.plot.update()));view.addWidget(self.preview_auto)
        self.preview_label=QLabel();self.preview_label.setWordWrap(True);view.addWidget(self.preview_label)
        self.dac_status=QPlainTextEdit();self.dac_status.setReadOnly(True);self.dac_status.setMaximumHeight(160);view.addWidget(self.dac_status)
        row=QHBoxLayout();row.addWidget(self.button('导出当前表 CSV',self.export_csv));row.addWidget(self.button('保存配置',self.save_profile));row.addWidget(self.button('加载配置',self.load_profile));view.addLayout(row)
        note=QLabel('DAC 标称满量程 5Vpp；ADC 模块标称 ±5V @50Ω。电压换算是模块标称估计，非实测。\n幅度、偏置联合检查：必须在 DAC 数字量程内。模拟负载、偏置和模块数字电源需另行核实。停止 = 保持中点码值，不是高阻。\n预览表示数字波形表；板卡 CRC 确认后标为“已确认”，不代表已测量模拟输出。');note.setWordWrap(True);view.addWidget(note)
        self.tabs.addTab(tab,'DAC · 信号发生器')
    def build_diagnostics(self):
        tab=QWidget();lay=QVBoxLayout(tab);row=QHBoxLayout()
        for label,cmd in [('刷新全部状态','settings'),('DDR / DMA 自检','selftest'),('长存储采集','memory capture'),('分段校验','segments'),('清除故障','errors clear'),('时钟状态','clocks'),('保存 ADC 配置到 RAM','config save'),('恢复 ADC 配置','config load')]:row.addWidget(self.button(label,lambda checked=False,c=cmd:self.send(c)))
        lay.addLayout(row);self.diagnostics=QPlainTextEdit();self.diagnostics.setReadOnly(True);self.diagnostics.setMaximumBlockCount(5000);lay.addWidget(self.diagnostics)
        row=QHBoxLayout();self.command=QLineEdit();self.command.setPlaceholderText('高级命令，例如 menu toggle / view gain 2');row.addWidget(self.command);row.addWidget(self.button('发送命令',lambda:self.send(self.command.text())));lay.addLayout(row)
        row=QHBoxLayout();row.addWidget(self.button('导出诊断日志',self.export_log));row.addStretch();lay.addLayout(row);self.tabs.addTab(tab,'系统 · 诊断')
        menu_row=QHBoxLayout()
        for label,cmd in [('HDMI 菜单','menu toggle'),('上一项','menu prev'),('下一项','menu next'),('修改选中项','menu edit'),('关闭菜单','menu back')]:menu_row.addWidget(self.button(label,lambda checked=False,c=cmd:self.send(c)))
        lay.addLayout(menu_row)
    def adc_apply(self):
        for c in [f'adc source {self.source.currentData()}',f'adc encoding {self.encoding.currentData()}',f'adc rate {self.adc_rate.currentData()}',f'mode {self.adc_mode.currentData()}','settings']:self.send(c)
    def view_apply(self):
        for key,value in [('span',int(self.span.value())),('gain',self.gain.currentData()),('zero',self.zero.value()),('offset',int(self.offset.value())),('segment',int(self.segment.value()))]:self.send(f'view {key} {value}')
        self.send('settings')
    def trigger_apply(self):
        for c in [f'trig type {self.trig_type.currentData()}',f'trig edge {self.edge.currentData()}',f'trig level {int(self.level.value())}',f'view hyst {int(self.hyst.value())}','settings']:self.send(c)
    def spectral_apply(self):
        for c in [f'fft n {self.fft_n.currentData()}',f'fft window {self.fft_window.currentData()}',f'eye rate {int(self.bitrate.value()*1e6)}','settings']:self.send(c)
    def calibrate(self):self.send(f'cal {self.uv.value():.6f} {self.cal_zero.value():.3f}')
    def preview(self):
        try:
            self.current_table=make_table(self.shape.currentData(),self.amp.value()/100,self.dc.value()/100,self.duty.value()/100,self.formula.text(),self.csv_values)
            f=actual_frequency(self.freq.value());self.plot.set_data(self.current_table,f)
            actual_pp=(int(self.current_table.max())-int(self.current_table.min()))/16383
            self.preview_label.setText(f'待发送：2048 点 · 实际 DDS 频率 {f:.9f} Hz · 数字表峰峰值 {actual_pp*100:.3f}% · 标称估计 {actual_pp*5:.3f} Vpp · 码值 {self.current_table.min()}～{self.current_table.max()}')
            return True
        except Exception as exc:self.error(str(exc));return False
    def upload(self):
        if not self.online:self.error('请先连接串口');return
        if self.preview():self.progress.setValue(0);self.worker.upload(self.current_table,self.freq.value(),self.enabled.isChecked())
    def applied(self,payload):
        table=payload["table"];frequency=payload["frequency"]
        self.confirmed_table=table;self.plot.set_data(table,actual_frequency(frequency),True);self.preview_label.setText('板卡已确认波形 CRC，数字表已提交。模拟输出仍需实际测量。')
    def import_csv(self):
        path,_=QFileDialog.getOpenFileName(self,'导入归一化样本','','CSV (*.csv *.txt)')
        if path:
            try:
                self.csv_values=np.loadtxt(path,delimiter=',',max_rows=1_000_001);self.shape.setCurrentIndex(self.shape.findData('csv'));self.preview()
            except Exception as exc:self.error(str(exc))
    def export_csv(self):
        path,_=QFileDialog.getSaveFileName(self,'导出待发送数字表','waveform.csv','CSV (*.csv)')
        if path and self.preview():np.savetxt(path,self.current_table,fmt='%d',header='DAC code, not measured voltage')
    def profile(self):return dict(shape=self.shape.currentData(),frequency=self.freq.value(),amplitude=self.amp.value(),offset=self.dc.value(),duty=self.duty.value(),formula=self.formula.text(),csv=None if self.csv_values is None else self.csv_values.tolist())
    def save_profile(self):
        path,_=QFileDialog.getSaveFileName(self,'保存 DAC 配置','dac_profile.json','JSON (*.json)')
        if path:Path(path).write_text(json.dumps(self.profile(),ensure_ascii=False,indent=2),encoding='utf-8')
    def load_profile(self):
        path,_=QFileDialog.getOpenFileName(self,'加载 DAC 配置','','JSON (*.json)')
        if path:
            try:
                d=json.loads(Path(path).read_text(encoding='utf-8'));i=self.shape.findData(d['shape'])
                if i<0:raise ValueError('未知波形')
                self.shape.setCurrentIndex(i)
                for w,k in [(self.freq,'frequency'),(self.amp,'amplitude'),(self.dc,'offset'),(self.duty,'duty')]:w.setValue(float(d[k]))
                self.formula.setText(d['formula']);self.csv_values=None if d.get('csv') is None else np.asarray(d['csv'],dtype=float);self.enabled.setChecked(False);self.preview()
            except Exception as exc:self.error(str(exc))
    def export_log(self):
        path,_=QFileDialog.getSaveFileName(self,'保存日志','Z7_diagnostics.txt','Text (*.txt)')
        if path:Path(path).write_text(self.diagnostics.toPlainText(),encoding='utf-8')
    def poll(self):
        if self.online and self.worker.jobs.empty():
            for c in ['settings','measure','status','dac status']:self.worker.command(c)
    def refresh_controls(self):
        self.refresh_pending=True;self.send('settings')
    def sync_controls(self,values):
        for key,widget in [('mode',self.adc_mode),('source',self.source),('rate',self.adc_rate),('gain',self.gain),('fft_n',self.fft_n)]:
            if key in values:
                value=values[key].lower() if key in ('mode','source') else int(values[key])
                if value=='adc':value='real'
                idx=widget.findData(value)
                if idx>=0:widget.setCurrentIndex(idx)
        for key,widget in [('span',self.span),('zero',self.zero),('offset',self.offset),('segment',self.segment),('level',self.level),('hyst',self.hyst),('uv_per_code',self.uv),('cal_zero',self.cal_zero)]:
            if key in values:widget.setValue(float(values[key]))
        if 'encoding' in values:self.encoding.setCurrentIndex(int(values['encoding']))
        if 'auto_scale' in values:
            self.auto_scale.blockSignals(True);self.auto_scale.setChecked(bool(int(values['auto_scale'])));self.auto_scale.blockSignals(False)
        if 'trig' in values:self.trig_type.setCurrentIndex(int(values['trig']))
        if 'edge' in values:self.edge.setCurrentIndex(int(values['edge']))
        if 'hann' in values:self.fft_window.setCurrentIndex(0 if int(values['hann']) else 1)
        if 'bitrate' in values:self.bitrate.setValue(float(values['bitrate'])/1e6)
    def received(self,cmd,line):
        self.log.appendPlainText(f'→ {cmd[:70]}\n← {line}');self.diagnostics.appendPlainText(f'{cmd}\n{line}\n')
        values=dict(re.findall(r'(\w+)=([^ ]+)',line))
        if cmd=='settings' and getattr(self,'refresh_pending',False):self.sync_controls(values);self.refresh_pending=False
        labels={'mode':'模式','run':'运行','source':'来源','rate':'采样率','span':'视窗点数','gain':'增益级别','zero':'中心码值','level':'触发电平','hyst':'触发滞回','fft_n':'FFT 点数','bitrate':'EYE 码率','dac_enabled':'DAC 输出','shape':'波形','fs':'DAC 更新率','actual_hz':'实际设定 Hz','amplitude_fs':'峰峰值 FS','offset_fs':'偏置 FS','duty':'占空比','table_crc':'波形 CRC','cycles':'DAC 时钟计数','frequency':'频率 Hz','frequency_valid':'频率有效','min':'最小码值','max':'最大码值','mean':'平均码值','calibrated':'已实测校准'}
        readable='  |  '.join(f'{labels[k]}: {v}' for k,v in values.items() if k in labels)
        if cmd=='dac status':self.dac_status.setPlainText(readable)
        elif cmd in ['settings','measure','status']:self.adc_status.setPlainText(self.adc_status.toPlainText()[-1400:]+'\n'+readable)
        if cmd=='dac status':
            running='运行' if values.get('dac_enabled')=='1' else '保持中点'
            self.status.setText(f"已连接 · HDMI {values.get('page','ADC')} · DAC {running} · 设定频率 {values.get('actual_hz','?')} Hz")
        elif cmd=='status':
            names={'DSO':'示波器','DPX':'DPX 密度','EYE':'EYE 眼图','FFT':'FFT 频谱','ROLL':'滚动','MEM':'长存储','SEG':'分段'}
            source='SIM 测试源' if values.get('source')=='SIM' else 'ADC 实际输入'
            self.status.setText(f"已连接 · {source} · {names.get(values.get('mode'),values.get('mode',''))} · {'RUN' if values.get('run')=='1' else 'STOP'} · {float(values.get('rate',0))/1e6:g} MSa/s · 故障 {values.get('errors','0')}")
        elif cmd.startswith('dac chunk '):self.status.setText(f"正在上传波形 · {values.get('dac_uploaded','?')} / 2048 点")
        elif cmd.startswith('dac commit '):self.status.setText('波形表已校验并提交，正在读取板卡状态')
    def error(self,message):
        self.log.appendPlainText('错误：'+message);self.status.setText('错误：'+message)
    def closeEvent(self,event):self.timer.stop();self.worker.shutdown();event.accept()

STYLE='''QWidget{background:#101a29;color:#d9e7f5;font-family:"Microsoft YaHei UI";font-size:12px} QGroupBox{border:1px solid #30435b;border-radius:10px;margin-top:14px;padding:16px 12px 10px} QGroupBox::title{subcontrol-origin:margin;left:16px;color:#71d8cc} QPushButton{background:#24394e;border:1px solid #3a5670;border-radius:6px;padding:8px 12px} QPushButton:hover{background:#355371} QPushButton#primary{background:#18796d;border-color:#45cdb7} QLineEdit,QComboBox,QSpinBox,QDoubleSpinBox,QPlainTextEdit{background:#0b1421;border:1px solid #30445a;border-radius:5px;padding:6px;selection-background-color:#28776d} QTabBar::tab{background:#18283b;padding:13px 28px;border-bottom:3px solid #18283b} QTabBar::tab:selected{background:#20394b;border-bottom-color:#57d2bd} QLabel#brand{font-size:28px;font-weight:700;color:#67dbc8} QLabel#status{background:#182c3c;padding:10px;border-radius:7px;color:#a4c9de} QProgressBar{border:1px solid #30445a;border-radius:4px;text-align:center} QProgressBar::chunk{background:#239381}'''
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--snapshot');args=parser.parse_args()
    app=QApplication(sys.argv[:1])
    for name in ['msyh.ttc','consola.ttf']:
        font_path=Path('C:/Windows/Fonts')/name
        if font_path.exists():QFontDatabase.addApplicationFont(str(font_path))
    app.setFont(QFont('Microsoft YaHei',10));app.setStyle('Fusion');app.setStyleSheet(STYLE.replace('Microsoft YaHei UI','Microsoft YaHei'));window=Window(bool(args.snapshot));window.show()
    if args.snapshot:
        def snap():window.tabs.setCurrentIndex(1);app.processEvents();window.grab().save(args.snapshot);window.close();app.quit()
        QTimer.singleShot(500,snap)
    return app.exec()
if __name__=='__main__':sys.exit(main())
