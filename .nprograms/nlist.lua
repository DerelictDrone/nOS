local cwd = shell.dir and shell.dir() or fs.getCWD()

local list = fs.list(cwd)

local color_groups = {}

local showHidden = settings.get("list.showhidden")

for ind, i in ipairs(list) do
	local c = fs.getAttributeColor(i)
	if not color_groups[c] then
		color_groups[c] = {}
	end
	if not showHidden and i:sub(1, 1) == "." then
		goto skip
	end
	table.insert(color_groups[c], i)
	::skip::
end

local arg = {}

local color_index = {}

for k, _ in pairs(color_groups) do
	table.insert(color_index, k)
end

-- higher colors in the palette go first
table.sort(color_index, function(a, b)
	return a > b
end)

for _, i in ipairs(color_index) do
	table.sort(color_groups[i])
	table.insert(arg, i)
	table.insert(arg, color_groups[i])
end

local x, y = term.getSize()
local curx, cury = term.getCursorPos()
local function nextLine()
	curx,cury = term.getCursorPos()
	if cury == y then
		term.scroll(1)
		term.setCursorPos(1,cury)
	else
		term.setCursorPos(1,cury+1)
	end
end
-- term.scroll(1)
term.setCursorPos(1, cury)
local startcolor = term.getTextColor()
while (true) do
	::start::
	local t = table.remove(arg, 1)
	local tp = type(t)
	if tp == "number" then
		term.setTextColor(t)
		goto start
	elseif not t then
		nextLine()
		term.setTextColor(startcolor)
		return
	end
	for _, i in ipairs(t) do
		curx, cury = term.getCursorPos()
		if curx + #i + 1 >= x then
			nextLine()
		end
		term.write(i .. " ")
	end
end
