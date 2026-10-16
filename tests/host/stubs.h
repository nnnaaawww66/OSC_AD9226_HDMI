#ifndef HOST_STUBS_H
#define HOST_STUBS_H
#define _WIN32_WINNT 0x0600
#include <stdint.h>
#include <windows.h>
typedef uintptr_t UINTPTR;typedef uint64_t XTime;typedef void(*Xil_ExceptionHandler)(void*);
typedef struct{unsigned CpuBaseAddress;}XScuGic_Config;typedef struct{unsigned dummy;}XScuGic;
#define COUNTS_PER_SECOND 1000000
#define XPAR_SCUGIC_SINGLE_DEVICE_ID 0
#define XPAR_XUARTPS_0_BASEADDR 0
#define XST_SUCCESS 0
#define XIL_EXCEPTION_ID_INT 0
#define XUARTPS_FIFO_OFFSET 0
static inline void XTime_GetTime(XTime*t){*t=GetTickCount64()*1000;}
static inline void Xil_DCacheFlushRange(UINTPTR p,unsigned n){(void)p;(void)n;}
static inline void Xil_DCacheInvalidateRange(UINTPTR p,unsigned n){(void)p;(void)n;}
static inline void Xil_ICacheEnable(void){}static inline void Xil_DCacheEnable(void){}
static inline XScuGic_Config*XScuGic_LookupConfig(unsigned n){static XScuGic_Config c;(void)n;return &c;}
static inline int XScuGic_CfgInitialize(XScuGic*a,XScuGic_Config*b,unsigned c){(void)a;(void)b;(void)c;return 0;}
static inline void Xil_ExceptionInit(void){}static inline void Xil_ExceptionEnable(void){}
static inline void Xil_ExceptionRegisterHandler(unsigned n,Xil_ExceptionHandler h,void*p){(void)n;(void)h;(void)p;}
static inline void XScuGic_InterruptHandler(void*p){(void)p;}
static inline void XScuGic_SetPriorityTriggerType(XScuGic*p,unsigned a,unsigned b,unsigned c){(void)p;(void)a;(void)b;(void)c;}
static inline void XScuGic_Connect(XScuGic*p,unsigned n,void(*h)(void*),void*d){(void)p;(void)n;(void)h;(void)d;}
static inline void XScuGic_Enable(XScuGic*p,unsigned n){(void)p;(void)n;}
static inline int XUartPs_IsReceiveData(unsigned a){(void)a;return 0;}
static inline unsigned XUartPs_ReadReg(unsigned a,unsigned b){(void)a;(void)b;return 0;}
static inline void usleep(unsigned a){Sleep(a/1000);}
#endif
