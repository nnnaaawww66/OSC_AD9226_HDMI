"""Build the native 16x24 ASCII/CJK atlas from the firmware's UTF-8 source.
Requires Pillow and the Windows Microsoft YaHei + Consolas fonts.
Generated atlas and mapping are checked in; no font dependency at runtime.
"""
from pathlib import Path
import re
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[1]
boot=['Z7 LAB / BOOT','PS 等待启动程序','ADC 实际输入 / DAC 默认保持中点','请加载完整 BOOT.BIN 或使用 program.ps1']
source=(r/'sw/src/main.c').read_text(encoding='utf-8-sig')
characters=sorted(set(c for c in source+''.join(boot) if ord(c)>127))
assert len(characters)+128<=512
mapping={c:i+128 for i,c in enumerate(characters)}
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
ascii_font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',19)
rows=[]
for index in range(len(characters)+128):
    char=chr(index) if index<128 else characters[index-128]
    im=Image.new('1',(16,24))
    if index>=32:
        temp=Image.new('1',(24,24));ImageDraw.Draw(temp).text((0,-2),char,font=ascii_font if index<128 else font,fill=1)
        if index>=128:temp=temp.crop((0,0,18,24)).resize((16,24),Image.Resampling.NEAREST)
        im.paste(temp,(0,0))
    for y in range(24):rows.append(sum(1<<(15-x) for x in range(16) if im.getpixel((x,y))))
(r/'hw/rtl/font.mem').write_text(''.join(f'{v:04x}\n' for v in rows))
header='''#ifndef SCOPE_UI_FONT_H
#define SCOPE_UI_FONT_H
static unsigned ui_glyph(unsigned code){
 if(code<128)return code;
 static const unsigned short unicode_map[]={'''+','.join(str(ord(c)) for c in characters)+'''};
 for(unsigned i=0;i<sizeof(unicode_map)/sizeof(*unicode_map);i++)if(unicode_map[i]==code)return i+128;
 return '?';
}
#endif
'''
(r/'sw/include/scope_ui_font.h').write_text(header)
screen=[32]*8192
for y,line in enumerate(boot):
    for x,c in enumerate(line):screen[y*80+x]=ord(c) if ord(c)<128 else mapping[c]
(r/'hw/rtl/screen.mem').write_text(''.join(f'{v:04x}\n' for v in screen))
p=r/'hw/rtl/scope_display.v';s=p.read_text();s=re.sub(r'font\[0 : \d+\]',f'font[0 : {len(rows)-1}]',s);p.write_text(s)
print(f'FONT_PASS {len(characters)} CJK/symbol glyphs +128 ASCII, {len(rows)} 16-bit rows')
