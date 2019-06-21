--%tabs=3

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
	[0x00] = "Undefined",

-- MOVIE/DRAMA

	[0x10] = "Movie/Drama",
	[0x11] = "Detective/Thriller",
	[0x12] = "Adventure/Western/War",
	[0x13] = "Science Fiction/Fantasy/Horror",
	[0x14] = "Comedy",
	[0x15] = "Soap/Melodrama/Folkloric",
	[0x16] = "Romance",
	[0x17] = "Serious/Classical/Religious/Historical Movie/Drama",
	[0x18] = "Adult Movie/Drama",

-- NEWS/CURRENT AFFAIRS

	[0x20] = "News/Current Affairs",
	[0x21] = "News/Weather Report",
	[0x22] = "News Magazine",
	[0x23] = "Documentary",
	[0x24] = "Discussion/Interview/Debate",

-- SHOW

	[0x30] = "Show/Game Show",
	[0x31] = "Game Show/Quiz/Contest",
	[0x32] = "Variety Show",
	[0x33] = "Talk Show",

-- SPORTS

	[0x40] = "Sports",
	[0x41] = "Special Event",
	[0x42] = "Sport Magazine",
	[0x43] = "Football",
	[0x44] = "Tennis/Squash",
	[0x45] = "Team Sports",
	[0x46] = "Athletics",
	[0x47] = "Motor Sport",
	[0x48] = "Water Sport",
	[0x49] = "Winter Sports",
	[0x4A] = "Equestrian",
	[0x4B] = "Martial Sports",

-- CHILDREN/YOUTH

	[0x50] = "Children's/Youth Programmes",
	[0x51] = "Pre-school Children's Programmes",
	[0x52] = "Entertainment Programmes for 6 to 14",
	[0x53] = "Entertainment Programmes for 10 to 16",
	[0x54] = "Informational/Educational/School Programme",
	[0x55] = "Cartoons/Puppets",

-- MUSIC/BALLET/DANCE

	[0x60] = "Music/Ballet/Dance",
	[0x61] = "Rock/Pop",
	[0x62] = "Serious/Classical Music",
	[0x63] = "Folk/Traditional Music",
	[0x64] = "Musical/Opera",
	[0x65] = "Ballet",

-- ARTS/CULTURE

	[0x70] = "Arts/Culture",
	[0x71] = "Performing Arts",
	[0x72] = "Fine Arts",
	[0x73] = "Religion",
	[0x74] = "Popular Culture/Traditional Arts",
	[0x75] = "Literature",
	[0x76] = "Film/Cinema",
	[0x77] = "Experimental Film/Video",
	[0x78] = "Broadcasting/Press",
	[0x79] = "New Media",
	[0x7A] = "Arts/Culture Magazines",
	[0x7B] = "Fashion",

-- SOCIAL/POLITICAL/ECONOMICS

	[0x80] = "Social/Political/Economics",
	[0x81] = "Magazines/Reports/Documentary",
	[0x82] = "Economics/Social Advisory",
	[0x83] = "Remarkable People",

-- EDUCATIONAL/SCIENCE

	[0x90] = "Education/Science/Factual",
	[0x91] = "Nature/Animals/Environment",
	[0x92] = "Technology/Natural Sciences",
	[0x93] = "Medicine/Physiology/Psychology",
	[0x94] = "Foreign Countries/Expeditions",
	[0x95] = "Social/Spiritual Sciences",
	[0x96] = "Further Education",
	[0x97] = "Languages",

-- LEISURE/HOBBIES

	[0xA0] = "Leisure/Hobbies",
	[0xA1] = "Tourism/Travel",
	[0xA2] = "Handicraft",
	[0xA3] = "Motoring",
	[0xA4] = "Fitness &amp; Health",
	[0xA5] = "Cooking",
	[0xA6] = "Advertisement/Shopping",
	[0xA7] = "Gardening",

-- SPECIAL

	[0xB0] = "Special Characteristics",
	[0xB1] = "Original Language",
	[0xB2] = "Black &amp; White",
	[0xB3] = "Unpublished",
	[0xB4] = "Live Broadcast",

-- USERDEFINED

	[0xF0] = "Drama",
	[0xF1] = "Detective/Thriller",
	[0xF2] = "Adventure/Western/War",
	[0xF3] = "Science Fiction/Fantasy/Horror",
---- below currently ignored by XBMC see http://trac.xbmc.org/ticket/13627
	[0xF4] = "Comedy",
	[0xF5] = "Soap/Melodrama/Folkloric",
	[0xF6] = "Romance",
	[0xF7] = "Serious/ClassicalReligion/Historical",
	[0xF8] = "Adult",
}	
local tagmap = {
	["aART"]		= { "Artist" },	-- "Album Artist"?
	["\169art"]	= { "Artist" },
	["\169alb"]	= { "Album" },
	["\169gen"]	= { "Genre" },
	gnre			= { "Genre",			function(d) return genres[tobinary(d)] or genres[0] end },
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
				--h.data = "\n" .. hexdump { data:byte(1, h.tag == "ilst" and 1024 or 64) }
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
