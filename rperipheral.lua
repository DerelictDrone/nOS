if peripheral.localonly then
    print("Enable remote peripherals before attempting to use this again.")
    return
end

local arg = table.pack(...)


if arg[1] == "connect" then
    peripheral.getNames()
    print(peripheral.subscribe(arg[2], "rperipheral", arg[3] == "exclusive"))
end
