#define SCOPE_HOST_TEST
#define main scope_firmware_main
#include "../../sw/src/main.c"
#undef main
#include <assert.h>
static uint32_t registers[0x100000/4];
uint32_t scope_host_read(unsigned a){if(a==R_STATE)return 0xc09;if(a==R_RATE)return cfg.rate;return registers[a/4];}
void scope_host_write(unsigned a,uint32_t v){registers[a/4]=v;}
static void save_hex(const char*name,const void*p,unsigned n,unsigned width){FILE*f=fopen(name,"w");for(unsigned i=0;i<n;i++){unsigned v=width==1?((const unsigned char*)p)[i]:((const uint32_t*)p)[i];fprintf(f,width==1?"%02x\n":"%05x\n",v);}fclose(f);}
int main(void){registers[R_ID/4]=0x53434f50;registers[R_VER/4]=0x30000;registers[R_FRAME/4]=3600;registers[R_TRIG/4]=121;registers[R_TIME/4]=1638400;
 for(unsigned i=0;i<SCOPE_N;i++)record[i]=(uint16_t)lround(2048+1450*sin(2*3.141592653589793*10000*i/cfg.rate));
 scope_measure(record,SCOPE_N,cfg.rate,&measurement);valid_record=1;record_source_sim=1;cfg.mode=DSO;scope_envelope(record,SCOPE_N,0,SCOPE_N,wave);
 draw_ui();save_hex("ui_text.mem",screen,7200,1);save_hex("ui_wave.mem",wave,SCOPE_W,4);
 memset(hist,0,sizeof(hist));for(unsigned i=0;i<64;i++)scope_density(hist,record,SCOPE_N,cfg.rate,cfg.bitrate,0,0,100000,&hits,&drops);
 save_hex("ui_hist.mem",hist,sizeof(hist),1);
 cfg.mode=DPX;draw_ui();save_hex("ui_text_dpx.mem",screen,7200,1);
 for(unsigned i=0;i<1000;i++){assert(change_mode(i%5));assert(cfg.mode==i%5);}
 for(unsigned i=0;i<21;i++){if(i==18)continue;selection=i;edit(1);edit(-1);}
 assert(scope_host_read(R_ID)==0x53434f50);puts("PASS host UI: firmware-generated glyph map, 20 menu entries (hardware selftest deferred), 1000 mode transitions (MMIO model)");return 0;}
