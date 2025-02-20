local global_mounts = {}

local function generic_string_fhandle(self,mode)
	local closed = false
	local binary = false
	local ptr = 0
		local handle = {
		close = function()
			closed = true
		end,
		seek = function(whence,offset)
			if type(whence) == "number" then
				error("bad argument #1 (string expected got number)")
			end
			local nPtr = ptr
			if not whence then return ptr end
			local nOffset = offset or 0
			if whence == "set" then
				nPtr = nOffset
				goto validate_ptr
			end
			if whence == "cur" then
				nPtr = ptr + nOffset
				goto validate_ptr
			end
			if whence == "end" then
				nPtr = #self[1] + nOffset
			end
			::validate_ptr::
			if nPtr < 0 then
				return nil,"Position is negative"
			end
			ptr = nPtr
			return ptr
		end
	}
	local sMode = mode
	if sMode:sub(-2) == "b" then
		sMode = sMode:sub(1,-2)
		binary = true
	end
	if sMode == "r" or sMode == "r+" then
		function handle.read(count)
			if closed then error("attempt to use a closed file") end
			if count and count < 0 then
				error("Cannot read a negative number of bytes")
			end
			if count == 0 then
				if ptr >= #self[1] then
					return
				else
					return ""
				end
			end
			local d
			if binary then
				if not count then
					d = self[1]:byte(ptr)
					ptr = ptr + 1
					return d
				else
					d = self[1]:sub(ptr+1,(ptr)+(count or 1))
				end
			else
				d = self[1]:sub(ptr+1,(ptr)+(count or 1))
			end
			ptr = ptr + (count or 1)
			if type(d) == "string" and #d == 0 then return end
			return d
		end
		function handle.readLine(trailing)
			if closed then error("attempt to use a closed file") end
			local d = self[1]:sub(ptr)
			local offset = -1
			if trailing then
				offset = 0
			end
			local match = d:match("()\n")
			d = d:sub(1,(match and match + offset) or -1)
			local cr
			d,cr = d:gsub("\r","")
			ptr = ptr + #d + cr + 1
			if ptr >= #self[1] and #d == 0 then return end
			return d
		end
		function handle.readAll()
			if closed then error("attempt to use a closed file") end
			return handle.read(#self[1]:sub(ptr))
		end
	end
	if sMode == "w" or sMode == "w+" then
		self[1] = ""
	end
	if sMode == "a" then
		ptr = #self[1]
	end
	if sMode == "w" or sMode == "w+" or sMode == "a" or sMode == "r+" then
		function handle.write(d)
			if closed then error("attempt to use a closed file") end
			local strd
			if binary then
				if type(d) == "number" then
					strd = string.char(math.floor(d) % 256)
				else
					strd = tostring(d)
				end
			else
				strd = tostring(d)
			end
			self[1] = self[1]:sub(0,ptr)..strd..self[1]:sub(ptr+(2+#strd))
			ptr = ptr + #strd
		end
		function handle.writeLine(d)
			if closed then error("attempt to use a closed file") end
			return handle.write(tostring(d).."\n")
		end
	end
	return handle
end

local function addVirtualFS(env,program)
	local fs = env.fs or fs
	local vfs = setmetatable({},createProxyTable({fs}))
	env.fs = vfs
	vfs.preferVirtualFiles = true
	program.local_mounts = {}
	local __index = function(self,path)
		if type(path) ~= "string" then 
			return nil
		end
		local split = vfs.splitPath(path)
		local curdir = self
		for _,i in ipairs(split) do
			if i == "" then goto skip_index end
			curdir = rawget(curdir,i)
			if not curdir then
				return nil
			end
			::skip_index::
		end
		return curdir
	end
	local __newindex = function(self,path,value)
		local split = vfs.splitPath(path)
		local last = table.remove(split)
		local curdir = self
		local tdir = curdir
		for _,i in ipairs(split) do
			if i == "" then goto skip_nindex end
			tdir = rawget(curdir,i)
			if not tdir then
				rawset(curdir,i,{})
			end
			curdir = rawget(curdir,i)
			::skip_nindex::
		end
		rawset(curdir,last,value)
	end
	local filesystem_meta = {
		__index = function(self,path)
			local res = __index(self,path)
			if not res then
				return __index(global_mounts,path)
			end
			return res
		end,
		__original_index = __index,
		__newindex = __newindex,
		__tostring = function(self)
			return "Filesystem"
		end,
	}
	setmetatable(program.local_mounts,filesystem_meta)
	function vfs.mount(dir,data)
		if not data or not data.files then return end
		for k,v in pairs(data.files) do
			if type(v) == "string" then
				program.local_mounts[dir.."/"..k] = {
					v,
					generic_string_fhandle
				}
			end
		end
	end
	vfs.mountLocal = vfs.mount
	function vfs.mountGlobal(dir,data)
		if not data or not data.files then return end
		for k,v in pairs(data.files) do
			if type(v) == "string" then
				__newindex(global_mounts,dir.."/"..k, {
					v,
					generic_string_fhandle
				})
			end
		end
	end
	function vfs.unmount(path)
		if vfs.isVirtual(path) then
			if not program.local_mounts[path] then
				return false,"Path is globally mounted, use fs.unmountGlobal"
			end
			program.local_mounts[path] = nil
			return true
		else
			return false,"Path is not virtual"
		end
	end
	vfs.unmountLocal = vfs.unmount
	function vfs.unmountGlobal(path)
		if vfs.isVirtual(path) then
			if not __index(global_mounts,path) then
				return false,"Path is locally mounted, use fs.unmountLocal"
			end
			__newindex(global_mounts,path,nil)
			return true
		else
			return false,"Path is not virtual"
		end
	end
	function vfs.getLocalMounts()
		return program.local_mounts
	end
	function vfs.setPreferVirtualFiles(bPreferVirtualFiles)
		if type(bPreferVirtualFiles) ~= "boolean" then error("Attempted to set preferVirtualFiles to non-boolean value: "..type(bPreferVirtualFiles)) end
		vfs.preferVirtualFiles = bPreferVirtualFiles
	end
	function vfs.getPreferVirtualFiles()
		return vfs.preferVirtualFiles
	end
	function vfs.exists(name)
		if not name then return fs.exists(name) end
		local tested
		::virtual::
		if vfs.preferVirtualFiles or tested then
			if program.local_mounts[name] then
				return true
			end
			if tested then return false end
			return fs.exists(name)
		else
			if fs.exists(name) then
				return true
			else
				tested = true
				goto virtual
			end
		end
	end
	function vfs.isVirtual(name)
		if vfs.preferVirtualFiles then
			if program.local_mounts[name] then return true end
			return false
		else
			if fs.exists(name) then
				return false
			end
			if program.local_mounts[name] then return true end
			return false
		end
	end
	function vfs.isDir(name)
		if not name then return fs.isDir(name) end
		local tested
		::virtual::
		if vfs.preferVirtualFiles or tested then
			local mnt = program.local_mounts[name]
			if mnt then
				if mnt[1] then -- has contents thus it's a file
					return false
				end
				return true -- has no contents, thus it's a dir
			end
			if tested then return false end
			return fs.isDir(name) -- doesn't exist, check regular
		else
			if fs.isDir(name) then
				return true
			else
				if fs.exists(name) then return false end
				tested = true
				goto virtual
			end
		end
	end
	function vfs.open(name,mode)
		if not name or not mode then return fs.open(name,mode) end
		::virtual::
		local tested
		if vfs.preferVirtualFiles or tested then
			local f = program.local_mounts[name]
			if not f then
				local isvirtual = false
				local str = name
				while(true) do
					str = fs.getDir(str)
					if str == ".." or str == "" then break end
					isvirtual = vfs.isVirtual(str)
					if isvirtual then break end
				end
				if isvirtual then
				-- filesystem is virtual so lets just make it then try again
					program.local_mounts[name] = {
						"",
						generic_string_fhandle
					}
					return vfs.open(name,mode)
				end
				return fs.open(name,mode)
			end
			return f[2](f,mode)
		else
			local f = fs.exists(name)
			if not f then
				tested = true
				goto virtual
			else
				return fs.open(name,mode)
			end
		end
	end
	function vfs.list(dir)
		local f = program.local_mounts[dir]
		local m = getmetatable(program.local_mounts)
		local g = m.__original_index(global_mounts,dir)
		local l = {}
		if fs.exists(dir) then
			l = fs.list(dir)
		end
		local names = {}
		if f then
			if f[1] and #l == 0 then
				error("Not a directory")
			else
				for k,v in pairs(f) do
					names[k] = true
				end
			end
		end
		if g then
			if not f and g[1] and #l == 0 then
				error("Not a directory")
			else
				for k,v in pairs(g) do
					names[k] = true
				end
			end
		end
		for k,v in pairs(names) do
			table.insert(l,k)
		end
		return l
	end
	function vfs.flushVirtualToDisk(vname,rname)
		if not fs.isVirtual(vname) then return false,"File isn't virtual" end
		local v = vfs.open(vname,"r")
		if not v then return false,"Couldn't open virtual file" end
		local f = fs.open(rname or vname,"w")
		if not f then return false,"Couldn't open file" end
		f.write(v.readAll())
		f.close()
		v.close()
		return true
	end
	-- copied directly from the original fs find implementation
	-- (since this now replaces a function rather than tailing onto the previous patch)
	-- (this will need to be the top FS patch or functionality will be lost)
	local function find_aux(path, parts, i, out)
		local part = parts[i]
		if not part then
			-- If we're at the end of the pattern, ensure our path exists and append it.
			if vfs.exists(path) then out[#out + 1] = path end
		elseif part.exact then
			-- If we're an exact match, just recurse into this directory.
			return find_aux(vfs.combine(path, part.contents), parts, i + 1, out)
		else
			-- Otherwise we're a pattern. Check we're a directory, then recurse into each
			-- matching file.
			if not vfs.isDir(path) then return end
	
			local files = vfs.list(path)
			for j = 1, #files do
				local file = files[j]
				if file:find(part.contents) then find_aux(vfs.combine(path, file), parts, i + 1, out) end
			end
		end
	end
	
	local find_escape = {
		-- Escape standard Lua pattern characters
		["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)", ["%"] = "%%",
		["."] = "%.", ["["] = "%[", ["]"] = "%]", ["+"] = "%+", ["-"] = "%-",
		-- Aside from our wildcards.
		["*"] = ".*",
		["?"] = ".",
	}

	function vfs.find(pattern)
		-- no expectations
		-- expect(1, pattern, "string")
		
		pattern = fs.combine(pattern) -- Normalise the path, removing ".."s.
	
		-- If the pattern is trying to search outside the computer root, just abort.
		-- This will fail later on anyway.
		if pattern == ".." or pattern:sub(1, 3) == "../" then
			error("/" .. pattern .. ": Invalid Path", 2)
		end
	
		-- If we've no wildcards, just check the file exists.
		if not pattern:find("[*?]") then
			if fs.exists(pattern) then return { pattern } else return {} end
		end
	
		local parts = {}
		for part in pattern:gmatch("[^/]+") do
			if part:find("[*?]") then
				parts[#parts + 1] = {
					exact = false,
					contents = "^" .. part:gsub(".", find_escape) .. "$",
				}
			else
				parts[#parts + 1] = { exact = true, contents = part }
			end
		end
	
		local out = {}
		find_aux("", parts, 1, out)
		return out
	end
end

addEnvPatch(addVirtualFS)