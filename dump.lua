#! /usr/bin/env lua
--[[-%tabs=3----------------------------------------------------------------
|                                                                          |
|  Module:     dump.lua                                                    |
|  Function:   General Lua Dump Function                                   |
|  Created:    17:04:11  13 Aug  2005                                      |
|  Author:     Andrew Cannon <ajc@gmx.net>                                 |
|                                                                          |
|  Copyright(c) 2005-2019 Andrew Cannon                                    |
|  Licensed under the terms of the MIT License                             |
|                                                                          |
]]--------------------------------------------------------------------------

local type = type
local tostring = tostring
local tonumber = tonumber
local error = error
local next = next
local pairs = pairs
local ipairs = ipairs
local rawget = rawget
local getmetatable = getmetatable
local io = io
local string = string
local table = table
local _G = _G

if _VERSION:match"Lua 5%.[12]" then
	module("dump")
end

local string_rep = string.rep
local string_gsub = string.gsub
local table_insert = table.insert
local table_sort = table.sort

local controlchars = {
	["\0"]="0",
	["\a"]="a", ["\b"]="b", ["\f"]="f", ["\n"]="n", ["\r"]="r", ["\t"]="t", ["\v"]="v",
	["\\"]="\\", ["\""]="\"", ["'"]="'"
}

-- formatted dump
-----------------
--
-- flags: an optional string or table containing option specifications:
--	maxlev=<num>	maximum depth for nested tables
--	indent=<num>	number of spaces or string (in table only) for indenting nested tables
--	expand			expand duplicated tables individually (caution!)
--	cooked			dump using pairs(), otherwise next() (raw entries)
--	nometa			do not show metatable
--	writer			specify output function (fn, true => debug_writer, or name of global fn)
--	header			header at start of dump (in table, or remainder of string option)
-- align				align dump output with end of header column
--	sort				sort table entries
-- noadrs			do not show table address
--
function _G.dump(var, flags)

	local opttab = type(flags) == "table" and flags or {}
	local optstr = type(flags) == "string" and flags or ""
	
	local maxlev = opttab.maxlev or tonumber(optstr:match"%f[%a]maxlev=(%d+)") or type(flags) == "number" and flags
	local indent = opttab.indent or tonumber(optstr:match"%f[%a]indent=(%d+)") or "   "
	local expand = opttab.expand or (optstr:match"%f[%a]expand%f[%A]")
	local cooked = opttab.cooked or (optstr:match"%f[%a]cooked%f[%A]") or type(flags) == "boolean" and flags
	local nometa = opttab.nometa or (optstr:match"%f[%a]nometa%f[%A]")
	local writer = opttab.writer or (optstr:match"%f[%a]writer=([%a_][%w_]*)")
	local header = opttab.header or (optstr:match"%f[%a]header=(.*)")
	local sort = opttab.sort or (optstr:match"%f[%a]sort%f[%A]")
	local align = opttab.align or (optstr:match"%f[%a]align%f[%A]")
	local noadrs = opttab.noadrs or (optstr:match"%f[%a]noadrs%f[%A]")
	
	if not writer then writer = io.write
	elseif writer == true then writer = _G.debug_writer or io.write
	elseif type(writer) ~= "function" then writer = _G[writer]
	end	
	if not writer then error("dump: invalid writer: "..tostring(writer)) end

	if header then
		writer(header)
		align = align and header:match"[^\n]+$"
		align = align and string_rep(' ', #align)
	end
	if type(indent) == "number" then indent = string_rep(" ", indent) end

	if sort and type(sort) ~= "function" then
		sort = function(k1, k2)
			local n1, n2 = type(k1) == "number", type(k2) == "number"
			
			if n1 then
				return not n2 or k1 < k2
			else
				return not n2 and tostring(k1) < tostring(k2)
			end
		end
	end
	
	local done = {}
	local level = 0
	local function putstr(s)
		writer((string_gsub(s, "[^%w%p%s'\"\\]", function(c) return "\\"..(controlchars[c] or ("x%02x"):format(c:byte())) end)))
	end
	local function newline(str)
		writer("\n")
		if align then writer(align) end
		for i = 1,level do
			writer(indent)
		end
		if str then putstr(str) end
	end
	local get = cooked and function(t, k) return t[k] end or rawget
	local scan = cooked and pairs or function(t) return next, t end
	
	-- determine lowest display level for each table
	--
	local function dump1(var)
		if maxlev and level == maxlev then return end
		if type(var) ~= "string" then
			level = level + 1
			if not done[var] then
				done[var] = level
				if type(var) == "table" then
					for key in scan(var) do
						dump1(get(var,key))
					end
				end
				
				local meta = getmetatable(var)
				
				if meta then
					dump1(meta)
				end				
			elseif level < done[var] then
				done[var] = level
			end
			level = level - 1
		end
	end
		
	local function dump2(var, parent)
		if type(var) == "string" then writer('"') end
		if noadrs and type(var) == "table" then
			putstr("<table>")
		else
			putstr(tostring(var))
		end
		if type(var) == "string" then writer('"') end
		
		if maxlev and level == maxlev then return end
		if type(var) ~= "string" and (not done[var] or done[var] > level) then
			done[var] = 0
			
			local meta = not nometa and getmetatable(var)
			
			if meta then
				level = level + 1
				newline("[metatable: ")
				dump2(meta, var)
				if meta == var then writer(" [self]") end
				if meta == parent then writer(" [parent]") end
				writer("]")
				level = level - 1
			end
			if type(var) == "table" then
				local function dokey(key)
					if type(key) == "string" then
						newline("."..tostring(key).."=>")
					elseif noadrs and type(key) == "table" then
						newline("[<table>]=>")
					else
						newline("["..tostring(key).."]=>")
					end
					
					local value = get(var, key)
					
					dump2(value, var)
					if value == var then writer(" [self]") end
					if value == parent then writer(" [parent]") end
				end
				
				writer(" = {")
				level = level + 1	
				if sort then
					local keys = {}
					
					for key in scan(var) do
						table_insert(keys, key)
					end
					table_sort(keys, sort)
					for _,key in ipairs(keys) do
						dokey(key)
					end
				else -- unsorted
					for key in scan(var) do
						dokey(key)
					end
				end
				level = level - 1
				newline("}")
			end
			if expand then done[var] = nil end
		end
	end
	
	if var == nil then
		writer"nil"
	else
		if not expand then dump1(var) end
		dump2(var)
	end
	writer("\n")
end

function _G.ddump(v, ...)			if _G.debug_level ~= 0 then _G.dump(v, ...) end end
function _G.d1dump(v, ...)			if _G.debug_level >= 1 then _G.dump(v, ...) end end
function _G.d2dump(v, ...)			if _G.debug_level >= 2 then _G.dump(v, ...) end end
function _G.d3dump(v, ...)			if _G.debug_level >= 3 then _G.dump(v, ...) end end
function _G.d4dump(v, ...)			if _G.debug_level >= 4 then _G.dump(v, ...) end end
function _G.d5dump(v, ...)			if _G.debug_level >= 5 then _G.dump(v, ...) end end
function _G.d6dump(v, ...)			if _G.debug_level >= 6 then _G.dump(v, ...) end end
function _G.d7dump(v, ...)			if _G.debug_level >= 7 then _G.dump(v, ...) end end
