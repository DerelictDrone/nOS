-- reloads all base craftos apis within the context of the program
local expect
do
	local h = fs.open("rom/modules/main/cc/expect.lua", "r")
	local f, err = loadstring(h.readAll(), "@/rom/modules/main/cc/expect.lua")
	h.close()

	if not f then error(err) end
	expect = f().expect
end

local function dofile(_sFile)
	expect(1, _sFile, "string")
	local fnFile, e = loadfile(_sFile, nil, _G)
	if fnFile then
		return fnFile()
	else
		error(e, 2)
	end
end

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
		local len = #ptables
		local keys = {}
		local lastkeys = {}
		local finished = {}
		local k,v
		return function()
			while #finished ~= len do
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

function _G.createPatcherMeta(patches,meta,env)
	local meta = meta or {} or getmetatable(env)
	local fenv = env or {}
	local varspace = {}
	meta.__index = function(k)
		local v = rawget(varspace,k)
		if v == nil then
			return rawget(fenv,k)
		else
			return v
		end
	end
	meta.__newindex = function(k,v)
		if patches[k] then
			if type(v) == "function" and type(patches[k]) == "function" then
				local newFN = debug.getinfo(v)
				local patFN = debug.getinfo(patches[k])
				local upvalues = {}
				for i=1,newFN.nups,1 do
					local name = debug.getupvalue(newFN,i)
					upvalues[name] = i
				end
				for i=1,patFN.nups,1 do
					local name = debug.getupvalue(patFN,i)
					if upvalues[name] then
						debug.upvaluejoin(patches[k],i,v,upvalues[name])
					end
				end
			end
			varspace[k] = patches[k]
		else
			varspace[k] = v
		end
	end
	return meta
end


-- ! Does not work for majority of usecases, only useful for intercepting globals inside of said file on runtime.
-- ! If you need to replace local/table defined functions use loadFileWithDiffs
-- Loads a file but any values that are set (persistently) will be substituted for the patch value
-- Upvalues will be joined to any functions provided if possible
function _G.loadFileWithPatches(file,patches,meta,name,mode,fenv)
	local f = setmetatable({},createPatcherMeta(patches,meta,fenv))
	-- print(file,name,mode and mode or f,(mode and fenv) and f or nil)
	-- sleep(4)
	return loadfile(file,name,mode and mode or f,(mode and fenv) and f or nil)
end
local expect,lex_one,parser
do
	local make_package = dofile("rom/modules/main/cc/require.lua").make
	local env = setmetatable({},{__index=_ENV})
	local require,package = make_package(env,"")
	env.require,env.package = require,package
	expect = require("cc.expect").expect
	lex_one = require("cc.internal.syntax.lexer").lex_one
	parser = require("cc.internal.syntax.parser")
end

