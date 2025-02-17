-- this file goes unused, it should likely get thrown in the bin at this point
local lco = coroutine
local coroutine_env = {__index=coroutine}
coroutine = setmetatable({raw = lco},coroutine_env)
_G.NOS_proxy = NOS_proxy or {}

local proxyFnMeta = {
	__name = "proxy function",
	__tostring = function (self)
		return "proxy function"
	end,
	__call = function (self,...)
		local backupenv = getfenv(self.fn)
		setfenv(self.fn,self.env)
		local ret = table.pack(self.fn(...))
		setfenv(self.fn,backupenv)
		return table.unpack(ret,1,ret.n)
	end
}

local proxyThreadMeta = {
	__name = "proxy thread",
	__tostring = function (self)
		return "proxy thread"
	end
}

function NOS_proxy.createProxy(fn,env)
	return setmetatable({
		fn = fn,
		env = env,
	},proxyFnMeta)
end

function coroutine.create(fn)
	if tostring(fn) ~= "proxy function" then
		return lco.create(fn)
	end
	return setmetatable({
		thread = lco.create(fn.fn),
		fn = fn.fn,
		env = fn.env
	},proxyThreadMeta)
end

function coroutine.status(thread)
	if tostring(thread) ~= "proxy thread" then
		return lco.status(thread)
	end
	return coroutine.status(thread.thread)
end

function coroutine.resume(thread,...)
	if tostring(thread) ~= "proxy thread" then
		return lco.resume(thread,...)
	end
	local env = getfenv(thread.fn)
	setfenv(thread.fn,thread.env)
	local ret = table.pack(lco.resume(thread.thread,...))
	return table.unpack(ret,1,ret.n)
end

function coroutine.wrap(fn)
	if tostring(fn) ~= "proxy function" then
		return lco.wrap(fn)
	end
	local thread = coroutine.create(fn)
	local function newfn(...)
		local ret = table.pack(coroutine.resume(thread,...))
		return table.unpack(ret,2,ret.n)
	end
	return newfn
end
