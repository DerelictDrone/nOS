nOSModule = nil
if fs.setAllPathsAbsolute then 
	fs.setAllPathsAbsolute(false)
end
local dir = [[
function shell.dir()
	return fs.getCWD()
end
]]

local setDir = [[
function shell.setDir(dir)
	expect(1, dir, "string")
	local sChar = string.sub(dir,1,1)
	if sChar ~= "/" then
		dir = "/" .. dir or ""
	end
	sDir = dir
	return fs.setCWD(dir)
end
]]

local resolve = [[
function shell.resolve(str)
	return "/"..fs.combine(str)
end
]]

local diffs = {
	["shell.dir"] = {str = dir},
	["shell.setDir"] = {str = setDir},
	["shell.resolve"] = {str = resolve},
}
local f = loadFileWithDiffs("rom/programs/shell.lua",diffs,nil,nil,_ENV)
f()