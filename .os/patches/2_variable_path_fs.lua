local fs = fs

local function generatePathPolyfill(fn,path_transforms)
	return function(path)
		if not path then return fn(path) end
		local spath = path
		for ind,i in ipairs(path_transforms) do
			spath = i(spath)
		end
		return fn(spath)
	end
end

local function generatePathDestPolyfill(fn,path_transforms)
	return function(path,dest)
		if (not path) and (not dest) then return fn(path,dest) end
		local spath,sdest = path,dest
		for ind,i in ipairs(path_transforms) do
			spath = i(spath)
			sdest = i(sdest)
		end
		return fn(spath,sdest)
	end
end

local pathPolyfills = {
	find = fs.find,
	isDriveRoot = fs.isDriveRoot,
	isDir = fs.isDir,
	list = fs.list,
	getName = fs.getName,
	getDir = fs.getDir,
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
	open = fs.open
}

local function createMFS(env,program,arg)
	local mfs = {
		allPathsAbsolute = false,
		cwd = ""
	}
	local path_transforms = {}
	-- relative
	path_transforms[1] = function(path)
		if mfs.allPathsAbsolute then
			return path
		end
		if string.sub(path,1,1) ~= "/" then
			return mfs.cwd..path
		end
		return path:sub(2)
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
		pathPolyfills = newPathPolyfills
		pathDestPolyfills = newPathDestPolyfills
	end
	for k,v in pairs(pathPolyfills) do
		mfs[k] = generatePathPolyfill(v,path_transforms)
	end
	for k,v in pairs(pathDestPolyfills) do
		mfs[k] = generatePathDestPolyfill(v,path_transforms)
	end
	for k,v in pairs(env.fs or fs) do
		if not mfs[k] then
			mfs[k] = v
		end
	end
	function mfs.setCWD(sCWD)
		if type(sCWD) ~= "string" then error("Attempted to set current working directory to non-string value: "..type(sCWD)) end
		mfs.cwd = sCWD
	end
	function mfs.getCWD()
		return mfs.cwd
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