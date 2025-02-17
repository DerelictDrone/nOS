if peripheral.remotelib then
	error("Peripheral extension loaded twice.")
end

local lperipheral = peripheral
local rperipheral = {
	serverport = 38242,
	clientport = 38241,
	operations = {}, -- peripheral protocols
	whitelist = {}, -- keys are whitelisted events, set them to any truthy value to pass
}
local rperipherals = {}
local rperipherals_by_host = {}
local rperipherals_by_type = {}
local peripheral = {
	remotelib = rperipheral,
	locallib = lperipheral
}

local function Periphery(env, program, args)
	env.peripheral = {
		localonly = true,
	}
	local pmeta = {
		__index = function(self,ind)
			if rawget(self,"localonly") then return lperipheral[ind] end
			if rperipheral[ind] ~= nil then return rperipheral[ind] end
			if peripheral[ind] ~= nil then return peripheral[ind] end
			if lperipheral[ind] ~= nil then return lperipheral[ind] end
			return nil
		end,
		__metatable = {},
		__pairs = function(self)
			local rkey,lkey,pkey,v 
			local localonly = rawget(self,"localonly")
			local rfirst,lfirst,pfirst = not localonly,true,not localonly
			return function()
				if rkey or rfirst then
					rkey,v = next(rperipheral,rkey)
					rfirst = false
					if rkey then
					return rkey,v
					end
				end
				if lkey or lfirst then
					lkey,v = next(lperipheral,lkey)
					lfirst = false
					if lkey then
					return lkey,v
					end
				end
				if pkey or pfirst then
					pkey,v = next(peripheral,pkey)
					pfirst = false
					if pkey then
					return pkey,v
					end
				end
			end
		end
	}
	setmetatable(env.peripheral,pmeta)
end

local function timeout(time,fn,...)
	local timedout = false
	local retvalue = {}
	local args = table.pack(...)
	parallel.waitForAny(
		function() retvalue = table.pack(fn(table.unpack(args,1,args.n))) end,
		function() sleep(time) timedout = true end
	)
	if timedout then
		return
	end
	return table.unpack(retvalue,1,retvalue.n)
end

local function callMethod(net_name,peripheral_name,method,timeout_time,retries,...)
	rperipheral.router:sendUDP(net_name,rperipheral.serverport,rperipheral.clientport,
		{
			peripheral = {
				name = peripheral_name,
				method = method,
				args = table.pack(...),
			},
			broadcast = net_name == "*" or nil
		}
	,32)
	retries = 0
	local x
	for i=retries,0,-1 do
		x = table.pack(timeout(timeout_time or 5,function()
			return os.pullEvent("periphery_"..method)
		end))
		if #x == 0 then break end
	end
	return table.unpack(x,2)
end

function rperipheral.ping(host,type)
	if not type then
		return callMethod(host,nil,"getNames",0.25)
	end
	return callMethod(host,nil,"find",0.25,type)
end


function rperipheral:setRouter(router)
	self.router = router
end

function rperipheral.createRemotePeripheral(host,name,meta)
	if not meta.types then
		meta.types = {"?"}
	end
	if rperipherals[host.."_"..name] then
		-- update instead
		local periph_obj = rperipherals[host.."_"..name]
		local periph = getmetatable(periph_obj)
		for _,type in ipairs(periph.types) do
			rperipherals_by_type[type][host.."_"..name] = nil
			if not next(rperipherals_by_type[type]) then -- quick len checker
				rperipherals_by_type[type] = nil
			end
		end
		periph.types = meta.types or periph.types
		periph.type = meta.types[1] or periph.type
		local newmeta
		if meta.methods then
			newmeta = setmetatable(meta.methods,periph)
			rperipherals[host.."_"..name] = newmeta
		end
		newmeta = newmeta or setmetatable({},periph)
		for _,type in ipairs(periph.types) do
			if not rperipherals_by_type[type] then rperipherals_by_type[type] = {} end
			rperipherals_by_type[type][host.."_"..name] = newmeta
		end
		return
	end
	meta.host = host
	meta.name = name
	meta.type = meta.types[1] or "?"
	local metatable = {
		__name = "peripheral",
		name = host.."_"..name,
		host = host,
		rname = name,
		type = meta.type,
		types = meta.types
	}
	local meta = setmetatable(meta.methods or {},metatable)
	rperipherals[host.."_"..name] = meta
	if not rperipherals_by_host[host] then rperipherals_by_host[host] = {} end
	rperipherals_by_host[host][name] = meta
	if not rperipherals_by_type[metatable.type] then rperipherals_by_type[metatable.type] = {} end
	for ind,type in ipairs(metatable.types) do
		rperipherals_by_type[type][host.."_"..name] = meta
	end
