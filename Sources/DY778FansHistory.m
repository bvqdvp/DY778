#import "DY778FansHistory.h"
#import "DY778RadarUI.h"
#import <CoreFoundation/CoreFoundation.h>

static BOOL DY778FansHistoryCurrent(NSString *account) {
    return DY778FansUID(account) && DY778Bool(@"fans.enabled") && [account isEqual:DY778CurrentAccountID()];
}
static NSString *DY778FansHistoryKey(NSString *account) { return [@"fans.history.v1." stringByAppendingString:account ?: @""]; }
static NSDictionary *DY778FansHistoryClean(id raw) {
    if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"user"] isKindOfClass:NSDictionary.class] || ![raw[@"results"] isKindOfClass:NSArray.class] || [raw[@"results"] count] > 100) return nil;
    id user = raw[@"user"]; NSMutableArray *results = [NSMutableArray array];
    for (id row in raw[@"results"]) {
        if (![row isKindOfClass:NSDictionary.class]) return nil;
        NSString *status = DY778FansString(row[@"status"]);
        if (![@[@"joined",@"unknown",@"error",@"not_joined"] containsObject:status]) return nil;
        NSNumber *level = DY778FansInteger(row[@"level"]);
        if (level && (level.integerValue < 1 || level.integerValue > 999)) return nil;
        NSMutableDictionary *copy = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"anchorId",@"anchorName",@"message",@"liveState"]) {
            NSString *value = DY778FansString(row[key]); if (value.length > 500) return nil; if (value.length) copy[key] = value;
        }
        if (![copy[@"anchorId"] length] || ![copy[@"anchorName"] length]) return nil;
        if ([status isEqual:@"joined"] && !level) return nil;
        copy[@"status"] = status; copy[@"level"] = [status isEqual:@"joined"] ? level : NSNull.null;
        copy[@"lit"] = [status isEqual:@"joined"] && [row[@"lit"] isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)row[@"lit"]) == CFBooleanGetTypeID() ? row[@"lit"] : NSNull.null;
        for (NSString *key in @[@"queriedAt",@"liveCheckedAt"]) if ([row[key] isKindOfClass:NSNumber.class]) copy[key] = row[key];
        [results addObject:copy];
    }
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"id",@"queriedAt",@"source",@"scope",@"sort",@"notice",@"runState"]) {
        NSString *value = DY778FansString(raw[key]); if (value.length > 1000) return nil; if (value.length) clean[key] = value;
    }
    NSMutableDictionary *identity = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"douyinId",@"uid",@"nickname"]) { NSString *s = DY778FansString(user[key]); if (s.length > 200) return nil; identity[key] = s; }
    if (![identity[@"nickname"] length]) identity[@"nickname"] = @"用户";
    clean[@"user"] = identity; clean[@"results"] = results;
    if ([raw[@"filteredLit"] isKindOfClass:NSNumber.class]) clean[@"filteredLit"] = @([raw[@"filteredLit"] boolValue]);
    return clean;
}
NSArray<NSDictionary *> *DY778FansHistoryLoad(NSString *account) {
    if (!DY778FansHistoryCurrent(account)) return @[];
    id data = [DY778Preferences() objectForKey:DY778FansHistoryKey(account)];
    if (![data isKindOfClass:NSData.class] || [data length] > 4 * 1024 * 1024) return @[];
    id raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![raw isKindOfClass:NSArray.class] || [raw count] > 50) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (id entry in raw) { NSDictionary *clean = DY778FansHistoryClean(entry); if (clean && [clean[@"id"] length]) [rows addObject:clean]; }
    return rows;
}
static BOOL DY778FansHistoryWrite(NSString *account, NSArray *records) {
    if (!DY778FansHistoryCurrent(account)) return NO;
    NSMutableArray *limited = [records mutableCopy]; NSData *data;
    while (limited.count) {
        data = [NSJSONSerialization dataWithJSONObject:limited options:0 error:nil];
        if (data && data.length <= 4 * 1024 * 1024 && limited.count <= 50) break;
        [limited removeLastObject];
    }
    if (!limited.count) data = [NSJSONSerialization dataWithJSONObject:@[] options:0 error:nil];
    if (!data) return NO;
    [DY778Preferences() setObject:data forKey:DY778FansHistoryKey(account)]; return YES;
}
BOOL DY778FansHistorySave(NSString *account, NSDictionary *snapshot, NSString *recordID) {
    if (!DY778FansHistoryCurrent(account) || !recordID.length) return NO;
    NSMutableDictionary *record = [DY778FansHistoryClean(snapshot) mutableCopy]; if (!record) return NO;
    record[@"id"] = recordID;
    NSMutableArray *rows = [NSMutableArray arrayWithObject:record];
    for (NSDictionary *old in DY778FansHistoryLoad(account)) if (![old[@"id"] isEqual:recordID]) [rows addObject:old];
    return DY778FansHistoryWrite(account,rows);
}
void DY778FansHistoryRemove(NSString *account, NSString *recordID) {
    if (!DY778FansHistoryCurrent(account)) return;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *old in DY778FansHistoryLoad(account)) if (![old[@"id"] isEqual:recordID]) [rows addObject:old];
    DY778FansHistoryWrite(account,rows);
}
void DY778FansHistoryClear(NSString *account) { if (DY778FansHistoryCurrent(account)) [DY778Preferences() removeObjectForKey:DY778FansHistoryKey(account)]; }
NSDictionary *DY778FansHistorySnapshot(DY778FansResult *result, NSDictionary *person, NSDictionary *anchor, NSError *error) {
    person = result.person ?: person ?: @{}; anchor = result.anchor ?: anchor;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *club in result.clubs) {
        NSString *uid = DY778FansString(club[@"anchorUID"]); if (!uid.length || [club[@"level"] integerValue] < 1) continue;
        NSInteger state = [club[@"status"] integerValue];
        [rows addObject:@{@"anchorId":uid,@"anchorName":[club[@"anchorName"] length] ? club[@"anchorName"] : anchor ? DY778FansPersonName(anchor) : [club[@"clubName"] length] ? club[@"clubName"] : uid,@"status":@"joined",@"level":club[@"level"],@"lit":state == 1 ? @YES : state == 2 ? @NO : NSNull.null,@"queriedAt":@(NSDate.date.timeIntervalSince1970)}];
    }
    if (!rows.count && anchor) [rows addObject:@{@"anchorId":DY778FansString(anchor[@"uid"]),@"anchorName":DY778FansPersonName(anchor),@"status":error ? @"error" : @"unknown",@"level":NSNull.null,@"lit":NSNull.null,@"message":error.localizedDescription ?: @"暂未取得可确认的灯牌，不代表未加入"}];
    return @{@"user":@{@"uid":DY778FansString(person[@"uid"]),@"douyinId":DY778FansString(person[@"handle"]),@"nickname":DY778FansPersonName(person)},@"results":rows,@"queriedAt":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date],@"source":@"DY778 单次查询 · 当前登录会话可返回资料",@"scope":anchor ? @"指定主播" : @"本次接口可返回的灯牌，非完整粉丝团列表",@"notice":error.localizedDescription ?: result.notice ?: @"查询结束",@"runState":error ? @"error" : @"completed"};
}

