--%tabs=3

local function prequire(module)
	local ok, mod = pcall(require, module)
	
	return ok and mod or nil
end

local _G = _G
local print = print
local pcall = pcall
local ipairs = ipairs
local table = require"table"
local string = require"string"
local coroutine = require"coroutine"
local bit = prequire"bit" or prequire"bit32" or {}
local utf8 = prequire"utf8" or {}

local char = string.char
local format = string.format
local insert = table.insert
local remove = table.remove
local concat = table.concat
local unpack = table.unpack or unpack
local band = bit and bit.band or load[[
		local r = 0xFFFFFFFF
		
		for _, n in ipairs { ... } do
			r = r & n
		end
		return r
	]]
local toutf8 = utf8.char or function(...)
		local t = { ... }
		
		for i, c in ipairs(t) do
			t[i] = c < 256 and char(c) or '?'
		end
		return concat(t)
	end

local wrap = coroutine.wrap
local yield = coroutine.yield

local dprint = dprint or function() end
local dprintf = dprintf or function() end


local tagmap = {
	-- 2.3 tags
	TSSE = function(text) return "CreatedBy", text end,
	TIT2 = function(text) return "TrackName", text end,
	TPE1 = function(text) return "Artist", text end,
	TALB = function(text) return "Album", text end,
	TRCK = function(text) return "TrackNumber", tonumber(text:match"0*(.*)") end,
	TCON = function(text) return "Genre", text end,
	TYER = function(text) return "Year", tonumber(text) end,
	TLEN = function(text) return "Length", tonumber(text) / 1000.0 end,
	
	-- 2.4 tags
	TORY = function(text) return "Year", tonumber(text) end,
	
	-- 2.2 tags
	TEN = function(text) return "CreatedBy", text end,
	TT2 = function(text) return "TrackName", text end,
	TP1 = function(text) return "Artist", text end,
	TAL = function(text) return "Album", text end,
	TRK = function(text) return "TrackNumber", tonumber(text:match"0*(.*)") end,
	TCO = function(text) return "Genre", text end,
	TYE = function(text) return "Year", tonumber(text) end,
	TLE = function(text) return "Length", tonumber(text) / 1000.0 end,
	
}


local id3 = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.id3 = id3
	module "id3"
end


