/*
 * traps, exceptions, interrupts, system calls.
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

int
fault(virt_addr addr, bool read) {
  panic("TODO: implement fault in OCaml");
  return -1;
}

#define INTREGS     (VIRTIO+0xB200)
#define LOCALREGS   (VIRTIO+IOSIZE)

typedef struct Intregs Intregs;
typedef struct Vctl Vctl;
typedef struct Vpage0 Vpage0;

enum {
    Debug = 1,

    Nvec = 8,       /* # of vectors at start of lexception.s */
    Fiqenable = 1<<7,

    Localtimerint   = 0x40,
    Localmboxint    = 0x50,
    Localintpending = 0x60,
};

/*
 *   Layout at virtual address KZERO (double mapped at HVECTORS).
 */
struct Vpage0 {
    void    (*vectors[Nvec])(void);
    u32int  vtable[Nvec];
};

/*
 * interrupt control registers
 */
// The order matters! the fields match the memory-mapped external registers.
struct Intregs {
    u32int  ARMpending;
    u32int  GPUpending[2];

    u32int  FIQctl;

    u32int  GPUenable[2];
    u32int  ARMenable;

    u32int  GPUdisable[2];
    u32int  ARMdisable;
};

struct Vctl {
    // enum<IRQ>
    int irq;

    u32int  *reg; // VIRTIO address
    u32int  mask;

    void    (*f)(Ureg*, void*); /* handler to call */
    void    *a; /* argument to call it with */

    int cpu;

    // Extra
    Vctl    *next;
};

static Lock vctllock;

// list<ref_own<Vctl>>> (next = Vctl.next)
static Vctl *vctl;

static Vctl *vfiq;

static char *trapnames[PsrMask+1] = {
    [ PsrMusr ] "user mode",
    [ PsrMsvc ] "svc/swi exception",
    [ PsrMirq ] "irq interrupt",
    [ PsrMabt ] "prefetch abort/data abort",
    [ PsrMabt+1 ] "data abort",
    [ PsrMund ] "undefined instruction",
    [ PsrMfiq ] "fiq interrupt",
};

/*
 *  set up for exceptions
 */
void
arch__trapinit(void)
{
    Vpage0 *vpage0;

    if (cpu->cpuno == 0) {
        /* disable everything */
        intrsoff();
        /* set up the exception vectors */
        vpage0 = (Vpage0*)HVECTORS;
        memmove(vpage0->vectors, vectors, sizeof(vpage0->vectors));
        memmove(vpage0->vtable, vtable, sizeof(vpage0->vtable));
        ///cacheuwbinv();
        ///l2cacheuwbinv();
    }

    /* set up the stacks for the interrupt modes */
    setr13(PsrMirq, cpu->sirq);
    setr13(PsrMabt, cpu->sabt);
    setr13(PsrMund, cpu->sund);
    setr13(PsrMfiq, (u32int*)(FIQSTKTOP));
    arch_coherence();
}

void
intrsoff(void)
{
    Intregs *ip;
    int disable;

    ip = (Intregs*)INTREGS;
    disable = ~0;
    ip->GPUdisable[0] = disable;
    ip->GPUdisable[1] = disable;
    ip->ARMdisable = disable;
    ip->FIQctl = 0;
}

static void
intrtime(void)
{
    ulong diff;
    ulong x;

    x = 0; //TODO: arch_perfticks();
    diff = x - cpu->perf.intrts;
    cpu->perf.intrts = x;

    cpu->perf.inintr += diff;
    if(up == nil && cpu->perf.inidle > diff)
        cpu->perf.inidle -= diff;
}


/*
 *  called by trap to handle irq interrupts.
 *  returns true iff a clock interrupt, thus maybe reschedule.
 */
