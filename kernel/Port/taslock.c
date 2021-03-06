// TAS: Test And Set
#include <u.h>
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"

struct TaslockStats
{
    ulong   locks;
    ulong   glare;
    ulong   inglare;
};
struct TaslockStats lockstats;
#ifdef LOCKCYCLES
long maxlockcycles;
long maxilockcycles;
long cumlockcycles;
long cumilockcycles;
ulong maxlockpc;
ulong maxilockpc;

ulong ilockpcs[0x100] = { [0xff] = 1 };
static int n;
#endif

// See also ref.c incref() and decref(), but we can't use them here as they
// themselves rely on lock() and unlock(). 
static void
inccnt(Ref *r)
{
    arch_xinc(&r->ref);
}

static int
deccnt(Ref *r)
{
    int x;

    x = arch_xdec(&r->ref);
    if(x < 0)
        panic("deccnt pc=%#p", getcallerpc(&r));
    return x;
}

void
lockloop(Lock *l, ulong pc)
{
    Proc *p;

    p = l->p;
    print("lock %#p loop key %#lux pc %#lux held by pc %#lux proc %lud\n",
        l, l->key, pc, l->pc, p ? p->pid : 0);
    dumpaproc(up);
    if(p != nil)
        dumpaproc(p);
}

int
lock(Lock *l)
{
    int i;
    ulong pc;

    pc = getcallerpc(&l);

    lockstats.locks++;
    if(up)
        inccnt(&up->nlocks);    /* prevent being scheded */
    if(arch_tas(&l->key) == 0){ // lock old value was 0, the lock was not held
        if(up)
            up->lastlock = l;
        l->pc = pc;
        l->p = up;
        l->isilock = false;
        l->cpu = CPUS(cpu->cpuno); // pad's third bugfix
        #ifdef LOCKCYCLES
                l->lockcycles = -arch_lcycles();
        #endif
        return 0;
    }
    //else
    //the lock was already held, need to spin

    if(up)
        deccnt(&up->nlocks);

    lockstats.glare++;
    for(;;){
        lockstats.inglare++;
        i = 0;
        while(l->key){
           if(conf.ncpu < 2 && up && up->edf && (up->edf->flags & Admitted)){
               /*
                * Priority inversion, yield on a uniprocessor; on a
                * multiprocessor, the other processor will unlock
                */
               print("inversion %#p pc %#lux proc %lud held by pc %#lux proc %lud\n",
                   l, pc, up ? up->pid : 0, l->pc, l->p ? l->p->pid : 0);
               up->edf->d = todget(nil);   /* yield to process with lock */
           }
            if(i++ > 100000000){
                i = 0;
                lockloop(l, pc);
            }
        }
        // try again
        if(up)
            inccnt(&up->nlocks);    /* prevent being scheded */
        if(arch_tas(&l->key) == 0){
            if(up)
                up->lastlock = l;
            l->pc = pc;
            l->p = up;
            l->isilock = false;
            #ifdef LOCKCYCLES
                    l->lockcycles = -arch_lcycles();
            #endif
            return 1;
        }
        if(up)
            deccnt(&up->nlocks);
    }
    return -1; // unreachable
}

// To provide mutual exclusion with interrupt code and avoiding deadlock.
// By using arch_splhi() we disable interrupts while running the critical region
// code.
void
ilock(Lock *l)
{
    ulong x;
    ulong pc;

    pc = getcallerpc(&l);
    lockstats.locks++;

    x = arch_splhi();
    // no need to take care of up->nlock++ here, we have disabled interrupt
    // so no risk of getting scheduled
    if(arch_tas(&l->key) != 0){
        lockstats.glare++;
        /*
         * Cannot also check l->pc, l->cpu, or l->isilock here
         * because they might just not be set yet, or
         * (for pc and m) the lock might have just been unlocked.
         */
        for(;;){
            lockstats.inglare++;
            arch_splx(x);
            while(l->key)
                ;
            // let's try again
            x = arch_splhi();
            if(arch_tas(&l->key) == 0)
                goto acquire;
        }
    }
acquire:
    cpu->ilockdepth++;
    if(up)
        up->lastilock = l;
    l->sr = x;
    l->pc = pc;
    l->p = up;
    l->isilock = true;
    l->cpu = CPUS(cpu->cpuno);
    #ifdef LOCKCYCLES
            l->lockcycles = -arch_lcycles();
    #endif
}

bool
canlock(Lock *l)
{
    if(up)
        inccnt(&up->nlocks);    /* prevent being scheded */
    if(arch_tas(&l->key) != 0){ // lock old value != 0, lock was already held
       if(up)
           deccnt(&up->nlocks);
        return false;
    }
    // else

    if(up)
        up->lastlock = l;
    l->pc = getcallerpc(&l);
    l->p = up;
    l->cpu = CPUS(cpu->cpuno);
    l->isilock = false;
    #ifdef LOCKCYCLES
            l->lockcycles = -arch_lcycles();
    #endif
    return true;
}

void
unlock(Lock *l)
{
    #ifdef LOCKCYCLES
        l->lockcycles += lcycles();
        cumlockcycles += l->lockcycles;
        if(l->lockcycles > maxlockcycles){
            maxlockcycles = l->lockcycles;
            maxlockpc = l->pc;
        }
    #endif

    if(l->key == 0)
        print("unlock: not locked: pc %#p\n", getcallerpc(&l));
    if(l->isilock)
        print("unlock of ilock: pc %lux, held by %lux\n", getcallerpc(&l), l->pc);
    if(l->p != up)
        print("unlock: up changed: pc %#p, acquired at pc %lux, lock p %#p, unlock up %#p\n", getcallerpc(&l), l->pc, l->p, up);
    l->cpu = nil;
    l->key = 0;
    // for processor caches, to ensure the lock value is seen by other
    // processors so that if they were doing while(l->key) { ... } they
    // can finally exit the while loop.
    arch_coherence();

    if(up && deccnt(&up->nlocks) == 0 && up->delaysched && arch_islo()){
        /*
         * Call sched if the need arose while locks were held
         * But, don't do it from interrupt routines, hence the arch_islo() test
         */
        sched();
    }
}

void
iunlock(Lock *l)
{
    ulong sr;

    #ifdef LOCKCYCLES
        l->lockcycles += lcycles();
        cumilockcycles += l->lockcycles;
        if(l->lockcycles > maxilockcycles){
            maxilockcycles = l->lockcycles;
            maxilockpc = l->pc;
        }
        if(l->lockcycles > 2400)
            ilockpcs[n++ & 0xff]  = l->pc;
    #endif
    if(l->key == 0)
        print("iunlock: not locked: pc %#p\n", getcallerpc(&l));
    if(!l->isilock)
        print("iunlock of lock: pc %#p, held by %#lux\n", getcallerpc(&l), l->pc);
    if(arch_islo())
        print("iunlock while lo: pc %#p, held by %#lux\n", getcallerpc(&l), l->pc);
    sr = l->sr;
    l->cpu = nil;
    l->key = 0;
    arch_coherence();
    cpu->ilockdepth--;
    if(up)
        up->lastilock = nil;
    arch_splx(sr);
}

