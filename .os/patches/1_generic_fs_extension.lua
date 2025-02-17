-- move any generic functions that would help any version of FS into here

local function addFSExtensions(env)
	local gfs = setmetatable({},createProxyTable({env.fs or fs}))
	env.fs = gfs
	function gfs.splitPath(filename)
		if not filename then return {} end
		filename = filename:gsub("\\","/")
		filename = filename:gsub("/+","/")
		local prevpoint = 1
		local explosions = {}
		for splitpoint in string.gmatch(filename,"()/") do
			table.insert(explosions,string.sub(filename,prevpoint,splitpoint-1))
			prevpoint = splitpoint+1
		end
		table.insert(explosions,string.sub(filename,prevpoint))
		return explosions
	end
end

addEnvPatch(addFSExtensions)