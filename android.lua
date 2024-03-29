--%tabs=3
--[[--

	lua/love2d helper functions for use with Android OS
	
--]]--

local require = require
local ipairs = ipairs
local pcall = pcall
local type = type

local table = require "table"
local lfs = require "lfs"

-- use terminal if available
local packageLoaded = package.loaded

local android = {}
if _VERSION:match"Lua 5%.[12]" then
	_G.android = android
	module "android"
end

local function getSdPaths(locations)
	--
	-- default locations (should work in most cases)
	--
	locations = locations or {
		{ name = "storage", "sdcard0", "extSdCard", "%w%w%w%w%-%w%w%w%w" },
		--{ name = "mnt", "sdcard", "extSdCard", "external_sd",	{ name = "media_rw", "%w%w%w%w%-%w%w%w%w" }},
	}
	
	local out = {}
	local ino = {}
	local function scandir(desc, path)
		for entry in lfs.dir(path or "/") do
			for _, sub in ipairs(desc) do
				local pattern = type(sub) == "table" and sub.name or sub
				
				if entry:match("^" .. pattern .. "$") then
					local dirpath = (path or "") .. "/" .. entry
					
					if type(sub) == "table" then
						pcall(scandir, sub, dirpath)
					else
						local attr = lfs.attributes(dirpath)
						
						if not ino[attr.ino] then
							table.insert(out, dirpath)
							ino[attr.ino] = dirpath
						end
					end
				end
			end
		end
	end
	pcall(scandir, locations)
	
	if packageLoaded.terminal then
		pcall(packageLoaded.terminal.print, "Android SD paths:")
		pcall(packageLoaded.terminal.dump, out)
	end
	
	return out
end

android.getSdPaths = getSdPaths

return android
