from pathlib import Path
import re,zlib,hashlib,json,datetime
r=Path(__file__).resolve().parents[1]
p=r/'backup/qspi_before_dac_20261017'
fields=dict(re.findall(r'(\w+)=([0-9a-f]+)',(p/'chip_and_crc.txt').read_text()))
data=(p/'qspi_16MiB.bin').read_bytes()
assert len(data)==16777216
crc=zlib.crc32(data)
assert crc==int(fields['crc32'],16),'JTAG binary backup differs from the device-side CRC'
assert fields['jedec']=='ef4018',fields
manifest=dict(sha256=hashlib.sha256(data).hexdigest(),crc32=f'{crc:08x}',jedec=fields['jedec'],bytes=len(data),read_only=True,created=datetime.datetime.now().astimezone().isoformat())
(p/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('QSPI_BACKUP_SEALED',manifest)
