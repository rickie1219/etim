//
//  Server.h
//  ETImServer
//
//  Created by Ethan on 14/7/28.
//  Copyright (c) 2014年 Pingan. All rights reserved.
//

#ifndef __ETImServer__Server__
#define __ETImServer__Server__

#include "Singleton.h"
#include "Session.h"
#include "Socket.h"
#include <sys/select.h>
#include <unistd.h>
#include <iostream>
#include <vector>

namespace etim {

    
    ///主服务
    class Server {
        friend class pub::Singleton<Server>;
    private:
        
    public:
        
        Server();
        ~Server();

        int Start();
        void KickOut();
        Session *FindSession(int userId);
        void DeleteSession(Session *s);
    private:
        typedef std::vector<Session *>::iterator iter;
        static fd_set readFds_;
        
        int fdMax_;
        std::vector<Session *> sessions_;
        timeval lastKick_;
    };

}   //end etim


#endif /* defined(__ETImServer__Server__) */
