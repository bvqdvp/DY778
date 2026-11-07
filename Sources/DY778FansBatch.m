#import "DY778FansBatch.h"
#import "DY778FansBatchPolicy.h"
#import "DY778RadarUI.h"
#import "DY778FansHistory.h"

/* Uses only the existing logged-in service. No tokens or session data are exported. */
@interface DY778FansBatchController : UITableViewController
@property(nonatomic, copy) NSDictionary *person;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, strong) NSMutableArray<NSString *> *inputs;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *rows;
@property(nonatomic, strong) NSMutableSet<NSString *> *selected;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *liveStates;
@property(nonatomic) BOOL liveOnly;
@property(nonatomic, copy) NSString *historyID;
@property(nonatomic, strong) NSArray<NSString *> *queue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *resolved;
@property(nonatomic, strong) DY778FansService *service;
@property(nonatomic) NSUInteger cursor;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL resolving;
@property(nonatomic) BOOL litFirst;
@property(nonatomic) BOOL onlyLit;
@property(nonatomic, strong) NSDate *startedAt;
@end

@implementation DY778FansBatchController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (NSString *)listKey { return [@"fans.batch.anchors." stringByAppendingString:self.account ?: @""]; }
- (BOOL)current { return DY778Bool(@"fans.enabled") && [self.account isEqual:DY778CurrentAccountID()]; }
- (BOOL)mayContinue:(NSUInteger)generation { return DY778FansBatchMayContinue([self current],self.running,generation,self.generation); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"多主播灯牌排行"; self.account = DY778CurrentAccountID();
    self.inputs = [NSMutableArray array]; self.selected = [NSMutableSet set]; self.liveStates = [NSMutableDictionary dictionary]; self.rows = [NSMutableArray array]; self.resolved = [NSMutableDictionary dictionary]; self.service = [DY778FansService new]; self.litFirst = YES;
    id saved = [DY778Preferences() objectForKey:self.listKey];
    NSArray *list = [saved isKindOfClass:NSDictionary.class] ? saved[@"inputs"] : saved;
    NSArray *selected = [saved isKindOfClass:NSDictionary.class] && [saved[@"selected"] isKindOfClass:NSArray.class] ? saved[@"selected"] : nil;
    if ([list isKindOfClass:NSArray.class]) for (id item in list) {
        if ([item isKindOfClass:NSString.class] && DY778FansASCIIHandle([item UTF8String],[item lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) && ![self.inputs containsObject:item] && self.inputs.count < 100) {
            [self.inputs addObject:item]; if (!selected || [selected containsObject:item]) [self.selected addObject:item];
        }
    }
    self.status = @"添加主播名单后开始查询；只查询名单内的主播。";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 76;
    DY778StyleController(self); self.tableView.backgroundColor = DY778Background();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addAnchor)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pause) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged) name:DY778PreferencesChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)dealloc { [self.service cancel]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)pause {
    if (!self.running && !self.resolving) return;
    if (self.running) [self checkpoint:@"paused"]; self.generation++; self.running = NO; self.resolving = NO; [self.service cancel];
    self.status = @"已停止。已完成结果保留，未完成主播可重试。"; [self.tableView reloadData];
}
- (void)preferencesChanged {
    DY778StyleController(self);
    if (![self current]) { [self pause]; [self.rows removeAllObjects]; [self.resolved removeAllObjects]; [self.inputs removeAllObjects]; [self.selected removeAllObjects]; [self.liveStates removeAllObjects]; self.person = @{}; self.queue = @[]; self.status = @"账号或设置已变化，请返回用户主页重新进入。"; [self.tableView reloadData]; }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) [self pause];
}
- (void)persist { if ([self current]) [DY778Preferences() setObject:@{@"version":@2,@"inputs":[self.inputs copy],@"selected":self.selected.allObjects} forKey:self.listKey]; }
- (void)checkpoint:(NSString *)runState {
    if (self.liveOnly || !self.historyID.length || !self.rows.count || ![self current]) return;
    NSMutableDictionary *snapshot = [[self exportObjectForRows:[self rankedRows:NO]] mutableCopy];
    snapshot[@"filteredLit"] = @NO; snapshot[@"runState"] = runState; snapshot[@"notice"] = self.status ?: @"";
    if (!DY778FansHistorySave(self.account,snapshot,self.historyID)) DY778Toast(@"本地历史未能保存，请导出结果备份");
}
- (NSString *)liveLabel:(NSDictionary *)state {
    NSString *label = [state[@"liveState"] isEqual:@"live"] ? @"直播中" : [state[@"liveState"] isEqual:@"ended"] ? @"直播已结束" : @"直播状态未知";
    if ([state[@"liveCheckedAt"] isKindOfClass:NSNumber.class]) {
        NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"HH:mm:ss";
        label = [label stringByAppendingFormat:@" · %@",[formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[state[@"liveCheckedAt"] doubleValue]]]];
    }
    return label;
}
- (void)addAnchor {
    if (self.running || self.resolving || ![self current]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加主播" message:@"输入完整抖音号，先核对主播身份。需要导入多个抖音号时，在下方选择“从剪贴板导入”。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"主播抖音号"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    __weak typeof(self) weakSelf = self; __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"查找并核对" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf resolveAndAdd:[weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)resolveAndAdd:(NSString *)input {
    if (![self current] || self.running || self.resolving) return;
    if (!DY778FansASCIIHandle(input.UTF8String,[input lengthOfBytesUsingEncoding:NSUTF8StringEncoding])) { DY778Toast(@"请输入有效的完整抖音号"); return; }
    if ([self.inputs containsObject:input]) { DY778Toast(@"该抖音号已在名单中"); return; }
    if (self.inputs.count >= 100) { DY778Toast(@"每份名单最多 100 位主播"); return; }
    self.resolving = YES; NSUInteger generation = ++self.generation; self.status = @"正在查找主播…"; [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [self.service resolveInput:input mode:DY778FansInputHandle completion:^(id person,NSError *error) {
        DY778FansBatchController *self = weakSelf;
        if (!self || generation != self.generation || ![self current]) return;
        self.resolving = NO;
        NSArray *candidates = [error.userInfo[@"DY778FansCandidates"] isKindOfClass:NSArray.class] ? error.userInfo[@"DY778FansCandidates"] : nil;
        if (!candidates.count && !error && [person isKindOfClass:NSDictionary.class]) candidates = @[person];
        if (!candidates.count) { self.status = error.localizedDescription ?: @"主播未匹配，请核对抖音号"; [self.tableView reloadData]; return; }
        self.status = @"请核对并确认主播身份"; [self.tableView reloadData];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"确认主播身份" message:@"只将你确认的账号加入名单。" preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *candidate in candidates) {
            if (![candidate isKindOfClass:NSDictionary.class] || !DY778FansUID(candidate[@"uid"])) continue;
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@ · UID %@",DY778FansPersonName(candidate),candidate[@"handle"] ?: @"",candidate[@"uid"]] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                DY778FansBatchController *self = weakSelf;
                if (![self current] || self.generation != generation || self.running || self.resolving || self.inputs.count >= 100) return;
                if (![self.inputs containsObject:input]) [self.inputs addObject:input];
                [self.selected addObject:input]; self.resolved[input] = candidate; [self persist]; self.status = @"主播已加入名单"; [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
        [self presentViewController:sheet animated:YES completion:nil];
    }];
}
- (void)importList {
    if (self.running || self.resolving || ![self current]) return;
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length || text.length > 20000) { DY778Toast(@"剪贴板为空或内容过长，请每行放一个抖音号"); return; }
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"\r\n,，;； \t"];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:separators]) {
        if (!part.length) continue;
        if (!DY778FansASCIIHandle(part.UTF8String,[part lengthOfBytesUsingEncoding:NSUTF8StringEncoding])) { DY778Toast(@"导入未执行：包含无效抖音号，请只粘贴抖音号列表"); return; }
        if (![values containsObject:part] && ![self.inputs containsObject:part]) [values addObject:part];
    }
    if (!values.count) { DY778Toast(@"没有可新增的抖音号"); return; }
    if (values.count + self.inputs.count > 100) { DY778Toast(@"导入未执行：名单上限为 100 位主播"); return; }
    NSUInteger generation = self.generation;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认导入主播名单" message:[NSString stringWithFormat:@"新增 %lu 个抖音号。查询时逐一匹配身份；有歧义的账号会停止该条查询，需单独核对。名单不等于该用户的全部关注或粉丝团。",(unsigned long)values.count] preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导入" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        DY778FansBatchController *self = weakSelf;
        if (![self current] || self.generation != generation || self.running || self.resolving) return;
        [self.inputs addObjectsFromArray:values]; [self.selected addObjectsFromArray:values]; [self persist]; self.status = @"名单已导入，可以开始查询"; [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSArray<NSDictionary *> *)visibleRows { return [self rankedRows:self.onlyLit]; }
- (NSArray<NSDictionary *> *)rankedRows:(BOOL)onlyLit {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *row in self.rows) if (!onlyLit || [row[@"lit"] isEqual:@YES]) [rows addObject:row];
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        int x = DY778FansBatchCompare(self.litFirst,[a[@"rawState"] intValue],[a[@"level"] isKindOfClass:NSNumber.class] ? [a[@"level"] intValue] : -1,[b[@"rawState"] intValue],[b[@"level"] isKindOfClass:NSNumber.class] ? [b[@"level"] intValue] : -1);
        return x < 0 ? NSOrderedAscending : x > 0 ? NSOrderedDescending : [a[@"input"] compare:b[@"input"]];
    }];
}
- (void)start:(BOOL)retry {
    if (self.running || self.resolving || ![self current]) return;
    NSMutableArray *queue = [NSMutableArray array];
    for (NSString *input in self.inputs) {
        NSDictionary *old = nil; for (NSDictionary *row in self.rows) if ([row[@"input"] isEqual:input]) { old = row; break; }
        if (DY778FansBatchShouldQueue([self.selected containsObject:input],retry,old != nil,[old[@"status"] isEqual:@"joined"])) [queue addObject:input];
    }
    if (!queue.count) { DY778Toast(retry ? @"没有失败、待确认或未完成的主播" : @"请先添加并勾选主播"); return; }
    if (!retry) [self.rows removeAllObjects];
    self.liveOnly = NO; self.historyID = NSUUID.UUID.UUIDString;
    self.queue = queue; self.cursor = 0; self.startedAt = NSDate.date; self.running = YES; self.generation++;
    [self next:self.generation];
}
- (void)startLiveRefresh {
    if (self.running || self.resolving || ![self current]) return;
    NSMutableArray *queue = [NSMutableArray array];
    for (NSString *input in self.inputs) if ([self.selected containsObject:input]) [queue addObject:input];
    if (!queue.count) { DY778Toast(@"请先勾选要刷新状态的主播"); return; }
    self.queue = queue; self.cursor = 0; self.liveOnly = YES; self.running = YES; self.generation++;
    [self next:self.generation];
}
- (void)next:(NSUInteger)generation {
    if (![self mayContinue:generation]) return;
    if (self.cursor >= self.queue.count) { self.running = NO; self.status = [NSString stringWithFormat:self.liveOnly ? @"直播状态刷新完成，共 %lu 位；以各项核对时间为准。" : @"本轮完成，共 %lu 位；未取得资料仍显示待确认。",(unsigned long)self.queue.count]; [self checkpoint:@"completed"]; [self.tableView reloadData]; return; }
    NSString *input = self.queue[self.cursor];
    self.status = [NSString stringWithFormat:self.liveOnly ? @"%lu / %lu · 正在刷新直播状态 %@" : @"%lu / %lu · 正在查询 %@",(unsigned long)(self.cursor + 1),(unsigned long)self.queue.count,input]; [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    NSDictionary *anchor = self.resolved[input];
    if (anchor) { [self queryAnchor:anchor input:input generation:generation]; return; }
    [self.service resolveInput:input mode:DY778FansInputHandle completion:^(id value,NSError *error) {
        DY778FansBatchController *self = weakSelf; if (![self mayContinue:generation]) return;
        if (error || ![value isKindOfClass:NSDictionary.class] || !DY778FansUID(value[@"uid"])) {
            NSString *message = error.userInfo[@"DY778FansCandidates"] ? @"账号匹配有歧义，请删除此条后通过“添加主播”核对身份" : error.localizedDescription ?: @"未匹配到主播";
            [self recordInput:input anchor:nil result:nil error:DY778FansError(error.code ?: 404,message) generation:generation]; return;
        }
        self.resolved[input] = value; [self queryAnchor:value input:input generation:generation];
    }];
}
- (void)queryAnchor:(NSDictionary *)anchor input:(NSString *)input generation:(NSUInteger)generation {
    if (![self mayContinue:generation]) return;
    __weak typeof(self) weakSelf = self;
    if (self.liveOnly) {
        [self.service refreshAnchorLive:anchor completion:^(id profile,NSError *error) {
            DY778FansBatchController *self = weakSelf; if (![self mayContinue:generation]) return;
            if ([profile isKindOfClass:NSDictionary.class]) self.resolved[input] = profile;
            [self recordInput:input anchor:profile ?: anchor result:nil error:error generation:generation];
        }]; return;
    }
    [self.service queryInput:@"" mode:DY778FansInputAutomatic target:self.person anchor:anchor completion:^(DY778FansResult *result,NSError *error) {
        [weakSelf recordInput:input anchor:anchor result:result error:error generation:generation];
    }];
}
- (void)recordInput:(NSString *)input anchor:(NSDictionary *)anchor result:(DY778FansResult *)result error:(NSError *)error generation:(NSUInteger)generation {
    if (![self mayContinue:generation]) return;
    if (self.liveOnly) {
        self.liveStates[input] = @{@"liveState":error ? @"unknown" : anchor[@"liveState"] ?: @"unknown",@"liveCheckedAt":@(NSDate.date.timeIntervalSince1970),@"message":error.localizedDescription ?: @""};
        self.cursor++; [self.tableView reloadData];
        if (error.code == 401 || error.code == 403 || error.code == 429) { self.running = NO; self.status = @"服务拒绝或限流，已停止刷新直播状态。"; [self.tableView reloadData]; return; }
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [weakSelf next:generation]; }); return;
    }
    NSDictionary *club = nil;
    for (NSDictionary *candidate in result.clubs) if ([candidate[@"anchorUID"] isEqual:anchor[@"uid"]] && [candidate[@"level"] integerValue] > 0) { club = candidate; break; }
    NSInteger rawState = [club[@"status"] integerValue];
    id lit = rawState == 1 ? @YES : rawState == 2 ? @NO : NSNull.null;
    NSDictionary *live = self.liveStates[input] ?: result.anchor ?: anchor ?: @{};
    NSDictionary *row = @{@"liveState":live[@"liveState"] ?: @"unknown",@"liveCheckedAt":live[@"liveCheckedAt"] ?: NSNull.null,@"input":input,@"anchorId":anchor[@"uid"] ?: input,@"anchorName":anchor ? DY778FansPersonName(anchor) : input,@"status":club ? @"joined" : error ? @"error" : @"unknown",@"level":club[@"level"] ?: NSNull.null,@"lit":club ? lit : NSNull.null,@"rawState":@(rawState),@"message":club ? @"" : error.localizedDescription ?: @"暂未取得可确认灯牌，不代表未加入",@"queriedAt":@([NSDate.date timeIntervalSince1970])};
    NSIndexSet *old = [self.rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop) { return [r[@"input"] isEqual:input]; }];
    [self.rows removeObjectsAtIndexes:old]; [self.rows addObject:row]; self.cursor++; [self checkpoint:@"running"]; [self.tableView reloadData];
    /* Permission/rate errors pause the queue; do not rotate identities or retry around them. */
    if (error.code == 401 || error.code == 403 || error.code == 429) { self.running = NO; self.status = @"服务要求登录、拒绝访问或限制频率，已停止。请确认状态后手动重试。"; [self checkpoint:@"blocked"]; [self.tableView reloadData]; return; }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0 * NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [weakSelf next:generation]; });
}
- (NSDictionary *)exportObject { return [self exportObjectForRows:[self visibleRows]]; }
- (NSDictionary *)exportObjectForRows:(NSArray *)records {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *row in records) {
        NSMutableDictionary *copy = [row mutableCopy];
        [copy removeObjectForKey:@"rawState"]; [copy removeObjectForKey:@"input"];
        [rows addObject:copy];
    }
    NSString *handle = DY778FansString(self.person[@"handle"]);
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    return @{@"user":@{@"douyinId":handle,@"uid":DY778FansString(self.person[@"uid"]),@"nickname":DY778FansPersonName(self.person)},@"source":@"DY778 多主播查询 · 当前登录会话可返回资料",@"queriedAt":[formatter stringFromDate:NSDate.date],@"results":rows,@"scope":@"仅限手动配置的主播名单；不是全部关注或全部粉丝团",@"sort":self.litFirst ? @"lit_then_level" : @"level",@"filteredLit":@(self.onlyLit)};
}
- (void)exportJSON {
    if (![self current] || self.running || self.resolving || ![self visibleRows].count) { DY778Toast(@"请先完成查询，并确保当前筛选下有结果"); return; }
    NSError *error; NSData *data = [NSJSONSerialization dataWithJSONObject:[self exportObject] options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) { DY778Toast(@"导出失败，请重试"); return; }
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"DY778-灯牌-%@.json",NSUUID.UUID.UUIDString]]];
    if (![data writeToURL:file options:NSDataWritingAtomic error:&error]) { DY778Toast(@"写入导出文件失败"); return; }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    sheet.completionWithItemsHandler = ^(__unused UIActivityType type,__unused BOOL complete,__unused NSArray *items,__unused NSError *failure) { [NSFileManager.defaultManager removeItemAtURL:file error:nil]; };
    [self presentViewController:sheet animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 4 : section == 1 ? 3 : section == 2 ? 3 + self.inputs.count : section == 3 ? MAX((NSUInteger)1,[self visibleRows].count) : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"当前用户与进度",@"排序与导出",@"主播名单（左滑删除）",@"本次排行榜",@"本地查询记录"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"串行查询，主播之间间隔 1 秒。离开页面、锁屏、退后台、切换账号会停止。";
    if (section == 1) return @"点亮状态沿用原插件状态映射；缺失时显示未知。接口未返回精确亲密度，因此仅按等级排序。导出当前排序及筛选结果。";
    if (section == 2) return @"点按主播行勾选，左滑删除；仅查询已勾选的主播。直播状态是刷新时快照，不持续后台监控，未知不代表未开播。";
    if (section == 4) return @"单次和批量查询记录按抖音账号保存在本机，最多 50 条、总计 4 MB；可回看、删除、导出。";
    return @"未返回灯牌不代表未加入。未查询的主播不在结果中；已完成结果包含各自时间，非同时刻快照。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        if (path.row == 0) return DY778RadarCell(DY778FansPersonName(self.person),self.status,@"person.crop.circle",NO);
        if (path.row == 1) return DY778RadarCell(self.running ? @"停止当前任务" : [NSString stringWithFormat:@"查询已勾选主播（%lu 位）",(unsigned long)self.selected.count],self.running ? @"保留本次已完成的结果" : @"重新查询已勾选主播，替换本次结果",self.running ? @"stop.circle" : @"play.circle",NO);
        if (path.row == 3) return DY778RadarCell(@"刷新已勾选主播直播状态",@"主动获取当前状态，显示核对时间；不定时轮询",@"dot.radiowaves.left.and.right",NO);
        return DY778RadarCell(@"重试失败、待确认及未完成主播",@"保留已确认有灯牌的结果",@"arrow.clockwise",NO);
    }
    if (path.section == 1) {
        if (path.row == 0) return DY778RadarCell(@"排序方式",self.litFirst ? @"已点亮优先，再按等级从高到低" : @"按等级从高到低",@"arrow.up.arrow.down",NO);
        if (path.row == 1) return DY778RadarCell(@"只看已点亮",self.onlyLit ? @"已开启（未知状态不显示）" : @"已关闭",@"line.3.horizontal.decrease.circle",NO);
        return DY778RadarCell(@"导出 JSON 到网页",@"通过分享菜单保存到“文件”，再在网页导入",@"square.and.arrow.up",NO);
    }
    if (path.section == 2) {
        if (path.row == 0) return DY778RadarCell(@"从剪贴板导入主播名单",@"每行一个完整抖音号，最多 100 位；点右上角 ＋ 可单独核对主播",@"doc.on.clipboard",NO);
        if (path.row == 1) return DY778RadarCell(@"全部勾选",[NSString stringWithFormat:@"已选 %lu / %lu 位主播",(unsigned long)self.selected.count,(unsigned long)self.inputs.count],@"checkmark.circle",NO);
        if (path.row == 2) return DY778RadarCell(@"取消全部勾选",@"保留主播名单和当前结果",@"circle",NO);
        NSString *input = self.inputs[(NSUInteger)path.row - 3]; NSDictionary *anchor = self.resolved[input];
        NSString *detail = [NSString stringWithFormat:@"抖音号：%@\n%@",input,[self liveLabel:self.liveStates[input] ?: anchor]];
        UITableViewCell *cell = DY778RadarCell(anchor ? DY778FansPersonName(anchor) : input,detail,[self.selected containsObject:input] ? @"checkmark.circle.fill" : @"circle",NO);
        cell.accessibilityValue = [self.selected containsObject:input] ? @"已勾选" : @"未勾选"; return cell;
    }
    if (path.section == 4) return DY778RadarCell(@"查看本地查询记录",@"查看单次和批量历史快照，支持删除、JSON 导出",@"clock.arrow.circlepath",YES);
    NSArray *rows = [self visibleRows];
    if (!rows.count) return DY778RadarCell(@"暂无符合条件的结果",self.onlyLit ? @"可以关闭只看已点亮筛选" : @"添加主播名单后开始查询",@"star.circle",NO);
    NSDictionary *row = rows[(NSUInteger)path.row];
    BOOL joined = [row[@"status"] isEqual:@"joined"];
    NSString *lit = [row[@"lit"] isEqual:@YES] ? @"已点亮" : [row[@"lit"] isEqual:@NO] ? @"未点亮" : @"点亮状态未知";
    NSString *detail = joined ? [NSString stringWithFormat:@"Lv.%@ · %@",row[@"level"],lit] : [row[@"status"] isEqual:@"error"] ? @"查询失败" : @"待确认";
    if ([row[@"message"] length]) detail = [detail stringByAppendingFormat:@"\n%@",row[@"message"]];
    return DY778RadarCell([NSString stringWithFormat:@"%lu. %@",(unsigned long)path.row + 1,row[@"anchorName"]],detail,@"star.fill",NO);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (![self current]) return;
    if (path.section == 0 && path.row == 1 && self.running) { [self pause]; return; }
    if (self.running || self.resolving) return;
    if (path.section == 0 && path.row == 3) [self startLiveRefresh];
    else if (path.section == 0 && path.row > 0) [self start:path.row == 2];
    else if (path.section == 1 && path.row == 0) { self.litFirst = !self.litFirst; [self.tableView reloadData]; }
    else if (path.section == 1 && path.row == 1) { self.onlyLit = !self.onlyLit; [self.tableView reloadData]; }
    else if (path.section == 1 && path.row == 2) [self exportJSON];
    else if (path.section == 2 && path.row == 0) [self importList];
    else if (path.section == 2) {
        if (path.row == 1) [self.selected addObjectsFromArray:self.inputs];
        else if (path.row == 2) [self.selected removeAllObjects];
        else { NSString *input = self.inputs[(NSUInteger)path.row - 3]; if ([self.selected containsObject:input]) [self.selected removeObject:input]; else [self.selected addObject:input]; }
        [self persist]; [self.tableView reloadData];
    } else if (path.section == 4) DY778FansOpenHistory(self);
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return [self current] && !self.running && !self.resolving && path.section == 2 && path.row >= 3; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:path]) return;
    NSString *input = self.inputs[(NSUInteger)path.row - 3]; [self.inputs removeObjectAtIndex:(NSUInteger)path.row - 3]; [self.resolved removeObjectForKey:input]; [self.selected removeObject:input]; [self.liveStates removeObjectForKey:input];
    NSIndexSet *matches = [self.rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop) { return [row[@"input"] isEqual:input]; }];
    [self.rows removeObjectsAtIndexes:matches]; [self persist]; [self.tableView reloadData];
}
@end
void DY778FansOpenBatch(UIViewController *presenter,NSDictionary *person) {
    if (!DY778Bool(@"fans.enabled") || !person) return;
    DY778FansBatchController *controller = [DY778FansBatchController new]; controller.person = person;
    DY778PresentController(presenter,controller);
}
