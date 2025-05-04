local function addRead(env,program,args)
	local function nread(_sReplaceChar, _tHistory, _fnComplete, _sDefault)
		expect(1, _sReplaceChar, "string", "nil")
		expect(2, _tHistory, "table", "nil")
		expect(3, _fnComplete, "function", "nil")
		expect(4, _sDefault, "string", "nil")
	
		term.setCursorBlink(true)
	
		local sLine
		if type(_sDefault) == "string" then
			sLine = _sDefault
		else
			sLine = ""
		end
		local nHistoryPos
		local nPos, nScroll = #sLine, 0
		if _sReplaceChar then
			_sReplaceChar = string.sub(_sReplaceChar, 1, 1)
		end
	
		local tCompletions
		local nCompletion
		local function recomplete()
			if _fnComplete and nPos == #sLine then
				tCompletions = _fnComplete(sLine)
				if tCompletions and #tCompletions > 0 then
					nCompletion = 1
				else
					nCompletion = nil
				end
			else
				tCompletions = nil
				nCompletion = nil
			end
		end
	
		local function uncomplete()
			tCompletions = nil
			nCompletion = nil
		end
	
		local w = term.getSize()
		local sx = term.getCursorPos()
	
		local function redraw(_bClear)
			local cursor_pos = nPos - nScroll
			if sx + cursor_pos >= w then
				-- We've moved beyond the RHS, ensure we're on the edge.
				nScroll = sx + nPos - w
			elseif cursor_pos < 0 then
				-- We've moved beyond the LHS, ensure we're on the edge.
				nScroll = nPos
			end
	
			local _, cy = term.getCursorPos()
			term.setCursorPos(sx, cy)
			local sReplace = _sReplaceChar
			if sReplace then
				term.write(string.rep(sReplace, math.max(#sLine - nScroll, 0)))
			elseif _bClear then
				local ln = string.sub(sLine,nScroll + 1)
				local len = #ln
				term.write(ln)
				local nx,ny = term.getCursorPos()
				term.setCursorPos(nx-1,ny)
				term.write(string.rep(" ",w-len))
				term.setCursorPos(nx,ny)
			else
				term.write(string.sub(sLine, nScroll + 1))
			end
	
			if nCompletion then
				local sCompletion = tCompletions[nCompletion]
				local oldText, oldBg
				if not _bClear then
					oldText = term.getTextColor()
					oldBg = term.getBackgroundColor()
					term.setTextColor(colors.white)
					term.setBackgroundColor(colors.gray)
				end
				if sReplace then
					term.write(string.rep(sReplace, #sCompletion))
				elseif _bClear then
					term.write(string.rep(" ", #sCompletion))
				else
					term.write(sCompletion)
				end
				if not _bClear then
					term.setTextColor(oldText)
					term.setBackgroundColor(oldBg)
				end
			end
	
			term.setCursorPos(sx + nPos - nScroll, cy)
		end
	
		local function clear()
			redraw(true)
		end
	
		recomplete()
		redraw()
	
		local function acceptCompletion()
			if nCompletion then
				-- Clear
				clear()
	
				-- Find the common prefix of all the other suggestions which start with the same letter as the current one
				local sCompletion = tCompletions[nCompletion]
				sLine = sLine .. sCompletion
				nPos = #sLine
	
				-- Redraw
				recomplete()
				redraw()
			end
		end
		local keyfns = {}
		local function enter()
			if nCompletion then
				clear()
				uncomplete()
				redraw()
			end
			return true
		end
		local function left()
			if nPos > 0 then
				clear()
				nPos = nPos - 1
				recomplete()
				redraw()
			end
		end
		local function right()
			-- Right
			if nPos < #sLine then
				-- Move right
				clear()
				nPos = nPos + 1
				recomplete()
				redraw()
			else
				-- Accept autocomplete
				acceptCompletion()
			end
		end
		local function updown(param)
			-- Up or down
			if nCompletion then
				-- Cycle completions
				clear()
				if param == keys.up then
					nCompletion = nCompletion - 1
					if nCompletion < 1 then
						nCompletion = #tCompletions
					end
				elseif param == keys.down then
					nCompletion = nCompletion + 1
					if nCompletion > #tCompletions then
						nCompletion = 1
					end
				end
				redraw()
	
			elseif _tHistory then
				-- Cycle history
				clear()
				if param == keys.up then
					-- Up
					if nHistoryPos == nil then
						if #_tHistory > 0 then
							nHistoryPos = #_tHistory
						end
					elseif nHistoryPos > 1 then
						nHistoryPos = nHistoryPos - 1
					end
				else
					-- Down
					if nHistoryPos == #_tHistory then
						nHistoryPos = nil
					elseif nHistoryPos ~= nil then
						nHistoryPos = nHistoryPos + 1
					end
				end
				if nHistoryPos then
					sLine = _tHistory[nHistoryPos]
					nPos, nScroll = #sLine, 0
				else
					sLine = ""
					nPos, nScroll = 0, 0
				end
				uncomplete()
				redraw()
	
			end
		end
		local function backspace()
			-- Backspace
			if nPos > 0 then
				clear()
				sLine = string.sub(sLine, 1, nPos - 1) .. string.sub(sLine, nPos + 1)
				nPos = nPos - 1
				if nScroll > 0 then nScroll = nScroll - 1 end
				recomplete()
				redraw()
			end
		end
		local function home()
			if nPos > 0 then
				clear()
				nPos = 0
				recomplete()
				redraw()
			end
		end
		local function delete()
			if nPos < #sLine then
				clear()
				sLine = string.sub(sLine, 1, nPos) .. string.sub(sLine, nPos + 2)
				recomplete()
				redraw()
			end
		end
		local function kend()
			-- End
			if nPos < #sLine then
				clear()
				nPos = #sLine
				recomplete()
				redraw()
			end
		end
		keyfns[keys.enter] = enter
		keyfns[keys.numPadEnter] = enter
		keyfns[keys.left] = left
		keyfns[keys.right] = right
		keyfns[keys.up] = updown
		keyfns[keys.down] = updown
		keyfns[keys.backspace] = backspace
		keyfns[keys.home] = home
		keyfns[keys.delete] = delete
		keyfns[keys["end"]] = kend
	
		while true do
			local sEvent, param, param1, param2 = os.pullEvent()
			if sEvent == "char" then
				-- Typed key
				clear()
				sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
				nPos = nPos + 1
				recomplete()
				redraw()
	
			elseif sEvent == "paste" then
				-- Pasted text
				clear()
				sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
				nPos = nPos + #param
				recomplete()
				redraw()
	
			elseif sEvent == "key" then
				if keyfns[param] then
					if keyfns[param](param) then break end
				end
			elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
				local _, cy = term.getCursorPos()
				if param1 >= sx and param1 <= w and param2 == cy then
					-- Ensure we don't scroll beyond the current line
					nPos = math.min(math.max(nScroll + param1 - sx, 0), #sLine)
					redraw()
				end
	
			elseif sEvent == "term_resize" then
				-- Terminal resized
				w = term.getSize()
				redraw()
	
			end
		end
	
		local _, cy = term.getCursorPos()
		term.setCursorBlink(false)
		term.setCursorPos(w + 1, cy)
		print()
	
		return sLine
	end
	env.read = setfenv(nread,env)
end
addEnvPatch(addRead)