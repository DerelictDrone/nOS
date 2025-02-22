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
	gfs.attributeProviders = {}
	gfs.colorProviders = {}
	function gfs.attributes(path)
		local attributes = {}
		for _,i in ipairs(gfs.attributeProviders) do
			i(path,attributes)
		end
		return attributes
	end
	function gfs.registerAttributeProvider(fn)
		table.insert(gfs.attributeProviders,fn)
	end
	function gfs.unregisterAttributeProvider(fn)
		if type(fn) == "number" then
			return table.remove(gfs.attributeProviders,fn) and true or false
		end
		for ind,i in ipairs(gfs.attributeProviders) do
			if i == fn then
				table.remove(gfs.attributeProviders,ind)
				return true
			end
		end
		return false
	end
	
	gfs.registerAttributeProvider(function(path,attributes)
		local succ,a = pcall(fs.attributes,path)
		if not succ then return end
		for k,v in pairs(a) do
			if attributes[k] == nil then
				attributes[k] = v
			end
		end
	end)

	function gfs.getAttributeColor(path)
		local attributes = gfs.attributes(path)
		for ind,i in ipairs(gfs.colorProviders) do
			local c = i(attributes)
			if c then
				return c
			end
		end
		return colors.white
	end
	function gfs.registerColorProvider(fn,priority)
		local len = #gfs.colorProviders+1
		table.insert(gfs.colorProviders,math.min(math.max(1,priority or len),len),fn)
	end
	function gfs.unregisterColorProvider(fn)
		if type(fn) == "number" then
			return table.remove(gfs.colorProviders,fn) and true or false
		end
		for ind,i in ipairs(gfs.colorProviders) do
			if i == fn then
				table.remove(gfs.colorProviders,ind)
				return true
			end
		end
		return false
	end

	gfs.registerColorProvider(function(attributes)
		if attributes.isDir then
			return colors.green
		end
	end)
end

addEnvPatch(addFSExtensions)