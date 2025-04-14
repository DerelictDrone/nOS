
shell.setAlias("shell",".os/modules/shell.lua")
settings.define("nos.use_nlist",{
	description = "Replace list.lua with nlist.lua, affects ls, list, and dir aliases",
	default = true,
	type = "boolean"
})
if settings.get("nos.use_nlist") then
	shell.setAlias("dir","nlist")
	shell.setAlias("list","nlist")
	shell.setAlias("ls","nlist")
end
shell.setPath(shell.path()..":/.nprograms")