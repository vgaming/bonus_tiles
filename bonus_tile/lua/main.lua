-- << main | bonus_tile
if rawget(_G, "main | bonus_tile") then
	-- TODO: remove this code once https://github.com/wesnoth/wesnoth/issues/8157 is fixed
	return
else
	rawset(_G, "main | bonus_tile", true)
end

bonustile = {}
local bonustile = bonustile
local wesnoth = wesnoth
local ipairs = ipairs
local math = math
local table = table
local string = string
local mathx = mathx
local on_event = wesnoth.require("lua/on_event.lua")

---@type number
local width = wesnoth.current.map.playable_width
---@type number
local height = wesnoth.current.map.playable_height
---@type number
local border = wesnoth.current.map.border_size
local bonus_tiles_per_side = math.ceil(
	(width + 1 - 2 * border)
		* (height + 1 - 2 * border)
		/ 25
)

---@return string
local function get_type(x, y)
	return wml.variables["bonustile_type_" .. x .. "_" .. y]
end

---@return number
local function get_value(x, y)
	return wml.variables["bonustile_value_" .. x .. "_" .. y]
end

local function set_type(x, y, type)
	wml.variables["bonustile_type_" .. x .. "_" .. y] = type
end
local function set_value(x, y, value)
	wml.variables["bonustile_value_" .. x .. "_" .. y] = value
end

local bonuses_type = {
	"gold", "gold", "gold", "gold", "gold", "gold", "gold",
	"heal", "heal", "heal", "heal", "heal", "heal",
	"xp", "xp", "xp", "xp",
	"mp", "mp",
	"hp", "hp",
	"dmg", "dmg",
	"teleport",
	"sand", "sand",
	"troll","troll","troll",
	"petrify",
	"friendship",
};

local bonuses_values = {
	gold = { 5, 5, 5, 5, 8, 8, 13 },
	heal = { 5, 5, 5, 5, 8, 8, 10 },
	xp = { 3, 3, 3, 5, 5, 5, 8 },
	mp = { 1 },
	hp = { 10 },
	dmg = { 10 },
	teleport = { -1 },
	sand = { 1 },
	troll = { 1 },
	petrify = { 1 },
	friendship = { 1 },
	--morph = { -1 },
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
	--morph = "morph",
}
local bonuses_name_long = {
	gold = "Gives +@ gold",
	heal = "Heals @ hp",
	xp = "Gives +@ experience permanently",
	mp = "Gives +@ movement permanently",
	hp = "Gives +@% of unit base hitpoints permanently",
	dmg = "Gives +@% to unit base damages permanently",
	teleport = "Teleports to a random place on the map (maximum 3 moves away)",
	sand = "Traps a unit for @ turn, making it unable to move",
	troll = "Transforms into a Troll for @ turn",
	petrify = "Traps and petrifies a unit for @ turn, making it unable to move or attack",
	friendship = "Makes the unit peaceful for @ turn. Such unit cannot attack and doesn't receive damage",
	--morph = "Permanently morph this unit into another one of same cost",
}

local function update_label(x, y)
	local type = get_type(x, y)
	local value = get_value(x, y)
	local text = type and bonuses_name_short[type]:gsub("@", value)
	local tooltip = type and bonuses_name_long[type]:gsub("@", value)
		--.. ". Applies to unit standing at this tile at beginning of side " .. side .. "'s turn"
		.. " (BonusTile add-on"
		--.. ", side " .. side
		.. ")"

	wesnoth.map.add_label {
		x = x,
		y = y,
		text = text,
		tooltip = tooltip,
		visible_in_fog = false,
		category = "bonus_tile",
	}
end

function bonustile.exported_change_bonus_position_v1(oldx, oldy, newx, newy)
	set_type(newx, newy, get_type(oldx, oldy))
	set_value(newx, newy, get_value(oldx, oldy))
	update_label(oldx, oldy)
	update_label(newx, newy)
end

