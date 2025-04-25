local ospath = "./.os/"

-- interface to add to this is available to spawned patches
local env_patchers = {

}

local program_meta_patchers = {

}

local function addEnvPatch(fn)
    if type(fn) ~= "function" then
        return "Has to be a function, taking (env, program, arg_table)"
    end
    table.insert(env_patchers,fn)
end

local function patchEnv(...)
    for _,i in ipairs(env_patchers) do
        i(...)
    end
end

local function addProgramMeta(fn)
    if type(fn) ~= "function" then
        return "Has to be a function, taking (program,program_meta)"
    end
    table.insert(program_meta_patchers,fn)
end

local function patchProgramMeta(program,program_meta,caller)
    for _,i in ipairs(program_meta_patchers) do
        i(program,program_meta,caller)
    end
end

-- local olderr = _G.error
-- function error(...)
--     print(...)
--     olderr(...)
-- end

function newOS()
    newOS = nil
    term.clear();
    term.setCursorPos(1,1);
    local topLevelCoroutines = {}
    local pidRefs = {}
    local eventListeners = {
        ["NOS_no_filter"] = {}
    }
    local curPid = 0
    local err = ""
    function os.version() return "NOS 1.9" end
    function os.spawn(env,filename,...)
        curPid = curPid + 1
        local program = {
                pid = curPid,
                name = filename,
                env = env,
                startTime = os.clock(),
                listeners = {"NOS_no_filter"},
                onExit = {},
            }
            env._G = env
            env._ENV = env
            local arg = table.pack(...)
            patchEnv(env,program,arg)
            program.coroutine = coroutine.create(
                function() loadfile(filename,nil,env)(table.unpack(arg)) end
                )
            pidRefs[curPid] = program
        table.insert(topLevelCoroutines,program)
        table.insert(eventListeners["NOS_no_filter"],program)
        return curPid, os.getProgram(curPid)
    end
    function os.kill(pid)
        if pidRefs[pid] then
            pidRefs[pid].dead = true
            return true
        end
        return false
    end
    local currentRunningPid = 0
    function os.getPid()
        return currentRunningPid
    end
    function os.exit()
        pidRefs[currentRunningPid].dead = true
        coroutine.yield()
    end
    function os.getPids()
        local t = {}
        for _,i in ipairs(topLevelCoroutines) do
            table.insert(t,i.pid)
        end
        return t
    end
    function os.getPrograms()
        local t = {}
        for _,i in ipairs(topLevelCoroutines) do
            table.insert(t,os.getProgram(i.pid))
        end
        return t
    end
    function os.getProgram(pid)
        local p = pidRefs[pid]
        if p then
            local programMeta = {
                    pid = p.pid,
                    name = p.name,
                    startTime = p.startTime,
            }
            patchProgramMeta(p,programMeta,pidRefs[currentRunningPid] or programMeta)
            return programMeta
        end
    end
    function os.getProgramStatus(pid)
        return pidRefs[pid] and true or false
    end
    local pullRaw = coroutine.yield
    function os.pullEventRaw(...)
        return coroutine.yield(...)
    end
    function os.pullEvent(...)
        local t = table.pack(pullRaw(...))
        if t[1] == "terminate" then
            error("Terminated", 0)
        end
        return table.unpack(t,1,t.n)
    end
    -- load patches
    local patches = fs.find(ospath.."patches/*.lua")
    _G.addEnvPatch = addEnvPatch
    _G.addProgramMeta = addProgramMeta
    for ind,i in ipairs(patches) do
        print("patching ",i)
        sleep(0.14)
        local fn,err = loadfile(i)
        if err then
            print(err)
            sleep(2)
        else
            fn()
        end
    end
    _G.addEnvPatch = nil
    _G.addProgramMeta = nil
    patches = nil
    local loadOrder = false
    local f = fs.open(ospath.."loadorder.txt","r")
    if f then
        loadOrder = textutils.unserialise(tostring(f.readAll()))
        f.close()
    end
    f = nil
    local blacklisted_events = {}
    local function blacklistEvent(event)
        blacklisted_events[event] = true
    end
    local function whitelistEvent(event)
        blacklisted_events[event] = nil
    end
    -- very very very very very very dangerous function don't give it to children
    local function getRawPrograms()
        return topLevelCoroutines,pidRefs
    end
    local function clearListeners(program)
        -- remove pre-existing listeners before adding new ones
        for _,listener in ipairs(program.listeners) do
            local found = false
            for ind,process in ipairs(eventListeners[listener]) do
                if process == program then
                    table.remove(eventListeners[listener],ind)
                    found = true
                    break
                end
            end
        end
        program.listeners = {}
    end
    local function addListener(program,event)
        if type(event) == "string" then
            if not eventListeners[event] then
                eventListeners[event] = {}
            end
            table.insert(program.listeners,event)
            table.insert(eventListeners[event],program)
        end
    end
    local lastEvent = {}
    -- If a program blacklists an event it'll start showing up as
    -- NOS_LL_$event instead which must be listened for separately
    -- you can pass them back out to programs by queueing the event but with
    -- "NOS_PASS" as first arg
    local deadProcessCount = 0
    local deadProcesses = {}
    local skipCurrentEvent = false
    local function runSet(eventListenerSet)
        if not eventListenerSet then return end
        skipCurrentEvent = false
        local setsize = #eventListenerSet
        for i=setsize,1,-1 do
            local curProcess = table.remove(eventListenerSet,1)
            if curProcess and curProcess.dead then
                while(curProcess and curProcess.dead) do
                    i = i - 1
                    curProcess = table.remove(eventListenerSet,1)
                end
            end
            if curProcess then
                currentRunningPid = curProcess.pid
                local res = table.pack(coroutine.resume(curProcess.coroutine,table.unpack(lastEvent)))
                res.n = nil
                if coroutine.status(curProcess.coroutine) == "dead" then
                    curProcess.dead = true
                else
                    if not res[2] then
                        res[2] = "NOS_no_filter"
                    end
                    table.remove(res,1)
                    clearListeners(curProcess)
                    for _,value in ipairs(res) do
                        addListener(curProcess,value)
                    end
                end
            end
        end
    end
    for _,i in ipairs(loadOrder) do
        print("spawning ",i)
        sleep(0.1)
        local pid = os.spawn({nOSModule = {
            blacklistEvent = blacklistEvent,
            whiteListEvent = whitelistEvent,
            addEnvPatch = addEnvPatch,
            addProgramMeta = addProgramMeta,
            getRawPrograms = getRawPrograms,
            clearListeners = clearListeners,
            addListener = addListener,
            }
        },ospath.."modules/"..i)
        runSet({pidRefs[pid]})
    end
    while(true) do
        if deadProcessCount > 0 then
            for _,process in ipairs(deadProcesses) do
                for ind,i in ipairs(topLevelCoroutines) do
                    if i == process then
                        table.remove(topLevelCoroutines,ind)
                        for _,exit_fn in ipairs(i.onExit) do
                            pcall(exit_fn,i)
                        end
                        break
                    end
                end
                pidRefs[process.pid] = nil
            end
            deadProcessCount = 0
            deadProcesses = {}
            if #topLevelCoroutines == 0 then
                -- term.clear()
                -- term.setCursorPos(1,1)
                sleep(2)
                os.shutdown()
            end
        end
        local nofilterSet = eventListeners["NOS_no_filter"]
        eventListeners["NOS_no_filter"] = {}
        runSet(eventListeners[lastEvent[1]])
        runSet(nofilterSet)
        for i,curProcess in ipairs(topLevelCoroutines) do
            if curProcess.dead then
                deadProcessCount = deadProcessCount + 1
                table.insert(deadProcesses,curProcess)
            end
        end
        lastEvent = table.pack(coroutine.yield())
        if blacklisted_events[lastEvent[1]] then
            lastEvent[1] = "NOS_LL_"..lastEvent[1]
        end
        if lastEvent[2] == "NOS_PASS" then
            lastEvent[1] = string.sub(lastEvent[1],8) -- remove NOS_LL_
            table.remove(lastEvent,2)
        end
        lastEvent.n = nil
    end
end
