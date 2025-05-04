
local lperipheral = {}
for k,v in pairs(peripheral) do
	lperipheral[k] = v
end
for k,v in pairs(lperipheral) do
	peripheral[k] = nil
end
local vperipheral = {}
local vperipherals = {}
local vperipherals_by_type = {}
setmetatable(peripheral,{__index = lperipheral})

function peripheral.createVirtualPeripheral(name,meta)
	local hasVirtual = false
	for ind,i in ipairs(meta.types) do
		if i == "virtual" then
			hasVirtual = true
			break
		end
	end
	if not hasVirtual then
		table.insert(meta.types,"virtual")
	end
	local metatable = {
		__name = "peripheral",
		name = name,
		virtualOwner = os.getPid(),
		type = meta.types[1],
		types = meta.types,
		methodFns = meta.methodFns
	}
	local meta = setmetatable(meta.methods or {},metatable)
	vperipherals[name] = meta
	for ind,type in ipairs(metatable.types) do
		if not vperipherals_by_type[type] then vperipherals_by_type[type] = {} end
		vperipherals_by_type[type][name] = meta
	end
	os.queueEvent("peripheral",name)
end

function peripheral.removeVirtualPeripheral(name)
	local periph = vperipherals[name]
	local meta = getmetatable(periph)
	vperipherals[name] = nil
	for _,type in ipairs(meta.types) do
		vperipherals_by_type[type][name] = nil
	end
	os.queueEvent("peripheral_detach",name)
end

function peripheral.call(name,method,...)
	if vperipherals[name] then
		local meta = getmetatable(vperipherals[name])
		local t = table.pack(meta.methodFns[method](...))
		return table.unpack(t,1,t.n)
	end
	return lperipheral.call(name,method,...)
end
function peripheral.find(type,fn,...)
	local rem = {}
	rem = vperipherals_by_type[type]
	local loc = table.pack(lperipheral.find(type))
	local final = {}
	if not fn then
		fn = function() return true end
	end
	if rem then
		for k,_ in pairs(rem) do
			local p = peripheral.wrap(k)
			if(fn(p.name,p,true)) then
				table.insert(final,p)
			end
		end
	end
	if loc then
		for _,p in ipairs(loc) do
			if(fn(p.name,p,false)) then
				table.insert(final,p)
			end
		end
	end
	return table.unpack(final)
end
function peripheral.getMethods(name,...)
	if vperipherals[name] then
		local final = {}
		for _,v in pairs(vperipherals[name]) do
			table.insert(final,v)
		end
		return final
	end
	return lperipheral.getMethods(name,...)
end
function peripheral.getName(periph,...)
	return lperipheral.getName(periph,...)
end
function peripheral.getNames(...)
	local final = {table.unpack(lperipheral.getNames(...))}
	for k,_ in pairs(vperipherals) do
		table.insert(final,k)
	end
	return final
end
function peripheral.getType(name,...)
	if vperipherals[name] then
		local m = getmetatable(vperipherals[name])
		return table.unpack(m.types)
	end
	return lperipheral.getType(name,...)
end
function peripheral.hasType(name,type,...)
	if vperipherals[name] then
		local rperiphmeta = getmetatable(vperipherals[name])
		return rperiphmeta.types[name] or false
	end
	return lperipheral.hasType(name,type,...)
end
function peripheral.isPresent(name,...)
	if vperipherals[name] then
		return true
	end
	return lperipheral.isPresent(name,...)
end
function peripheral.wrap(name,...)
	if vperipherals[name] then
		local periph = vperipherals[name]
		if #periph == 0 then
			return peripheral.wrap(name,...)
		end
		local newWrap = {}
		setmetatable(newWrap,getmetatable(periph))
		for k,v in pairs(periph) do
			newWrap[v] = function(...)
				return peripheral.call(name,v,...)
			end
		end
		return newWrap
	end
	return lperipheral.wrap(name,...)
end