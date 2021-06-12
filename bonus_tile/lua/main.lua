-- << bonustile/main.lua

bonustile = {}
local bonustile = bonustile
local wesnoth = wesnoth
local ipairs = ipairs
local math = math
local on_event = wesnoth.require("lua/on_event.lua")
local T = wesnoth.require("lua/helper.lua").set_wml_tag_metatable {}

---@type number
local width, height, border = wesnoth.get_map_size()
local bonus_tiles_per_side = math.ceil(
	(width + 1 - 2 * border)
		* (height + 1 - 2 * border)
		/ #wesnoth.sides -- bonuses are generated for each side
		/ 30
)

---@return number
local function get_side(x, y)
	return wesnoth.get_variable("bonustile_side_" .. x .. "_" .. y)
end

---@return string
local function get_type(x, y)
	return wesnoth.get_variable("bonustile_type_" .. x .. "_" .. y)
end

---@return number
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

local bonuses_type = {
	"gold", "gold", "gold",
	"heal", "heal",
	"xp", "xp",
	"mp", "mp",
	"hp", "hp",
	"dmg", "dmg",
	"teleport",
	"sand", "sand", "sand",
	"troll",
	"petrify",
	"friendship",
};
local bonuses_values = {
	gold = { 5, 5, 5, 8, 8, 13 },
	heal = { 5, 5, 5, 8, 8, 10 },
	xp = { 5, 5, 5, 10, 10, 15 },
	mp = { 1 },
	hp = { 10 },
	dmg = { 10 },
	teleport = { -1 },
	sand = { 1 },
	troll = { 1 },
	petrify = { 1 },
	friendship = { 1 },
}
local bonuses_name_short = {
	gold = "+@gold",
	heal = "+@heal",
	xp = "+@xp",
	mp = "+@mp",
	hp = "+@%hp",
	dmg = "+@%dmg",
	teleport = "portal",
	sand = "quicksand",
	troll = "trollify",
	petrify = "petrify",
	friendship = "friendship",
}
local bonuses_name_long = {
	gold = "Gives +@ gold",
	heal = "Gives +@ heal",
	xp = "Gives +@ experience",
	mp = "Gives +@ movement (permanent)",
	hp = "Gives +@% of unit base hitpoints (permanent, but not current)",
	dmg = "Gives +@% of unit base damages (permanent, cumulative but rounded down)",
	teleport = "Brings you to a random place on the map",
	sand = "Traps for @ turn",
	troll = "Gives troll appearance for @ turn",
	petrify = "Petrifies for @ turn",
	friendship = "Makes the unit peaceful for @ turn. It cannot attack and doesn't receive damage",
}

