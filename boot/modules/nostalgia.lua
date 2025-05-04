-- nostalgia window & keypress management for top level shells
-- we may have to hook or fork stdout pipes, and maybe change write()
-- globally as well


local hotkeys = {}

local function registerHotkey(keycode,fn,force,noreplace)
	if hotkeys[keycode] then
		if hotkeys[keycode].noreplace then
			return false,"This keycode cannot be hooked (hook is noreplace)",hotkeys[keycode].pid
		end
		if not force then
			return false,"Keycode is already registered, by process "..hotkeys[keycode].pid.." use force if you must replace this",hotkeys[keycode].pid
		end
	end
	local me = os.getPid()
	hotkeys[keycode] = {
		fn=fn,
		pid=os.getPid()
	}
	return true
end

function io.registerHotkey(keycode,fn,force)
	return registerHotkey(keycode,fn,force)
end

local blacklistEvent,whitelistEvent = nOSModule.blacklistEvent,nOSModule.whitelistEvent
local addEnvPatch = nOSModule.addEnvPatch

blacklistEvent("terminate")
blacklistEvent("paste")
blacklistEvent("file_transfer")

local installed_drivers = {}

-- driver struct
--[[
	driver = {
		events = event_struct[],
		peripheralTypes = []
	}
]]

-- event struct
--[[
	name = string,
	processor = function(event_args),
	pNameIndex = n -- which parameter to check for peripheral name
]]

local driverEventRefs = {}

local function installDriver(name,driver,dontReplace)
	if type(name) ~= "string" then
		error("type(name) ~= string, got ("..type(name)..")",2)
	end
	if type(driver) ~= "table" then
		error("type(driver) ~= table, got ("..type(driver)..")",2)
	end
	if installed_drivers[name] then
		return nil,"Driver already installed"
	end
	for name,_ in pairs(driver.events) do
		if not driverEventRefs[name] then
			driverEventRefs[name] = {}
		end
		table.insert(driverEventRefs[name],driver)
		blacklistEvent(name)
	end
	local newEvents = {}
	for k,v in pairs(driver.events) do
		newEvents[k] = v
	end
	local description
	if type(driver.description) == "string" then
		description = driver.description
	end
	installed_drivers[name] = {
		events = newEvents,
		users = {},
		requireFocus = driver.requireFocus and true or nil,
		peripheralTypes = driver.peripheralTypes,
		dontReplace = dontReplace,
		description = description or "No description provided."
	}
	return true
end

local function uninstallDriver(name)
	if not installed_drivers[name] then
		return nil,"No driver installed by this name"
	end
	if installed_drivers[name].dontReplace then
		return false,"Driver cannot be removed"
	end
	local driver = installed_drivers[name]
	for event,_ in pairs(driver.events) do
		for ind,d in ipairs(driverEventRefs[event]) do
			if d == driver then
				table.remove(driverEventRefs[event],d)
				if #driverEventRefs[event] == 0 then
					driverEventRefs[event] = nil
					whitelistEvent(event)
				end
				break
			end
		end
	end
	return true
end

local driverExitMeta = {
	__call = function (self)
		return self.fn()
	end
}
local function internalRemoveDriver(program,name,exit)
	local d = program.drivers[name]
	if not d then return false end
	program.drivers[name] = nil
	for ind,user in ipairs(d.users) do
		if user == program then
		table.remove(d.users,ind)
		end
	end
	if not exit then
		for ind,i in ipairs(program.onExit) do
			if type(i) == "table" then
				if i.fn and i.name == name then
					table.remove(program.onExit,ind)
					return true
				end
			end
		end
	end
	return true
end

local function internalUseDriver(program,name)
	local dtable = installed_drivers[name]
	if not dtable then
		return false
	end
	program.drivers[name] = dtable
	table.insert(dtable.users,program)
	table.insert(program.onExit,setmetatable({
		fn = function() internalRemoveDriver(program,name) end,
		name = name
	},driverExitMeta))
	return true
end