static bool
irq(Ureg* ureg)
{
    Vctl *v;
    bool clockintr;
    bool found;
    iprint("irq()\n");

    //TODO: cpu->perf.intrts = arch_perfticks();
    clockintr = false;
    found = false;
    for(v = vctl; v; v = v->next)
        if(v->cpu == cpu->cpuno && (*v->reg & v->mask) != 0){
            found = true;
            arch_coherence();
            // Dispatch
            v->f(ureg, v->a);
            arch_coherence();
            if(v->irq == IRQclock || v->irq == IRQcntps || v->irq == IRQcntpns)
                clockintr = true;
        }
    if(!found)
        cpu->spuriousintr++;
    intrtime();
    return clockintr;
}

/*
 * called direct from lexception.s to handle fiq interrupt.
 */
void
fiq(Ureg *ureg)
{
    Vctl *v;

    //TODO: cpu->perf.intrts = arch_perfticks();
    v = vfiq;
    if(v == nil)
        panic("cpu%d: unexpected item in bagging area", cpu->cpuno);
    cpu->intr++;
    ureg->pc -= 4;
    arch_coherence();

    // Dispatch!
    v->f(ureg, v->a);

    arch_coherence();
    intrtime();
}

void
irqenable(int irq, void (*f)(Ureg*, void*), void* a)
{
    Vctl *v;
    Intregs *ip;
    u32int *enable;

    ip = (Intregs*)INTREGS;
    v = (Vctl*)malloc(sizeof(Vctl));
    if(v == nil)
        panic("irqenable: no mem");
    v->irq = irq;
    v->cpu = 0;
    if(irq >= IRQlocal){
        enable = (u32int*)(LOCALREGS + Localtimerint) + cpu->cpuno;
        v->reg = (u32int*)(LOCALREGS + Localintpending) + cpu->cpuno;
        v->mask = 1 << (irq - IRQlocal);
        v->cpu = cpu->cpuno;
    }
    else if(irq >= IRQbasic){
        enable = &ip->ARMenable;
        v->reg = &ip->ARMpending;
        v->mask = 1 << (irq - IRQbasic);
    }
    else{
        enable = &ip->GPUenable[irq/32];
        v->reg = &ip->GPUpending[irq/32];
        v->mask = 1 << (irq % 32);
    }
    v->f = f;
    v->a = a;
    lock(&vctllock);
    if(irq == IRQfiq){
        assert((ip->FIQctl & Fiqenable) == 0);
        assert((*enable & v->mask) == 0);
        vfiq = v;
        ip->FIQctl = Fiqenable | irq;
    }
    else{
        v->next = vctl;
        vctl = v;
        if(irq >= IRQlocal)
            *enable |= 1 << (irq - IRQlocal);
        else
            *enable = v->mask;
    }
    unlock(&vctllock);
}

static char *
trapname(int psr)
{
    char *s;

    s = trapnames[psr & PsrMask];
    if(s == nil)
        s = "unknown trap number in psr";
    return s;
}

/* this is quite helpful during mmu and cache debugging */
static void
ckfaultstuck(uintptr va)
{
    static int cnt, lastpid;
    static uintptr lastva;

    if (va == lastva && up->pid == lastpid) {
        ++cnt;
        if (cnt >= 2)
            /* fault() isn't fixing the underlying cause */
            panic("fault: %d consecutive faults for va %#p",
                cnt+1, va);
    } else {
        cnt = 0;
        lastva = va;
        lastpid = up->pid;
    }
}

/*
 *  called by trap to handle access faults
 */
static void
faultarm(Ureg *ureg, uintptr va, int user, bool read)
{
    bool insyscall;
    int n;
    char buf[ERRMAX];

    if(up == nil) {
        dumpregs(ureg);
        panic("fault: nil up in faultarm, pc %#p accessing %#p", ureg->pc, va);
    }
    insyscall = up->insyscall;
    up->insyscall = true; // ???
    if (Debug)
       ckfaultstuck(va);
    n = fault(va, read); // portable code

    if(n < 0){
        if(!user){
            dumpregs(ureg);
            panic("fault: kernel accessing %#p", va);
        }
        /* don't dump registers; programs suicide all the time */
        snprint(buf, sizeof buf, "sys: trap: fault %s va=%#p",
            read? "read": "write", va);
        postnote(up, 1, buf, NDebug);
    }
    up->insyscall = insyscall;
}

