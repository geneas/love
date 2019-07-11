--%tabs=3
--[[

	Display Terminal for love2d
		
	Copyright(c) 2019 Andrew Cannon <ajc@gmx.net>
	
	Licensed under the MIT licence.
	For details see file LICENSE in this directory.

--]]

require "dump"


local string = require "string"
local table = require "table"
local math = require "math"
local utf8 = require "utf8"
local love = require "love"

local tostring = tostring
local unpack = unpack or table.unpack
local ipairs = ipairs
local assert = assert or function(b) if not b then error"assertion" end end
local error = error
local pcall = pcall
local dump = dump


local terminal = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.terminal = terminal
	module "terminal"
end

local max = math.max
local min = math.min
local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local round = function(x) return floor(x + 0.5) end

local insert = table.insert
local remove = table.remove
local concat = table.concat

local format = string.format
local errorf = function(...) error(format(...)) end

-- config
local g_lmarg, g_rmarg = 2, 35
local g_idgap, g_trgap = 2, 2
local g_maxblocks = 10000

-- screen parameters
local g_width, g_height
local g_font
local g_lineHeight
local g_nlines

-- display contents
local g_screen
local g_scroll
local g_lineref
local g_linecount
local g_blockid


-- compute wrapping for one text block
local function wrap(block)
	---[[
	local prevnseg = block.nseg or 1
	local text = block.text
	local tlen = #text
	local xlen = g_font:getWidth(text)
	local idlen = g_font:getWidth(tostring(block.id))
	local linew = max(1, g_width - g_lmarg - idlen - g_idgap - g_trgap - g_rmarg)
	local pos = 1
	local function nextline()
		local crem = tlen - pos + 1				-- characters remaining
		local clen = ceil(crem * linew / xlen)	-- approx chars per line
		local over = false
		local n = utf8.offset(text, 0, pos + max(1, min(clen, crem))) - pos
		
		if n == 0 then n = utf8.offset(text, 2, pos) - pos end
		--assert(n > 0)
		--local cnt = 0
		while true do
			local t = text:sub(pos, pos + n - 1)
			--local l = g_font:getWidth(t)
			local ok, l = pcall(g_font.getWidth, g_font, t)
			if not ok then errorf("pos=%d n=%d t='%s'", pos, n, t) end
			
			if l == linew then break			-- exact fit
			elseif l < linew then				-- too short
				if over then break end			-- if we have decremented then stop
				if n == crem then break end	-- if end of string then stop
				n = utf8.offset(text, 2, pos + n) - pos
			else
				local p = utf8.offset(text, 0, pos + n - 1) - pos
				
				if p == 0 then break end		-- string too short?
				n = p
				over = true
			end
			--cnt = cnt + 1
			--if cnt > 99 then
			--	errorf("tlen=%d xlen=%d done=%d crem=%d clen=%d n=%d over=%s l=%d linew=%d", tlen, xlen, done, crem, clen, n, tostring(over), l, linew)
			--end
		end
		insert(block.segs, { pos = pos, last = n < crem and pos + n - 1 or nil })
		pos = pos + n
		return n < crem
	end
	
	if xlen <= linew then
		block.nseg = 1
		block.segs = nil
	else
		block.segs = {}
		while nextline() do end
		block.nseg = #block.segs
	end
	g_linecount = g_linecount + block.nseg - prevnseg
	--]]
end

local function lnewline()
	if #g_screen >= g_maxblocks then
		remove(g_screen, 1)
	end
	
	local blockid = g_blockid + 1
	local block = { text = "", id = blockid }
	
	insert(g_screen, block)
	g_blockid = blockid
	g_linecount = g_linecount + 1
	
	return block
end

local function lclear()
	g_lineref = nil
	g_blockid = 0		-- ?
	g_linecount = 0
	g_screen = {}
	lnewline()
end