local function loadtag(fd, setpos, hdr)
	local rev1, rev2 = hdr:byte(4, 5)
	local flags = hdr:byte(6, 6)
	local s1, s2, s3, s4 = hdr:byte(7, 10)
	local size = ((s1 * 128 + s2) * 128 + s3) * 128 + s4

	dprintf("version 2.%d.%d flags 0x%02X size %d", rev1, rev2, flags, size)

	local unsync = band(flags, 0x80) ~= 0
	local hasexthdr = rev1 > 2 and band(flags, 0x40) ~= 0
	local experimental = rev1 > 2 and band(flags, 0x20) ~= 0
	local footer = rev1 > 3 and band(flags, 0x10) ~= 0				-- 2.4 only
	
	local length = size
	local function reader()
		if length == 0 then return end
		length = length - 1
		
		local ch = fd:read(1)
	
		if not ch then error "unexpected end of tag" end
		return ch:byte()
	end
	local readsync = wrap(function()
			local ff = false
			
			while true do
				local byte = reader()
			
				if not ff or byte ~= 0 then	-- skip 00 following FF
					yield(byte)
				end
				ff = byte == 0xFF
			end
		end)
	local get1 = reader		-- read one byte (default for 2.4)
	local function get(n, unsync)
		local t = {}
		local getter = unsync and readsync or get1
		
		for i = 1, n do insert(t, getter()) end
		return t
	end
	local function skip(n)
		for i = 1, n do get1() end
	end
	local sizemult = 128
	local sizesize = 4
	local function getsize()
		local acc = 0
		
		for i = 1, n or sizesize do
			acc = acc * sizemult + get1()
		end
		return acc
	end
	local tagsize = 4
	local function getframe()
		if length > 0 then
			local tag = char(unpack(get(tagsize)))
			
			if tag:match"^%z" then return end	-- reached padding
			
			local size = getsize()
			
			if rev1 > 2 then
				local flag1 = get1()	
				local flag2 = get1()				
			
				--local tagalterpres = band(flag1, 0x40) ~= 0
				--local filealterpres = band(flag1, 0x20) ~= 0
				--local readonly = band(flag1, 0x10) ~= 0
				local grouping = band(flag2, 0x40) ~= 0
				local compression = band(flag2, 0x08) ~= 0
				local encryption = band(flag2, 0x04) ~= 0
				local unsyncframe = band(flag2, 0x02) ~= 0
				local datalengthind = band(flag2, 0x01) ~= 0
		
				if grouping then get1() end -- read and ignore grouping byte
				if encryption then get1() end -- read and ignore encryption scheme
				if datalengthind then get(4) end -- read and ignore uncompressed data length
				
				return { tag = tag, size = size, flags = { flag1, flag2 }, data = get(size, unsyncframe) }
			else
				return { tag = tag, size = size, flags = {}, data = get(size) }
			end
		end
	end
	local function hexdump(t, head)
		local out = { "0000 "}
		local ascii = {}
		
		for i, b in ipairs(t) do
			
			if i > 1 and i % 16 == 1 then
				insert(out, ("  %s\n%s%04X "):format(concat(ascii), head, i - 1))
				ascii = {}
			elseif i > 1 and i % 8 == 1 then
				insert(out, " ")
			end
			insert(out, (" %02X"):format(b))
			insert(ascii, b >= 0x20 and b < 0x7F and char(b) or ".")
		end
		local r = #t % 16
		if r > 0 then
			insert(out, (" "):rep((16 - r) * 3 + (r <= 8 and 3 or 2)))
			insert(out, concat(ascii))
		end
		return concat(out)
	end
	
	
	if rev1 < 4 then	
		-- 2.2/2.3 use global unsync flag for reading all tag data
		get1 = function()
				if unsync then return readsync()
				else return reader()
				end
			end
		sizemult = 256			-- size fields are 32 bits
		if rev1 < 3 then
			tagsize = 3
			sizesize = 3		-- 2.2 has 3 byte sizes
		end
	end

	if hasexthdr then
		-- get extended header
		local exthdrsize = getsize()
		
		-- ...and ignore it
		skip(exthdrsize)
	end

	local tab = {}
	for f in getframe do
		local tagfn = tagmap[f.tag]
		
		d2printf("%4s[%02X%02X]: %s", f.tag, f.flags[1] or 0, f.flags[2] or 0, hexdump(f.data, "            "))
		
		if tagfn then
			local text = ""

			if f.data[1] == 0 then			-- ascii (ISO-8859-1) data
				text = char(unpack(f.data, 2))
				
			elseif f.data[1] == 1 or f.data == 2 then		-- utf-16 data
				-- UTF16 data
				local t = {}
				local function fromutf16(c) -- insert unicode into table; handle surrogates
					if c >= 0xD800 and c <= 0xDBFF then
						c = (c - 0xD800) * 1024 + 0x100000
					elseif c >= 0xDC00 and c <= 0xDFFF then
						c = c - 0xDC00 + (remove(t) or 0)
					end
					insert(t, c)
				end
				
				if f.data[1] == 2 or f.data[2] == 0xFE then
					-- BE data
					for i = 1, (#f.data - 1) / 2 do
						fromutf16(f.data[i * 2] * 256 + f.data[i * 2 + 1])
					end
				else
					-- LE data
					for i = 1, (#f.data - 1) / 2 do
						fromutf16(f.data[i * 2] + f.data[i * 2 + 1] * 256)
					end
				end
				
				if f.data[1] == 1 then	-- check BOM
					if t[1] == 0xfeff then remove(t, 1)
					else print " byte order mark missing"
					end
				end
				
				text = toutf8(unpack(t))
				
			elseif f.data[1] == 3 then
				-- UTF-8 data
				text = toutf8(unpack(f.data, 2))
				
			else						-- other (numeric?) data
				local hex = {}
				
				for _, b in ipairs(f.data) do insert(hex, format("%02X", b)) end
				text = concat(hex, " ")
			end	
			
			dprintf("%s: %s", f.tag, text)
		
			local item, data = tagfn(text)
					
			tab[item] = data
		end
	end

	if setpos then
		skip(length)
	else
		fd:close()
	end
	
	return tab
end


--[[--------------------------------------------------------------------

\brief read id3 tag

\param fd		an open File object positioned at the start of the file
\param setpos	if nil/false then the File will be closed; otherwise
					it will be positioned at the end of the ID3 tag on exit.

\return	table containing id3 info fields

--]]--------------------------------------------------------------------
id3.load = function(fd, setpos)
	local hdr = fd:read(10)

	if not hdr:match"^ID3[%z\1-\254][%z\1-\254].[%z\1-\127][%z\1-\127][%z\1-\127][%z\1-\127]" then
		return nil, "no id3v2 header found"
	end

	local r = { pcall(loadtag, fd, setpos, hdr) }
	
	if not r[1] then
		return nil, r[2]
	end
	return unpack(r, 2)
end

return id3