/*
 *  returns true if the instruction writes memory, false otherwise
 */
bool
writetomem(ulong inst)
{
    /* swap always write memory */
    if((inst & 0x0FC00000) == 0x01000000)
        return true;

    /* loads and stores are distinguished by bit 20 */
    if(inst & (1<<20))
        return false;

    return true;
}

/*
 *  here on all exceptions other than syscall (SWI) and fiq
 */
void
arch__trap(Ureg *ureg)
{
    bool user;
    bool clockintr;
    int rem;
    char buf[ERRMAX];
    int x;
    ulong fsr;
    virt_addr va; // can be a kern_addr?
    ulong inst;
    int rv;

    assert(!arch_islo());

    if(up != nil)
        rem = ((char*)ureg)-up->kstack;
    else
        rem = ((char*)ureg)-((char*)cpu + sizeof(Cpu));
    if(rem < 256) {
        iprint("trap: %d stack bytes left, up %#p ureg %#p at pc %#lux\n",
            rem, up, ureg, ureg->pc);
        arch_delay(1000);
        arch_dumpstack();
        panic("trap: %d stack bytes left, up %#p ureg %#p at pc %#lux",
            rem, up, ureg, ureg->pc);
    }

    user = (ureg->psr & PsrMask) == PsrMusr; // TODO: arch_userureg
    if(user){
        up->dbgreg = ureg;
        //TODO: arch_cycles(&up->kentry);
    }

    /*
     * All interrupts/exceptions should be resumed at ureg->pc-4,
     * except for Data Abort which resumes at ureg->pc-8.
     */
    if(ureg->type == (PsrMabt+1))
        ureg->pc -= 8;
    else
       ureg->pc -= 4;

    clockintr = false;      /* if set, may call sched() before return */

    switch(ureg->type){
    case PsrMund:           /* undefined instruction */
        if(user){
            //TODO:
            // if(seg(up, ureg->pc, false) != nil &&
            //    *(u32int*)ureg->pc == 0xD1200070)
            //     postnote(up, 1, "sys: breakpoint", NDebug);
            // /*e: [[trap()]] when undefined instruction, if breakpoint(arm) */
            // else
            {
                /* look for floating point instructions to interpret */
                rv = fpuemu(ureg);
                if(rv == 0)
                {
                    snprint(buf, sizeof buf,
                        "undefined instruction: pc %#lux\n",
                        ureg->pc);
                    postnote(up, 1, buf, NDebug);
                }
            }
        }else{
            if (ureg->pc & 3) {
                iprint("rounding fault pc %#lux down to word\n",
                    ureg->pc);
                ureg->pc &= ~3;
            }
            iprint("undefined instruction: pc %#lux inst %#ux\n",
                ureg->pc, *(u32int*)ureg->pc);
            panic("undefined instruction");
        }
        break;
    case PsrMabt:           /* prefetch fault */
        x = ifsrget();
        fsr = (x>>7) & 0x8 | x & 0x7;
        switch(fsr){
        case 0x02:      /* instruction debug event (BKPT) */
            if(user){
                snprint(buf, sizeof buf, "sys: breakpoint");
                postnote(up, 1, buf, NDebug);
            }else{
                iprint("kernel bkpt: pc %#lux inst %#ux\n",
                    ureg->pc, *(u32int*)ureg->pc);
                panic("kernel bkpt");
            }
            break;
        default:
            // Page fault on code!!
            faultarm(ureg, ureg->pc, user, true);
            break;
        }
        break;
    case PsrMabt+1:         /* data fault */
        va = farget();
        inst = *(ulong*)(ureg->pc);
        /* bits 12 and 10 have to be concatenated with status */
        x = fsrget();
        fsr = (x>>7) & 0x20 | (x>>6) & 0x10 | x & 0xf;
        switch(fsr){
        case 0xd:
        case 0xf:
            /* permission error, copy on write or real permission error */
            faultarm(ureg, va, user, !writetomem(inst));
            break;
        case 0x5:       /* translation fault, no section entry */
        case 0x7:       /* translation fault, no page entry */
            // Page fault on data!!
            faultarm(ureg, va, user, !writetomem(inst));
            break;
        case 0x9:
        case 0xb:
            /* domain fault, accessing something we shouldn't */
            if(user){
                snprint(buf, sizeof buf,
                    "sys: access violation: pc %#lux va %#p\n",
                    ureg->pc, va);
                postnote(up, 1, buf, NDebug);
            } else
                panic("kernel access violation: pc %#lux va %#p",
                    ureg->pc, va);
            break;
        case 0x0:
            panic("vector exception at %#lux", ureg->pc);
            break;
        case 0x1:       /* alignment fault */
        case 0x3:       /* access flag fault (section) */
            if(user){
                snprint(buf, sizeof buf,
                    "sys: alignment: pc %#lux va %#p\n",
                    ureg->pc, va);
                postnote(up, 1, buf, NDebug);
            } else
                panic("kernel alignment: pc %#lux va %#p", ureg->pc, va);
            break;
        case 0x2:
            panic("terminal exception at %#lux", ureg->pc);
            break;
        case 0x4:       /* icache maint fault */
        case 0x6:       /* access flag fault (page) */
        case 0x8:       /* precise external abort, non-xlat'n */
        case 0x28:
        case 0xc:       /* l1 translation, precise ext. abort */
        case 0x2c:
        case 0xe:       /* l2 translation, precise ext. abort */
        case 0x2e:
        case 0x16:      /* imprecise ext. abort, non-xlt'n */
        case 0x36:
            panic("external abort %#lux pc %#lux addr %#p",
                fsr, ureg->pc, va);
            break;
        case 0x1c:      /* l1 translation, precise parity err */
        case 0x1e:      /* l2 translation, precise parity err */
        case 0x18:      /* imprecise parity or ecc err */
            panic("translation parity error %#lux pc %#lux addr %#p",
                fsr, ureg->pc, va);
            break;
        default:
        case 0xa:       /* ? was under external abort */
            panic("unknown data fault, 6b fsr %#lux", fsr);
            break;
        }
        break;
    case PsrMirq:
        clockintr = irq(ureg);
        cpu->intr++;
        break;
    default:
        panic("unknown trap; type %#lux, psr mode %#lux pc %lux", ureg->type,
            ureg->psr & PsrMask, ureg->pc);
        break;
    }
    arch_splhi();

    /* delaysched set because we held a lock or because our quantum ended */
    if(up && up->delaysched && clockintr){
        sched();
        arch_splhi();
    }

    //TODO:
    //if(user){
    //    /*s: [[trap()]] call possibly notify(arm) */
    //    if(up->procctl || up->nnote)
    //        arch__notify(ureg);
    //    /*e: [[trap()]] call possibly notify(arm) */
    //    arch__kexit(ureg);
    //}
}

