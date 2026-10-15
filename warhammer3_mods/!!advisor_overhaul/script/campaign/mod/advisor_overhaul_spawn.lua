--- Advisor Overhaul spawn script: gives every human faction one Advisor at the start of a new campaign, next to its faction leader, whatever its race.
---
--- The Advisor's agent subtype is not recruitable, so this is the only way he enters a campaign. He is made immortal, so a defeat wounds him
--- instead of killing him, and he comes back. Each faction is spawned once: a saved value per faction guards it, so a reload never adds a second.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- The Advisor's agent type.
local AGENT_TYPE = "wizard"

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul_spawn"

--- How far from the faction leader, in map hexes, the game may look for a free spot.
local SPAWN_DISTANCE = 2

--- How far from the home settlement the game may look for a free spot when the leader is not on the map.
local SETTLEMENT_DISTANCE = 10

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end

--- The saved value key that marks a faction as done.
--- @param faction_key string The faction key.
--- @returns string The key.
local function done_key(faction_key)
	return TAG .. "_done_" .. faction_key
end

--- Whether the faction already has an Advisor. Uses the loadout script's listing, read when called since script load order is not promised.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @returns boolean True when one of its characters is an Advisor.
local function has_advisor(faction)
	return #ADVISOR_OVERHAUL.faction_advisors(faction) > 0
end

--- A free spot next to the faction leader, or next to the home settlement when the leader is not on the map.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @returns number|nil The x position, or nil when no spot was found.
--- @returns number|nil The y position.
--- @returns string How the spot was chosen, for the log.
local function spawn_spot(faction)
	local faction_key = faction:name()
	local leader = faction:faction_leader()
	if leader and not leader:is_null_interface() and not leader:is_wounded() and leader:has_military_force() then
		local where = "leader cqi " .. leader:command_queue_index() .. " at " .. leader:logical_position_x() .. "," .. leader:logical_position_y()
		local x, y = cm:find_valid_spawn_location_for_character_from_character(faction_key, cm:char_lookup_str(leader), true, SPAWN_DISTANCE)
		if x and x > 0 then
			return x, y, "next to " .. where
		end
		log(faction_key .. ": no free spot within " .. SPAWN_DISTANCE .. " of the " .. where .. ", trying the home settlement")
	else
		log(faction_key .. ": the faction leader is missing, wounded or leads no army, trying the home settlement")
	end
	local home = faction:home_region()
	if home and not home:is_null_interface() then
		local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, home:name(), false, true, SETTLEMENT_DISTANCE)
		if x and x > 0 then
			return x, y, "next to the home settlement " .. home:name()
		end
	end
	return nil, nil, "no leader and no home settlement spot"
end

--- Spawns one Advisor for a faction, unless it has been done before or the faction already has one.
--- @param faction_key string The faction key.
local function spawn_for(faction_key)
	if cm:get_saved_value(done_key(faction_key)) then
		log(faction_key .. ": already spawned in this campaign, skipped")
		return
	end
	local faction = cm:get_faction(faction_key)
	if not faction then
		log(faction_key .. ": faction not found, skipped")
		return
	end
	if has_advisor(faction) then
		log(faction_key .. ": already has an Advisor, marked done")
		cm:set_saved_value(done_key(faction_key), true)
		return
	end
	local x, y, how = spawn_spot(faction)
	if not x then
		log(faction_key .. ": " .. how .. ", no Advisor spawned")
		return
	end
	-- The subtype comes from the generated data, read when called since script load order is not promised.
	local advisor = cm:create_agent(faction_key, AGENT_TYPE, ADVISOR_OVERHAUL_RIGS.subtype, x, y, true)
	if not advisor or advisor:is_null_interface() then
		log(faction_key .. ": create_agent failed at " .. x .. "," .. y .. " (" .. how .. ")")
		return
	end
	local lookup = cm:char_lookup_str(advisor)
	cm:set_character_immortality(lookup, true)
	cm:replenish_action_points(lookup)
	local name = ADVISOR_OVERHAUL_RIGS.name
	if name then
		cm:change_character_localised_name(advisor, name, "", "", "")
	end
	cm:set_saved_value(done_key(faction_key), true)
	log(faction_key .. ": spawned Advisor cqi " .. advisor:command_queue_index() .. " at " .. x .. "," .. y .. " (" .. how .. "), immortal, named "
		.. tostring(name))
end

--- Gives every Advisor of a faction the hidden skills he is made with (his hero actions), when he lacks them. An Advisor spawned before they were
--- added to his tree never got them.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
local function add_learned_skills(faction)
	for _, advisor in ipairs(ADVISOR_OVERHAUL.faction_advisors(faction)) do
		for _, skill in ipairs(ADVISOR_OVERHAUL_RIGS.learned_skills or {}) do
			if not advisor:has_skill(skill) then
				cm:add_skill(advisor, skill, true, true)
				log(faction:name() .. ": Advisor cqi " .. advisor:command_queue_index() .. " lacked " .. skill .. ", added it, has it now: "
					.. tostring(advisor:has_skill(skill)))
			end
		end
	end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Start

cm:add_first_tick_callback(function()
	for _, faction_key in ipairs(cm:get_human_factions()) do
		local ok, err = pcall(add_learned_skills, cm:get_faction(faction_key))
		if not ok then
			log(faction_key .. ": adding learned skills failed with error " .. tostring(err))
		end
	end
	if not cm:is_new_game() then
		log("loaded game, nothing to spawn")
		return
	end
	local humans = cm:get_human_factions()
	log("new game, " .. #humans .. " human factions: " .. table.concat(humans, ", "))
	for _, faction_key in ipairs(humans) do
		local ok, err = pcall(spawn_for, faction_key)
		if not ok then
			log(faction_key .. ": spawn failed with error " .. tostring(err))
		end
	end
end)
