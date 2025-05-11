-- Copied from craftos.lua


local function patchSettings(env)
	local settings = env.settings
	-- extract values table from original rq
	-- #2 is _ENV, 1 and 3 are as follows.
	settings.define("settings.split_settings",{
		description = "Any setting with a 'group.settingName' structure will be exported to a file named 'group'",
		default = false,
		type = "boolean"
	})
	settings.define("settings.directory",{
		description = "Directory to put settings files in by default",
		default = "/",
		type = "string"
	})
	local _,expect = debug.getupvalue(settings.save,1)
	local _,values = debug.getupvalue(settings.save,3)
	local unlinked_groups = {}
	function settings.save(path)
		expect(1, path, "string", "nil")
		local path = path or fs.combine((settings.get("settings.directory") or ""),".settings")
		local pfilename = fs.getName(path)
		if settings.get("settings.split_settings") then
			local files = {}
			for k,v in pairs(values) do
				local s,e = k:match("()%.()")
				if not e then
					if not files[pfilename] then
						files[pfilename] = {}
					end
					files[pfilename][k] = v
					goto skip
				end
				local fname = k:sub(1,s-1)
				if not files[fname] then
					files[fname] = {}
				end
				files[fname][k] = v
				::skip::
			end
			local dir = fs.getDir(path)
			for k,v in pairs(files) do
				unlinked_groups[k] = nil
				local f = fs.open(fs.combine(dir,k),"w")
				if not f then return false end
				f.write(textutils.serialize(v))
				f.close()
			end
			for k,_ in pairs(unlinked_groups) do
				fs.delete(fs.combine(dir,k))
			end
			unlinked_groups = {}
			return true
		end
		local file = fs.open(path, "w")
		if not file then
			return false
		end
		file.write(textutils.serialize(values))
		file.close()
		return true
	end
	local details = debug.getupvalue(settings.set,2)
	local function set_value(name, new)
		local old = values[name]
		if old == nil then
			local opt = details[name]
			old = opt and opt.default
		end
	
		values[name] = new
		if old ~= new then
			-- This should be safe, as os.queueEvent copies values anyway.
			os.queueEvent("setting_changed", name, new, old)
		end
		if new == nil then
			local s,e = name:match("()%.()")
			if e then
				-- if there are any other members of group this will clear on save
				unlinked_groups[name:sub(1,s-1)] = true
			end
		end
	end
	debug.setupvalue(settings.set,3,set_value)
	debug.setupvalue(settings.unset,2,set_value)
	debug.setupvalue(settings.clear,3,set_value)

	settings.define("shell.allow_startup", {
		default = true,
		description = "Run startup files when the computer turns on.",
		type = "boolean",
	})
	settings.define("shell.allow_disk_startup", {
		default = commands == nil,
		description = "Run startup files from disk drives when the computer turns on.",
		type = "boolean",
	})

	settings.define("shell.autocomplete", {
		default = true,
		description = "Autocomplete program and arguments in the shell.",
		type = "boolean",
	})
	settings.define("edit.autocomplete", {
		default = true,
		description = "Autocomplete API and function names in the editor.",
			type = "boolean",
	})
	settings.define("lua.autocomplete", {
		default = true,
		description = "Autocomplete API and function names in the Lua REPL.",
			type = "boolean",
	})

	settings.define("edit.default_extension", {
		default = "lua",
		description = [[The file extension the editor will use if none is given. Set to "" to disable.]],
		type = "string",
	})
	settings.define("paint.default_extension", {
		default = "nfp",
		description = [[The file extension the paint program will use if none is given. Set to "" to disable.]],
		type = "string",
	})

	settings.define("list.show_hidden", {
		default = false,
		description = [[Whether the list program show  hidden files (those starting with ".").]],
		type = "boolean",
	})

	settings.define("motd.enable", {
		default = pocket == nil,
		description = "Display a random message when the computer starts up.",
		type = "boolean",
	})
	settings.define("motd.path", {
		default = "/rom/motd.txt:/motd.txt",
		description = [[The path to load random messages from. Should be a colon (":") separated string of file paths.]],
		type = "string",
	})

	settings.define("lua.warn_against_use_of_local", {
		default = true,
		description = [[Print a message when input in the Lua REPL starts with the word 'local'. Local variables defined in the Lua REPL are be inaccessible on the next input.]],
		type = "boolean",
	})
	settings.define("lua.function_args", {
		default = true,
		description = "Show function arguments when printing functions.",
		type = "boolean",
	})
	settings.define("lua.function_source", {
		default = false,
		description = "Show where a function was defined when printing functions.",
		type = "boolean",
	})
	settings.define("bios.strict_globals", {
		default = false,
		description = "Prevents assigning variables into a program's environment. Make sure you use the local keyword or assign to _G explicitly.",
		type = "boolean",
	})
	settings.define("shell.autocomplete_hidden", {
		default = false,
		description = [[Autocomplete hidden files and folders (those starting with ".").]],
		type = "boolean",
	})

	if term.isColour() then
		settings.define("bios.use_multishell", {
			default = true,
			description = [[Allow running multiple programs at once, through the use of the "fg" and "bg" programs.]],
			type = "boolean",
		})
	end
	if _CC_DEFAULT_SETTINGS then
		for sPair in string.gmatch(_CC_DEFAULT_SETTINGS, "[^,]+") do
			local sName, sValue = string.match(sPair, "([^=]*)=(.*)")
			if sName and sValue then
				local value
				if sValue == "true" then
					value = true
				elseif sValue == "false" then
					value = false
				elseif sValue == "nil" then
					value = nil
				elseif tonumber(sValue) then
					value = tonumber(sValue)
				else
					value = sValue
				end
				if value ~= nil then
					settings.set(sName, value)
				else
					settings.unset(sName)
				end
			end
		end
	end
	function settings.reload()
		settings.clear()
		local dir = settings.get("settings.directory")
		if not settings.get("settings.split_settings") then
			settings.load(fs.combine(dir,".settings"))
			return true
		end
		local sfiles = fs.list(dir)
		for _,i in ipairs(sfiles) do
			local p = fs.combine(dir,i)
			if not fs.isDir(p) then
				if not settings.load(p) then return false end
			end
		end
		return true
	end
end

addEnvPatch(patchSettings)