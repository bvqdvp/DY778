#include <assert.h>
#include <stdio.h>
#include "DY778FansBatchPolicy.h"
int main(void) {
    /* Lit preference is explicit, not a guess from missing status. */
    assert(DY778FansBatchCompare(true,1,2,2,10) < 0);
    assert(DY778FansBatchCompare(false,1,2,2,10) > 0);
    assert(DY778FansBatchCompare(true,0,10,1,2) > 0);
    assert(DY778FansBatchCompare(true,2,10,0,3) < 0);
    assert(DY778FansBatchCompare(false,0,-1,2,1) > 0);
    assert(DY778FansBatchCompare(false,0,-1,2,-1) == 0);
    for (int mode=0;mode<2;mode++) for(int a=0;a<3;a++) for(int b=0;b<3;b++) {
        int ab=DY778FansBatchCompare(mode,a,6,b,10),ba=DY778FansBatchCompare(mode,b,10,a,6);
        assert(ab == -ba);
    }
    assert(DY778FansBatchMayContinue(true,true,4,4));
    assert(!DY778FansBatchMayContinue(false,true,4,4));
    assert(!DY778FansBatchMayContinue(true,false,4,4));
    assert(!DY778FansBatchMayContinue(true,true,3,4));
    assert(DY778FansBatchLiveState(true,2,true) == 1);
    assert(DY778FansBatchLiveState(true,4,true) == 2);
    assert(DY778FansBatchLiveState(false,2,true) == 0);
    assert(DY778FansBatchLiveState(true,2,false) == 0);
    assert(DY778FansBatchLiveState(true,0,true) == 0);
    assert(DY778FansBatchLiveState(true,99,true) == 0);
    for (int retry=0;retry<2;retry++) for (int has=0;has<2;has++) for (int joined=0;joined<2;joined++) assert(!DY778FansBatchShouldQueue(false,retry,has,joined));
    assert(DY778FansBatchShouldQueue(true,false,true,true));
    assert(!DY778FansBatchShouldQueue(true,true,true,true));
    assert(DY778FansBatchShouldQueue(true,true,true,false));
    assert(DY778FansBatchShouldQueue(true,true,false,false));
    puts("PASS: ranking, unknown state, cancellation, account change, stale callback, selection/retry, live state identity and unknown handling");
}
