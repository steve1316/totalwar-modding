--- Advisor Overhaul test script for the skills plan. Its rows come from `generators/advisor_overhaul_spike.py`, and both come out once the answers are in.
---
--- S1: while he holds the Greatsword he wears a test bundle (a Lore of Death spell, +20 melee attack, +10 melee attack to his army). Checked on
---     selecting him and at the start of his turn.
--- S2, S3, S4: at the start of turn 2 the script adds three skills, spending no point:
---     - the hidden actions skill, which should give him two champion actions (Stimulate Growth, Scavenge);
---     - the hidden pact skill, which should lock the visible "Test: Defiance" node on row 5;
---     - the Disc's unlock skill, which should make the Disc pickable in Change Loadout.
---     It also puts the pact bundle (+10 Tzeentch corruption) on him.
--- Every step is logged with the `advisor_overhaul_spike` tag.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul_spike"

--- S1: the bundle he wears while holding this weapon.
local ART_BUNDLE = "advisor_overhaul_spike_art_greatsword"
local ART_WEAPON = "greatsword"

--- S2 to S4: the skills added at the start of turn 2, and the bundle put on him.
local ADDED_SKILLS = { "advisor_overhaul_spike_actions", "advisor_overhaul_spike_pact", "advisor_overhaul_choose_mount_disc" }
local PACT_BUNDLE = "advisor_overhaul_spike_pact"

--- The turn the skills are added on.
local ADD_TURN = 2

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end

--- Whether a character is an Advisor.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @returns boolean True for the Advisor's subtype.
local function is_advisor(character)
	return not character:is_null_interface() and character:character_subtype_key() == ADVISOR_OVERHAUL_RIGS.subtype
end

--- The weapon he holds now, read from the rig ancillary he wears.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns string|nil The weapon key, or nil when he wears no rig.
local function held_weapon(character)
	for pair, ancillary in pairs(ADVISOR_OVERHAUL_RIGS.ancillaries) do
		if character:has_ancillary(ancillary) then
			return (pair:match("^([^|]+)|"))
		end
	end
	return nil
end

--- The listed skills he has, as text.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns string "skill=true/false" for each of `ADDED_SKILLS`.
local function skills_text(character)
	local parts = {}
	for _, skill in ipairs(ADDED_SKILLS) do
		table.insert(parts, skill .. "=" .. tostring(character:has_skill(skill)))
	end
	return table.concat(parts, ", ")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Tests

--- S1: puts the art bundle on him while he holds `ART_WEAPON`, and takes it off otherwise.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for the check, for the log.
local function sync_art(character, why)
	local weapon, has = held_weapon(character), character:has_effect_bundle(ART_BUNDLE)
	local want = weapon == ART_WEAPON
	if want and not has then
		cm:apply_effect_bundle_to_character(ART_BUNDLE, character, 0)
	elseif has and not want then
		cm:remove_effect_bundle_from_character(ART_BUNDLE, character)
	end
	log("S1 (" .. why .. ") cqi " .. character:command_queue_index() .. " holds " .. tostring(weapon) .. ", art bundle was " .. tostring(has)
		.. ", wanted " .. tostring(want) .. ", now " .. tostring(character:has_effect_bundle(ART_BUNDLE)))
end

--- S2 to S4: adds whichever test skills he lacks, and the pact bundle.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for the add, for the log.
local function add_skills(character, why)
	local cqi = character:command_queue_index()
	local missing = {}
	for _, skill in ipairs(ADDED_SKILLS) do
		if not character:has_skill(skill) then
			table.insert(missing, skill)
		end
	end
	if #missing == 0 and character:has_effect_bundle(PACT_BUNDLE) then
		return
	end
	log("S2-S4 (" .. why .. ") cqi " .. cqi .. " rank " .. character:rank() .. ", before: " .. skills_text(character))
	for _, skill in ipairs(missing) do
		local ok, err = pcall(function() cm:add_skill(character, skill, true, true) end)
		log("S2-S4 add_skill " .. skill .. (ok and " ran" or (" raised " .. tostring(err))))
	end
	if not character:has_effect_bundle(PACT_BUNDLE) then
		cm:apply_effect_bundle_to_character(PACT_BUNDLE, character, 0)
	end
	-- The skills may only show up a moment later.
	cm:callback(function()
		local again = cm:get_character_by_cqi(cqi)
		if again and not again:is_null_interface() then
			log("S2-S4 cqi " .. cqi .. " after: " .. skills_text(again) .. ", pact bundle " .. tostring(again:has_effect_bundle(PACT_BUNDLE)))
		end
	end, 0.5)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_selected",
	"CharacterSelected",
	function(context) return is_advisor(context:character()) end,
	function(context) sync_art(context:character(), "selected") end,
	true
)

-- The faction's turn start, read over its characters, so a hero on the map is not missed.
core:add_listener(
	TAG .. "_turn_start",
	"FactionTurnStart",
	function(context) return context:faction():is_human() end,
	function(context)
		local characters = context:faction():character_list()
		for i = 0, characters:num_items() - 1 do
			local character = characters:item_at(i)
			if is_advisor(character) then
				sync_art(character, "turn start")
				if cm:model():turn_number() >= ADD_TURN then
					add_skills(character, "turn start")
				end
			end
		end
	end,
	true
)

core:add_listener(
	TAG .. "_rank_up",
	"CharacterRankUp",
	function(context) return is_advisor(context:character()) end,
	function(context) log("CharacterRankUp fired for cqi " .. context:character():command_queue_index() .. ", rank " .. context:character():rank()) end,
	true
)

-- On load too, so a save made after an add that did not stick tries again.
cm:add_first_tick_callback(function()
	log("loaded, turn " .. cm:model():turn_number())
	if cm:model():turn_number() < ADD_TURN then
		return
	end
	for _, faction_key in ipairs(cm:get_human_factions()) do
		for _, character in ipairs(ADVISOR_OVERHAUL.faction_advisors(cm:get_faction(faction_key))) do
			add_skills(character, "load")
		end
	end
end)
