#! /usr/bin/env lua5.1
--%tabs=3

local function prequire(module)
	local ok, mod = pcall(require, module)
	
	return ok and mod or nil
end

local _G = _G
local print = print
local table = require"table"
local string = require"string"
local coroutine = require"coroutine"
local bit = prequire"bit" or prequire"bit32"
local utf8 = prequire"utf8" or string -- use string.char if no utf8

local char = string.char
local format = string.format
local insert = table.insert
local remove = table.remove
local concat = table.concat
local unpack = table.unpack or unpack
local band = bit.band
local wrap = coroutine.wrap
local yield = coroutine.yield

local ipairs = ipairs
local dprint = print--function() end

local tagmap = {
	TSSE = function(text) return "CreatedBy", text end,
	TIT2 = function(text) return "TrackName", text end,
	TPE1 = function(text) return "Artist", text end,
	TALB = function(text) return "Album", text end,
	TRCK = function(text) return "TrackNumber", tonumber(text:match"0*(.*)") end,
	TCON = function(text) return "Genre", text end,
	TYER = function(text) return "Year", tonumber(text) end,
	TLEN = function(text) return "Length", tonumber(text) / 1000.0 end,
}


module"id3"


local function load(fd, setpos)
	local hdr = fd:read(10)

	if not hdr:match"^ID3[%z\1-\254][%z\1-\254].[%z\1-\127][%z\1-\127][%z\1-\127][%z\1-\127]" then
		return nil, "no id3v2 header found"
	end

	local rev1, rev2 = hdr:byte(4, 5)
	local flags = hdr:byte(6, 6)
	local s1, s2, s3, s4 = hdr:byte(7, 10)
	local size = ((s1 * 128 + s2) * 128 + s3) * 128 + s4

	dprint(format("version 2.%d.%d flags 0x%02X size %d", rev1, rev2, flags, size))

	local unsync = band(flags, 0x80) ~= 0
	local hasexthdr = band(flags, 0x40) ~= 0
	local experimental = band(flags, 0x20) ~= 0

	local length = size
	local get1 = wrap(function()
			local ff = false
			
			while true do
				if length == 0 then return
				elseif length then length = length - 1
				end
				
				local char = fd:read(1)
				
				if not char then return end
				
				local byte = char:byte()
				
				if not ff or byte ~= 0 then
					yield(byte)
				end
				ff = unsync and byte == 0xFF
			end
		end)
				
	local function get(n)
		local t = {}
		
		for i = 1,n do
			local byte = get1()
			
			if not byte then break end
			insert(t, byte)
		end
		return t
	end
				
	local function skip(n)
		for i = 1, n do get1() end
	end

	local function getsize()
		local tsize = get(4)
		
		return ((tsize[1] * 256 + tsize[2]) * 256 + tsize[3]) * 256 + tsize[4]
	end

	if hasexthdr then
		-- get extended header
		local exthdrsize = getsize()
		
		-- ...and ignore it
		skip(exthdrsize)
	end

	local function getframe()
		if length > 0 then
			local tag = char(unpack(get(4)))
			local size = getsize()
			local flags = get(2)
		
			return { tag = tag, size = size, flags = flags, data = get(size) }
		end
	end

	local tab = {}
	for f in getframe do
		local text = ""

		if f.data[1] == 0 then
			text = char(unpack(f.data, 2))
		elseif f.data[1] == 1 then
			-- UTF16 data
			local t = {}
			
			if f.data[2] == 0xff then
				for i = 1, (#f.data - 1) / 2 do
					insert(t, f.data[i * 2] + f.data[i * 2 + 1] * 256)
				end
			else		
				for i = 1, (#f.data - 1) / 2 do
					insert(t, f.data[i * 2] * 256 + f.data[i * 2 + 1])
				end
			end
			if t[1] ~= 0xfeff then print " byte order mark missing"
			else remove(t, 1)
			end
			
			text = utf8.char(unpack(t))
			
		else
			local hex = {}
			
			for _, b in ipairs(f.data) do insert(hex, format("%02X", b)) end
			text = concat(hex, " ")
		end	
		
		dprint(format("%s: %02X %02X: %s", f.tag, f.flags[1], f.flags[2], text))
		
		local fn = tagmap[f.tag]
		if fn then
			local item, data = fn(text)
					
			--insert(tab, item)
			tab[item] = data
		end
	end

	--[[ ex:
	TSSE: 00 00: LAME 64bits version 3.100 (http://lame.sf.net)
	TIT2: 00 00: Bad Boyfriend
	TPE1: 00 00: Garbage
	TALB: 00 00: Bleed Like Me
	TRCK: 00 00: 01
	TCON: 00 00: Other
	TYER: 00 00: 2005
	TLEN: 00 00: 227173
	]]
	--[[
		if f.tag == "TSSE" then
		elseif f.tag == "TIT2" then
		elseif f.tag == "TPE1" then
		elseif f.tag == "TALB" then
		elseif f.tag == "TRCK" then
		elseif f.tag == "TCON" then
		elseif f.tag == "TYER" then
		elseif f.tag == "TLEN" then
		else
	]]
	
	if setpos then
		skip(length)
	else
		fd:close()
	end
	
	return tab
end

_G.id3.load = load