@interface DY778FansHistoryController : UITableViewController
@property(nonatomic, copy) NSString *account;
@property(nonatomic, strong) NSArray<NSDictionary *> *records;
@property(nonatomic, copy) NSDictionary *snapshot;
@end
@implementation DY778FansHistoryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.account = DY778CurrentAccountID(); self.title = self.snapshot ? @"历史灯牌结果" : @"本地查询记录";
    DY778StyleController(self); self.tableView.backgroundColor = DY778Background(); self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 76;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:self.snapshot ? UIBarButtonSystemItemAction : UIBarButtonSystemItemTrash target:self action:self.snapshot ? @selector(share) : @selector(clear)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:DY778PreferencesChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self reload];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)reload {
    DY778StyleController(self);
    if (!DY778FansHistoryCurrent(self.account)) { self.records = @[]; self.snapshot = nil; self.title = @"账号或设置已变化"; self.navigationItem.rightBarButtonItem.enabled = NO; }
    else if (!self.snapshot) self.records = DY778FansHistoryLoad(self.account);
    [self.tableView reloadData];
}
- (void)clear {
    if (!DY778FansHistoryCurrent(self.account)) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空本地查询记录？" message:@"只清除当前抖音账号的历史，无法撤销。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { DY778FansHistoryClear(weakSelf.account); [weakSelf reload]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)share {
    if (!DY778FansHistoryCurrent(self.account) || !self.snapshot) return;
    if (![self.snapshot[@"results"] count]) { DY778Toast(@"此记录没有可导出的灯牌结果"); return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.snapshot options:NSJSONWritingPrettyPrinted error:nil]; if (!data) return;
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"DY778-历史-%@.json",NSUUID.UUID.UUIDString]]];
    if (![data writeToURL:file options:NSDataWritingAtomic error:nil]) { DY778Toast(@"导出失败"); return; }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    sheet.completionWithItemsHandler = ^(__unused UIActivityType type,__unused BOOL completed,__unused NSArray *items,__unused NSError *error) { [NSFileManager.defaultManager removeItemAtURL:file error:nil]; };
    [self presentViewController:sheet animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.snapshot ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.snapshot ? (section == 0 ? 1 : MAX((NSUInteger)1,[self.snapshot[@"results"] count])) : MAX((NSUInteger)1,self.records.count); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"历史快照，不代表当前实时状态。最多保留 50 条、总计 4 MB，超限移除最早记录；账号间隔离，可左滑删除记录。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (!DY778FansHistoryCurrent(self.account)) return DY778RadarCell(@"请返回主页重新进入",@"当前账号或功能开关已变化",@"person",NO);
    if (!self.snapshot) {
        if (!self.records.count) return DY778RadarCell(@"暂无查询记录",@"单次和批量查询结果会保存在此设备",@"clock",NO);
        NSDictionary *record = self.records[(NSUInteger)path.row];
        return DY778RadarCell(record[@"user"][@"nickname"],[NSString stringWithFormat:@"%@\n%lu 位主播 · %@",record[@"queriedAt"] ?: @"时间未知",(unsigned long)[record[@"results"] count],@{@"completed":@"已完成",@"paused":@"已停止",@"running":@"未完成快照",@"blocked":@"权限或限流中止",@"error":@"查询失败"}[record[@"runState"] ?: @""] ?: @"历史快照"],@"clock",YES);
    }
    if (path.section == 0) return DY778RadarCell(self.snapshot[@"user"][@"nickname"],[NSString stringWithFormat:@"%@\n%@\n%@",self.snapshot[@"queriedAt"] ?: @"",self.snapshot[@"scope"] ?: @"",self.snapshot[@"notice"] ?: @""],@"person",NO);
    NSArray *rows = self.snapshot[@"results"];
    if (!rows.count) return DY778RadarCell(@"未取得灯牌资料",self.snapshot[@"notice"] ?: @"不代表未加入",@"star",NO);
    NSDictionary *row = rows[(NSUInteger)path.row];
    NSString *lit = [row[@"lit"] isEqual:@YES] ? @"已点亮" : [row[@"lit"] isEqual:@NO] ? @"未点亮" : @"点亮未知";
    NSString *detail = [row[@"status"] isEqual:@"joined"] ? [NSString stringWithFormat:@"Lv.%@ · %@",row[@"level"],lit] : row[@"message"] ?: @"待确认，不代表未加入";
    return DY778RadarCell(row[@"anchorName"],detail,@"star.fill",NO);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.snapshot || !DY778FansHistoryCurrent(self.account) || !self.records.count) return;
    DY778FansHistoryController *detail = [DY778FansHistoryController new]; detail.snapshot = self.records[(NSUInteger)path.row]; DY778PresentController(self,detail);
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return !self.snapshot && self.records.count && DY778FansHistoryCurrent(self.account); }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete && [self tableView:tableView canEditRowAtIndexPath:path]) { DY778FansHistoryRemove(self.account,self.records[(NSUInteger)path.row][@"id"]); [self reload]; }
}
@end
void DY778FansOpenHistory(UIViewController *presenter) {
    if (DY778Bool(@"fans.enabled")) DY778PresentController(presenter,[DY778FansHistoryController new]);
}
