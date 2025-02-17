if not addEnvPatch then
	error("Tried to patch io.lua outside of patch window")
end

-- io.stdout = nil
-- io.stdin = nil
-- io.stderr = nil

local whitelistedCopyKeys = {
	peek = true,
	length = true,
	fork = true,
}

local function createReadablePipe(forked_buffers,forkers,readable_buffer,pid)
	local owner = pid
	local closed = false
	return {
		_handle = {
			read = function(n)
				n = math.floor(n)
				if n and n > 0 then
					local str = ""
					local c
					local i = n
					while(i > 0) do
						c = table.remove(readable_buffer, 1)
						if not c then
							break
						end
						if type(c) == "string" then
							str = str .. c -- skip key inputs
							i = i - 1
						end
						readable_buffer[0] = readable_buffer[0] - 1
					end
					if #str == 0 then
						return nil
					end
					return str
				end
				local c
				while(type(c) ~= "string" and readable_buffer[0] > 0) do
					c = table.remove(readable_buffer, 1)
					if not c then
						break
					end
					readable_buffer[0] = readable_buffer[0] - 1
				end
				return c
			end,
			peek = function(ind)
				return readable_buffer[ind]
			end,
			seek = function(n)
				for i=1,n,1 do
					if not table.remove(readable_buffer,1) then
						return
					end
					readable_buffer[0] = readable_buffer[0] - 1
				end
			end,
			length = function()
				return readable_buffer[0]
			end,
			fork = function()
				if closed then return nil,"Can't fork a closed pipe!" end
				local buff = {[0]=0}
				local pid = os.getPid()
				if not forked_buffers[pid] then
					forked_buffers[pid] = {}
				end
				table.insert(forked_buffers[pid],buff)
				local pipe = createReadablePipe(forked_buffers,forkers,buff,pid)
				if not forkers[pid] then
					forkers[pid] = {}
				end
				table.insert(forkers[pid],pipe)
				return pipe
			end,
			close = function()
				if closed then return end
				closed = true
				local myforks = forked_buffers[owner]
				local forker = forkers[owner]
				for ind,buff in ipairs(myforks) do
					if buff == readable_buffer then
						table.remove(myforks,ind)
						table.remove(forker,ind)
						if #myforks == 0 then
							forked_buffers[owner] = nil
						end
						if #forker == 0 then
							forkers[owner] = nil
						end
						break
					end
				end
			end,
			
		}
	}
end

local function createWritablePipe(forked_buffers,forkers,writer_meta)
	local closed = false
	return {
		_handle = {
			write = function(str)
				if closed then return nil,"Can't write to a closed pipe!" end
				local data = {}
				writer_meta.purge_counter = writer_meta.purge_counter + 1
				if writer_meta.purge_counter > writer_meta.writes_until_purge then
					writer_meta.purge_counter = 0
					for k,forks in pairs(forkers) do
						if not os.getProgramStatus(k) then
							for _,pipe in ipairs(forks) do
								pipe:close()
							end
							forkers[k] = nil
						end
					end
				end
				if type(str) == "number" then
					table.insert(data, str)
				else
					for c in string.gmatch(str, ".") do
						table.insert(data, c)
					end
				end
				for _,program_buffers in pairs(forked_buffers) do
					for _,buffer in ipairs(program_buffers) do
						for _,c in ipairs(data) do
							table.insert(buffer,c)
							buffer[0] = buffer[0] + 1
						end
					end
				end
			end,
			fork = function()
				if closed then return nil,"Can't fork a closed pipe!" end
				writer_meta.writers = writer_meta.writers + 1
				return createWritablePipe(forked_buffers,forkers,writer_meta)
			end,
			close = function()
				if closed then return end
				closed = true
				writer_meta.writers = writer_meta.writers - 1
				if writer_meta.writers < 1 then
					-- we closed all the writers, the readers should get closed now too
					for _,program_pipes in pairs(forkers) do
						for _,pipe in ipairs(program_pipes) do
							pipe:close()
						end
					end
				end
			end
		}
	}
end

local function addPipes(env, program, args)
	program.pipes = {}
	program.pipes_ext = {}
	program.pipe_meta = getmetatable(env.io.stdin or io.stdin)
	local function createPipePair(pid)
		local readable_buffer = {[0]=0}
		local forked_buffers = {[pid]={readable_buffer}}
		local forkers = {}
		local writer_meta = {
			purge_counter = 0,
			writes_until_purge = 256,
			writers = 1,
		}
		local pipe_meta = program.pipe_meta
		local readable = setmetatable(createReadablePipe(forked_buffers,forkers,readable_buffer,pid),pipe_meta)
		local writable = setmetatable(createWritablePipe(forked_buffers,forkers,writer_meta),pipe_meta)
		forkers[pid] = {readable}
		return readable, writable
	end
	env.io.createPipePair = function() return createPipePair(program.pid) end
	program.pipes_ext[1], program.pipes[1] = env.io.createPipePair()
	program.pipes[2], program.pipes_ext[2] = env.io.createPipePair()
	program.pipes_ext[3], program.pipes[3] = env.io.createPipePair()
	if env.io then
		env.io.stdout = program.pipes[1]
		env.io.stdin  = program.pipes[2]
		env.io.stderr = program.pipes[3]
	else
		env.io = {
			stdout = program.pipes[1],
			stdin  = program.pipes[2],
			stderr = program.pipes[3],
		}
	end
	local iometa = createProxyTable({env.io or io})
	setmetatable(env.io,iometa)
end

local function copyPipe(pipe, pipe_meta)
	local p = {
		_handle = {}
	}
	for k, v in pairs(pipe._handle) do
		p._handle[k] = v
	end
	setmetatable(p, pipe_meta)
	return p
end

local function pipeMeta(program, program_env, caller)
	program_env.pipes = {}
	for _, i in ipairs(program.pipes_ext) do
		local pipe = copyPipe(i,caller.pipe_meta)
		if pipe._handle.read then
			-- readable pipes require a fork before you're allowed to access them
			pipe._handle = {
				fork = pipe._handle.fork
			}
		end
		table.insert(program_env.pipes, pipe)
	end
end

addEnvPatch(addPipes)
addProgramMeta(pipeMeta)
