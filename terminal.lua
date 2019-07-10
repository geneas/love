--%tabs=3
--[[

		display terminal for love2d
		
--]]

require "dump"

local ipairs = ipairs

local string = require "string"
local table = require "table"
local love = require "love"
local math = require "math"

local dump = dump
local tostring = tostring
local unpack = unpack or table.unpack

local terminal = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.terminal = terminal
	module "terminal"
end

local g_screen = {{ text = "", num = 1 }}
local g_scroll
local g_lmarg, g_rmarg = 2, 35

local g_width, g_height
local g_font
local g_lineHeight
--local g_dpiScale
local g_textw, g_texth
local g_nlines

local g_maxblocks = 10000
local g_blocknum = 0

-- compute wrapping for one text block
local function wrap(block)
	--[[
	local text = block.text
	local len = #text
	local xlen = g_font:getWidth(text)
	local lmarg = g_font:getWidth(tostring(g_linenum)) + g_lmarg
	local linew = g_textw - lmarg - g_rmarg
	local pos = 1
	local function nextline()
		local crem = len + pos - 1 -- characters remaining
		local clen = math.floor(crem * g_textw / xlen)	-- approx chars per line
		local n = math.min(clen, crem)
		local over = (n == crem)
		while true do
			local t = text:sub(pos, pos + n - 1)
			local l = g_font:getWidth(t)
			
			if l == linew then break		-- exact fit
			elseif l < linew then			-- too short
				if over then break end		-- if we have decremented then stop
				n = n + 1
			elseif n <= 1 then break		-- text too short?
			else
				over = true
				n = n - 1
			end
		end
		table.insert(block.segs, { pos = pos, last = n < crem and pos + n - 1 or nil })
		pos = pos + n
		return n < crem
	end
	
	block.segs = {}
	while nextline() do end
	]]
end

local function lnewline()
	if #g_screen >= g_maxblocks then
		table.remove(g_screen, 1)
	end
	
	local blocknum = g_blocknum + 1
	local block = { text = "", num = blocknum }
	
	table.insert(g_screen, block)
	g_blocknum = blocknum
	
	return block
end

local function lprint(...)
	local t = { ... }
	
	for i = 1, #t do t[i] = tostring(t[i]) end
	
	local line = table.concat(t, "\t")
	local block = g_screen[#g_screen]
	
	if block then
		block.text = block.text .. line
		wrap(block)
	end
	
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

local function lprintf(s, ...)
	lprint(string.format(s, ...))
end

local function ldump(t, n)
	local d = ""
	
	dump(t, {writer=function(s) d = d .. s end, maxlev=n, sort=true, noadrs=false})
	if d then
		for l in d:gmatch"[^\n]+" do lprint(l) end
	end
end

local g_shown
local function lshowinfo()
	-- write some system info at the top
	--
	g_shown = true
	
	lprintf("Love2d terminal version 0.2")
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



local function getscreen()
	local width, height = love.window.getMode()
	local font = love.graphics.getFont()
	local dpiScale = font:getDPIScale()
	
	return math.floor(width / dpiScale), math.floor(height / dpiScale), font
end
	
-- update screen after resize, font change etc
local function setscreen()
	g_width, g_height, g_font = getscreen()
	
	g_lineHeight = g_font:getHeight()
	g_textw, g_texth = g_width, g_height
	g_nlines = math.floor(g_texth / g_lineHeight)

	for _, blk in ipairs(g_screen) do
		wrap(blk)
	end
end

local function chkscreen()
	local width, height, font = getscreen()

	return width ~= g_width or	height ~= g_height
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
	
--[[	
	local blk, seg = 1, 1
	if g_scroll then
		local rem = g_scroll
		
		for b, block in ipairs(g_screen) do
			if #block.segs > rem then
				blk = b
				break
			end
			rem = rem - #block.segs
		end
		seg = rem + 1
	else
		-- display last lines
		for b = #g_screen, 1, -1 do
			local block = g_screen[b]
	--]]		
	
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
	local moved = math.abs(dx) > bound or math.abs(dy) > bound
	local mvid = mdown and g_pvid or nil
	
	if press then
		g_refx, g_refy, g_rstat = mx, my, true
	elseif moved then
		g_rstat = false
	end

		
	love.graphics.clear(1, 1, 0.8)
	
	-- effective scroll position
	local scrollmax = math.max(0, #g_screen - g_nlines)
	local scroll = g_scroll or scrollmax
	
	-- display text
	local x, y = g_lmarg, 0
	
	for i = scroll + 1, #g_screen do
		local blk = g_screen[i]
		
		if not blk then break end
		
		local lineno = tostring(blk.num)
		local linenlen = g_font:getWidth(lineno)
		
		love.graphics.setColor(1, 0, 0)
		love.graphics.print(lineno, x, y)
		love.graphics.setColor(0, 0, 0)
		love.graphics.print(blk.text, x + linenlen + 2, y)
		y = y + g_lineHeight
	end
	
	-- display scroll bar & buttons; handle mouse operations
	local bheight = g_rmarg
	local bwidth = g_rmarg
	local xbar = g_width - bwidth
	
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
	
	
	love.graphics.setColor(0.7, 0.7, 0.7, 1)
	love.graphics.rectangle("fill", xbar, 0, g_rmarg, g_height)
	
	local button1 = { id = 1, x = xbar, y = 0, w = bwidth, h = bheight, colour = { 0.8, 0.3, 0.3 },
		onclick = function()
			--lprintf("exit terminal")
			mactive = false
		end
	}
	local button2 = { id = 2, x = xbar, y = bheight, w = bwidth, h = bheight, colour = { 0.3, 0.3, 0.8 }, onclick = function()
			g_scroll = math.max(0, scroll - 1)
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
	
	local hheight = 20
	local sheight = g_height - bheight * 3 - hheight
	local hpos = math.floor(0.5 + sheight * scroll / math.max(1, #g_screen - g_nlines))
	local htop = bheight * 2 + hheight / 2
	local handle = { id = 4, x = xbar, y = bheight * 2 + hpos, w = bwidth, h = hheight, colour = { 0.2, 0.2, 0.2 },
		onpress = function(b)
			--lprintf("press handle")
			mvid = b.id
		end,
		onmove = function(b)
			--lprintf("move handle")
			scroll = math.max(0, math.min(scrollmax, math.floor(0.5 + scrollmax * (my - htop) / sheight)))
			g_scroll = scroll < scrollmax and scroll or nil
		end
	}
	button(handle)
	

	-- save current state
	g_px, g_py, g_pdown, g_pvid, g_pactive = mx, my, mdown, mvid, mactive
	
	return mactive
end

setscreen()

terminal.draw = ldraw
terminal.print = lprint
terminal.printf = lprintf
terminal.dump = ldump
terminal.putch = lputch
terminal.showinfo = lshowinfo

return terminal
