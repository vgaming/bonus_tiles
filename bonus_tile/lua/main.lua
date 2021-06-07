-- << bonustile/main.lua

bonustile = {}
local bonustile = bonustile
local wesnoth = wesnoth
local ipairs = ipairs
local math = math
local on_event = wesnoth.require("lua/on_event.lua")

local width, height, border = wesnoth.get_map_size()
local bonus_tiles_per_side = math.ceil(
	(width + 1 - 2 * border)
		* (height + 1 - 2 * border)
		/ #wesnoth.sides
		/ 30
)

local function get_side(x, y)
	return wesnoth.get_variable("bonustile_side_" .. x .. "_" .. y)
end
local function get_type(x, y)
	return wesnoth.get_variable("bonustile_type_" .. x .. "_" .. y)
end
local function get_value(x, y)
	return wesnoth.get_variable("bonustile_value_" .. x .. "_" .. y)
end

local function set_side(x, y, side)
	wesnoth.set_variable("bonustile_side_" .. x .. "_" .. y, side)
end
local function set_type(x, y, type)
	wesnoth.set_variable("bonustile_type_" .. x .. "_" .. y, type)
end
local function set_value(x, y, value)
	wesnoth.set_variable("bonustile_value_" .. x .. "_" .. y, value)
end

local function set_label(x, y, text, tooltip)
	wesnoth.label {
		x = x,
		y = y,
		text = text,
		tooltip = tooltip,
		visible_in_fog = false,
		category = "bonus_tile",
	}
end

local function remove_bonus(x, y)
	set_side(x, y, nil)
	set_type(x, y, nil)
	set_value(x, y, nil)
	set_label(x, y, nil, nil)
end

local fibonacci = { 1, 2, 3, 5, 8, 13, 21 }
local function place_random_bonus(orig_x, orig_y, side)
	local linked_hexes = bonustile.find_linked_hexes(orig_x, orig_y)
	local is_gold = wesnoth.random(1, 3) == 3
	local value = fibonacci[is_gold and wesnoth.random(4, 6) or wesnoth.random(5, 7)]
	local type = is_gold and "gold" or "xp"
	local text = "+" .. value .. type
	local type_long = is_gold and "gold" or "experience"
	local tooltip = "Gives +" .. value .. type_long
		.. " to unit standing at this tile at beginning of side " .. side .. "'s turn (BonusTile add-on)"

	local number_of_bonuses_placed = 0
	for _, pair in ipairs(linked_hexes) do
		local x = pair[1]
		local y = pair[2]
		if get_side(x, y) == nil then
			number_of_bonuses_placed = number_of_bonuses_placed + 1
			set_value(x, y, value)
			set_type(x, y, type)
			set_side(x, y, side)
			set_label(x, y, text, tooltip)
		end
	end
	return number_of_bonuses_placed
end

local peasant = wesnoth.get_units { id = "bonustile_peasant" }[1]
if peasant == nil then
	peasant = wesnoth.create_unit { type = "Peasant", id = "bonustile_peasant" }
end

on_event("start", function()
	for _, side in ipairs(wesnoth.sides) do
		if side.__cfg.allow_player then
			side.village_gold = side.village_gold - 1
		end
	end
end)

on_event("side turn", function()
	local side = wesnoth.current.side

	for y = border, height - border + 1 do
		for x = border, width - border + 1 do
			local bonus_side = get_side(x, y)
			if bonus_side == side then
				local unit = wesnoth.get_unit(x, y)
				if unit then
					local bonus_type = get_type(x, y)
					local bonus_value = get_value(x, y)
					if bonus_type == "xp" then
						unit.experience = unit.experience + bonus_value
						wesnoth.advance_unit(unit)
					else
						wesnoth.sides[unit.side].gold = wesnoth.sides[unit.side].gold + bonus_value
					end
				end
				remove_bonus(x, y)
			end
		end
	end

	local attempts = 0
	local number_of_bonuses_placed = 0
	while number_of_bonuses_placed < bonus_tiles_per_side and attempts < bonus_tiles_per_side * 10 do
		attempts = attempts + 1
		local x = wesnoth.random(border, width - border + 1)
		local y = wesnoth.random(border, height - border + 1)
		local terrain = wesnoth.get_terrain(x, y)
		if wesnoth.unit_movement_cost(peasant, terrain) < 10 then
			number_of_bonuses_placed = number_of_bonuses_placed + place_random_bonus(x, y, side)
		end
	end
end)

-- >>
