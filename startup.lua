-- bootloader by phpminor

if fs.exists("./.os/main.lua") then
    if os.bootloaded then return end
    local oldsleep = sleep
    _G.sleep = function() end
    os.oldShutdown = os.shutdown
    os.oldReboot = os.reboot
    local function loader()
        os.bootloaded = true
        os.reboot = os.oldReboot
        os.shutdown = os.oldShutdown
        os.oldReboot,os.oldShutdown = nil,nil
        _G.sleep = oldsleep
        loadfile("./.os/main.lua")()
        return newOS()
    end
    os.shutdown,os.reboot = loader,loader
    term.clear()
    term.setCursorPos(1,1)
    print("Press any key to boot into CraftOS instead of preferred OS")
    local function boot()
        local x,y = term.getCursorPos()
        for i=3,1,-1 do
            term.setCursorPos(x,y)
            term.write(tostring(i))
            oldsleep(0.2)
        end
        os.queueEvent("terminate")
    end
    local function cancel()
        os.pullEvent("key")
        term.clear()
        term.setCursorPos(1,1)
        print(os.version())
        if settings.get("motd.enable") then
            shell.run("motd")
        end
        os.reboot = os.oldReboot
        os.shutdown = os.oldShutdown
        os.oldReboot,os.oldShutdown = nil,nil
        _G.sleep = oldsleep
    end
    parallel.waitForAny(boot,cancel)
else
    print("Bootloader failed to find any suitable OS to load.")
end