local function lputch(c)
	if c == "\n" then lnewline()
	else
		local block = g_screen[#g_screen]
		
		if block then
			if c == "\b" then block.text = block.text:sub(1, -2)
			else block.text = block.text .. c
			end
			wrap(block)
		end
	end
end

local function lprint(...)
	local t = { ... }
	
	for i = 1, #t do t[i] = tostring(t[i]) end
	
	local data = concat(t, "\t")
	local block = g_screen[#g_screen]
	
	for line in data:gmatch"[^\n]+" do
		if block then
			block.text = block.text .. line
			wrap(block)
		end
		block = lnewline()
	end
end

local function lprintf(s, ...)
	lprint(format(s, ...))
end

local function ldump(t, n)
	local d = ""
	
	dump(t, {writer=function(s) d = d .. s end, maxlev=n, sort=true, noadrs=false})
	if #d > 0 then lprint(d) end
end

local g_shown
local function lshowinfo()
	-- write some system info at the top
	--
	g_shown = true
	
	lprintf("Löve2d terminal version 0.3")
	lprintf("---------------------------")
	lprintf("width %d height %d dpiScale %f", g_width, g_height, g_font:getDPIScale())
	local function show(name)
		local f = love.filesystem[name]
		
		lprintf("love.filesystem.%s: %s", name, f and tostring(f()) or "?")
	end
	show"getAppdataDirectory"
	show"getSaveDirectory"
	show"getSourceBaseDirectory"
	show"getUserDirectory"
	show"getWorkingDirectory"
	show"getIdentity"
	lprintf("love.filesystem.getRealDirectory(main.lua): %s", tostring(love.filesystem.getRealDirectory"main.lua"))
	lprintf("---------------------------")
end


-- get current screen parameters
local function getscreen()
	local width, height = love.window.getMode()
	local font = love.graphics.getFont()
	local dpiScale = font:getDPIScale()
	
	return floor(width / dpiScale), floor(height / dpiScale), font
end
	
-- update screen after resize, font change etc
local function setscreen()
	g_width, g_height, g_font = getscreen()
	g_lineHeight = g_font:getHeight()
	g_nlines = floor(g_height / g_lineHeight)

	for _, blk in ipairs(g_screen) do
		wrap(blk)
	end
	
	local scrollmax = max(0, g_linecount - g_nlines)
	
	g_scroll = g_scroll and min(g_scroll, scrollmax) or nil
	g_lineref = nil
end

-- check whether screen parameters have changed
local function chkscreen()
	local width, height, font = getscreen()

	return width ~= g_width or	height ~= g_height
end


-- find block and segment for line
local function getline(line)
	local ref = g_lineref
	
	-- check for no change
	if ref and ref.line == line then return ref.blknum, ref.segnum end
		
	local function getref()
		local first, last
		
		-- check for different line in same block, otherwise set upper/lower bound for search
		if ref then
			local block = ref.block
			local nsegs = block.nseg or 1
			
			if line < ref.line then
				if ref.line - line < ref.segnum then return block, ref.blknum, ref.segnum - (ref.line - line) end
				last = ref
			else
				if line - ref.line <= nsegs - ref.segnum then return block, ref.blknum, ref.segnum + (line - ref.line) end
				first = ref
			end
		end
		
		first = first or { line = 0, blknum = 1, segnum = 1, block = g_screen[1] }
		last = last or { line = g_linecount - (g_screen[#g_screen].nseg or 1), blknum = #g_screen, segnum = 1, block = g_screen[#g_screen] }
		
		-- determine which end is closer to desired line number
		if line - first.line < last.line - line then
			-- scan forwards from first
			local blknum = first.blknum
			local dist = line - first.line + first.segnum - 1
			
			while blknum <= #g_screen do
				local block = g_screen[blknum]
				local nsegs = block.nseg or 1
			
				if dist < nsegs then return block, blknum, dist + 1 end
				blknum = blknum + 1
				dist = dist - nsegs
			end
			errorf("line %d dist %d first.line %d last.line %d blknum %d #g_screen %d", line, dist, first.line, last.line, blknum, #g_screen)
		else
			-- scan backwards from last
			local blknum = last.blknum
			local dist = line - last.line + last.segnum - 1
			local block = g_screen[blknum]
			
			while blknum > 0 do
				if dist >= 0 then return block, blknum, dist + 1 end
				blknum = blknum - 1
				block = g_screen[blknum]
				dist = dist + (block.nseg or 1)
			end
			errorf("line %d dist %d first.line %d last.line %d blknum %d #g_screen %d", line, dist, first.line, last.line, blknum, #g_screen)
		end
	end
	local block, blknum, segnum = getref()
	
	g_lineref = { line = line, blknum = blknum, segnum = segnum, block = block }
	
	return blknum, segnum
end

-- update screen
local function drawscreen(startline, count, drawfunc)
	local blknum, segnum = getline(startline)
	
	while blknum <= #g_screen do
		local block = g_screen[blknum]
		local text = block.text
		local nsegs = block.nseg or 1
		local segments = block.segs or {{ pos = 1 }}
		
		while segnum <= nsegs do
			local seg = segments[segnum]
			--if not seg then errorf("blknum %d segnum %d nsegs %d count %d", blknum, segnum, nsegs, count) end
			local line = text:sub(seg.pos, seg.last)
			
			drawfunc(line, block.id, segnum == 1)
			
			count = count - 1
			if count <= 0 then return end
			segnum = segnum + 1
		end
		blknum = blknum + 1
		segnum = 1
	end
end

	

-- screen update & mouse handling
---------------------------------

local g_px, g_py, g_pdown, g_pvid		-- previous state
local g_refx, g_refy, g_rstat				-- reference posn
local g_first = true

local function ldraw( )
	--love.graphics.print("start here: ", x, y)
	--y = y + 20
	if chkscreen() then setscreen() end
	if not g_shown then lshowinfo() end
	--if not g_first then return end
	--g_first = nil
	
	-- mouse handling
	local mactive = true
	local mx, my = love.mouse.getPosition()
	local mdown = love.mouse.isDown(1)
	if not g_pactive then
		g_px, g_py, g_pdown = mx, my, mdown
	end
	
	local dx, dy = mx - g_px, my - g_py
	local press = mdown and not g_pdown
	local reles = not mdown and g_pdown
	local bound = g_pvid and 0 or 2
	local moved = abs(dx) > bound or abs(dy) > bound
	local mvid = mdown and g_pvid or nil
	
	if press then
		g_refx, g_refy, g_rstat = mx, my, true
	elseif moved then
		g_rstat = false
	end

		
	love.graphics.clear(1, 1, 0.8)
	
	-- effective scroll position
	local scrollmax = max(0, g_linecount - g_nlines)
	local scroll = g_scroll or scrollmax
	
	-- display text
	local x, y = g_lmarg, 0
	local function drawline(text, ident, first)
		local idstr = tostring(ident)
		local idlen = g_font:getWidth(idstr)
		
		if first then
			love.graphics.setColor(1, 0, 0)
			love.graphics.print(idstr, x, y)
		end
		love.graphics.setColor(0, 0, 0)
		love.graphics.print(text, x + idlen + g_idgap, y)
		
		y = y + g_lineHeight
	end
	drawscreen(scroll, g_nlines, drawline)
	
	-- display scroll bar & buttons; handle mouse operations
	local bheight = g_rmarg
	local bwidth = g_rmarg
	local xbar = g_width - bwidth
	
	local hheight = 20
	local sheight = g_height - bheight * 3 - hheight
	local spos = bheight * 2
	local hpos = round(sheight * (g_scroll and scroll / max(1, scrollmax) or 1))
	local htop = spos + round(hheight / 2)
	
	local function button(b)
		
		-- check for mouse operations
		if mdown and moved and b.id == mvid and b.onmove then b.onmove(b) end
		if mx > b.x and mx < b.x + b.w and my > b.y and my < b.y + b.h then
			-- mouse in button
			--if press then lprintf("mouse press button %d", b.id) end
			--if moved then lprintf("mouse move button %d", b.id) end
			--if reles then lprintf("mouse release button %d", b.id) end
			if press and b.onpress then b.onpress(b) end
			if reles and g_rstat and b.onclick then b.onclick(b) end
		end
		
		-- draw button
		love.graphics.setColor(unpack(b.colour))
		love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
				
	end
	
	
	love.graphics.setColor(0.7, 0.7, 0.7)
	love.graphics.rectangle("fill", xbar, 0, bwidth, g_height)
	love.graphics.setColor(0.4, 0.4, 0.4)
	love.graphics.rectangle("fill", xbar + (bwidth - 2) / 2, htop, 2, sheight)
	
	local button1 = { id = 1, x = xbar, y = 0, w = bwidth, h = bheight, colour = { 0.8, 0.3, 0.3 },
		onclick = function()
			--lprintf("exit terminal")
			mactive = false
		end
	}
	local button2 = { id = 2, x = xbar, y = bheight, w = bwidth, h = bheight, colour = { 0.3, 0.3, 0.8 }, onclick = function()
			g_scroll = max(0, scroll - 1)
		end
	}
	local button3 = { id = 3, x = xbar, y = g_height - bheight, w = bwidth, h = bheight, colour = { 0.3, 0.3, 0.8 },
		onclick = function()
			if g_scroll then
				g_scroll = scroll + 1
				if g_scroll >= scrollmax then g_scroll = nil end
			end
		end
	}
	button(button1)
	button(button2)
	button(button3)
	
	local handle = { id = 4, x = xbar, y = bheight * 2 + hpos, w = bwidth, h = hheight, colour = { 0.2, 0.2, 0.2 },
		onpress = function(b)
			--lprintf("press handle")
			mvid = b.id
		end,
		onmove = function(b)
			--lprintf("move handle")
			scroll = max(0, min(scrollmax, round(scrollmax * (my - htop) / sheight)))
			g_scroll = scroll < scrollmax and scroll or nil
		end
	}
	button(handle)
	

	-- save current state
	g_px, g_py, g_pdown, g_pvid, g_pactive = mx, my, mdown, mvid, mactive
	
	return mactive
end

local function lexit()
	g_pactive = false
end

lclear()
setscreen()


terminal.draw = ldraw
terminal.exit = lexit
terminal.putch = lputch
terminal.print = lprint
terminal.printf = lprintf
terminal.dump = ldump
terminal.showinfo = lshowinfo
terminal.clear = lclear

return terminal
