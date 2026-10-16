/* OCM-only recovery console. It does not touch DDR, DMA or QSPI. */
#include "xparameters.h"
#include "xil_printf.h"
#include "xuartps_hw.h"
#include <stdint.h>
#define REG(a) (*(volatile unsigned *)(0x40000000u + (a)))
int main(void) {
    unsigned cfg = 0x00880003, key = 0;
    xil_printf("\r\nZ7_SCOPE OCM_DIAG DDR_UNAVAILABLE MEM_SEG_DISABLED\r\n");
    xil_printf("keys: K1 source SIM/ADC; K2 RUN/STOP; UART s=SIM a=ADC r=RUN p=STOP v=STATUS\r\n");
    REG(100) = 0;
    REG(8) = cfg;
    for (;;) {
        unsigned e = REG(60);
        if ((e >> 16) != key) {
            key = e >> 16;
            REG(60) = e;
            if ((e & 3) == 1)
                cfg ^= 2;
            if ((e & 3) == 2)
                cfg ^= 1;
            REG(8) = cfg;
        }
        if (XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)) {
            unsigned c = XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_FIFO_OFFSET);
            if (c == 's') {
                cfg |= 2;
            }
            if (c == 'a') {
                cfg &= ~2u;
            }
            if (c == 'r') {
                cfg |= 1;
            }
            if (c == 'p') {
                cfg &= ~1u;
            }
            if (c == 'v')
                xil_printf("OCM id=%08x state=%08x frame=%u otr=%u errors=%08x ctrl=%08x\r\n",
                           REG(0), REG(36), REG(56), REG(28), REG(64), REG(8));
            if (c == 's' || c == 'a' || c == 'r' || c == 'p') {
                REG(8) = cfg;
                xil_printf("OK OCM ctrl=%08x\r\n", cfg);
            }
        }
    }
}
