//
//  BuddyModel.m
//  ETImClient
//
//  Created by Ethan on 14/9/1.
//  Copyright (c) 2014年 Pingan. All rights reserved.
//

#import "BuddyModel.h"
#import "Client.h"

using namespace etim;

@implementation BuddyModel

- (id)initWithUser:(etim::IMUser)user {
    if (self = [super init]) {
        self.userId = user.userId;
        self.username = stdStrToNsStr(user.username);
        self.regDate = stdStrToNsStr(user.regDate);
        self.signature = stdStrToNsStr(user.signature);
        self.gender = user.gender;
        self.relation = user.relation;
        self.status = user.status;
        self.statusName = stdStrToNsStr(user.statusName);
    }
    
    return self;
}

- (NSString *)buddyGender {
    return self.gender ? @"男" : @"女";
}
- (NSString *)description {
    return [NSString stringWithFormat:@"用户id: %06d, 用户名:%@, 注册日期: %@, 签名:%@, 性别:%@, 状态:%@",
            self.userId,
            self.username,
            self.regDate,
            self.signature,
            [self buddyGender],
            self.statusName];
}

+ (NSMutableArray *)buddys:(const std::list<etim::IMUser> &)users {
    NSMutableArray *result = [NSMutableArray array];
    std::list<IMUser>::const_iterator it;
    for (it = users.begin(); it != users.end(); ++it) {
        BuddyModel *model = [[BuddyModel alloc] initWithUser:*it];
        [result addObject:model];
    }

    return result;
}

@end
