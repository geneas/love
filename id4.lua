--%tabs=3
--[[--

	MP4 Metadata Decoder for Lua
	
	Copyright(c) 2019 Andrew Cannon <ajc@gmx.net>
	
	Licensed under the MIT licence.
	For details see file LICENSE in this directory.

--]]--

local _G = _G
local pcall = pcall
local ipairs = ipairs
local tonumber = tonumber

--local table = require"table"

local char = string.char
local insert = table.insert
--local remove = table.remove
local concat = table.concat
local unpack = table.unpack or unpack

local debug_enabled = _G.debug_level and _G.debug_level > 0

local dprint = debug_enabled and (dprint or function() end)
local dprintf = debug_enabled and (dprintf or function() end)
local d2printf = debug_enabled and (d2printf or function() end)
local dump = debug_enabled and (dump or function() end)

local id4 = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.id4 = id4
	module "id4"
end


local function tobinary(data, i, j)
	local acc = 0
	local s = data:sub(i or 1, j)
	
	if s then
		for c in s:gmatch"." do
			acc = acc * 256 + c:byte()
		end
	end
	return acc
end
local genres = {
        "Blues", "Classic Rock", "Country", "Dance",
        "Disco", "Funk", "Grunge", "Hip-Hop",
        "Jazz", "Metal", "New Age", "Oldies",
        "Other", "Pop", "R&B", "Rap",
        "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks",
        "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
        "Vocal", "Jazz+Funk", "Fusion", "Trance",
        "Classical", "Instrumental", "Acid", "House",
        "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk",
        "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
        "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
        "Electronic", "Pop-Folk", "Eurodance", "Dream",
        "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle",
        "Native US", "Cabaret", "New Wave", "Psychedelic",
        "Rave", "Showtunes", "Trailer", "Lo-Fi",
        "Tribal", "Acid Punk", "Acid Jazz", "Polka",
        "Retro", "Musical", "Rock & Roll", "Hard Rock",
        "Folk", "Folk-Rock", "National Folk", "Swing",
        "Fast Fusion", "Bebob", "Latin", "Revival",
        "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock",
        "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock",
        "Big Band", "Chorus", "Easy Listening", "Acoustic",
        "Humour", "Speech", "Chanson", "Opera",
        "Chamber Music", "Sonata", "Symphony", "Booty Bass",
        "Primus", "Porn Groove", "Satire", "Slow Jam",
        "Club", "Tango", "Samba", "Folklore",
        "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
        "Duet", "Punk Rock", "Drum Solo", "Acapella",
        "Euro-House", "Dance Hall", "Goa", "Drum & Bass",
        "Club - House", "Hardcore", "Terror", "Indie",
        "BritPop", "Negerpunk", "Polsk Punk", "Beat",
        "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
        "Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
        "Thrash Metal", "Anime", "JPop", "Synthpop",
        "Unknown",
}	
local tagmap = {
	["aART"]		= { "Artist" },	-- "Album Artist"?
	["\169art"]	= { "Artist" },
	["\169alb"]	= { "Album" },
	["\169gen"]	= { "Genre" },
	gnre			= { "Genre",			function(d) return genres[tobinary(d)] or genres[#genres] end },
	["\169nam"]	= { "TrackName" },
	trkn			= { "TrackNumber",	function(d) return d:byte(4) end },
	["\169day"]	= { "Year",				function(d) return tonumber(d:sub(1, 4)) end },
	["\169too"]	= { "CreatedBy" },
	covr			= { "CoverArt" },
--	covr			= { "CoverArt",		function(d) return "size=" .. #d end }, -- for testing
}


local function hexdump(t, head)
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
local function indent(container)
	local super = container.super
	
	return super and (indent(super) .. "  ") or ""
end

local function mp4load(fd, coverart, rewind)
	local seek = fd.tell and -- assume love2d File object
		function(file, whence, offset)
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
		or fd.seek -- plain Lua (file object has no 'tell' function)
	local function get(container, n, skip)
		-- read n bytes from container
		local len = container.len
		
		if len and n > len then return end	-- past end of container
		
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
		if len then container.len = len - n end
		return data
	end
	local function getnum(container, nbytes)
		-- read number (Big-endian binary) from container
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
	local function getheader(super)
		-- read next box header
		local size = getnum(super, 4)
		local tag = size and get(super, 4)
		local offset = 8
		
		if size == 1 then
			size = getnum(super, 8)
			offset = offset + 8
		end
		if tag == "uuid" then
			tag = tag .. "/" .. get(super, 16)
			offset = offset + 16
		end
		
		if not size or not tag then return end
		
		_ = dprintf and dprintf("%s%4s size %d (0x%08X)", indent(super), tag, size, size)
		
		return { super = super, tag = tag, len = size - offset }
	end
		
	local out = {}
			
	local function proc_tkhd(box, data)
		local function tobin(i, j) return tobinary(data, i, j) end
		local volume
		
		_ = dprint and dprint(hexdump { data:byte(1, 256) })
		
		if box.version == 1 then
			volume = tobin(45, 46)
		else
			volume = tobin(33, 34)
		end
		
		-- store in 'trak' box
		box.super.volume = volume / 256
	end
	local function proc_mdhd(box, data)
		local function tobin(i, j) return tobinary(data, i, j) end
		local timescale, duration
		
		_ = dprint and dprint(hexdump { data:byte(1, 256) })
		
		if box.version == 1 then
			timescale = tobin(17, 20)
			duration = tobin(21, 28)
		else
			timescale = tobin(9, 12)
			duration = tobin(13, 16)
		end
		
		-- store in 'mdia' box
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
		trak = { nested = true },
		tkhd = { full = true, proc = proc_tkhd },
		mdhd = { full = true, proc = proc_mdhd },
		mdia = { nested = true },
		hdlr = { full = true, proc = proc_hdlr },
		udta = { nested = true },
		meta = { nested = true, full = true },
		ilst = { nested = true },
		data = { full = true, predef = 4, proc = proc_data },
	
		-- disable reading of some ilst elements
		covr = not coverart and { },
	}
	
	
	local gotftyp = false
	local function scan(container)
		-- scan next box in container
		local subs = {}
		
		container.subs = subs
		for h in getheader, container do
			if h.tag == "ftyp" then gotftyp = true end
			
			insert(subs, h)
			
			local fmt = boxtypes[h.tag]
			local proc = fmt and fmt.proc
			
			-- ftyp must come before other significant boxes
			if fmt and not gotftyp then error " not an mp4 file" end
			
			if fmt and fmt.full then
				h.version = getnum(h, 1)
				h.flags = getnum(h, 3)
			end
			if fmt and fmt.nested or not fmt and container and container.tag == "ilst" then
				scan(h)
			end
			if proc then
				-- data container (skip data?)
				local predef = fmt.predef
				
				if predef then get(h, predef, true) end
				
				local data = get(h, h.len)
					
				proc(h, data)
			
				-- test:
				if dump then
					h.data = "\n" .. hexdump { data:byte(1, h.tag == "ilst" and 1024 or 64) }
					dump(h, "maxlev=1")
					h.data = nil
				end
			else
				-- skip uninteresting container
				get(h, h.len, true)
			end				
		end
		
		return container
	end
			
	local tree = scan { posn = 0 }
	
--	dump(tree)
	if not out.Length then return nil, "not an MP4 file" end
	
	if rewind then seek(fd, "set", 0)
	else fd:close()
	end
	
	return out
end

--[[--------------------------------------------------------------------
\brief extract metadata from mp4/aac file
\param fd			an open File object positioned at the start of the file
\param coverart	if nil/false then cover art data will be ignored
\return	table containing metadata info fields
--]]--------------------------------------------------------------------
id4.load = function(file, coverart, rewind)
	local r = { pcall(mp4load, file, coverart, rewind) }
	
	if not r[1] then return nil, r[2] end
	
	return unpack(r, 2)
end

return id4
