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

local run = [[
function shell.run(...)
	local tWords = tokenise(...)
	local sCommand = tWords[1]
	if sCommand then -- try extension association
		local ext = sCommand:match("[^%.]*$")
		local s = settings.get("associations."..(ext or ""):lower())
		if s then
			tWords = tokenise(string.format(s,table.unpack(tWords)))
			sCommand = tWords[1]
		end
	end
	if sCommand then
		return shell.execute(sCommand, table.unpack(tWords, 2))
	end
	return false
end
]]

local diffs = {
	["shell.dir"] = {str = dir},
	["shell.setDir"] = {str = setDir},
	["shell.resolve"] = {str = resolve},
	["shell.run"] = {str = run},
}
local f = loadFileWithDiffs("rom/programs/shell.lua",diffs,nil,nil,_ENV)
f()