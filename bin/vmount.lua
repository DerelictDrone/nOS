-- quick check to make sure we have virtual fs
if not fs.preferSymbols then
	print("Virtual FS api is unavailable, vmount cannot continue.")
end

local arg = table.pack(...)

if arg[1] == nil then
	print("Syntax: (args) (path) (destination)")
	print("use -h for more options")
	return
end

local unmounting = false
local function u()
	unmounting = true
end

local lmount = false
local function l()
	lmount = true
end

local function g()
	lmount = false
end

local function h()
	print("Welcome to Virtual Mount!")
	print("Syntax: (args) (path) (destination)")
	print("If destination unspecified, will be remounted at (path)")
	print("Available args:")
	print("-u(nmount)")
	print("-l(ocal mount)")
	print("-g(lobal mount, default)")
	print("-h(elp) Display this message")
	error("",0)
end

local argfuncs = {
	u=u,
	l=l,
	g=g,
	h=h,
}

local src,dest

for ind,i in ipairs(arg) do
	if string.match(i,"-%g") then
		local fn = string.sub(i,2)
		if argfuncs[fn] then
			argfuncs[fn]()
		else
			print("Unrecognized argument ",fn)
		end
	else
		if src and not dest then
			dest = i
		end
		if not src then
			src = i
		end
	end
end

if not dest then
	dest = src
end

local mount = lmount and fs.mountLocal or fs.mountGlobal
local dismount = lmount and fs.unmountLocal or fs.unmountGlobal

local stack = {}
local filesystem = {}
local function recursiveRead()
	if #stack == 0 then
		return
	end
	local cur = table.remove(stack,1)
	if fs.isDir(cur) then
		local list = fs.list(cur)
		-- print(cur,"dir, searching.")
		for _,v in ipairs(list) do
			-- print("putting",v,"on backburner")
			table.insert(stack,fs.combine(cur,v))
		end
		return recursiveRead()
	else
		-- print("opening",cur)
		local f = fs.open(cur,"r")
		local str = f.readAll()
		f.close()
		local path = fs.splitPath(cur)
		local fname = table.remove(path) -- pop file name off the end
		local curnode
		while(true) do
			local seg = table.remove(path,1)
			if not seg then
				break
			end
			if not filesystem[seg] then
				filesystem[seg] = {}
			end
			curnode = filesystem[seg]
		end
		-- print("applying",fname)
		curnode[fname] = str
	end
	return recursiveRead()
end

if unmounting then
	dismount(src)
	print("Dismounted",src)
	return
end

if not fs.exists(src) then
	print("Source doesn't exist, mounting empty folder")
	mount(fs.combine(dest))
	return
end

print("Mounting",src,"as",dest)
table.insert(stack,src)
recursiveRead()
mount(dest,filesystem)