end

function rperipheral.removeRemotePeripheral(name)
	local periph = rperipherals[name]
	local meta = getmetatable(periph)
	rperipherals[name] = nil
	rperipherals_by_host[meta.host][meta.rname] = nil
	for _,type in ipairs(meta.types) do
		rperipherals_by_type[i][name] = nil
	end
end

function rperipheral.subscribe(name,reason,exclusive)
	if not rperipherals[name] then
		return false,"not yet discovered"
	end
	local meta = getmetatable(rperipherals[name])
	if callMethod(meta.host,meta.rname,"subscribe",0.25,0,reason or "",exclusive) then
		rperipheral.router:expectKeepAlivesFrom(meta.host,name..rperipheral.router.name..(reason or ""))
		return true
	else
		return false,"timed out"
	end
end

function rperipheral.dump_remote()
	return rperipherals,rperipherals_by_host,rperipherals_by_type
end

function peripheral.call(name,...)
	if rperipherals[name] then
		local meta = getmetatable(rperipherals[name])
		local t = table.pack(callMethod(meta.host,meta.rname,"call",0.25,0,...))
		return table.unpack(t,1,t.n-2)
	end
	return lperipheral.call(name,...)
end
function peripheral.find(type,fn,...)
	local rem = {}
	rperipheral.ping("*",type)
	rem = rperipherals_by_type[type]
	local loc = table.pack(lperipheral.find(type))
	local final = {}
	if not fn then
		fn = function() return true end
	end
	if rem then
		for k,_ in pairs(rem) do
			local p = peripheral.wrap(k)
			if(fn(p.name,p,true)) then
				table.insert(final,p)
			end
		end
	end
	if loc then
		for _,p in ipairs(loc) do
			if(fn(p.name,p,false)) then
				table.insert(final,p)
			end
		end
	end
	return table.unpack(final)
end
function peripheral.getMethods(name,...)
	if rperipherals[name] then
		local final = {}
		for _,v in pairs(rperipherals[name]) do
			table.insert(final,v)
		end
		if #final == 0 then
			local m = getmetatable(rperipherals[name])
			callMethod(m.host,m.rname,"getMethods",0.25)
			if #rperipherals[name] > 0 then
				return peripheral.getMethods(name,...)
			end
		end
		return final
	end
	return lperipheral.getMethods(name,...)
end
function peripheral.getName(periph,...)
	return lperipheral.getName(periph,...)
end
function peripheral.getNames(...)
	local final = {table.unpack(lperipheral.getNames(...))}
	rperipheral.ping("*")
	for k,_ in pairs(rperipherals) do
		table.insert(final,k)
	end
	return final
end
function peripheral.getType(name,...)
	if rperipherals[name] then
		local m = getmetatable(rperipherals[name])
		if not m.types or m.types[1] == "?" then
			local ret = callMethod(m.host,m.rname,"getType",0.25)
			return table.unpack(ret or {"?"})
		end
		return table.unpack(m.types)
	end
	return lperipheral.getType(name,...)
end
function peripheral.hasType(name,type,...)
	if rperipherals[name] then
		local rperiphmeta = getmetatable(rperipherals[name])
		return rperiphmeta.types[name] or false
	end
	return lperipheral.hasType(name,type,...)
end
function peripheral.isPresent(name,...)
	if rperipherals[name] then
		return true
	end
	return lperipheral.isPresent(name,...)
end
function peripheral.wrap(name,...)
	if rperipherals[name] then
		local periph = rperipherals[name]
		if #periph == 0 then
			local methods = peripheral.getMethods(name)
			if not methods or #methods == 0 then
				return nil
			else
				return peripheral.wrap(name,...)
			end
		end
		local newWrap = {}
		setmetatable(newWrap,getmetatable(periph))
		for k,v in pairs(periph) do
			newWrap[v] = function(...)
				return peripheral.call(name,v,...)
			end
		end
		return newWrap
	end
	return lperipheral.wrap(name,...)
end

addEnvPatch(Periphery)