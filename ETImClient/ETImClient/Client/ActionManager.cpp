//
//  ActionManager.cpp
//  ETImServer
//
//  Created by Ethan on 14/7/30.
//  Copyright (c) 2014年 Pingan. All rights reserved.
//

#include "ActionManager.h"
#include "Logging.h"
#include "Session.h"
#include "Register.h"
#include "Login.h"
#include "HeartBeat.h"
#include "SendMsg.h"
#include "AddBuddy.h"
#include "SwitchStatus.h"
#include "RetrieveBuddy.h"
#include "Unread.h"
#include "InStream.h"

#include <assert.h>

using namespace etim::action;
using namespace etim;
using namespace etim::pub;

ActionManager::ActionManager()
{
	actions_[CMD_REGISTER] = new Register;
	actions_[CMD_LOGIN] = new Login;
    actions_[CMD_LOGOUT]  = new Logout;
	actions_[CMD_HEART_BEAT] = new HeartBeat;
	actions_[CMD_SEND_MSG] = new SendMsg;
	actions_[CMD_REQUEST_ADD_BUDDY] = new RequestAddBuddy;
	actions_[CMD_SWITCH_STATUS] = new SwitchStatus;
	actions_[CMD_RETRIEVE_BUDDY_LIST] = new RetrieveBuddyList;
	actions_[CMD_SEARCH_BUDDY] = new SearchBuddy;
    actions_[CMD_RETRIEVE_UNREAD_MSG] = new RetrieveUnreadMsg;
    actions_[CMD_RETRIEVE_BUDDY_REQUEST] =  new RetrieveBuddyRequest;
    actions_[CMD_UNREAD] =  new Unread;
}

ActionManager::~ActionManager()
{
    typedef std::map<uint16_t, action::Action *>::iterator mapActIt;
	for (mapActIt it = actions_.begin(); it != actions_.end(); ++it) {
        delete it->second;
	}
}

bool ActionManager::SendPacket(Session &s)
{
    //TODO 处理异常
	uint16_t cmd = s.GetSendCmd();
	if (actions_.find(cmd) != actions_.end()) {
		actions_[cmd]->DoSend(s);
		return true;
	}
    
    LOG_FATAL<<"没有对应的命令处理类";
    return false;
}

bool ActionManager::RecvPacket(Session &s)
{
    s.Recv();	// 接收应答包
    uint16 cmd;
    cmd = s.GetResponsePack()->head.cmd;
    
	if (actions_.find(cmd) != actions_.end()) {
		actions_[cmd]->DoRecv(s);
		return true;
	}
    
    LOG_FATAL<<"没有对应的命令处理类";
    return false;
}
