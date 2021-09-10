-- << mapanalyze.lua

-- This "module" uses so called Complex Numbers https://en.wikipedia.org/wiki/Complex_number
-- We note wesnoth coordinates as wes_x, wes_y.
-- We note complex coordinates as re,im (real and imaginary components of a complex number).

local wesnoth = wesnoth
local math = math
local ipairs = ipairs
local bonustile = bonustile

local config_threshold = 0.9

local width, height = wesnoth.get_map_size()
local hex_horisontal_size = math.sqrt(3) / 2

local function to_complex(wesnoth_x, wesnoth_y)
	local re = wesnoth_x * hex_horisontal_size
	local im = - wesnoth_y + (wesnoth_x % 2) / 2
	return re, im
end

local function to_wes_coordinates(re, im)
	local wes_x = re / hex_horisontal_size
	wes_x = math.floor(wes_x + 1 / 2)
	local wes_y = math.floor((wes_x % 2) / 2 - im + 0.5)
	return wes_x, wes_y
end

local map_has_castles_or_villages = false
for wes_x = 1, width do
	for wes_y = 1, height do
		local terrain_string = wesnoth.get_terrain(wes_x, wes_y)
		local info = wesnoth.get_terrain_info(terrain_string)
		if info.castle or info.village then
			map_has_castles_or_villages = true
		end
	end
end

local unit = wesnoth.create_unit { type = "Peasant" }

local center_re = wesnoth.get_variable("mapanalyze_center_re")
local center_im = wesnoth.get_variable("mapanalyze_center_im")
if center_re == nil or center_im == nil then
	center_re = 0
	center_im = 0
	local center_tile_count = 0
	for wes_x = 1, width do
		for wes_y = 1, height do
			local terrain_string = wesnoth.get_terrain(wes_x, wes_y)
			local info = wesnoth.get_terrain_info(terrain_string)
			local walkable = not map_has_castles_or_villages
				and wesnoth.unit_movement_cost(unit, terrain_string) < 10
			if info.castle or info.village or walkable then
				local re, im = to_complex(wes_x, wes_y)
				center_re = center_re + re
				center_im = center_im + im
				center_tile_count = center_tile_count + 1
			end
		end
	end
	center_re = center_re / center_tile_count
	center_im = center_im / center_tile_count
	wesnoth.set_variable("mapanalyze_center_re", center_re)
	wesnoth.set_variable("mapanalyze_center_im", center_im)
end


local function complex_multiply(first_re, first_im, second_re, second_im)
	return first_re * second_re - first_im * second_im, first_re * second_im + first_im * second_re
end

local function rot_func(rot_re, rot_im)
	return function(wes_x, wes_y)
		local re1, im1 = to_complex(wes_x, wes_y)
		local re2, im2 = re1 - center_re, im1 - center_im
		local re3, im3 = complex_multiply(re2, im2, rot_re, rot_im)
		local re4, im4 = re3 + center_re, im3 + center_im
		return to_wes_coordinates(re4, im4)
	end
end

local rot60 = rot_func(1 / 2, hex_horisontal_size)
local rot120 = rot_func(-1 / 2, hex_horisontal_size)
local rot180 = rot_func(-1, 0)
local rot240 = rot_func(-1 / 2, -hex_horisontal_size)
local rot300 = rot_func(1 / 2, -hex_horisontal_size)

local x_mirror_func = function(wes_x, wes_y)
	local re, im = to_complex(wes_x, wes_y)
	return to_wes_coordinates(re, center_im * 2 - im)
end

local function mirror_func(rotation)
	return function(x, y)
		local mirrored_x, mirrored_y = x_mirror_func(x, y)
		return rotation(mirrored_x, mirrored_y)
	end
end

local function similar_terrain(terrain_a, terrain_b)
	if map_has_castles_or_villages then
		local a = wesnoth.get_terrain_info(terrain_a)
		local b = wesnoth.get_terrain_info(terrain_b)
		return a.castle == b.castle and a.village == b.village
	else
		--local clean = string.gsub(terrain_string, "[^A-DF-Z]", "")
		local cost_a = math.min(10, wesnoth.unit_movement_cost(unit, terrain_a))
		local cost_b = math.min(10, wesnoth.unit_movement_cost(unit, terrain_b))
		return cost_a == cost_b
	end
end

local function test_bijection(func)
	local tested_count = 0
	local match = 0
	for wes_x = 1, width do
		for wes_y = 1, height do
			local new_x, new_y = func(wes_x, wes_y)
			if new_x and new_y and new_x >= 1 and new_x <= width and new_y >= 1 and new_y <= height then
				tested_count = tested_count + 1
				local terrain_orig = wesnoth.get_terrain(wes_x, wes_y)
				local terrain_new = wesnoth.get_terrain(new_x, new_y)
				if similar_terrain(terrain_orig, terrain_new) then
					match = match + 1
				end
			end
		end
	end
	local above_threshold = match > tested_count * config_threshold
	print("hex matches: " .. tested_count ..
		", match fraction: " .. match / tested_count ..
		", is match?: " .. (above_threshold and "YES!" or "no"))
	return tested_count > 0 and above_threshold
end


local symmetry_functions = {}
for _, func in ipairs {
	rot60, rot120, rot180, rot240, rot300,
	x_mirror_func, mirror_func(rot60), mirror_func(rot120),
	mirror_func(rot180), mirror_func(rot240), mirror_func(rot300),
} do
	if test_bijection(func) then
		symmetry_functions[#symmetry_functions + 1] = func
	end
end


function bonustile.find_linked_hexes(x, y)
	local result = { {x, y} }
	local set = { [x .. "," .. y] = true }
	for _, func in ipairs(symmetry_functions) do
		local new_x, new_y = func(x, y)
		if not set[new_x .. "," .. new_y] then
			set[new_x .. "," .. new_y] = true
			result[#result + 1] = { new_x, new_y }
		end
	end
	return result
end


-- >>
