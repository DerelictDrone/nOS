function os.makeRoute(modemside, name)
    local router = {
        modemside = modemside,
        modem = false,
        name = name or "client_" .. os.getComputerID(),
        router_name = "",
        protocol_handlers = {},
        keepalives_expected = {},
        keepalive_targets = {},
        keepalives_tracked = 0,
        keepalive_delay = 2,
    }
    if type(modemside) == "string" then
        router.modem = peripheral.wrap(modemside)
    else
        router.modem = modemside
    end
    function router:transmit(...)
        self.modem.transmit(...)
    end
    function router:connectHost(requested_ports, mobile)
        if not mobile then
            self.modem.open(32766)
        end
        local port = mobile and 32767 or 32766
        local target
        if mobile then
            -- first things first, lets find the closest router
            local dists = {}
            self.modem.open(32767)
            self:transmit(32767,32767,{
                protocol = "PING",
                sender = self.name,
                receiver = self.name,
                payload={
                    donotrebroadcast=true,
                    loopback=true
                },
            })
            parallel.waitForAny(function ()
                while(true) do
                    local _,m,d = os.pullEvent("router_ping")
                    if m.receiver == self.name then
                        print("found "..m.sender.." dist: "..d)
                        dists[m.sender] = d
                    end
                end
            end,
            function () sleep(2) end
            )
            local closest = false
            local closestdist = 1e24
            for k,i in pairs(dists) do
                if i < closestdist then
                    closestdist = i
                    closest = k
                end
            end
            if not closest then return false,"No nearby routers" end
            target = closest
        end
        local packet = {
            protocol = "DHCP",
            sender = self.name,
            payload = {
                server = false,
                mobile = mobile and true
            }
        }
        if not mobile then
            self:transmit(port, port, packet)
            local _, m = os.pullEvent("router_dhcp")
        end
        packet.payload.ports = requested_ports
        self.router_name = target or m.sender
        packet.receiver = target or m.sender
        -- print("sending to "..target)
        self:transmit(port, port, packet)
        local m
        while(true) do
            _, m = os.pullEvent("router_dhcp")
            if m.sender == self.router_name then
                break
            end
        end
        if not mobile then
            self.modem.close(32766)
        end
        if (#m.payload.denied_ports == 0) then
            if mobile then self:expectKeepAlivesFrom(target) end
            return true,"ports were accepted",m.payload.accepted_ports,m.payload.denied_ports
        else
            return false,"some ports were denied",m.payload.accepted_ports,m.payload.denied_ports
        end
    end
    function router:sendUDP(target, outport, retport, payload, ttl)
        local packet = {
            protocol = "UDP",
            sender = self.name,
            receiver = target,
            inbport = retport,
            outport = outport,
            payload = payload,
            ttl = ttl
        }
        self:transmit(32767, 32767, packet)
    end
    function router:listen()
        while (true) do
            self.modem.open(32767)
            -- event name, side, sending channel, receiving channel, message, distance
            local e, s, sc, rc, m, d = os.pullEvent("modem_message")
            if type(m) == "table" then
                if m.protocol then
                    if m.sender ~= self.name then
                        local protocol = string.lower(m.protocol)
                        local handler = router.protocol_handlers[protocol]
                        if not handler or not handler(protocol,m,d) then
                            os.queueEvent("router_" .. protocol, m, d)
                        end
                    end
                end
            end
        end
    end
    function router.listener()
        return router.listen(router)
    end
    function router:keepAliveListen()
        while(true) do 
            local _, m = os.pullEvent("router_keepalive")
            if self.keepalives_expected[m.sender] and m.receiver == self.name then
                m.receiver = m.sender
                m.sender = self.name
                self:transmit(32767, 32767, m)
            end
        end
    end
    function router.keepAliveResponder()
        return router.keepAliveListen(router)
    end
    function router:keepAliveSend()
        local packet = {
            protocol = "KEEPALIVE",
            sender = self.name,
            payload = {
                server = true,
                identifier = "error"
            }
        }
        local removalTargets = {}
        while(true) do
            for target_name,identifiers in pairs(self.keepalive_targets) do
                for identifier,_ in pairs(identifiers) do
                    identifiers[identifier] = identifiers[identifier] + 1 -- increment timeout countdown
                    packet.payload.identifier = identifier
                    if identifiers[identifier] > 9 then
                        -- remove absentees
                        table.insert(removalTargets,{target_name,identifier})
                    else
                        self:transmit(32767,32767,packet)
                    end
                end
            end
            for _,i in ipairs(removalTargets) do
                os.queueEvent("router_keepalive_timeout",i[1],i[2])
                self:stopSendingKeepAlivesTo(i[1],i[2])
            end
            removalTargets = {}
            sleep(self.keepalive_delay)
        end
    end
    function router.keepAliveSender()
        return router.keepAliveSend(router)
    end
    function router:expectKeepAlivesFrom(netname,identifier)
        if not identifier then
            identifier = self.name.."_keepalive_"..self.keepalives_expected
            self.keepalives_expected = self.keepalives_expected + 1
        end
        if not self.keepalives_expected[netname] then
            self.keepalives_expected[netname] = {}
        end
        self.keepalives_expected[netname][identifier] = 0
        return identifier
    end
    function router:stopExpectingKeepAlivesFrom(name,identifier)
        self.keepalives_expected[name][identifier] = nil
        -- count with keyed values included
        local len = 0
        for _,_ in pairs(self.keepalive_targets[name]) do
            len = len + 1
        end
        if len == 0 then
            self.keepalive_targets[name] = nil
        end
    end
    function router:sendKeepAlivesTo(netname,identifier)
        if not identifier then
            identifier = self.name.."_keepalive_"..self.keepalives_tracked
            self.keepalives_tracked = self.keepalives_tracked + 1
        end
        if not self.keepalive_targets[netname] then
            self.keepalive_targets[netname] = {}
        end
        self.keepalive_targets[netname][identifier] = 0
        return identifier
    end
    function router:stopSendingKeepAlivesTo(name,identifier)
        self.keepalive_targets[name][identifier] = nil
        -- count with keyed values included
        local len = 0
        for _,_ in pairs(self.keepalive_targets[name]) do
            len = len + 1
        end
        if len == 0 then
            self.keepalive_targets[name] = nil
        end
    end

    -- required dependency for tcp
    if io.createPipePair then
        router.tcp = {
            connections = {}
        }
        function router.tcp:createTCPConnection(target, port, ttl)
            -- returns a read pipe and a write pipe
            -- we write to one pipe, read from the other
            -- there should be a function that manages sending the packets for us
            if self.connections[target..port] then
                return nil,"Already connected to "..target.." "..port
            end
            local intread,extwrite = io.createPipePair()
            local extread,intwrite = io.createPipePair()
            local intpipes = {read=intread, write=intwrite}
            local packet = {
                tcp = "CONNECT_CLIENT"
            }
            self.connections[target..port] = {}
            router:sendUDP(target,port,port,packet,ttl or 32)
            return extread,extwrite
        end
        function router.tcp:listenForTCP(ports)
            
        end
    end
    return router
end
