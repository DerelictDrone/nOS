-- hack to get it to pass what I want to its run programs until I make my own shell
local envmeta = {__index = function(t,ind)
	if(ind == "_G") then
		return _ENV
	end
	local envmatch = _ENV[ind]
	if envmatch then return envmatch end
	return _G[ind]
end}
local env = {}
setmetatable(env,envmeta)
nOSModule = nil
if fs.setAllPathsAbsolute then 
	fs.setAllPathsAbsolute(false)
end
loadfile("rom/programs/shell.lua",nil,env)()