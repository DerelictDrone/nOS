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

local blacklistEvent = nOSModule.blacklistEvent
local addEnvPatch = nOSModule.addEnvPatch

blacklistEvent("char")
blacklistEvent("key")
blacklistEvent("key_up")
blacklistEvent("mouse_click")
blacklistEvent("mouse_drag")
blacklistEvent("mouse_scroll")
blacklistEvent("mouse_up")
blacklistEvent("terminate")

local processors = {}

function processors.NOS_LL_key(key,held)
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

function processors.NOS_LL_key_up(key)
	if hotkeys[key] then
		if not hotkeys[key].fn(false,true) then return end
	end
	return 2,key+0.5
end

function processors.NOS_LL_char(char)
	return 2,char
end

local xmod = 0
local ymod = -1

local program_positions = {}
local program_bar_dirty = false

local function generateBiosFuncCopies()
	local env = setmetatable({},{__index=_G})
	loadfile("./.os/CraftOS.lua",nil,env)()
	setmetatable(env,nil)
	return env
end

local lterm = term
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
	env.write = env.write or setfenv(biosCopies.write,env)
	env.print = env.print or setfenv(biosCopies.print,env)
	local olderr = error
	local function err(msg)
		io.stderr:write(tostring(msg))
		olderr("",0)
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

	env.pcall = pcall

	function env.printError(...)
		for ind,i in ipairs(table.pack(...)) do
			io.stderr:write((ind > 1 and " " or "")..tostring(i))
		end
		io.stderr:write("\n")
	end
	setfenv(env.error,env)
	setfenv(env.printError,env)
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
	-- a hooked version, on first call to any function will install the real version
	-- and then call the desired function
	-- ! This in place so nostalgia can identify which windows are in the background
	-- ! If they don't use the terminal at all, we won't show them as valid windows.
	local term_installer = {}
	local function install()
		program.window.setup = true
		term_installer = nil
		env.term = exposedterm
		program_bar_dirty = true
	end
	for k,v in pairs(lterm) do
		if type(v) == "function" then
			term_installer[k] = function(...)
				install()
				return newterm[k](...)
			end
		end
	end
	table.insert(program.onExit,function(self)
		program_bar_dirty = true
	end)
	if env.fs.isVirtual then
		-- Mount a virtual file containing the error output
		table.insert(program.onExit,function(self)
			local err = self.pipes_ext[3]._handle
			local errorText = err.read(err.length())
			env.fs.mountGlobal("nostalgia/errors",{files = {[tostring(program.pid)] = errorText}})
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

local programs,pidRefs = nOSModule.getRawPrograms()
local currentProcess = 0 -- no starter
local switchlocked = false

function processors.NOS_LL_terminate()
	if switchlocked then
		os.kill(currentProcess)
	else
		coroutine.resume(pidRefs[currentProcess].coroutine,"terminate")
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
			lterm.blit(" ","F","F")
		end
	end
	lterm.setCursorPos(x,y)
end

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
		os.shutdown()
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

function processors.NOS_LL_mouse_drag(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"d",m,(x+xmod),(y+ymod)
end

function processors.NOS_LL_mouse_scroll(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"s",m,(x+xmod),(y+ymod)
end

function processors.NOS_LL_mouse_click(m,x,y)
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

function processors.NOS_LL_mouse_up(m,x,y)
	if (y+ymod) == 0 or (x+xmod) == 0 then return end
	return 4,"u",m,(x+xmod),(y+ymod)
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
registerHotkey(keys.pageDown,prevWindow,false,true)
registerHotkey(keys.pageUp,nextWindow,false,true)
registerHotkey(keys["end"],lockAutoSwitching,false,true)

while(true) do
	local t = table.pack(os.pullEventRaw())
	local process = pidRefs[currentProcess] or findNextWindowProgram()
	local pipe = process.pipes_ext[1]
	local win = process.window
	if processors[t[1]] then
		local ret = table.pack(processors[t[1]](table.unpack(t,2,t.n)))
		if ret then
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