int
isvalidaddr(void *v)
{
    return (uintptr)v >= KZERO;
}

static void
dumplongs(char *msg, ulong *v, int n)
{
    int i, l;

    l = 0;
    iprint("%s at %.8p: ", msg, v);
    for(i=0; i<n; i++){
        if(l >= 4){
            iprint("\n    %.8p: ", v);
            l = 0;
        }
        if(isvalidaddr(v)){
            iprint(" %.8lux", *v++);
            l++;
        }else{
            iprint(" invalid");
            break;
        }
    }
    iprint("\n");
}

static void
dumpstackwithureg(Ureg *ureg)
{
    uintptr l, i, v, estack;
    u32int *p;
    char *s;

    if((s = getconf("*nodumpstack")) != nil && strcmp(s, "0") != 0){
        iprint("dumpstack disabled\n");
        return;
    }
    iprint("ktrace /kernel/path %#.8lux %#.8lux %#.8lux # pc, sp, link\n",
        ureg->pc, ureg->sp, ureg->r14);
    arch_delay(2000);
    i = 0;
    if(up != nil && (uintptr)&l <= (uintptr)up->kstack+KSTACK)
        estack = (uintptr)up->kstack+KSTACK;
    else if((uintptr)&l >= (uintptr)cpu->stack
         && (uintptr)&l <= (uintptr)cpu + CPUSIZE)
        estack = (uintptr)cpu + CPUSIZE;
    else{
        if(up != nil)
            iprint("&up->kstack %#p &l %#p\n", up->kstack, &l);
        else
            iprint("&m %#p &l %#p\n", cpu, &l);
        return;
    }
    for(l = (uintptr)&l; l < estack; l += sizeof(uintptr)){
        v = *(uintptr*)l;
        if(KTZERO < v && v < (uintptr)etext && !(v & 3)){
            v -= sizeof(u32int);        /* back up an instr */
            p = (u32int*)v;
            if((*p & 0x0f000000) == 0x0b000000){    /* BL instr? */
                iprint("%#8.8lux=%#8.8lux ", l, v);
                i++;
            }
        }
        if(i == 4){
            i = 0;
            iprint("\n");
        }
    }
    if(i)
        iprint("\n");
}

