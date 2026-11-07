#import "DY778FansUI.h"
NSArray<NSDictionary *> *DY778FansHistoryLoad(NSString *account);
BOOL DY778FansHistorySave(NSString *account, NSDictionary *snapshot, NSString *recordID);
void DY778FansHistoryRemove(NSString *account, NSString *recordID);
void DY778FansHistoryClear(NSString *account);
NSDictionary *DY778FansHistorySnapshot(DY778FansResult *result, NSDictionary *person, NSDictionary *anchor, NSError *error);
void DY778FansOpenHistory(UIViewController *presenter);