local function getDriverInfo(name)
	local driver = {}
	local pdriver = installed_drivers[name]
	if not pdriver then
		return nil
	end
	driver.events = {}
	driver.requireFocus = pdriver.requireFocus and true or false
	driver.description = pdriver.description
	driver.doNotReplace = pdriver.doNotReplace
	for k,_ in pairs(pdriver.events) do
		table.insert(driver.events,k)
	end
	driver.peripheralTypes = {}
	for _,v in ipairs(pdriver.peripheralTypes) do
		table.insert(driver.peripheralTypes,v)
	end
	return driver
end

-- drivers installed on system
local function getInstalledDrivers()
	local drivers = {}
	for k,v in pairs(installed_drivers) do
		drivers[k] = getDriverInfo(k)
	end
	return drivers
end

-- drivers used by program
local function internalGetUsedDrivers(program)
	local drivers = {}
	for k,v in pairs(program.drivers) do
		drivers[k] = getDriverInfo(k)
	end
	return drivers
end


local function NOS_LL_key(key,held)
	if hotkeys[key] then
		-- they'll pass us true if they want us to receive this
		if not hotkeys[key].fn(held,false) then return end
	end
	if held then
		return 2,key*-1
	else
		return 2,key
	end
end

local function NOS_LL_key_up(key)
	if hotkeys[key] then
		if not hotkeys[key].fn(false,true) then return end
	end
	return 2,key+0.5
end

local function NOS_LL_char(char)
	return 2,char
end

installDriver("os_keyboard",{
	events = {
		key = {
			processor = NOS_LL_key,
			pNameIndex = 0, -- none
		},
		key_up = {
			processor = NOS_LL_key_up,
			pNameIndex = 0,
		},
		char = {
			processor = NOS_LL_char,
			pNameIndex = 0,
		},
	},
	requireFocus = true,
	peripheralTypes = {},
	description = "Writes keyboard events to the program's io.stdin while it is focused. As long as it is using said driver."
})

local xmod = 0
local ymod = -1
local program_positions = {}
local program_bar_dirty = false
local programs,pidRefs = nOSModule.getRawPrograms()

local myProgram = pidRefs[os.getPid()]

local lterm = term

local function crashScreen()
	lterm.setCursorPos(1,1)
	lterm.setCursorBlink(false)
	lterm.setTextColor(colors.white)
	lterm.setBackgroundColor(colors.blue)
	lterm.clear()
	print("NOSTALGIA HAS CRASHED")
	local c = true
	local sX,sY = term.getSize()
	while c do
		c = myProgram.pipes_ext[3]._handle.read(1)
		if lterm.getCursorPos() >= sX then
			local x,y = term.getCursorPos()
			if y >= sY then
				lterm.scroll(1)
				lterm.setCursorPos(1,y)
			else
				lterm.setCursorPos(1,y+1)
			end
		end
		if c then
			lterm.write(c)
		end
		sleep() -- aesthetic effect
	end
	print("\nREBOOTING PC IN 5 SECONDS")
	sleep(5)
	os.reboot()
end

table.insert(myProgram.onExit,crashScreen)

local currentProcess = 0 -- no starter
local switchlocked = false

local function switchWindow(pid)
	local curp = pidRefs[currentProcess]
	if curp and curp.window then
		curp.window.setVisible(false)
		lterm.clear()
	end
	local newp = pidRefs[pid]
	currentProcess = pid
	if newp and newp.window then
		newp.window.setVisible(true)
	end
	program_bar_dirty = true
	return newp
end

