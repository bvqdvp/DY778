#include "DY778FansBatchPolicy.h"
int DY778FansBatchCompare(bool litFirst, int stateA, int levelA, int stateB, int levelB) {
    if (litFirst && (stateA == 1) != (stateB == 1)) return stateA == 1 ? -1 : 1;
    int a = levelA > 0 ? levelA : -1, b = levelB > 0 ? levelB : -1;
    return a > b ? -1 : a < b ? 1 : 0;
}
bool DY778FansBatchMayContinue(bool current, bool running, unsigned long expected, unsigned long actual) {
    return current && running && expected == actual;
}

int DY778FansBatchLiveState(bool present, int status, bool identityMatches) {
    if (!present || !identityMatches) return 0;
    return status == 2 ? 1 : status == 4 ? 2 : 0;
}

bool DY778FansBatchShouldQueue(bool selected, bool retry, bool hasResult, bool joined) {
    return selected && (!retry || !hasResult || !joined);
}
