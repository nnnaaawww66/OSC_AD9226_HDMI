"""Build a native 24x24, four-coverage-level font for 1080p30.
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
scale=4
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24*scale)
ascii_font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',24*scale)
rows=[]
for index in range(32,len(characters)+128):
    char=chr(index) if index<128 else characters[index-128]
    chosen=ascii_font if index<128 else font
    im=Image.new('L',(24*scale,24*scale))
    # Render native-size outlines supersampled, then coverage-filter once.
    # No binary threshold or nearest-neighbor enlargement.
    if index<128:
        advance=round(chosen.getlength('0'))
        temp=Image.new('L',(advance,24*scale))
        ImageDraw.Draw(temp).text((0,scale),char,font=chosen,fill=255)
        im=Image.new('L',(24,24));im.paste(temp.resize((12,24),Image.Resampling.LANCZOS),(0,0))
    else:
        ImageDraw.Draw(im).text((0,-5*scale),char,font=chosen,fill=255)
        im=im.resize((24,24),Image.Resampling.LANCZOS)
    for y in range(24):rows.append(sum(min(3,(im.getpixel((x,y))*3+127)//255)<<(2*(23-x)) for x in range(24)))
for plane,shift in [('hi',32),('mid',16),('lo',0)]:
    (r/f'hw/rtl/font_{plane}.mem').write_text(''.join(f'{(v>>shift)&65535:04x}\n' for v in rows))
assert len(rows)<=8192,'Font ROM budget exceeded'
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
screen=[32]*16384
for y,line in enumerate(boot):
    x=0
    for c in line:
        code=ord(c) if ord(c)<128 else mapping[c]
        screen[y*160+x]=code;x+=1
        if ord(c)>=128:screen[y*160+x]=code|512;x+=1
(r/'hw/rtl/screen.mem').write_text(''.join(f'{v:04x}\n' for v in screen))
p=r/'hw/rtl/scope_display.v';s=p.read_text();s=re.sub(r'(font_(?:hi|mid|lo))\[0 : \d+\]',lambda m:f'{m[1]}[0 : {len(rows)-1}]',s);p.write_text(s)
print(f'FONT_PASS {len(characters)} CJK/symbol glyphs +96 printable ASCII, {len(rows)} rows x48bit, 4 coverage levels')
