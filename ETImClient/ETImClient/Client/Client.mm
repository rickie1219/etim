//
//  Client.m
//  ETImClient
//
//  Created by ethan on 8/6/14.
//  Copyright (c) 2014 Pingan. All rights reserved.
//

/**
09 - 01 遇到的问题主要是多个命令连续发的时候会产生SESSION被改变而这时上一个命令可能还未发出(因为发送用异步, 虽然BLOCK所在线程是SERIAL的 , 主线程先于发送执行)
 所以导致发的CMD及PARAM被改变 后面考虑做成OPERATIONQUQUE 每次把CMD及PARAM存到
 NSOPERATION去执行 解决命令顺序问题
 */

#import "Client.h"
#import "BuddyModel.h"
#import "SendOperation.h"
#import "Reachability.h"
#import "NSTimer+WeakTarget.h"
#import "CmdParamModel.h"

#include "Socket.h"
#include "Logging.h"
#include "ActionManager.h"
#include "Exception.h"
#include <string>
#include <signal.h>
#include <map>
#include <sstream>

using namespace etim;
using namespace etim::pub;
using namespace etim::action;
using namespace std;

#define kBgQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)


@interface Client () {
    @private
    etim::Session *_session;
}

@property (nonatomic, strong) Reachability *hostReachability;
@property (nonatomic, assign) BOOL isLogin;
@property (nonatomic, assign) BOOL isLogout;
@property (nonatomic, strong) NSTimer *heartBeatTimer;
@property (nonatomic, strong) NSMutableArray *queuedCmdArr;

- (void)connectCallBack:(bool)connected;

@end




@implementation Client

static Client *sharedClient = nil;
static dispatch_once_t predicate;

///连接结果回调
void clientConnectCallBack(bool connected)  {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[Client sharedInstance] connectCallBack:connected];
    });
    
}

+(Client*)sharedInstance{
    dispatch_once(&predicate, ^{
        sharedClient = [[Client alloc]init];
        //忽略send产生的sigpipe信号
        signal(SIGPIPE, SIG_IGN);
    });
    
    return sharedClient;
}

+ (void)sharedDealloc {
    if (sharedClient) {
        sharedClient = nil;
        predicate = 0;
    }
}

- (void)dealloc {
    DDLogDebug(@"======= Client DEALLOC ========");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNoConnectionNotification object:nil];
    [_heartBeatTimer invalidate];
    [_sendQueue cancelAllOperations];
    if (_session) {
        delete _session;
    }
}

- (id)init {
    if (self = [super init]) {
        self.hostReachability = [Reachability reachabilityWithHostName:@"www.baidu.com"];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reachabilityChanged:)
                                                     name:kReachabilityChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(showNoConnection:)
                                                     name:kNoConnectionNotification
                                                   object:nil];
        self.isLogin = NO;
        self.isLogout = YES;
        self.queuedCmdArr = [NSMutableArray arrayWithCapacity:10];
        
        _sendQueue = [[NSOperationQueue alloc] init];
        _recvQueue = dispatch_queue_create("com.ethan.clientRecv", NULL);
    }
    
    return self;
}


- (void)connectCallBack:(bool)connected {
    if (connected) {
        [self doRecv:*_session];
        _heartBeatTimer = [NSTimer scheduledTimerWithTimeInterval:HEART_BEAT_SECONDS weakTarget:self selector:@selector(heartBeart) userInfo:nil repeats:YES];
        [self.queuedCmdArr enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CmdParamModel *model = (CmdParamModel *)obj;
            SendOperation *operation = [[SendOperation alloc] initWithCmdParamModel:model];
            [_sendQueue addOperation:operation];
        }];
    } else {
        [self reconnect];
    }
}

- (void)connect {
    if (_session) {
        delete _session;
        _session = NULL;
        [_heartBeatTimer invalidate];
    }
    
    dispatch_async(kBgQueue, ^{
        std::auto_ptr<Socket> connSoc(new Socket(-1, 0));
        ///令人头痛的命名冲突
        _session = new Session(connSoc, clientConnectCallBack);
    });
}

- (void)reconnect {
    if ([self connected]) {
        return;
    }
    
    DDLogInfo(@"尝试重连");
    
    [self connect];
}

- (BOOL)connected {
    return _session->IsConnected();
}
- (void)close {
    _session->Close();
}
- (void)reLogin {
    
}

- (void)startReachabilityNoti {
    [self.hostReachability startNotifier];
}

- (etim::Session *)session {
    if (_session) {
        return _session;
    }

    [self connect];
    return _session;
}

- (BuddyModel *)user {
    if (_user) {
        _user = [[BuddyModel alloc] initWithUser:_session->GetIMUser()];
        
        return _user;
    } else {
        if (_user.userId == _session->GetIMUser().userId) {
            return _user;
        } else {
            _user = [[BuddyModel alloc] initWithUser:_session->GetIMUser()];
            return _user;
        }
    }
}

- (void)pullUnread {
    [self pullWithCommand:CMD_UNREAD];
}

- (void)autoLogin {
    if (self.isLogin)
        return;
    
    NSMutableDictionary *param = [NSMutableDictionary dictionary];
    [param setObject:@"admin1" forKey:@"name"];
    [param setObject:@"admin" forKey:@"pass"];
    [self doAction:*_session cmd:CMD_LOGIN param:param];
}

///只有参数为userId时的命令操作
- (void)pullWithCommand:(uint16)cmd {
    NSMutableDictionary *param = [NSMutableDictionary dictionary];
    string value = Convert::IntToString(_session->GetIMUser().userId);
    [param setObject:stdStrToNsStr(value) forKey:@"userId"];
    [self doAction:*_session cmd:cmd param:param];
}