local function random_from(arr)
	return arr[wesnoth.random(1, #arr)]
end

local function place_random_bonus(orig_x, orig_y, side)
	local linked_hexes = bonustile.find_linked_hexes(orig_x, orig_y)
	local type = random_from(bonuses_type)
	local values_arr = bonuses_values[type]
	local value = random_from(values_arr)

	local label_text = bonuses_name_short[type]:gsub("@", value)
	local label_tooltip = bonuses_name_long[type]:gsub("@", value)
		.. ". Applies to unit standing at this tile at beginning of side "
		.. side .. "'s turn (BonusTile add-on)"

	local number_of_bonuses_placed = 0
	for _, pair in ipairs(linked_hexes) do
		local x = pair[1]
		local y = pair[2]
		if get_side(x, y) == nil then
			number_of_bonuses_placed = number_of_bonuses_placed + 1
			set_value(x, y, value)
			set_type(x, y, type)
			set_side(x, y, side)
			set_label(x, y, label_text, label_tooltip)
		end
	end
	return number_of_bonuses_placed
end

local peasant = wesnoth.get_units { id = "bonustile_peasant" }[1]
if peasant == nil then
	peasant = wesnoth.create_unit { type = "Peasant", id = "bonustile_peasant" }
end

local function generate_bonuses_for_side(side)
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
end

on_event("start", function()
	for _, side in ipairs(wesnoth.sides) do
		if side.__cfg.allow_player then
			side.village_gold = side.village_gold - 1
		end
		generate_bonuses_for_side(side.side)
	end
end)

on_event("turn refresh", function()
	local side = wesnoth.current.side

	for y = border, height - border + 1 do
		for x = border, width - border + 1 do
			local bonus_side = get_side(x, y)
			if bonus_side == side then
				local unit = wesnoth.get_unit(x, y)
				if unit then
					local bonus_type = get_type(x, y)
					local bonus_value = get_value(x, y)
					if bonus_type == "gold" then
						wesnoth.sides[unit.side].gold = wesnoth.sides[unit.side].gold + bonus_value
					elseif bonus_type == "heal" then
						-- some Eras allow more than maximum HP
						if unit.hitpoints < unit.max_hitpoints then
							unit.hitpoints = math.min(unit.max_hitpoints, unit.hitpoints + bonus_value)
						end
					elseif bonus_type == "xp" then
						unit.experience = unit.experience + bonus_value
						wesnoth.advance_unit(unit)
					elseif bonus_type == "mp" then
						wesnoth.add_modification(unit, "object", {
							T.effect { apply_to = "movement", increase = bonus_value },
						})
					elseif bonus_type == "hp" then
						local add_raw = wesnoth.unit_types[unit.type].max_hitpoints * bonus_value / 100
						local add = math.max(1, math.floor(add_raw))
						wesnoth.add_modification(unit, "object", {
							T.effect { apply_to = "hitpoints", increase_total = add },
						})
					elseif bonus_type == "dmg" then
						local prev = unit.variables["bonustile_dmg"] or 0
						local new = prev + bonus_value
						unit.variables["bonustile_dmg"] = new
						wesnoth.wml_actions.remove_object {
							object_id = "bonustile_dmg"
						}
						wesnoth.add_modification(unit, "object", {
							id = "bonustile_dmg",
							T.effect { apply_to = "attack", increase_damage = "+" .. new .. "%" },
						})
					elseif bonus_type == "teleport" then
						local teleport_attempt = 0
						while teleport_attempt < 10 do
							teleport_attempt = teleport_attempt + 1
							local tx = wesnoth.random(border, width + 1 - border)
							local ty = wesnoth.random(border, height + 1 - border)
							if wesnoth.unit_movement_cost(unit, wesnoth.get_terrain(tx, ty)) <= 4
								and wesnoth.get_unit(tx, ty) == nil
							then
								unit.loc = { tx, ty }
							end
						end
					elseif bonus_type == "sand" then
						unit.variables.bonustile_sand = bonus_value
					elseif bonus_type == "troll" then
						unit.variables.bonustile_troll = bonus_value
						wesnoth.add_modification(unit, "object", {
							duration = "turn",
							T.effect { apply_to = "image_mod", add = "O(0)" },
							T.effect { apply_to = "overlay", add = "units/trolls/whelp.png" },
						})
					elseif bonus_type == "petrify" then
						unit.variables.bonustile_petrify = bonus_value
						unit.status.petrified = true
					elseif bonus_type == "friendship" then
						unit.variables.bonustile_friendship = bonus_value
						unit.status.invulnerable = true
					else
						wesnoth.message("Bonus Tiles", "Cannot apply unknown bonus type " .. bonus_type)
					end
				end
				remove_bonus(x, y)
			end
		end
	end
	generate_bonuses_for_side(side)
end)

on_event("turn refresh", function()
	local side = wesnoth.current.side
	for _, unit in ipairs(wesnoth.get_units { side = side }) do

		-- sand
		local sand = unit.variables.bonustile_sand or -1
		if sand > 0 then
			unit.moves = 0
			unit.variables.bonustile_sand = sand - 1
		end

		-- troll
		local troll = unit.variables.bonustile_troll or -1
		if troll > 0 then
			unit.variables.bonustile_troll = troll - 1
		elseif troll == 0 then
			unit.variables.bonustile_troll = nil
			wesnoth.wml_actions.remove_unit_overlay {
				image = "units/trolls/whelp.png",
			}
			local img = unit.image_mods:gsub("O%(0%)$", "NOP()", 1)
			wesnoth.add_modification(unit, "object", {
				T.effect { apply_to = "image_mod", replace = img },
			})
		end

		-- petrify
		local petrify = unit.variables.bonustile_petrify or -1
		if petrify > 0 then
			unit.variables.bonustile_petrify = petrify - 1
		elseif petrify == 0 then
			unit.status.petrified = false
			unit.variables.bonustile_petrify = nil
		end

		-- friendship
		local friendship = unit.variables.bonustile_friendship or -1
		if friendship > 0 then
			unit.variables.bonustile_friendship = friendship - 1
			unit.attacks_left = 0
		elseif friendship == 0 then
			unit.status.invulnerable = false
		end

	end
end)

--on_event("side turn", function()
--	local side = wesnoth.current.side
--	for _, unit in ipairs(wesnoth.get_units { side = side }) do
--	end
--end)

-- >>
