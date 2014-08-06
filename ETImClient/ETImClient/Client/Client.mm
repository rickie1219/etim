//
//  Client.m
//  ETImClient
//
//  Created by ethan on 8/6/14.
//  Copyright (c) 2014 Pingan. All rights reserved.
//

#import "Client.h"
#include "Socket.h"
#include "Logging.h"
#include "ActionManager.h"

using namespace etim;
using namespace etim::pub;

@interface Client () {
    @private
    etim::Session *_session;
}


@end

@implementation Client

static Client *sharedClient = nil;

+(Client*)sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClient=[[Client alloc]init];
    });
    
    return sharedClient;
}

- (void)dealloc {
    delete _session;
    
}

- (id)init {
    if (self = [super init]) {
        _queueId = dispatch_queue_create("hello", NULL);
        std::auto_ptr<Socket> connSoc(new Socket(-1, 0));
        ///令人头痛的命名冲突
        _session = new Session(connSoc);
    }
    
    return self;
}

- (etim::Session *)session {
    return _session;
}

- (void)doAction:(etim::Session &)s {
    dispatch_async(_queueId, ^{
        Singleton<ActionManager>::Instance().DoAction(s);
    });
}

@end