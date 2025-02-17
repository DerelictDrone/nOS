-- reloads all base craftos apis within the context of the program

-- I'm so sick of writing proxy tables
function _G.createProxyTable(tables,deny_access)
	local meta = {
		proxies = tables
	}
	if deny_access then
		meta.__metatable = false
	end
	if not tables or #tables == 0 then return meta end
	-- check if any of these tables are actually proxied(and accessible)
	local newtables = {}
	local proxies_exist = false
	for ind,i in ipairs(tables) do
		local imeta = getmetatable(i)
		if imeta and imeta.proxies then
			proxies_exist = true
			local newtable = {}
			-- raw pairs
			for k,v in next,i do
				newtable[k] = v
			end
			table.insert(newtables,newtable)
			for ind,i in ipairs(imeta.proxies) do
				table.insert(newtables,i)
			end
		else
			table.insert(newtables,i)
		end
	end
	if proxies_exist then
		return createProxyTable(newtables,deny_access)
	end
	function meta.__pairs(self)
		local ptables = {self,table.unpack(tables)}
		local keys = {}
		local lastkeys = {}
		local finished = {}
		local k,v
		return function()
			for ind,i in ipairs(ptables) do
				if finished[ind] then
					goto skip_table
				end
				k,v = next(i,lastkeys[ind])
				lastkeys[ind] = k
				if v == nil then
					finished[ind] = true
					goto skip_table
				end
				if not keys[k] then
					keys[k] = true
					return k,v
				end
				::skip_table::
			end
		end
	end
	if #tables == 1 then
		local mytable = tables[1]
		meta.__index = mytable
		return meta
	end
	function meta.__index(self,k)
		local v = rawget(self,k)
		if v == nil then
			for _,i in ipairs(tables) do
				v = rawget(i,k)
				if v ~= nil then
					return v
				end
			end
		end
	end
	return meta
end

local tAPIsLoading = {}
local expect
do
	local h = fs.open("rom/modules/main/cc/expect.lua", "r")
	local f, err = loadstring(h.readAll(), "@/rom/modules/main/cc/expect.lua")
	h.close()

	if not f then error(err) end
	expect = f().expect
end

local function loadAPI(_sPath,env,indexer)
	local sName = fs.getName(_sPath)
	if sName:sub(-4) == ".lua" then
		sName = sName:sub(1, -5)
	end
	if tAPIsLoading[sName] == true then
		printError("API " .. sName .. " is already being loaded")
		return false
	end
	tAPIsLoading[sName] = true

	local tEnv = {}
	setmetatable(tEnv, { __index = indexer })

	local tEnv = setmetatable({}, { __index = indexer })

	local fnAPI, err = loadfile(_sPath, nil, tEnv)
	if fnAPI then
		local ok, err = pcall(fnAPI)
		if not ok then
			tAPIsLoading[sName] = nil
			return error("Failed to load API " .. sName .. " due to " .. err, 1)
		end
	else
		tAPIsLoading[sName] = nil
		return error("Failed to load API " .. sName .. " due to " .. err, 1)
	end

	local tAPI = {}
	for k, v in pairs(tEnv) do
		if k ~= "_ENV" then
			tAPI[k] =  v
		end
	end

	env[sName] = tAPI
	tAPIsLoading[sName] = nil
	return true
end

local function unloadAPI(_sName,env)
	if _sName ~= "_G" and type(env[_sName]) == "table" then
		env[_sName] = nil
	end
end

local function load_apis(dir,env,indexer)
	if not fs.isDir(dir) then return end

	for _, file in ipairs(fs.list(dir)) do
		if file:sub(1, 1) ~= "." then
			local path = fs.combine(dir, file)
			if not fs.isDir(path) then
				if not loadAPI(path,env,indexer) then
					print("aw shucks",path)
					sleep(10)
				end
			end
		end
	end
end

local function apiLoader(env,program,args)
	local function indexer(self,k)
		local v = rawget(env,k)
		if v ~= nil then return v end
		return rawget(_G,k)
	end
	do
		local h = fs.open("rom/modules/main/cc/expect.lua", "r")
		local f, err = loadstring(h.readAll(), "@/rom/modules/main/cc/expect.lua")
		h.close()

		if not f then error(err) end
		setfenv(f,setmetatable({},{__index = indexer}))
		env.expect = f().expect
	end
	load_apis("rom/apis",env,indexer)
	if http then load_apis("rom/apis/http",env,indexer) end
	if turtle then load_apis("rom/apis/turtle",env,indexer) end
	if pocket then load_apis("rom/apis/pocket",env,indexer) end

	if commands and fs.isDir("rom/apis/command") then
		-- Load command APIs
		if loadAPI("rom/apis/command/commands.lua",env,indexer) then
			-- Add a special case-insensitive metatable to the commands api
			local tCaseInsensitiveMetatable = {
				__index = function(table, key)
					local value = rawget(table, key)
					if value ~= nil then
						return value
					end
					if type(key) == "string" then
						local value = rawget(table, string.lower(key))
						if value ~= nil then
							return value
						end
					end
					return nil
				end,
			}
			setmetatable(commands, tCaseInsensitiveMetatable)
			setmetatable(commands.async, tCaseInsensitiveMetatable)

			-- Add global "exec" function
			exec = commands.exec
		end
	end
end

addEnvPatch(apiLoader)