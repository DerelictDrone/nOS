-- held = -1
-- keyup = 0.5

local function parseKeyEvent(n)
	if n < 0 then
		return "key",math.floor(n)*-1,true
	end
	if math.floor(n)-n ~= 0 then
		return "key_up",math.floor(n)
	end
	return "key",n,false
end

local mouse_events = {
	d = "mouse_drag",
	s = "mouse_scroll",
	c = "mouse_click",
	u = "mouse_up",
}

local pullEventRaw = os.pullEventRaw
local pullEvent = os.pullEvent


-- parallel doesn't support multiple filters which I need for this to work so bwuh

local function waitForAny(...)
	local args = table.pack(...)
	local coroutines = {}
	local eventListeners = {}
	for _,i in ipairs(args) do
		table.insert(coroutines,coroutine.create(i))
		table.insert(eventListeners,{"NOS_no_filter"})
	end
	local lastEvent = {}
	while(true) do
		for ind,i in ipairs(coroutines) do
			local eventFound = false
			if eventListeners[ind] then
				eventFound = false
				for _,event in ipairs(eventListeners[ind]) do
					if event == lastEvent[1] or event == "NOS_no_filter" then
						eventFound = true
						break
					end
				end
			end
			local eventReq
			if eventFound then
				eventReq = table.pack(coroutine.resume(i,table.unpack(lastEvent,1,lastEvent.n)))
			end
			if coroutine.status(i) == "dead" then
				return ind
			end
			if eventFound then
				if eventReq and eventReq[2] then
					table.remove(eventReq,1)
					eventReq.n = nil
					eventListeners[ind] = eventReq
				else
					eventListeners[ind] = {"NOS_no_filter"}
				end
			end
		end
		lastEvent = table.pack(coroutine.yield())
	end
end

local function stdMouse(env,program,args)
	if env.io then
		program.pipes[4], program.pipes_ext[4] = env.io.createPipePair()
		env.io.stdmouse = program.pipes[4]
	end
end