local function make_context(input)
	expect(1, input, "string")

	local context = {}

	local lines = { 1 }
	function context.line(pos) lines[#lines + 1] = pos end

	function context.get_pos(pos)
		expect(1, pos, "number")
		for i = #lines, 1, -1 do
			local start = lines[i]
			if pos >= start then return i, pos - start + 1 end
		end

		error("Position is <= 0", 2)
	end

	function context.get_line(pos)
		expect(1, pos, "number")
		for i = #lines, 1, -1 do
			local start = lines[i]
			if pos >= start then return input:match("[^\r\n]*", start) end
		end

		error("Position is <= 0", 2)
	end

	return context
end

local function make_lexer(input, context)
	local tokens, last_token = parser.tokens, parser.tokens.COMMENT
	local pos = 1
	return function()
		while true do
			local token, start, finish = lex_one(context, input, pos)
			if not token then return tokens.EOF, #input + 1, #input + 1 end

			pos = finish + 1

			if token < last_token then
				return token, start, finish
			elseif token == tokens.ERROR then
				error("Bad token",2)
			end
		end
	end
end

local tokens = {}

for k,v in pairs(parser.tokens) do
	tokens[v] = k
	tokens[k] = v
end

local lex = {
	make_lexer = make_lexer,
	make_context = make_context,
	tokens = tokens
}

local function extract_functions(fstr)
	local ctx = lex.make_context(fstr)
	local lexer = lex.make_lexer(fstr,ctx)

	local tokens = lex.tokens
	local token_list = {}
	local token_len = 0
	local charted_functions = {}
	local last_token
	local cur_function
	local f_stack = {}
	local last_end = 0
	while true do
		::restart::
		local t,s,e = lexer()
		if cur_function then
			if t == tokens.END then
				cur_function.n_ends = cur_function.n_ends - 1
				if cur_function.n_ends == 0 then
					cur_function.lend = e+1
					table.insert(charted_functions,cur_function)
					cur_function = table.remove(f_stack)
				end
				goto skip
			end
			if t == tokens.THEN or t == tokens.DO then
				cur_function.n_ends = cur_function.n_ends + 1
				goto skip
			end
			if not cur_function.oparen_done then
				if t == tokens.OPAREN then
					cur_function.oparen_done = true
				else
					cur_function.name = cur_function.name .. fstr:sub(s,e)
				end
			end
			goto skip
		end
		if last_token == tokens.FUNCTION then
			local f_name
			local paren_done = false
			if t == tokens.IDENT then
				f_name = fstr:sub(s,e)
			end
			if t == tokens.OPAREN then
				f_name = "(anonymous)"
				paren_done = true
			end
			if cur_function then
				table.insert(f_stack,cur_function)
			end
			cur_function = {
				name = f_name,
				lstart = ((token_list[token_len-1][1] == tokens.LOCAL) and token_list[token_len-1][2] or token_list[token_len][2])-1,
				is_local = token_list[token_len-1][1] == tokens.LOCAL,
				n_ends = 1, -- when n_ends == 0 we have the end of the function
				oparen_done = paren_done,
			}
		end
		::skip::
		if e == last_end then break end
		last_end = e
		table.insert(token_list,{t,s,e,tokens[t]})
		token_len = token_len + 1
		last_token = t
	end
	local anon = {}
	charted_functions.anonymous = anon
	for _,f in ipairs(charted_functions) do
		if f.name == "(anonymous)" then
			table.insert(anon,f)
		else
			charted_functions[f.name] = f
		end
	end
	return charted_functions
end

-- ! Replaces functions with your own at compile time, can target locals. Names must match up in diffs table
function _G.loadFileWithDiffs(fname,diffs,name,mode,fenv)
	local f,fstr = fs.open(fname,"r")
	if not f then
		error("Missing file ",fname)
	end
	fstr = f.readAll()
	f.close()
	local functions = extract_functions(fstr)
	local function ripairs(t)
		local i = #t
		return function()
			local v = t[i]
			i = i - 1
			if i == -1 then return nil end
			return i,v
		end
	end
	for _,v in ripairs(functions) do
		if not diffs[v.name] then
			goto skip
		end
		-- if diffs[v.name].patched then
		-- 	error("Tried to patch ",k," twice in one load",2)
		-- end
		local lstart = v.lstart
		local lend = v.lend
		-- functions[k].patched = true
		fstr = fstr:sub(1,lstart) .. diffs[v.name].str .. fstr:sub(lend)
		::skip::
	end
	return load(fstr,name,mode,fenv),fstr
end

local tAPIsLoading = {}

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
	local meta = debug.getmetatable(env)
	local function indexer(self,k)
		local v = rawget(env,k)
		if v ~= nil then return v end
		return rawget(_G,k)
	end
	-- load anything else missing from _G
		for k,v in pairs(_G) do
			if env[k] == nil then
				env[k] = v
			end
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
			setmetatable(env.commands, tCaseInsensitiveMetatable)
			setmetatable(env.commands.async, tCaseInsensitiveMetatable)

			-- Add global "exec" function
			env.exec = env.commands.exec
		end
	end
	function env.getmetatable(t)
		local m = debug.getmetatable(t)
		if m and m.__metatable == false then return nil end
		if m and m.__metatable then m = m.__metatable end
		return m
	end
	function env.setmetatable(t,nm)
		local m = debug.getmetatable(t)
		if type(t) ~= "table" then error("bad argument (table expected, got number)",2) end
		if m and m.__metatable == false then return t end
		debug.setmetatable(t,nm)
		return t
	end
	function env.load(str,name,mode,fenv)
		if type(mode) == "table" and fenv == nil then
			mode, fenv = nil, mode
		end
		local nenv = debug.getinfo(2)
		if nenv then
			nenv = debug.getfenv(nenv.func)
		else
			nenv = nil
		end
		return load(str,name,mode,fenv or nenv)
	end
	function env.loadfile(str,mode,fenv)
		if type(mode) == "table" and fenv == nil then
			mode, fenv = nil, mode
		end
		local nenv = debug.getinfo(2)
		if nenv then
			nenv = debug.getfenv(nenv.func)
		else
			nenv = nil
		end
		return loadfile(str,mode,fenv or nenv)
	end
	function env.dofile(_sFile)
		expect(1, _sFile, "string")
		local fnFile, e = env.loadfile(_sFile, nil, env._G)
		if fnFile then
			return fnFile()
		else
			error(e, 2)
		end
	end
	env._G = env
	setmetatable(env,meta)
	env.addEnvPatch = nil
	env.addProgramMeta = nil
end

addEnvPatch(apiLoader)