-- Copied from craftos.lua


local function patchSettings(env)
	local settings = env.settings
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
	settings.load(".settings")
end

addEnvPatch(patchSettings)