local function pullEventReplacer(env,program,args)
	-- nondestructive, returns key or char event depending on first incoming
	local newOS = {}
	local function pullStdin()
		while(true) do
			local peeked = io.stdin._handle.peek(1)
			if peeked then
				if type(peeked) == "number" then
					io.stdin._handle.seek(1)
					return parseKeyEvent(peeked)
				end
				if type(peeked) == "string" then
					return "char",io.stdin:read(1)
				end
			else
				peeked = io.stdmouse._handle.peek(1)
				if peeked and io.stdmouse._handle.length() > 3 then
					if type(peeked) == "string" then
						local x = io.stdmouse._handle.peek(2)
						local y = io.stdmouse._handle.peek(3)
						local z = io.stdmouse._handle.peek(4)
						io.stdmouse._handle.seek(4)
						if mouse_events[peeked] then
							return mouse_events[peeked],x,y,z
						end
					else
						local seekpoint = 1
						for i=1,math.min(100,io.stdmouse._handle.length()) do
							if type(io.stdmouse._handle.peek()) ~= "string" then
								seekpoint = i
							else
								break
							end
						end
						io.stdmouse._handle.seek(seekpoint)
					end
				end
				coroutine.yield()
			end
		end
	end

	-- destructive, returns only first key event skipping any char events
	local function pullKeyStdin()
		while(true) do
			local peeked = io.stdin._handle.peek(1)
			if peeked then
				if type(peeked) == "number" then
					io.stdin._handle.seek(1)
					local e = table.pack(parseKeyEvent(peeked))
					if e[1] == "key" then
						return table.unpack(e,1,e.n)
					end
				else
					io.stdin._handle.seek(1)
				end
			else
				coroutine.yield()
			end
		end
	end

	-- destructive, returns only first key event skipping any char events
	local function pullKeyUpStdin()
		while(true) do
			local peeked = io.stdin._handle.peek(1)
			if peeked then
				if type(peeked) == "number" then
					io.stdin._handle.seek(1)
					local e = table.pack(parseKeyEvent(peeked))
					if e[1] == "key_up" then
						return table.unpack(e,1,e.n)
					end
				else
					io.stdin._handle.seek(1)
				end
			else
				coroutine.yield()
			end
		end
	end
	-- destructive, returns only first char event skipping any key events
	local function pullCharStdin()
		while(true) do
			local peeked = io.stdin._handle.peek(1)
			if peeked then
				if type(peeked) == "string" then
					io.stdin._handle.seek(1)
					return "char",peeked
				else
					io.stdin._handle.seek(1)
				end
			else
				coroutine.yield()
			end
		end
	end

	-- destructive, returns only first mouse_up event skipping any other mouse events
	local function pullMouse(e_code)
		local e_name = mouse_events[e_code]
		while(true) do
			local peeked = io.stdmouse._handle.peek(1)
			if peeked and io.stdmouse._handle.length() > 3 then
				if type(peeked) == "string" then
					local x = io.stdmouse._handle.peek(2)
					local y = io.stdmouse._handle.peek(3)
					local z = io.stdmouse._handle.peek(4)
					io.stdmouse._handle.seek(4)
					if mouse_events[peeked] then
						return mouse_events[peeked],x,y,z
					end
				else
					local seekpoint = 1
					for i=1,math.min(100,io.stdmouse._handle.length()) do
						if type(io.stdmouse._handle.peek()) ~= "string" then
							seekpoint = i
						else
							break
						end
					end
					io.stdmouse._handle.seek(seekpoint)
				end
			end
			coroutine.yield()
		end
	end

	local function pullMouseUp()
		return pullMouse("u")
	end
	local function pullMouseScroll()
		return pullMouse("s")
	end
	local function pullMouseClick()
		return pullMouse("c")
	end
	local function pullMouseDrag()
		return pullMouse("d")
	end

	local pullTable = {
		["char"] = pullCharStdin,
		["key"] = pullKeyStdin,
		["key_up"] = pullKeyUpStdin,
		["mouse_up"] = pullMouseUp,
		["mouse_scroll"] = pullMouseScroll,
		["mouse_click"] = pullMouseClick,
		["mouse_drag"] = pullMouseDrag,
	}

-- versions that will parallel between pullEvent and a stdin read
	function newOS.pullEvent(...)
		local args = table.pack(...)
		local event = args[1]
		local pullChoice = pullStdin
		if event then
			pullChoice = pullTable[event]
		end
		if not io.stdin or not pullChoice then
			return pullEvent(...)
		end
		local returner = {}
		local who = waitForAny(
		function() returner = table.pack(pullEventRaw("terminate")) end,
		function() returner = table.pack(pullChoice()) end,
		function() returner = table.pack(pullEvent(table.unpack(args,1,args.n))) end
		)
		if who == 1 and returner[1] == "terminate" then
			error("Terminated", 0)
		end
		return table.unpack(returner)
	end

	function newOS.pullEventRaw(...)
		local args = table.pack(...)
		local event = args[1]
		local pullChoice = pullStdin
		if event then
			pullChoice = pullTable[event]
		end
		if not io.stdin or not pullChoice then
			return pullEventRaw(...)
		end
		local returner = {}
		local who = waitForAny(
		function() returner = table.pack(pullChoice()) end,
		function() returner = table.pack(pullEventRaw(table.unpack(args,1,args.n))) end
		)
		return table.unpack(returner)
	end
	env.os = setmetatable(newOS,createProxyTable({env.os or os}))
	setfenv(newOS.pullEvent,env)
	setfenv(newOS.pullEventRaw,env)
	setfenv(pullStdin,env)
	setfenv(pullKeyStdin,env)
	setfenv(pullKeyUpStdin,env)
	setfenv(pullCharStdin,env)
	setfenv(pullMouse,env)
end

addEnvPatch(stdMouse)
addEnvPatch(pullEventReplacer)
