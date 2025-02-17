-- fs with symlink support


local function addFS(env)
	local fs = env.fs or fs
	local fsMeta = createProxyTable({fs})
	local nfs = setmetatable({},fsMeta)
	env.fs = nfs
	nfs.preferSymbols = true
	function nfs.exists(filename)
		if nfs.preferSymbols then
			return fs.exists(nfs.getSymRef(filename) or filename)
		end
		if fs.exists(filename) then
			return true
		else
			local sym = nfs.getSymRef(filename)
			if sym and fs.exists(sym) then
				return true
			end
		end
		return false
	end
	function nfs.isSym(filename)
		if string.match(filename,"%.sym") then
			return fs.exists(filename)
		end
		if nfs.preferSymbols then
			return fs.exists(filename..".sym")
		else
			if fs.exists(filename) then
				return false
			else
				return fs.exists(filename..".sym")
			end
		end
	end
	function nfs.getSymRef(filename,replacement_occurred)
		local path = nfs.splitPath(filename)
		for ind,i in ipairs(path) do
			local s = nfs.getSymRefLiteral(fs.combine(table.unpack(path,1,ind)))
			if s then
				return nfs.getSymRef(fs.combine(s,table.unpack(path,ind+1)),true)
			end
		end
		if replacement_occurred then return filename end
		return nfs.getSymRefLiteral(filename)
	end
	function nfs.getSymRefLiteral(filename,recursions)
		if not filename then return end
		local sym_name = filename..".sym"
		recursions = recursions or 0
		if recursions > 40 then
			return
		end
		if fs.exists(sym_name) then
			local f = fs.open(sym_name,"r")
			local contents = f.readLine()
			f.close()
			if string.match(contents,"%.sym") then
				return nfs.getSymRef(contents,recursions+1)
			end
			return contents
		end
	end
	function nfs.list(dir,...)
		local files = fs.list(nfs.getSymRef(dir) or dir,...)
		local sym_filter = {}
		local filtered = {}
		for ind,i in ipairs(files) do
			if not sym_filter[string.gsub(i,"%.sym","")] then
				local replaced = string.gsub(i,"%.sym","")
				table.insert(filtered,replaced)
				sym_filter[string.gsub(i,"%.sym","")] = true
			end
		end
		return filtered
	end
	function nfs.find(match)
		local files = fs.find(match)
		local sym = fs.find(match..".sym")
		local sym_filter = {}
		local filtered = {}
		for ind,i in ipairs(files) do
			if not sym_filter[string.gsub(i,"%.sym","")] then
				local replaced = string.gsub(i,"%.sym","")
				table.insert(filtered,replaced)
				sym_filter[string.gsub(i,"%.sym","")] = true
			end
		end
		for ind,i in ipairs(sym) do
			if not sym_filter[string.gsub(i,"%.sym","")] then
				local replaced = string.gsub(i,"%.sym","")
				table.insert(filtered,replaced)
				sym_filter[string.gsub(i,"%.sym","")] = true
			end
		end
		return filtered
	end
	function nfs.open(filename,...)
		if nfs.preferSymbols then
			return fs.open(nfs.getSymRef(filename) or filename,...)
		end
		if fs.exists(filename) then
			return fs.open(filename,...)
		else
			return fs.open(nfs.getSymRef(filename),...)
		end
	end
	function nfs.isDir(filename)
		return fs.isDir(nfs.getSymRef(filename) or filename)
	end
	function nfs.setPreferSymbols(bPreferSymbols)
		if type(bPreferSymbols) ~= "boolean" then error("Attempted to set preferSymbols to non-boolean value: "..type(bPreferSymbols)) end
		nfs.setpreferSymbols = bPreferSymbols
	end
	function nfs.getPreferSymbols()
		return nfs.preferSymbols
	end
end

addEnvPatch(addFS)