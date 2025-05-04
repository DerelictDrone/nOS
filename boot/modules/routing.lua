-- this does everything it needs to do
local routermodem = settings.get("main_router") and peripheral.wrap(settings.get("main_router")) or peripheral.find("modem")
local router
if routermodem then
	router = os.makeRoute(routermodem,settings.get("netname") or settings.get("net_name"))
	os.router = router
end

local function addRouter(env,program,args)
	if env.os then
		env.os.router = router
	else
		env.os = setmetatable({router=router},createProxyTable({env.os or os}))
	end
end

nOSModule.addEnvPatch(addRouter)
parallel.waitForAny(router.listener,router.keepAliveResponder,router.keepAliveSender)
