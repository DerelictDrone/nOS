peripheral.localonly = false
local remotelib = peripheral.remotelib
local operations = peripheral.remotelib.operations
local locallib = peripheral.locallib

local subscriptions = {

}

function remotelib.dumpSubscriptions()
	return subscriptions
end 

local function callMethod(net_name,peripheral_name,method,...)
	remotelib.router:sendUDP(net_name,remotelib.serverport,remotelib.clientport,
		{
			peripheral = {
				name = peripheral_name,
				method = method,
				args = table.pack(...),
			},
			broadcast = net_name == "*" or nil
		}
	,32)
end

remotelib:setRouter(os.router)

local function reply(m,name,fn_name,...)
	remotelib.router:sendUDP(m.sender,32767,32767,{
		peripheral = {
			reply = fn_name,
			name = name,
			data = table.pack(...)
		}
	},32)
end

function operations.subscribe(m,periph,name)
	reply(m,periph,"subscribe",true)
	os.router:sendKeepAlivesTo(m.sender,m.sender.."_"..periph..((name and "#"..name) or ""))
	if not subscriptions[periph] then
		subscriptions[periph] = {}
	end
	subscriptions[periph][m.sender] = {exclusive = m.payload.peripheral.args[1] or false}
end

function operations.event(m,periph)
	-- do what is needed
	local peripheral = m.payload.peripheral
	table.insert(peripheral.args,m.sender.."_"..periph)
	peripheral.args.n = peripheral.args.n + 1
	os.queueEvent(table.unpack(peripheral.args))
end

function operations.call(m,periph,...)
	reply(m,periph,"call",locallib.call(periph,...))
end

function operations.getType(m,periph) 
	reply(m,periph,"getType",table.pack(locallib.getType(periph)))
end

function operations.getMethods(m,periph)
	reply(m,periph,"getMethods",locallib.getMethods(periph))
end

function operations.getNames(m,periph)
	reply(m,periph,"getNames",locallib.getNames())
end

function operations.find(m,periph,...)
	local t = table.pack(locallib.find(...))
	local result = {}
	for ind,i in ipairs(t) do
		local meta = getmetatable(i)
		local methods = {}
		result[meta.name] = {
			types = meta.types,
			methods = methods
		}
		for k,_ in pairs(i) do
			table.insert(methods,k)
		end
	end
	reply(m,periph,"find",result)
end

local function main()
	while(true) do
		::retry::
		local e,m,d = os.pullEvent("router_udp")
		local payload = m.payload
		if not payload.peripheral or (m.receiver ~= remotelib.router.name and m.receiver ~= "*") then
			goto retry
		end
		local periph = payload.peripheral
		if periph.method then
			local fn = operations[periph.method]
			if fn then
				fn(m,periph.name,table.unpack(periph.args))
			end
		elseif periph.reply then
			-- Table.unpack doesn't unpack more than 1 value unless it is the last passed value, hence this code :(
			table.insert(periph.data,periph.name)
			table.insert(periph.data,m.sender)
			periph.data.n = periph.data.n + 2
			os.queueEvent("periphery_"..periph.reply,table.unpack(periph.data,1,periph.data.n))
		end
	end
end

local periphery_events = {
	periphery_getNames = function(peripheral)
		for k,v in pairs(peripheral[2]) do
			remotelib.createRemotePeripheral(peripheral[peripheral.n],v,{})
		end
	end,
	periphery_find = function(peripheral)
		for k,v in pairs(peripheral[2]) do
			remotelib.createRemotePeripheral(peripheral[peripheral.n],k,v)
		end
	end,
	periphery_getMethods = function(peripheral)
		remotelib.createRemotePeripheral(peripheral[peripheral.n],peripheral[peripheral.n-1],{methods = peripheral[2]})
	end,
	periphery_getType = function(peripheral)
		remotelib.createRemotePeripheral(peripheral[peripheral.n],peripheral[peripheral.n-1],{types = {table.unpack(peripheral[2])}})
	end,
}

local function rperipheral_registrar()
	while(true) do
		local t = table.pack(os.pullEvent())
		if t[1] and periphery_events[t[1]] then
			remotelib.pass = t
			periphery_events[t[1]](t)
		end
	end
end

local function rperipheral_event_sender()
	while(true) do
		::retry_event::
		local e = table.pack(os.pullEvent())
		local subscription_list = subscriptions[e[e.n]]
		if not subscription_list then goto retry_event end
		for k,v in pairs(subscription_list) do
			callMethod(k,e[e.n],"event",table.unpack(e,1,e.n-1))
		end
	end
end

local function rperipheral_timeouts()
	while(true) do
		local e,host,identifier = os.pullEvent("router_keepalive_timeout")
		-- separated into two steps to prevent hosts named with # from messing with this
		local periph = identifier:sub(#host+2)
		periph = periph:sub(1,#periph-#periph:match("#.*"))
		subscriptions[periph][host] = nil
	end
end

parallel.waitForAny(rperipheral_registrar,rperipheral_event_sender,rperipheral_timeouts,main)
