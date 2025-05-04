
shell.setAlias("shell",".os/modules/shell.lua")
settings.define("nos.use_nlist",{
	description = "Replace list.lua with nlist.lua, affects ls, list, and dir aliases",
	default = true,
	type = "boolean"
})
settings.define("nos.no_fun",{
	description = "Remove rom/programs/fun from the path, to declutter 'programs'",
	default = false,
	type = "boolean"
})
settings.define("nos.no_rednet",{
	description = "Remove rom/programs/rednet from the path, to declutter 'programs'",
	default = true,
	type = "boolean"
})
local split = settings.getDetails("settings.split_settings")
if not split.changed then
	settings.define("settings.split_settings",{
		description = split.description,
		default = true,
		type = split.type,
	})
end
local dir = settings.getDetails("settings.directory")
if not dir.changed then
	settings.define("settings.directory",{
		description = dir.description,
		default = "/etc",
		type = dir.type,
	})
end

if settings.reload then
	-- reload it from /etc now
	settings.reload()
end

if settings.get("nos.use_nlist") then
	shell.setAlias("dir","nlist")
	shell.setAlias("list","nlist")
	shell.setAlias("ls","nlist")
end
shell.setPath(shell.path()..":/bin")
shell.setDir("/")
local function removePath(path)
	local p = shell.path()
	local l = string.match(p,"()"..path)
	shell.setPath(p:sub(1,l-1)..p:sub(l+#path))
end
if settings.get("nos.no_fun") then
	removePath(":/rom/programs/fun")
end
if settings.get("nos.no_rednet") then
	removePath(":/rom/programs/rednet")
end