- (void)heartBeart {
    [self pullWithCommand:CMD_HEART_BEAT];
}

#pragma mark -
#pragma mark send & recv action

- (void)doAction:(etim::Session &)s cmd:(etim::uint16)cmd param:(NSMutableDictionary *)params {
    CmdParamModel *model = [[CmdParamModel alloc] init];
    model.cmd = cmd;
    model.params = params;
    
    if (&s) {
        if (s.IsConnected()) {
            try {
                DDLogInfo(@"发送cmd: 0X%04X, 通知名称: %@， 参数: %@", cmd, notiNameFromCmd(cmd), params);

                SendOperation *operation = [[SendOperation alloc] initWithCmdParamModel:model];
                [_sendQueue addOperation:operation];
            } catch (Exception &e) {
                DDLogError(@"出错发送cmd: 0X%04X, 通知名称: %@", cmd, notiNameFromCmd(cmd));
                s.SetErrorCode(kErrCodeMax);
                s.SetErrorMsg(e.what());
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:notiNameFromCmd(cmd) object:nil];
                });
                
            }
        } else {
            [self.queuedCmdArr addObject:model];
            s.SetErrorCode(kErrCodeMax);
            s.SetErrorMsg("无服务器连接");
            [[NSNotificationCenter defaultCenter] postNotificationName:notiNameFromCmd(cmd) object:nil];
        }
    } else {
        DDLogWarn(@"还未建立连接");
        [self.queuedCmdArr addObject:model];
    }
   
}

- (void)doRecv:(etim::Session &)s {
    if (s.IsConnected()) {
        __weak Client *wself = self;
        dispatch_async(_recvQueue, ^{
            while (1) {
                if (!wself)
                    break;
                try {
                    Singleton<ActionManager>::Instance().RecvPacket(s);
                    if (!wself)
                        break;
                    ///必须dispatch_sync,不然如果多个命令连续的话会导致重新发出相同的最后一个命令名称
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        DDLogInfo(@"接收cmd: 0X%04X, 通知名称: %@", s.GetRecvCmd(), notiNameFromCmd(s.GetRecvCmd()));
                        if (s.GetRecvCmd() == CMD_LOGIN && !s.IsError()) {
                            wself.isLogin = YES;
                            wself.isLogout = NO;
                        }
                        
                        if (s.GetRecvCmd() == CMD_LOGOUT && !s.IsError()) {
                            wself.isLogout = YES;
                            wself.isLogin = NO;
                        }
                        
                        [[NSNotificationCenter defaultCenter] postNotificationName:notiNameFromCmd(s.GetRecvCmd()) object:nil];
                    });
                } catch (RecvException &e) {
                    if (!wself)
                        return;
                    LOG_INFO<<e.what();
                    if (e.GetReceived() == 0) {
                        ///TODO 关闭客户端socket并进行重连
                        LOG_ERROR<<"服务端关闭或超时";
                        [[TWMessageBarManager sharedInstance] showMessageWithTitle:@"服务器错误" description:@"服务端关闭" type:TWMessageBarMessageTypeError];
                        if (!wself)
                            break;
                        wself.isLogin = NO;
                        if (wself.isLogout) {
                            
                        } else {
                            [wself autoLogin];
                        }

                        /*
                        s.SetErrorCode(kErrCodeMax);
                        s.SetErrorMsg(e.what());
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:notiNameFromCmd(s.GetRecvCmd()) object:nil];
                        });
                         */
                        break;
                    } else if (e.GetReceived() == -1) {
                        LOG_ERROR<<e.what();
                    } else {
                        s.SetErrorCode(kErrCodeMax);
                        s.SetErrorMsg(e.what());
                        LOG_ERROR<<e.what();
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:notiNameFromCmd(s.GetRecvCmd()) object:nil];
                        });
                    }
                }
                
                catch (Exception &e) {
                    if (!wself)
                        return;
                    LOG_INFO<<e.what();
                }

                
            }
        });
    } else {
        s.SetErrorCode(kErrCodeMax);
        s.SetErrorMsg("无服务器连接");
        [[NSNotificationCenter defaultCenter] postNotificationName:kNoConnectionNotification object:nil];
    }
}

/*!
 * Called by Reachability whenever status changes.
 */
- (void)reachabilityChanged:(NSNotification *)note
{
	Reachability* curReach = [note object];
	NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
    NetworkStatus netStatus = [curReach currentReachabilityStatus];
    __weak Client *wself = self;
    switch (netStatus)
    {
        case NotReachable:        {
            _session->Close();
            wself.isLogin = NO;
            break;
        }
            
        case ReachableViaWWAN:
        case ReachableViaWiFi: {
            dispatch_async(kBgQueue, ^{
                if (_session->Connect()) {
                    [wself autoLogin];
                }
            });
            break;
        }
    }
}

- (void)showNoConnection:(NSNotification *)note {
    Reachability *reach = [Reachability reachabilityWithHostName:@"www.baidu.com"];
    DDLogInfo(@"status : %d", reach.currentReachabilityStatus);
    if (reach.currentReachabilityStatus == NotReachable) {
        [[TWMessageBarManager sharedInstance] showMessageWithTitle:@"网络错误" description:@"无网络连接" type:TWMessageBarMessageTypeError];
    } else {
        [[TWMessageBarManager sharedInstance] showMessageWithTitle:@"服务器错误" description:@"无法连接至服务器" type:TWMessageBarMessageTypeError];
    }
    
}

@end
