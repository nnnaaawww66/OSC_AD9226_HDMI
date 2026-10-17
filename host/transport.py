"""Single-owner serial transport with per-command ACK and bounded timeouts."""
import queue, threading, time, re, zlib
import serial
from PySide6.QtCore import QObject, Signal

class SerialWorker(QObject):
    response = Signal(str, str)
    failed = Signal(str)
    connected = Signal(bool)
    progress = Signal(int)
    applied = Signal(object)
    def __init__(self):
        super().__init__(); self.jobs=queue.Queue();self.stop_event=threading.Event();self.cancel_upload=threading.Event();self.port=None;self.request_id=0
        self.thread=threading.Thread(target=self.run, daemon=True);self.thread.start()
    def connect_port(self, port): self.jobs.put(("open",port))
    def close_port(self): self.jobs.put(("close",None))
    def command(self, text): self.jobs.put(("command",text))
    def upload(self, table, frequency, enabled): self.cancel_upload.clear();self.jobs.put(("upload",(table.copy(),frequency,enabled)))
    def stop_output(self): self.cancel_upload.set();self.command('dac enable 0')
    def ask(self, command, timeout=6):
        if not self.port: raise RuntimeError("尚未连接板卡")
        self.request_id=(self.request_id+1)&0xffffffff
        request_id=self.request_id
        self.port.write((f"@{request_id:08x} "+command+"\n").encode("ascii"));self.port.flush()
        deadline=time.monotonic()+timeout
        lines=[]
        while time.monotonic()<deadline:
            line=self.port.readline().decode("ascii",errors="replace").strip()
            if line:
                lines.append(line)
                if re.match(r"^(OK|ERR) seq=\d+ ",line) and f"rid={request_id:08x} " in line:
                    if line.startswith("ERR"): raise RuntimeError(line)
                    self.response.emit(command,line);return line
        raise TimeoutError(f"等待板卡确认超时：{command[:50]}")
    def run(self):
        while not self.stop_event.is_set():
            try: kind,payload=self.jobs.get(timeout=.2)
            except queue.Empty: continue
            try:
                if kind=="close":
                    if self.port:self.port.close();self.port=None
                    self.connected.emit(False)
                elif kind=="open":
                    if self.port:self.port.close()
                    self.port=serial.Serial(payload,115200,timeout=.15,write_timeout=2)
                    self.port.reset_input_buffer()
                    line=self.ask("ver")
                    if "product=Z7_SCOPE" not in line: raise RuntimeError("串口设备不是 Z7 Scope")
                    self.connected.emit(True);self.ask("settings");self.ask("dac status")
                elif kind=="command": self.ask(payload,60 if payload in ("selftest","memory test","memory capture","memory bandwidth") else 6)
                elif kind=="upload":
                    table,freq,on=payload
                    self.ask("dac begin")
                    for i in range(0,len(table),24):
                        if self.cancel_upload.is_set():raise RuntimeError('上传已取消；正在请求 DAC 保持中点')
                        self.ask(f"dac chunk {i} "+"".join(f"{int(v):04x}" for v in table[i:i+24]))
                        self.progress.emit(min(99,int(100*(i+24)/len(table))))
                    crc=zlib.crc32(table.astype("<u2").tobytes())
                    result=self.ask(f"dac commit {crc:08x} {freq:.9f} {int(on)}")
                    if f"crc={crc:08x}" not in result:raise RuntimeError("板卡返回的波形 CRC 不匹配")
                    self.progress.emit(100);self.applied.emit(dict(table=table.copy(),frequency=freq));self.ask("dac status")
            except Exception as exc:
                self.failed.emit(str(exc))
                if kind=="open" or isinstance(exc,serial.SerialException):
                    if self.port:self.port.close();self.port=None
                    self.connected.emit(False)
            finally: self.jobs.task_done()
    def shutdown(self):
        self.stop_event.set();self.thread.join(timeout=3)
        if self.port:self.port.close();self.port=None
