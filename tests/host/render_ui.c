#define SCOPE_HOST_TEST
#define main scope_firmware_main
#include "../../sw/src/main.c"
#undef main
#include <assert.h>
static uint32_t registers[0x100000/4];
static unsigned physical_rate=10000000;
uint32_t scope_host_read(unsigned a){if(a==R_STATE)return 0xc09;if(a==R_RATE)return physical_rate;return registers[a/4];}
void scope_host_write(unsigned a,uint32_t v){registers[a/4]=v;if(a==R_RATE){static const unsigned rates[]={10000000,25000000,50000000,65000000};assert(v<4);physical_rate=rates[v];}}
static void save_hex(const char*name,const void*p,unsigned n,unsigned width){FILE*f=fopen(name,"w");assert(f);for(unsigned i=0;i<n;i++){unsigned v=width==1?((const uint8_t*)p)[i]:width==2?((const uint16_t*)p)[i]:((const uint32_t*)p)[i];fprintf(f,width==1?"%02x\n":width==2?"%04x\n":"%05x\n",v);}fclose(f);}
int main(void){
 debug_init();assert(DEBUG_MAILBOX->magic==SCOPE_DEBUG_MAGIC);
 strcpy((char*)DEBUG_MAILBOX->command,"ver");DEBUG_MAILBOX->request=1;poll_debug();
 assert(DEBUG_MAILBOX->done==1&&DEBUG_MAILBOX->flags==0);
 assert(strstr((const char*)DEBUG_MAILBOX->response,"product=Z7_SCOPE"));
 strcpy((char*)DEBUG_MAILBOX->command,"menu toggle");DEBUG_MAILBOX->request=2;poll_debug();
 assert(menu==1);poll_debug();assert(menu==1);menu=0;
registers[R_ID/4]=0x53434f50;registers[R_VER/4]=0x30000;registers[R_FRAME/4]=3600;registers[R_TRIG/4]=121;registers[R_TIME/4]=1638400;
 for(unsigned i=0;i<SCOPE_N;i++)record[i]=(uint16_t)lround(2048+1450*sin(2*3.141592653589793*10000*i/cfg.rate));
 scope_measure(record,SCOPE_N,cfg.rate,&measurement);valid_record=1;record_source_sim=1;cfg.mode=DSO;scope_envelope(record,SCOPE_N,(SCOPE_N-cfg.span)/2,cfg.span,wave);
 draw_ui();save_hex("ui_text.mem",screen,2400,2);save_hex("ui_wave.mem",wave,SCOPE_W,4);
 memset(hist,0,sizeof(hist));for(unsigned i=0;i<64;i++)scope_density(hist,record,SCOPE_N,cfg.rate,cfg.bitrate,0,0,100000,&hits,&drops);
 save_hex("ui_hist.mem",hist,sizeof(hist),1);
 cfg.mode=DPX;draw_ui();save_hex("ui_text_dpx.mem",screen,2400,2);
 for(unsigned n=1024;n<=4096;n*=2){
  cfg.mode=FFT;cfg.fft_n=n;draw_ui();assert(screen[27*80+1]=='F');
  fft_wave();for(unsigned x=0;x<SCOPE_W;x++){assert((wave[x]&1023)>=70);assert((wave[x]>>10)<=609);assert((wave[x]&1023)<=(wave[x]>>10));}
 }
 for(unsigned i=0;i<1000;i++){assert(change_mode(i%5));assert(cfg.mode==i%5);}
 for(unsigned i=0;i<21;i++){if(i==18)continue;selection=i;edit(1);edit(-1);}
 assert(change_rate(1));assert(cfg.rate==25000000&&physical_rate==25000000);cfg.mode=DSO;
 char save_command[]="config save";dispatch(save_command);
 assert(change_rate(3));assert(cfg.rate==65000000&&physical_rate==65000000);
 char load_command[]="config load";dispatch(load_command);
 assert(cfg.rate==25000000&&physical_rate==25000000&&mem_gate==0);
 for(unsigned i=0;i<DAC_N;i++)dac_table[i]=(uint16_t)(8192+4000*sin(6.28318530718*i/DAC_N));
 dac_on=1;page_dac=1;draw_ui();save_hex("ui_text_dac.mem",screen,2400,2);for(unsigned i=0;i<SCOPE_W;i++)wave[i]=dac_preview(i);save_hex("ui_wave_dac.mem",wave,SCOPE_W,4);
 page_dac=0;cfg.mode=DSO;assert(scope_host_read(R_ID)==0x53434f50);puts("PASS host UI: firmware-generated glyph map, 20 menu entries (hardware selftest deferred), 1000 mode transitions (MMIO model)");return 0;}
