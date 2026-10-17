/* Read-only QSPI backup helper. No erase/program commands exist in this file. */
#include "xparameters.h"
#include "xqspips.h"
#include "xil_cache.h"
#include <stdint.h>
#include <string.h>
static XQspiPs qspi;
static uint8_t tx[4101],rx[4101];
#define REPORT ((volatile uint32_t*)0x2f000)
#define DEST ((uint8_t*)0x11000000)
int main(void){
 Xil_DCacheDisable();
 REPORT[0]=0x51535049;REPORT[1]=1;REPORT[2]=0;REPORT[3]=0;
 XQspiPs_Config *c=XQspiPs_LookupConfig(XPAR_XQSPIPS_0_DEVICE_ID);
 if(!c || XQspiPs_CfgInitialize(&qspi,c,c->BaseAddress)!=XST_SUCCESS){REPORT[1]=0xe001;return 1;}
 XQspiPs_SetOptions(&qspi,XQSPIPS_MANUAL_START_OPTION|XQSPIPS_FORCE_SSELECT_OPTION|XQSPIPS_HOLD_B_DRIVE_OPTION);
 XQspiPs_SetClkPrescaler(&qspi,XQSPIPS_CLK_PRESCALE_8);
 XQspiPs_SetSlaveSelect(&qspi);
 tx[0]=0x9f;
 if(XQspiPs_PolledTransfer(&qspi,tx,rx,4)!=XST_SUCCESS){REPORT[1]=0xe002;return 1;}
 REPORT[2]=((uint32_t)rx[1]<<16)|((uint32_t)rx[2]<<8)|rx[3];
 // Winbond manufacturer, 128Mbit density. Reject unknown chip geometry.
 if(rx[1]!=0xef || rx[3]!=0x18){REPORT[1]=0xe003;return 1;}
 for(uint32_t at=0;at<0x1000000;at+=4096){
  memset(tx,0,sizeof tx);tx[0]=0x0b;tx[1]=at>>16;tx[2]=at>>8;tx[3]=at;
  if(XQspiPs_PolledTransfer(&qspi,tx,rx,sizeof tx)!=XST_SUCCESS){REPORT[1]=0xe004;return 1;}
  memcpy(DEST+at,rx+5,4096);REPORT[3]=at+4096;
 }
 uint32_t crc=0xffffffff;
 for(unsigned i=0;i<0x1000000;i++){crc^=DEST[i];for(unsigned b=0;b<8;b++)crc=(crc>>1)^((crc&1)?0xedb88320:0);}
 REPORT[4]=~crc;REPORT[1]=2;
 for(;;){}
}
