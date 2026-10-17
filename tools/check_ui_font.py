from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
s=(r/'sw/src/main.c').read_text(encoding='utf-8-sig')
header=(r/'sw/include/scope_ui_font.h').read_text()
codes=set(map(int,re.search(r'unicode_map\[\]=\{([^}]+)',header)[1].split(',')))
missing=set(ord(c) for c in s if ord(c)>127)-codes
assert not missing,missing
planes=[(r/f'hw/rtl/font_{p}.mem').read_text().splitlines() for p in ['hi','mid','lo']]
assert all(len(rows)==(96+len(codes))*24 for rows in planes)
assert all(0<=int(x,16)<=65535 for rows in planes for x in rows)
packed=[(int(h,16)<<32)|(int(m,16)<<16)|int(l,16) for h,m,l in zip(*planes)]
assert set((v>>bit)&3 for v in packed for bit in range(0,48,2))=={0,1,2,3}
assert len((r/'hw/rtl/screen.mem').read_text().splitlines())==16384
print('PASS native UI font coverage, mapping, ROM length and 4-level antialiasing',len(codes),'CJK/symbols')