local function NOS_LL_mouse_drag(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"d",m,(x+xmod),(y+ymod)
end

local function NOS_LL_mouse_scroll(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"s",m,(x+xmod),(y+ymod)
end

local function NOS_LL_mouse_click(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then
		if m ~= 1 then
			return
		end
		for ind,i in ipairs(program_positions) do
			if x > i[2] and x < i[4] then
				switchWindow(i[1])
			end
		end
	end
	return 4,"c",m,(x+xmod),(y+ymod)
end

local function NOS_LL_mouse_up(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"u",m,(x+xmod),(y+ymod)
end

installDriver("os_mouse",{
	events = {
		mouse_drag = {
			processor = NOS_LL_mouse_drag,
			pNameIndex = 0, -- none
		},
		mouse_scroll = {
			processor = NOS_LL_mouse_scroll,
			pNameIndex = 0,
		},
		mouse_click = {
			processor = NOS_LL_mouse_click,
			pNameIndex = 0,
		},
		mouse_up = {
			processor = NOS_LL_mouse_up,
			pNameIndex = 0,
		},
	},
	requireFocus = true,
	peripheralTypes = {},
	description = "Writes mouse events to the program's io.stdmouse while it is focused. Will translate Y to account for the program bar."
})

local processors = {}

local function generateBiosFuncCopies()
	local env = setmetatable({},{__index=_G})
	loadfile(fs.combine(nOSModule.osPath,"CraftOS.lua"),nil,env)()
	setmetatable(env,nil)
	return env
end

-- an implementation of multishell for compatibility with multishell using programs
local multishellImplementation = {}

local function windowizer(env,program,args)
	local x,y = lterm.getSize()
	local newterm = window.create(term.current(),1,2,x,y-1,false)
	local curterm = newterm
	local exposedterm = setmetatable({},createProxyTable({newterm}))
	function exposedterm.native()
		return newterm
	end
	function exposedterm.current()
		return curterm
	end
	function exposedterm.redirect(termobj)
		local oldterm = curterm
		setmetatable(exposedterm,createProxyTable({termobj}))
		return oldterm
	end
	newterm.native = exposedterm.native
	newterm.current = exposedterm.current
	newterm.redirect = exposedterm.redirect
	local function writeToStdout(...)
		return io.stdout:write(...)
	end
	program.window = setmetatable({setVisible = newterm.setVisible, reposition = newterm.reposition},{__index = newterm})
	newterm.setVisible = nil
	newterm.reposition = nil
	if env.io then
		env.io.write = writeToStdout
	end

	local biosCopies = generateBiosFuncCopies(env)
	env.read = env.read or setfenv(biosCopies.read,env)
	env.write = setfenv(biosCopies.write,env)
	env.print = setfenv(biosCopies.print,env)
	local olderr = error
	local function err(msg,ctx)
		io.stderr:write(tostring(msg))
		if ctx == 0 then
			return olderr(msg,0)
		end
		olderr(msg,ctx+2)
	end
	env.error = err
	local function pcall2(...)
		env.error = olderr
		env.pcall = pcall
		local ret = table.pack(pcall(...))
		env.pcall = pcall2
		env.error = err
		return table.unpack(ret)
	end

	env.pcall = pcall2

	function env.printError(...)
		for ind,i in ipairs(table.pack(...)) do
			io.stderr:write((ind > 1 and " " or "")..tostring(i))
		end
		do -- old printError
			local oldColour
			if term.isColour() then
				oldColour = term.getTextColour()
				term.setTextColour(colors.red)
			end
			print(...)
			if term.isColour() then
				term.setTextColour(oldColour)
			end
		end
		io.stderr:write("\n")
	end
	setfenv(env.error,env)
	setfenv(env.printError,env)

	-- install keyboard driver
	program.drivers = {}
	internalUseDriver(program,"os_keyboard")
	internalUseDriver(program,"os_mouse")
	function env.os.installDriver(sName,tDriver)
		return installDriver(sName,tDriver)
	end
	function env.os.uninstallDriver(sName)
		return uninstallDriver(sName)
	end
	function env.os.useDriver(sDriver)
		return internalUseDriver(program,sDriver)
	end
	function env.os.removeDriver(sDriver)
		return internalRemoveDriver(program,sDriver)
	end
	function env.os.getUsedDrivers()
		return internalGetUsedDrivers(program)
	end
	function env.os.getInstalledDrivers()
		return getInstalledDrivers()
	end
	-- terminal command structure
	-- 0(n) fn_ind(n) params
	-- if length of stdout < fn_ind's needed params
	-- just give up and do a :read() print
	-- Any functions that serve to return stuff are going to be left alone
	-- clear (0 args)
	-- blit (1 char each call though) (3 chars)
	-- setCursorPos (2 ints)
	-- setTextColor (1 int)
	-- setBackgroundColor (1 int)
	-- scroll (1 int)
	-- setCursorBlink(1 int, 0 falsy)
	-- 1 = fn 2 = arg count
	local nclear = newterm.clear
	local nblit = newterm.blit
	local nsetCursorPos = newterm.setCursorPos
	local nsetTextColor = newterm.setTextColor
	local nsetBackgroundColor = newterm.setBackgroundColor
	local nscroll = newterm.scroll
	local nsetCursorBlink = newterm.setCursorBlink
	local nclearLine = newterm.clearLine
	local interpreterFuncs = {
		{
			function()
				nclear()
			end,
			0
		},
		{
			function(a,b,c)
				nblit(a,b,c)
			end,
			3
		},
		{
			function(a,b)
				nsetCursorPos(a,b)
			end,
			2
		},
		{
			function(a)
				nsetTextColor(a)
			end,
			1
		},
		{
			function(a)
				nsetBackgroundColor(a)
			end,
			1
		},
		{
			function(a)
				nscroll(a)
			end,
			1
		},
		{
			function(a)
				nsetCursorBlink(a == 1)
			end,
			1
		},
		{
			function()
				nclearLine()
			end,
			0
		}
	}
	function newterm.clear()
		writeToStdout(0)
		writeToStdout(1)
	end
	function newterm.blit(txt,fg,bg)
		local txtExtract = string.gmatch(txt,".")
		local fgExtract  = string.gmatch(fg,".")
		local bgExtract  = string.gmatch(bg,".")
		while(true) do
			local c = txtExtract()
			if not c then break end
			writeToStdout(0)
			writeToStdout(2)
			writeToStdout(c)
			writeToStdout(fgExtract() or "0")
			writeToStdout(bgExtract() or "F")
		end
	end
	function newterm.setCursorPos(x,y)
		writeToStdout(0)
		writeToStdout(3)
		writeToStdout(x)
		writeToStdout(y)
	end
	function newterm.setTextColor(c)
		writeToStdout(0)
		writeToStdout(4)
		writeToStdout(c)
	end
	newterm.setTextColour = newterm.setTextColor
	function newterm.setBackgroundColor(c)
		writeToStdout(0)
		writeToStdout(5)
		writeToStdout(c)
	end
	newterm.setBackgroundColour = newterm.setBackgroundColor
	function newterm.scroll(y)
		writeToStdout(0)
		writeToStdout(6)
		writeToStdout(y)
	end
	function newterm.setCursorBlink(blink)
		writeToStdout(0)
		writeToStdout(7)
		writeToStdout(blink and 1 or 0)
	end
	function newterm.clearLine()
		writeToStdout(0)
		writeToStdout(8)
	end
	-- getter functions need to immediately flush all of the pipe
	-- to update the state of the terminal to current
	local handle = program.pipes_ext[1]._handle
	program.window.interpreterFuncs = interpreterFuncs
	program.window.write = newterm.write
	local nwrite = newterm.write
	newterm.write = function(d) writeToStdout(tostring(d)) end
	local function safeWrite(c)
		return nwrite(c)
	end
	local function commandInterpreter()
		if handle.length() < 2 then
			return safeWrite(handle.read(1))
		end
		local peeked = handle.peek(1)
		if peeked == 0 then
			-- command sequence
			-- check next int for index
			local fn_ind = handle.peek(2)
			if type(fn_ind) ~= "number" then
				-- bwomp bwomp
				return safeWrite(handle.read(1))
			end
			local fn = interpreterFuncs[fn_ind]
			if not fn then
				return safeWrite(handle.read(1))
			end
			if handle.length() >= fn[2]+2 then
				local args = {}
				handle.seek(2)
				for i=1,fn[2],1 do
					table.insert(args,handle.peek(1))
					handle.seek(1)
				end
				fn[1](table.unpack(args,1,fn[2]))
				return
			else
				return safeWrite(handle.read(2)) -- give up once again
			end
		else
			return safeWrite(handle.read(1))
		end
	end
	program.window.commandInterpreter = commandInterpreter
	local function flush()
		if handle.length() == 0 then
			return
		end
		while(handle.length() > 0) do
			commandInterpreter()
		end
	end
	local ngetCursorPos = newterm.getCursorPos
	local ngetCursorBlink = newterm.getCursorBlink
	local ngetTextColor = newterm.getTextColor
	local ngetBackgroundColor = newterm.getBackgroundColor
	function newterm.getCursorPos()
		flush()
		return ngetCursorPos()
	end
	function newterm.getCursorBlink()
		flush()
		return ngetCursorBlink()
	end
	function newterm.getTextColor()
		flush()
		return ngetTextColor()
	end
	newterm.getTextColour = newterm.getTextColor
	function newterm.getBackgroundColor()
		flush()
		return ngetBackgroundColor()
	end
	newterm.getBackgroundColour = newterm.getBackgroundColor
	program.window.flush = flush
	-- Hook index of term, if program tries to access it we know it wants a terminal
	-- and can give it our exposed term obj
	-- ! This in place so nostalgia can identify which windows are in the background
	-- ! If they don't use the terminal at all, we won't show them as valid windows.
	local term_installer
	local function install()
		program.window.setup = true
		term_installer = nil
		env.term = exposedterm
		program_bar_dirty = true
	end
	term_installer = setmetatable({},{
		__index = function(self,k)
			install()
			return exposedterm[k]
		end,
		__newindex = function(self,k,v)
			install()
			exposedterm[k] = v
		end,
		__pairs = function(self)
			install()
			return pairs(exposedterm)
		end,
		__metatable = false
	})
	table.insert(program.onExit,function(self)
		program_bar_dirty = true
	end)
	if env.fs.isVirtual then
		-- Mount a virtual file containing the error output
		table.insert(program.onExit,function(self)
			local err = self.pipes_ext[3]._handle
			local errorText = err.read(err.length())
			env.fs.mountGlobal(env.fs.combine("/nostalgia/errors"),{files = {[tostring(program.pid)] = errorText}})
		end)
	else
		-- Dump function to screen
		table.insert(program.onExit,function(self)
			local err = self.pipes_ext[3]._handle
			if err.length > 0 then
				print(err.read(err.length()))
			end
		end)
	end
	env.term = term_installer
	env.multishell = multishellImplementation
	setfenv(writeToStdout,env)
	setfenv(program.window.commandInterpreter,env)
end

local function appendFriendly(p,pmeta)
	pmeta.friendlyName = p.friendlyName or string.match(p.name,"[^\\/]*$")
end

addEnvPatch(windowizer)
nOSModule.addProgramMeta(appendFriendly)

function processors.NOS_LL_paste(paste)
	coroutine.resume(pidRefs[currentProcess].coroutine,"paste",paste)
end

function processors.NOS_LL_file_transfer(files)
	coroutine.resume(pidRefs[currentProcess].coroutine,"file_transfer",files)
end

function processors.NOS_LL_terminate()
	if switchlocked then
		os.kill(currentProcess)
	else
		local e = table.pack(coroutine.resume(pidRefs[currentProcess].coroutine,"terminate"))
		if coroutine.status(pidRefs[currentProcess].coroutine) ~= "dead" then
			nOSModule.clearListeners(pidRefs[currentProcess])
			for k,v in ipairs(e) do
				if type(v) ~= "string" then
					v = nil
				end
				nOSModule.addListener(pidRefs[currentProcess],v or "NOS_no_filter")
			end
		end
	end
end

local function draw_program_bar()
	local x,y = lterm.getCursorPos()
	lterm.setCursorPos(1,1)
	lterm.clearLine()
	lterm.setCursorPos(1,1)
	program_positions = {}
	if switchlocked then
		lterm.blit("Locked ","7777777","FFFFFFF")
	end
	for _,program in ipairs(programs) do
		if program.window and program.window.setup then
			local str = program.friendlyName or string.match(program.name,"[^\\/]*$")
			local beforeX,beforeY = term.getCursorPos()
			if program.pid == currentProcess then 
				lterm.blit(str,string.rep("F",#str),string.rep("0",#str))
			else
				lterm.blit(str,string.rep("0",#str),string.rep("7",#str))
			end
			table.insert(program_positions,{program.pid,beforeX,beforeY,lterm.getCursorPos()})
			lterm.write(" ")
		end
	end
	lterm.setCursorPos(x,y)
end

local dying = false

local function findNextWindowProgram()
	for _,program in ipairs(programs) do
		if program.window and program.window.setup then
			return switchWindow(program.pid)
		end
	end
	-- nothing's really going to fix this if the user has no input
	-- so we just gotta die I guess
	if not dying then
		dying = true
		print("Trying to find another available window, shutdown in")
		for i=5,0,-1 do
			print(i)
			local x = findNextWindowProgram()
			if x then dying = false return x end
			sleep(1)
		end
		if fs.flushVirtualToDisk then
			local list = fs.list(fs.combine("/nostalgia/errors"))
			if list then
				for _,file in ipairs(list) do
					fs.flushVirtualToDisk(file)
				end
			end
		end
		os.reboot()
	end
end

local function getTLCIndex(pid)
	for ind,program in ipairs(programs) do
		if program.pid == pid then
			return ind
		end
	end
	return false
end

local function nextWindow(held,up)
	if up then return end
	local index = getTLCIndex(currentProcess)
	for ind=index+1,#programs,1 do
		local program = programs[ind]
		if not program then return end
		if program.window and program.window.setup then
			return switchWindow(program.pid)
		end
	end
end

local function prevWindow(held,up)
	if up then return end
	local index = getTLCIndex(currentProcess)
	for ind=index-1,0,-1 do
		local program = programs[ind]
		if not program then return end
		if program.window and program.window.setup then
			return switchWindow(program.pid)
		end
	end
end

multishellImplementation.launch = os.spawn

function multishellImplementation.getTitle(n)
	local p = pidRefs[n]
	if p then
		return p.friendlyName or p.name
	end
	return nil
end

function multishellImplementation.setTitle(n,name)
	local p = pidRefs[n]
	if p then
		program_bar_dirty = true
		p.friendlyName = tostring(name)
	end
end

function multishellImplementation.getCount()
	return #programs
end

function multishellImplementation.getFocus()
	return currentProcess
end

function multishellImplementation.setFocus(n)
	if switchlocked then return false end
	local x = switchWindow(n)
	return x and true or false
end

multishellImplementation.getCurrent = os.getPid

local function lockAutoSwitching(held,up)
	if up then
		switchlocked = not switchlocked
	end
	program_bar_dirty = true
end
registerHotkey(keys.pageUp,prevWindow,false,true)
registerHotkey(keys.pageDown,nextWindow,false,true)
registerHotkey(keys.f1,lockAutoSwitching,false,true)

local ll_length = #"NOS_LL_ "

local function main()
	while(true) do
		local t = table.pack(os.pullEventRaw())
		local process = pidRefs[currentProcess] or findNextWindowProgram()
		local pipe = process.pipes_ext[1]
		local win = process.window
		local hl_name = string.sub(t[1] or "",ll_length)
		for _,driver in pairs(installed_drivers) do
			if not driver.events[hl_name] then goto skip_driver end
			for _,user in ipairs(driver.users) do
				if user and ((not driver.requireFocus) or (user == process)) then
					local ret = table.pack(driver.events[hl_name].processor(table.unpack(t,2,t.n)))
					if ret.n > 0 then
						local pipeID = table.remove(ret,1)
						ret.n = ret.n - 1
						for _,i in ipairs(ret) do
							user.pipes_ext[pipeID]._handle.write(i)
						end
					end
				end
			end
			::skip_driver::
		end
		if processors[t[1]] then
			local ret = table.pack(processors[t[1]](table.unpack(t,2,t.n)))
			if ret.n > 0 then
				local pipeID = table.remove(ret,1)
				ret.n = ret.n - 1
				for _,i in ipairs(ret) do
					process.pipes_ext[pipeID]:write(i)
				end
			end
		end
		if win and win.setup then
			win.flush()
		end
		if program_bar_dirty then
			draw_program_bar()
			program_bar_dirty = false
		end
	end
end

local s,e = pcall(main)
if not s then
	myProgram.pipes[3]:write(tostring(e))
	return crashScreen()
end