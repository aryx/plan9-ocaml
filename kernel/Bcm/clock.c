/*
 * bcm283[56] timers
 *  System timers run at 1MHz (timers 1 and 2 are used by GPU)
 *  ARM timer usually runs at 250MHz (may be slower in low power modes)
 *  Cycle counter runs at 700MHz (unless overclocked)
 *    All are free-running up-counters
 *  Cortex-a7 has local generic timers per cpu (which we run at 1MHz)
 *
 * Use system timer 3 (64 bits) for hzclock interrupts and fastticks
 *   For smp on bcm2836, use local generic timer for interrupts on cpu1-3
 * Use ARM timer (32 bits) for perfticks
 * Use ARM timer to force immediate interrupt
 * Use cycle counter for cycles()
 */
#include <u.h>
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

#include "io.h"
#include "ureg.h"
#include "arm.h"

//pad: The problem is that under QEMU only the Cortex-a7 generic timers
// are working and only the IRQcntps is connected. So I had to rewrite
// the code to rely only on this generic timer. For more information see:
// - https://lists.gnu.org/archive/html/qemu-arm/2016-03/msg00256.html
// - https://github.com/tuxillo/minios-armv7
// - http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.ddi0464d/BABIGHII.html

// does not work under QEMU
//#define SYSTIMERS (VIRTIO+0x3000)
//#define ARMTIMER (VIRTIO+0xB400)

//TODO factorize in mem.h
#define ARMLOCAL    (VIRTIO+IOSIZE)

enum {
// does not work under QEMU
//    Localctl    = 0x00,
//    Prescaler   = 0x08,

//    SystimerFreq    = 1*Mhz,
      // for QEMU
      // less: use cprdsc(0, CpTIMER, 0, 0) to read timer frequency instead?
      SystimerFreq = 62500000, // but really generic timer Freq

    MaxPeriod   = SystimerFreq / Arch_HZ,
    MinPeriod   = SystimerFreq / (100*Arch_HZ),
};

//typedef struct Systimers Systimers;
//typedef struct Armtimer Armtimer;

// The order matters! the fields match the memory-mapped external registers.
//struct Systimers {
//    u32int  cs;
//
//    u32int  clo;
//    u32int  chi;
//
//    u32int  c0;
//    u32int  c1;
//    u32int  c2;
//    u32int  c3;
//};
//
//struct Armtimer {
//    u32int  load;
//    u32int  val;
//    u32int  ctl;
//    u32int  irqack;
//    u32int  irq;
//    u32int  maskedirq;
//    u32int  reload;
//    u32int  predivider;
//    u32int  count;
//};

enum {
//    CntPrescaleShift= 16,   /* freq is sys_clk/(prescale+1) */
//    CntPrescaleMask = 0xFF,
//    CntEnable   = 1<<9,
//
//    TmrDbgHalt  = 1<<8,
//    TmrEnable   = 1<<7,
//    TmrIntEnable    = 1<<5,
//    TmrPrescale1    = 0x00<<2,
//    TmrPrescale16   = 0x01<<2,
//    TmrPrescale256  = 0x02<<2,
//
//    CntWidth16  = 0<<1,
//    CntWidth32  = 1<<1,

    /* generic timer (cortex-a7) */
    Enable  = 1<<0,
    Imask   = 1<<1,
    Istatus = 1<<2,
};

//static void
//clockintr(Ureg *ureg, void*)
//{
//    Systimers *tn;
//
//    tn = (Systimers*)SYSTIMERS;
//    /* dismiss interrupt */
//    tn->cs = 1<<3;
//    timerintr(ureg, 0);
//}

static void
localclockintr(Ureg *ureg, void *)
{
    uvlong v;
    unsigned int x;
    print("localclockintr\n");

    tmrget(&v);
    print("val1: %lld\n", v);
    x = (unsigned int) cprdsc(0, CpTIMER, CpTIMERphys, CpTIMERphysval);
    print("val2: %ud\n", x);

    //pad: we must use the generic timer also for cpu0 under QEMU
    //if(cpu->cpuno == 0)
    //    panic("cpu0: Unexpected local generic timer interrupt");
    // acknowledge interrupt
    cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysctl, Imask|Enable);

    //to test:
    //cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysval, 62500000);
    //cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysctl, Enable);

    timerintr(ureg, 0);
}


