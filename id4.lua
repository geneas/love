--%tabs=3

local _G = _G
local pcall = pcall
local ipairs = ipairs
local table = require"table"

local char = string.char
local insert = table.insert
--local remove = table.remove
local concat = table.concat
local unpack = table.unpack or unpack

local dprint = dprint or function() end
local dprintf = dprintf or function() end
local d2printf = d2printf or function() end
local dump = dump or function() end


local id4 = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.id4 = id4
	module "id4"
end


local tagmap = {
	["aART"]		= { "Artist" },	-- "Album Artist"?
	["\xa9art"]	= { "Artist" },
	["\xa9alb"]	= { "Album" },
	["\xa9gen"]	= { "Genre" },
	gnre			= { "Genre" },
	["\xa9nam"]	= { "TrackName" },
	trkn			= { "TrackNumber",	function(d) return d:byte(4) end },
	["\xa9day"]	= { "Year",				function(d) return tonumber(d:sub(1, 4)) end },
	["\xa9too"]	= { "CreatedBy" },
	covr			= { "CoverArt",		function(d) return "size=" .. #d end },
}

---[[-- debug fn
local function hexdump(t, head)
	-- this is only for debugging
	if not _G.debug_level or _G.debug_level == 0 then return "" end
	
	local out = { "0000 " }
	local ascii = { "  " }
	
	for i, b in ipairs(t) do
		if i > 1 and i % 16 == 1 then
			insert(out, ("%s\n%s%04X "):format(concat(ascii), head or "", i - 1))
			ascii = { "  " }
		elseif i > 1 and i % 8 == 1 then
			insert(out, " ")
		end
		insert(out, (" %02X"):format(b))
		insert(ascii, b >= 0x20 and b < 0x7F and char(b) or b >= 0xA0 and "?" or ".")
	end
	local r = #t % 16
	if r > 0 then
		insert(out, (" "):rep((16 - r) * 3 + (r <= 8 and 1 or 0)))
	end
	insert(out, concat(ascii))
	return concat(out)
end
--]]

local function mp4load(fd, coverart)
	local seek = fd.seek or function(file, whence, offset)
			--
			-- for love2d file objects
			--
			if whence == "cur" then
				offset = offset + file:tell()
			elseif whence == "end" then
				offset = offset + file:getSize()
			end
			return file:seek(offset)
		end
	local function get(container, n, skip)
		local size = container.size
		local endpos = container.posn + n
		
		if size and endpos > size then return end	-- past end of container
		
		local super = container.super
		local data
		
		if container.super then
			data = get(super, n, skip)
			if not data then return end
		else
			-- top level - read from file
			if skip then
				data = seek(fd, "cur", n) and true
			else
				data = fd:read(n)
			end
			if not data then return end
		end
		if not skip and #data ~= n then error"length error" end
		container.posn = endpos
		return data
	end
	local function indent(container)
		local super = container.super
		
		return super and (indent(super) .. "  ") or ""
	end
	local function getnum(container, nbytes)
		local acc = 0
		
		for i = 1, nbytes do
			local ch = get(container, 1)
			
			if not ch then
				if i == 1 then return else error "unexpected end of container" end
			end
			acc = acc * 256 + ch:byte()
		end
		return acc
	end
	local gotftyp = false
	local function getheader(super)
		local size = getnum(super, 4)
		local tag = size and get(super, 4)
		
		if not tag then return end
--		dprintf("%s%4s size %d (0x%08X) at 0x%08X end 0x%08X", indent(super), tag, size, size, filepos, filepos + size - 8)
		
		if tag == "ftyp" then gotftyp = true
		elseif not gotftyp then error "not an mp4 file"
		end
		
		return { super = super, tag = tag, size = size, posn = 8 }
	end
	local function tobinary(data, i, j)
		local acc = 0
		local s = data:sub(i, j)
		
		if s then
			for c in s:gmatch"." do
				acc = acc * 256 + c:byte()
			end
		end
		return acc
	end
		
	local out = {}
			
	local function proc_tkhd(box, data)
		local function tobin(i, j) return tobinary(data, i, j) end
		local volume
		
		dprint(hexdump { data:byte(1, 256) })
		
		if box.version == 1 then
			volume = tobin(45, 46)
		else
			volume = tobin(33, 34)
		end
		
		-- store in trak box
		box.super.volume = volume
	end
	local function proc_mdhd(box, data)
		local function tobin(i, j) return tobinary(data, i, j) end
		local timescale, duration
		
		dprint(hexdump { data:byte(1, 256) })
		
		if box.version == 1 then
			timescale = tobin(17, 20)
			duration = tobin(21, 28)
		else
			timescale = tobin(9, 12)
			duration = tobin(13, 16)
		end
		
		-- store in mdia box
		box.super.length = duration / timescale
	end
	local function proc_hdlr(box, data)
		if box.super.tag == "mdia" and data:sub(5, 8) == "soun" then
			out.Length = box.super.length
			out.Volume = box.super.super.volume
		end
	end
	local function proc_data(box, data)
		local tagfmt = tagmap[box.super.tag]
		
		if tagfmt then
			local fn = tagfmt[2]
			
			out[tagfmt[1]] = fn and fn(data) or data
		end
	end
		
	local boxtypes = {
		moov = { nested = true },
--		mvhd = { full = true, proc = proc_mvhd },
		udta = { nested = true },
		meta = { nested = true, full = true },
		ilst = { nested = true },
		data = { full = true, pad = 4, proc = proc_data },
	
		-- disable reading of some ilst elements
		covr = not coverart and { },
		
		-- ...to get volume info
		trak = { nested = true },
		tkhd = { full = true, proc = proc_tkhd },
		mdhd = { full = true, proc = proc_mdhd },
		mdia = { nested = true },
		hdlr = { full = true, proc = proc_hdlr },
	}
	
	
	local function scan(container)
		local subs = {}
		
		container.subs = subs
		for h in getheader, container do
			insert(subs, h)
			
			local fmt = boxtypes[h.tag]
			local proc = fmt and fmt.proc
			
			if fmt and fmt.full then
				h.version = getnum(h, 1)
				h.flags = getnum(h, 3)
			end
			if fmt and fmt.nested or not fmt and container and container.tag == "ilst" then
				scan(h)
			end
			if proc then
				-- data container (skip data?)
				local pad = fmt.pad
				
				if pad then get(h, pad, true) end
				
				local data = get(h, h.size - h.posn)
					
				proc(h, data)
			
				-- test:
				--h.data = "\n" .. hexdump { data:byte(1, h.tag == "ilst" and 1024 or 64) }
			else
				-- skip uninteresting container
				get(h, h.size - h.posn, true)
			end				
		end
		
		return container
	end
			
	local tree = scan { posn = 0 }
	
--	dump(tree)
	if not out.Length then return nil, "not an MP4 file" end
	
	return out
end

--[[--------------------------------------------------------------------
\brief extract metadata from mp4/aac file
\param fd			an open File object positioned at the start of the file
\param coverart	if nil/false then cover art data will be ignored
\return	table containing metadata info fields
--]]--------------------------------------------------------------------
id4.load = function(file, coverart)
	local r = { pcall(mp4load, file, coverart) }
	
	if not r[1] then return nil, r[2] end
	
	return unpack(r, 2)
end

return id4
