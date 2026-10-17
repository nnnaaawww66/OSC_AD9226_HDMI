#define SCOPE_HOST_TEST
#define main scope_firmware_main
#include "../../sw/src/main.c"
#undef main
#include <assert.h>
static uint32_t registers[0x100000/4];
static unsigned commits,readback_fault;
uint32_t scope_host_read(unsigned a){
 if(a==R_STATE)return 0xc09;
 if(a==R_RATE)return cfg.rate;
 if(a==0x108)return 0;
 if(readback_fault && a==0x30004)return registers[a/4]^1;
 return registers[a/4];
}
void scope_host_write(unsigned a,uint32_t v){
 if(a==0x108){commits++;return;}
 registers[a/4]=v;
}
static void command_line(const char *s){char b[160];snprintf(b,sizeof b,"%s",s);dispatch(b);}
int main(void){
 settings before=cfg;
 assert(dac_generate(0,1234,.2,.5,.5,0));
 assert(memcmp(&cfg,&before,sizeof cfg)==0);
 assert(commits==1 && dac_on==0);
 assert(dac_table[512]>9800 && dac_table[1536]<6600);
 uint32_t crc=dac_crc;double f=dac_frequency;
 command_line("page dac");assert(page_dac && !memcmp(&cfg,&before,sizeof cfg));
 command_line("view gain 3");assert(cfg.gain==3 && dac_crc==crc && dac_frequency==f);
 command_line("mode fft");assert(cfg.mode==FFT && dac_crc==crc && commits==1);
 command_line("dac set square 5000 1 0.9 0.25 1");assert(commits==1);
 command_line("dac set square 5000 0.8 0.5 0.25 1");assert(commits==2 && dac_on && dac_shape==1);
 unsigned high=0;for(unsigned i=0;i<DAC_N;i++)if(dac_table[i]>10000)high++;
 assert(high==512);
 command_line("dac begin");command_line("dac chunk 0 20002000zzzz");assert(dac_uploaded==0);
 command_line("dac chunk 1 2000");assert(dac_uploaded==0);
 command_line("dac commit 00000000 1000 1");assert(commits==2);
 command_line("dac begin");
 for(unsigned i=0;i<DAC_N;i+=24){char b[160],*p=b;p+=sprintf(p,"dac chunk %u ",i);for(unsigned j=0;j<24&&i+j<DAC_N;j++)p+=sprintf(p,"%04x",(i+j)*8);command_line(b);}
 assert(dac_uploaded==DAC_N);
 char cmd[160];snprintf(cmd,sizeof cmd,"dac commit %08lx 1000 1",(unsigned long)scope_crc32(dac_staging,sizeof dac_staging));command_line(cmd);
 assert(commits==3 && dac_shape==5 && dac_table[2047]==16376);
 readback_fault=1;assert(!dac_generate(0,1000,.5,.5,.5,1));assert(commits==3);readback_fault=0;
 assert(!dac_generate(0,NAN,.5,.5,.5,1));
 puts("PASS independent firmware: ADC/DAC configuration isolation, argument rejection, transactional uploads, CRC, readback failure prevents commit");
 return 0;
}
