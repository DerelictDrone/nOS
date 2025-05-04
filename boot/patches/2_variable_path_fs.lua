local fs = fs

local function generatePathPolyfill(fn,path_transforms)
	return function(path,...)
		if not path then return fn() end
		local spath = path
		local succ
		for ind,i in ipairs(path_transforms) do
			succ,spath = pcall(i,spath)
			if not succ then error(spath,2) end
		end
		local ret = table.pack(pcall(fn,spath,...))
		if ret[1] then
			return table.unpack(ret,2,ret.n)
		else
			error(ret[2],2)
		end
	end
end

local function generatePathDestPolyfill(fn,path_transforms)
	return function(path,dest,...)
		if (not path) and (not dest) then return fn(path,dest,...) end
		local spath,sdest = path,dest
		local succ
		for ind,i in ipairs(path_transforms) do
			succ,spath = pcall(i,spath)
			if not succ then error(spath,2) end
			succ,sdest = pcall(i,sdest)
			if not succ then error(spath,2) end
		end
		local ret = table.pack(pcall(fn,spath,sdest,...))
		if ret[1] then
			return table.unpack(ret,2,ret.n)
		else
			error(ret[2],2)
		end
	end
end

local pathPolyfills = {
	isDriveRoot = fs.isDriveRoot,
	isDir = fs.isDir,
	list = fs.list,
	getName = fs.getName,
	getSize = fs.getSize,
	exists = fs.exists,
	isReadOnly = fs.isReadOnly,
	makeDir = fs.makeDir,
	delete = fs.delete,
	getDrive = fs.getDrive,
	getFreeSpace = fs.getFreeSpace,
	getCapacity = fs.getCapacity,
	attributes = fs.attributes,
}

local pathDestPolyfills = {
	move = fs.move,
	copy = fs.copy,
}

local function createMFS(env,program,arg)
	local mfs = {
		allPathsAbsolute = false,
		cwd = ""
	}
	local combine = env.fs.combine
	local path_transforms = {}
	-- relative
	path_transforms[1] = function(path)
		if mfs.allPathsAbsolute then
			return combine(path)
		end
		local sStartChar = path:sub(1, 1)
		if sStartChar == "/" or sStartChar == "\\" then
			return combine(path)
		end
		return mfs.combine(mfs.cwd,path)
	end
	local pathPolyfills,pathDestPolyfills = pathPolyfills,pathDestPolyfills
	if env.fs then
		-- generate new polyfills based off of the original polyfill lists
		local newPathPolyfills = {}
		for k,v in pairs(pathPolyfills) do
			newPathPolyfills[k] = env.fs[k] or v
		end
		local newPathDestPolyfills = {}
		for k,v in pairs(pathDestPolyfills) do
			newPathDestPolyfills[k] = env.fs[k] or v
		end
		-- check for any extra functions that aren't already tagged that take path,dest as args
		for k,v in pairs(env.fs) do
			if type(v) == "function" and not newPathDestPolyfills[k] and not newPathPolyfills[k] then
				local info = debug.getinfo(v)
				if info.nparams > 0 then
					local l1 = debug.getlocal(v,1)
					local l2 = debug.getlocal(v,2)
					if l2 == "dest" and l1 == "path" then
						newPathDestPolyfills[k] = v
						goto skip
					end
					if l1 == "path" then
						newPathPolyfills[k] = v
					end
				end
			end
			::skip::
		end
		pathPolyfills = newPathPolyfills
		pathDestPolyfills = newPathDestPolyfills
	end
	for k,v in pairs(pathPolyfills) do
		mfs[k] = setfenv(generatePathPolyfill(v,path_transforms),env)
	end
	for k,v in pairs(pathDestPolyfills) do
		mfs[k] = setfenv(generatePathDestPolyfill(v,path_transforms),env)
	end
	for k,v in pairs(env.fs or fs) do
		if not mfs[k] then
			mfs[k] = v
		end
	end
	function mfs.setCWD(sCWD)
		if type(sCWD) ~= "string" then error("Attempted to set current working directory to non-string value: "..type(sCWD),2) end
		mfs.cwd = sCWD
	end
	function mfs.getCWD()
		return mfs.cwd
	end
	function mfs.combine(start,...)
		if mfs.allPathsAbsolute then
			return combine(start,...)
		end
		local startc = start:sub(1,1)
		local str,cwd = "",""
		local abs = false
		if startc ~= "/" and startc ~= "\\" then
			cwd = mfs.getCWD()
		else
			abs = true
		end
		local s,str = pcall(combine,cwd,start,...)
		if not s then
			error(str,2)
		end
		if abs then
			return "/"..str
		end
		return str
	end
	local getDir = fs.getDir
	function mfs.getDir(path)
		if not path or type(path) ~= "string" then error("bad argument #1 (expected string, got "..type(path)..")") end
		local npath = mfs.combine(path)
		local abs = npath:sub(1,1) == "/"
		local dir = getDir(path)
		if abs then
			return "/"..dir
		end
		return dir
	end
	local find = env.fs.find
	function mfs.find(pattern)
		local files = find(mfs.combine(pattern))
		if not pattern:find("[*?]") then
			if env.fs.exists(pattern) then files = { pattern } else return {} end
		end
		if mfs.allPathsAbsolute then
			return files
		end
		-- they paths are all absolute anyway, just throw a / on the front and call it a day
		for ind,v in ipairs(files) do
			files[ind] = mfs.combine("/",v)
		end
		return files
	end
	local open = env.fs.open
	function mfs.open(name,mode)
		return open(mfs.combine(name),mode)
	end
	function mfs.setAllPathsAbsolute(bAbsolute)
		if type(bAbsolute) ~= "boolean" then error("Attempted to set allPathsAbsolute to non-boolean value: "..type(bAbsolute)) end
		mfs.allPathsAbsolute = bAbsolute
	end
	function mfs.getAllPathsAbsolute()
		return mfs.allPathsAbsolute
	end
	function mfs.addPathTransform(fn)
		if type(fn) ~= "function" then
			error("Attempted to add non-function path transform: "..type(fn))
		end
		table.insert(path_transforms,fn)
		return #path_transforms
	end
	function mfs.removePathTransform(fn)
		if type(fn) == "number" then
			table.remove(path_transforms,fn)
			return true
		end
		if type(fn) == "function" then
			for ind,i in ipairs(path_transforms) do
				if i == fn then
					table.remove(path_transforms,i)
					return true
				end
			end
		end
		return false
	end
	env.fs = setmetatable(mfs,createProxyTable({env.fs,fs}))
end

addEnvPatch(createMFS)