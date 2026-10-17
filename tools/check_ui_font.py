from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
s=(r/'sw/src/main.c').read_text(encoding='utf-8-sig')
header=(r/'sw/include/scope_ui_font.h').read_text()
codes=set(map(int,re.search(r'unicode_map\[\]=\{([^}]+)',header)[1].split(',')))
missing=set(ord(c) for c in s if ord(c)>127)-codes
assert not missing,missing
rows=(r/'hw/rtl/font.mem').read_text().splitlines()
assert len(rows)==(128+len(codes))*24
assert all(0<=int(x,16)<=65535 for x in rows)
print('PASS native UI font coverage, mapping and ROM length',len(codes),'CJK/symbols')