void
clockinit(void)
{
    //Systimers *tn;
    //Armtimer *tm;
    //u32int t0, t1, tstart, tend;

    if(((cprdsc(0, CpID, CpIDfeat, 1) >> 16) & 0xF) != 0) {
        /* generic timer supported */
        if(cpu->cpuno == 0){
         // does not work under QEMU
         //*(ulong*)(ARMLOCAL + Localctl) = 0;             /* magic */
         //*(ulong*)(ARMLOCAL + Prescaler) = 0x06aaaaab;   /* magic for 1 Mhz */
        }
        cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysctl, Imask);
    } else {
        panic("clockinit requires support for generic timer");
    }

    // Does not work under QEMU!
    //tn = (Systimers*)SYSTIMERS;
    //tstart = tn->clo;
    //do{
    //    t0 = arch_lcycles();
    //}while(tn->clo == tstart); // PB QEMU
    //tend = tstart + 10000;
    //do{
    //    t1 = arch_lcycles();
    //}while(tn->clo != tend); // PB QEMU
    //t1 -= t0;

    //cpu->cpuhz = 100 * t1;
    //cpu->cpumhz = (cpu->cpuhz + Mhz/2 - 1) / Mhz;
    //
    //cpu->cyclefreq = cpu->cpuhz;

    // Does not work under QEMU!
    //if(cpu->cpuno == 0){
    //    tn->c3 = tn->clo - 1;
    //    tm = (Armtimer*)ARMTIMER;
    //    tm->load = 0;
    //    tm->ctl = TmrPrescale1|CntEnable|CntWidth32;
    //    arch_intrenable(IRQtimer3, clockintr, nil, 0, "clock");
    //}
    //else
        // does not work under QEMU. 
        // seehttps://lists.gnu.org/archive/html/qemu-arm/2016-03/msg00256.html
        // QEMU handles only Physical (IRQLOCAL+0) and Virt IRQLOCAL+3) timers
        //arch_intrenable(IRQcntpns, localclockintr, nil, 0, "clock"); 
        arch_intrenable(IRQcntps, localclockintr, nil, 0, "clock");
}

void
clockshutdown(void)
{
    panic("clockshutdown");
    //Armtimer *tm;

    //tm = (Armtimer*)ARMTIMER;
    //tm->ctl = 0;
    ////wdogoff();
}

void
arch_timerset(Tval next)
{
    //Systimers *tn;
    uvlong now;
    long period;

    now = arch_fastticks(nil);
    period = next - now;
    // disabled for now to let more flexibility in timersinit()
    //if(period < MinPeriod)
    //    period = MinPeriod;
    //else if(period > MaxPeriod)
    //    period = MaxPeriod;

    //panic("next = %lld, now = %ulld, period = %d \n", period);

    // we must do that also for cpu0 under QEMU
    //if(cpu->cpuno > 0)
    {
        cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysval, period);
        cpwrsc(0, CpTIMER, CpTIMERphys, CpTIMERphysctl, Enable);
    }
    //else{
    //    tn = (Systimers*)SYSTIMERS;
    //    tn->c3 = (ulong)(now + period);
    //}
}

uvlong
clock_arch_fastticks(uvlong *hz)
{
    //Systimers *tn;
    ulong lo, hi;
    uvlong now;
    int s;

    if(hz)
        *hz = SystimerFreq;

    s = arch_splhi();
    // does not work under QEMU
    // tn = (Systimers*)SYSTIMERS;
    //do{
    //    hi = tn->chi;
    //    lo = tn->clo;
    //}while(tn->chi != hi);
    //now = (uvlong)hi<<32 | lo;
    tmrget(&now);    

    cpu->fastclock = now;
    arch_splx(s);
    return cpu->fastclock;
}

ulong
arch_perfticks(void)
{
    //Armtimer *tm;

    panic("arch_perfticks");
    return 0;

    //tm = (Armtimer*)ARMTIMER;
    //return tm->count;
}

//this is not used only in USB driver
//void
//armtimerset(int n)
//{
//    Armtimer *tm;
//
//    tm = (Armtimer*)ARMTIMER;
//    if(n > 0){
//        tm->ctl |= TmrEnable|TmrIntEnable;
//        tm->load = n;
//    }else{
//        tm->load = 0;
//        tm->ctl &= ~(TmrEnable|TmrIntEnable);
//        tm->irq = 1;
//    }
//}

ulong
arch_us(void)
{
    if(SystimerFreq != 1*Mhz)
        return fastticks2us(arch_fastticks(nil));
    return arch_fastticks(nil);
}

void
clock_arch_microdelay(int n)
{
    //Systimers *tn;
    u32int now, diff;
    
    panic("clock_arch_microdelay");
    //diff = n + 1;
    //tn = (Systimers*)SYSTIMERS;
    //now = tn->clo;
    //while(tn->clo - now < diff) // PB QEMU
    //    ;
}

void
clock_arch_delay(int n)
{
    while(--n >= 0)
        arch_microdelay(1000);
}