/*
 * Fill in enough of Ureg to get a stack trace, and call a function.
 * Used by debugging interface rdb.
 */
static void
getpcsp(ulong *pc, ulong *sp)
{
    *pc = getcallerpc(&pc);
    *sp = (ulong)&pc-4;
}

void
arch_callwithureg(void (*fn)(Ureg*))
{
    Ureg ureg;

    getpcsp((ulong*)&ureg.pc, (ulong*)&ureg.sp);
    ureg.r14 = getcallerpc(&fn);
    fn(&ureg);
}

void
trap_arch_dumpstack(void)
{
    arch_callwithureg(dumpstackwithureg);
}

void
dumpregs(Ureg* ureg)
{
    int s;

    if (ureg == nil) {
        iprint("trap: no user process\n");
        return;
    }
    s = arch_splhi();
    iprint("trap: %s", trapname(ureg->type));
    if(ureg != nil && (ureg->psr & PsrMask) != PsrMsvc)
        iprint(" in %s", trapname(ureg->psr));
    iprint("\n");
    iprint("psr %8.8lux type %2.2lux pc %8.8lux link %8.8lux\n",
        ureg->psr, ureg->type, ureg->pc, ureg->link);
    iprint("R14 %8.8lux R13 %8.8lux R12 %8.8lux R11 %8.8lux R10 %8.8lux\n",
        ureg->r14, ureg->r13, ureg->r12, ureg->r11, ureg->r10);
    iprint("R9  %8.8lux R8  %8.8lux R7  %8.8lux R6  %8.8lux R5  %8.8lux\n",
        ureg->r9, ureg->r8, ureg->r7, ureg->r6, ureg->r5);
    iprint("R4  %8.8lux R3  %8.8lux R2  %8.8lux R1  %8.8lux R0  %8.8lux\n",
        ureg->r4, ureg->r3, ureg->r2, ureg->r1, ureg->r0);
    iprint("stack is at %#p\n", ureg);
    iprint("pc %#lux link %#lux\n", ureg->pc, ureg->link);

    //if(up)
    //    iprint("user stack: %#p-%#p\n", up->kstack, up->kstack+KSTACK-4);
    //else
    //    iprint("kernel stack: %8.8lux-%8.8lux\n",
    //        (ulong)(cpu+1), (ulong)cpu+BY2PG-4);
    //dumplongs("stack", (ulong *)(ureg + 1), 16);
    //arch_delay(2000);
    //arch_dumpstack();
    //arch_splx(s);
}