local function random_from(arr)
	return arr[mathx.random(1, #arr)]
end

local function place_random_bonus(orig_x, orig_y)
	local linked_hexes = bonustile.find_linked_hexes(orig_x, orig_y)
	local type = random_from(bonuses_type)
	local values_arr = bonuses_values[type]
	local value = random_from(values_arr)

	local number_of_bonuses_placed = 0
	for _, pair in ipairs(linked_hexes) do
		local x = pair[1]
		local y = pair[2]
		if get_type(x, y) == nil then
			number_of_bonuses_placed = number_of_bonuses_placed + 1
			set_value(x, y, value)
			set_type(x, y, type)
			update_label(x, y)
		end
	end
	return number_of_bonuses_placed
end

local peasant = wesnoth.units.find_on_map { id = "bonustile_peasant" }[1]
if peasant == nil then
	peasant = wesnoth.units.create { type = "Peasant", id = "bonustile_peasant" }
end

local function generate_bonuses()
	local attempts = 0
	local number_of_bonuses_placed = 0
	while number_of_bonuses_placed < bonus_tiles_per_side and attempts < bonus_tiles_per_side * 10 do
		attempts = attempts + 1
		local x = mathx.random(math.max(border, 1) + 1, width - math.max(border, 1) + 1)
		local y = mathx.random(math.max(border, 1) + 1, height - math.max(border, 1) + 1)
		local terrain = wesnoth.current.map[{x, y}]
		if wesnoth.units.movement_on(peasant, terrain) < 10 then
			number_of_bonuses_placed = number_of_bonuses_placed + place_random_bonus(x, y)
		end
	end
end

on_event("start", function()
	for _, side in ipairs(wesnoth.sides) do
		if side.__cfg.allow_player then
			side.village_gold = side.village_gold - 1
		end
	end
	wml.variables["bonustile_enabled"] = true
end)

local humans_count = 0
for _, side in ipairs(wesnoth.sides) do
	if side.__cfg.allow_player then
		humans_count = humans_count + 1
	end
end

on_event("turn refresh", function()
	if not wesnoth.sides[wesnoth.current.side].__cfg.allow_player then
		return
	end
	if wml.variables.bonus_tile_turn_refreshes
		and wml.variables.bonus_tile_turn_refreshes < humans_count - 2 then
		wml.variables.bonus_tile_turn_refreshes = wml.variables.bonus_tile_turn_refreshes + 1
		return
	end
	wml.variables.bonus_tile_turn_refreshes = 0
	--wesnoth.message(
	--	"Bonus Tiles",
	--	"Let's harvest and generate bonuses! Turn: "
	--		.. wesnoth.current.turn
	--		.. ", side: " .. wesnoth.current.side
	--)

	for y = math.max(border, 1), height - math.max(border, 1) + 1 do
		for x = math.max(border, 1), width - math.max(border, 1) + 1 do
			local bonus_type = get_type(x, y)
			local unit = wesnoth.units.get(x, y)
			if unit ~= nil and bonus_type ~= nil then
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
					wesnoth.units.add_modification(unit, "object", {
						wml.tag.effect { apply_to = "movement", increase = bonus_value },
					})
				elseif bonus_type == "hp" then
					local add_raw = wesnoth.unit_types[unit.type].max_hitpoints * bonus_value / 100
					local add = math.max(1, math.floor(add_raw))
					wesnoth.units.add_modification(unit, "object", {
						wml.tag.effect { apply_to = "hitpoints", increase_total = add },
					})
				elseif bonus_type == "dmg" then
					local dmg = (unit.variables["bonustile_dmg"] or 0) + bonus_value
					unit.variables["bonustile_dmg"] = dmg
					wesnoth.remove_modifications(unit, { id = "bonustile_dmg" }, "object")
					wesnoth.units.add_modification(unit, "object", {
						id = "bonustile_dmg",
						wml.tag.effect { apply_to = "attack", increase_damage = "+" .. dmg .. "%" },
					})
				elseif bonus_type == "teleport" then
					local teleport_attempt = 0
					while teleport_attempt < 10 do
						teleport_attempt = teleport_attempt + 1
						local tx = mathx.random(border, width + 1 - border)
						local ty = mathx.random(border, height + 1 - border)
						local _, cost = wesnoth.paths.find_path(unit.loc, tx, ty, { ignore_units = true })
						if wesnoth.units.get(tx, ty) == nil and cost <= unit.max_moves * 3 then
							unit.loc = { tx, ty }
						end
					end
				elseif bonus_type == "sand" then
					unit.variables.bonustile_sand = bonus_value
				elseif bonus_type == "troll" then
					unit.variables.bonustile_troll = bonus_value
					if not unit.variables.bonustile_troll_type then
						unit.variables.bonustile_troll_type = unit.type
						unit.variables.bonustile_troll_advances = table.concat(unit.advances_to, ",")
						local increase_max_hp = math.max(0, unit.max_hitpoints - 50)
						wesnoth.units.add_modification(unit, "object", {
							id = "bonustile_troll",
							wml.tag.effect { apply_to = "hitpoints", increase_total = increase_max_hp },
							wml.tag.effect { apply_to = "max_experience", increase = 1000 },
						})
						if unit.level <= 1 then
							wesnoth.transform_unit(unit, "Troll Whelp")
						elseif unit.level == 2 then
							wesnoth.transform_unit(unit, "Troll")
						else
							wesnoth.transform_unit(unit, "Troll Warrior")
						end
					end
				elseif bonus_type == "troll_old" then
					unit.variables.bonustile_troll = bonus_value
					wesnoth.units.add_modification(unit, "object", {
						wml.tag.effect { apply_to = "image_mod", add = "O(0)" },
						wml.tag.effect { apply_to = "overlay", add = "units/trolls/whelp.png" },
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
			set_type(x, y, nil)
			set_value(x, y, nil)
			update_label(x, y)
		end
	end

	generate_bonuses()
end)

local function split_comma(str)
	local result = {}
	local n = 1
	for s in string.gmatch(str or "", "%s*[^,]+%s*") do
		if s ~= "" then
			result[n] = s
			n = n + 1
		end
	end
	return result
end

on_event("turn refresh", function()
	local side = wesnoth.current.side
	for _, unit in ipairs(wesnoth.units.find_on_map { side = side }) do

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
			wesnoth.remove_modifications(unit, { id = "bonustile_troll" }, "object")
			wesnoth.transform_unit(unit, unit.variables.bonustile_troll_type)
			unit.advances_to = split_comma(unit.variables.bonustile_troll_advances)
			unit.variables.bonustile_troll = nil
			unit.variables.bonustile_troll_type = nil
			unit.variables.bonustile_troll_advances = nil
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

-- >>
