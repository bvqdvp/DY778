#import "DY778FansLiveState.h"
#import "DY778FansBatchPolicy.h"
NSDictionary *DY778FansReadLiveState(id room, NSString *roomID, NSString *anchorUID, NSUInteger depth) {
    if (!room || room == NSNull.null || depth > 4) return nil;
    if ([room isKindOfClass:NSString.class]) {
        if ([room length] > 131072) return nil;
        room = [NSJSONSerialization JSONObjectWithData:[room dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; if (!room) return nil;
    }
    NSString *identifier = DY778FansString(DY778FansFirst(room,@[@"roomID",@"id_str",@"idStr",@"id",@"id_p",@"room_id"]));
    if (DY778FansUID(identifier)) {
        if (DY778FansUID(roomID) && ![identifier isEqual:roomID]) return nil;
        id owner = DY778FansFirst(room,@[@"owner",@"anchor"]);
        NSString *ownerID = DY778FansString(DY778FansFirst(owner,@[@"uid",@"id",@"id_str"]));
        if (DY778FansUID(ownerID) && DY778FansUID(anchorUID) && ![ownerID isEqual:anchorUID]) return nil;
        NSNumber *status = DY778FansInteger(DY778FansFirst(room,@[@"status",@"room_status",@"roomStatus"]));
        int state = DY778FansBatchLiveState(status != nil,status.intValue,true);
        if (state) return @{@"liveState":state == 1 ? @"live" : @"ended",@"liveRawStatus":status,@"liveCheckedAt":@(NSDate.date.timeIntervalSince1970)};
    }
    for (NSString *key in @[@"room",@"data",@"room_info",@"roomInfo",@"rawRoom",@"roomModel",@"rawHTSLiveRoomModel"]) {
        id nested = DY778FansRead(room,key); if (!nested || nested == room) continue;
        NSDictionary *state = DY778FansReadLiveState(nested,roomID,anchorUID,depth+1); if (state) return state;
    }
    return nil;
}
