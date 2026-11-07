#ifndef DY778FansBatch_POLICY_H
#define DY778FansBatch_POLICY_H
#include <stdbool.h>
/* Unknown states are not equivalent to unlit; unknown levels sort last. */
int DY778FansBatchCompare(bool litFirst, int stateA, int levelA, int stateB, int levelB);
bool DY778FansBatchMayContinue(bool current, bool running, unsigned long expected, unsigned long actual);
/* Room status: 2 live, 4 ended; every other/missing state is unknown. */
int DY778FansBatchLiveState(bool present, int status, bool identityMatches);
bool DY778FansBatchShouldQueue(bool selected, bool retry, bool hasResult, bool joined);
#endif
