--- Advisor Overhaul loadout script: lets the player switch the Advisor between the weapons and mounts he has unlocked.
---
--- Weapon and mount skills unlock an item. The default weapon and mount are always unlocked. A Change Loadout button shows while the character panel
--- shows the local player's Advisor, and while he is selected on the campaign map with no full-screen panel open. It opens a picker of his unlocked
--- weapons and mounts. A pick goes through a UI trigger, so every client applies it, and this script equips the hidden mount ancillary of the
--- chosen pair (its bodyguard unit and uniform are the pair's). The pairs come from `ADVISOR_OVERHAUL_RIGS`, which
--- generators/advisor_overhaul.py writes into advisor_overhaul_rigs.lua. advisor_overhaul_spawn.lua spawns the Advisors.
---
--- The rigs he does not wear sit in the faction pool, so the character panel's Mount box lists them. A pick there is read back from the worn rig.
---
--- It also gives him each weapon's art bundles and the Polymath bundle for the skills he owns, and builds their boxes over the art and Polymath
--- skill cards.
---
--- The button and picker are drawn by the ui_panel_button_picker mod, and the card boxes by the Expanded Skill Panel UI mod. This pack ships both at the
--- same in-pack paths as their own packs.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul"

--- When true the Advisor may change his loadout only once per turn.
local ONE_CHANGE_PER_TURN = false

--- Icon of the Change Loadout button (ui2.pack).
local BUTTON_ICON = "ui/skins/default/icon_swap.png"

--- Start of the UI trigger string that asks every client to read the Advisor's worn rig again, after a pick in the panel's Mount box.
local RECONCILE_PREFIX = TAG .. "_reconcile:"

--- The character panel's Mount box list (ui3.pack character_details_panel_details.twui.xml). A click inside it may pick a rig or "None".
local MOUNT_BOX = "ancillary_selector_mount"

--- How many parents a clicked component is followed up to find `MOUNT_BOX`.
local MOUNT_BOX_DEPTH = 12

--- Name of the one-shot real-time callback that checks the worn rig after a click in the Mount box.
local MOUNT_PICK_NAME = TAG .. "_mount_pick"

--- Delay of that callback in milliseconds, so the game has run the native equip command first.
local MOUNT_PICK_MS = 500

--- Id of the Change Loadout button in the panel button picker.
local LOADOUT_ID = TAG .. "_loadout"

--- UI text: loc key in text/db/!!advisor_overhaul_ui.loc (item names are in !!advisor_overhaul_ancillaries.loc) and the English fallback if the key does not resolve.
local TEXT = {
	--- Tooltip of the Change Loadout button.
	button = { "advisor_overhaul_ui_button_tooltip", "Change Loadout||Choose which of the Advisor's unlocked weapons and mounts he takes to war. Learn weapon and mount skills to unlock more." },
	--- Tooltip of the button once he has changed his loadout this turn.
	button_used = { "advisor_overhaul_ui_button_used_tooltip", "Change Loadout||The Advisor has already changed his loadout this turn." },
	--- Start of a weapon option's label, followed by the weapon. No UI text holds `%`: reading one through the game broke every script and crashed it.
	weapon = { "advisor_overhaul_ui_weapon_option", "Weapon:" },
	--- Start of a mount option's label, followed by the mount.
	mount = { "advisor_overhaul_ui_mount_option", "Mount:" },
	--- End of the label of the option he already uses.
	current = { "advisor_overhaul_ui_option_current", "(current)" },
	--- Tooltip of an option he can switch to.
	pick = { "advisor_overhaul_ui_option_pick_tooltip", "Switch the Advisor to this. The change applies at once." },
	--- Tooltip of the option he already uses.
	in_use = { "advisor_overhaul_ui_option_current_tooltip", "The Advisor already uses this." },
	--- Tooltip of a weapon with no unit on his current mount.
	weapon_blocked = { "advisor_overhaul_ui_weapon_blocked_tooltip", "The Advisor cannot use this weapon on his current mount. Pick another mount first." },
	--- Tooltip of a mount with no unit for his current weapon.
	mount_blocked = { "advisor_overhaul_ui_mount_blocked_tooltip", "The Advisor cannot ride this mount with his current weapon. Pick another weapon first." },
	--- Start of the line an art slot skill's tooltip gets for the weapon he holds, followed by the weapon's name.
	art_with = { "advisor_overhaul_ui_art_with", "With" },
	--- Start of the line an art slot skill's tooltip gets while its weapon is still locked, followed by the weapon's name.
	art_locked = { "advisor_overhaul_ui_art_locked", "Available after unlocking" },
	--- Line of the Polymath box before the disciplines that count, once he has the Polymath and before he has it.
	polymath_counted = { "advisor_overhaul_ui_polymath_counted", "Disciplines counted:" },
	polymath_counted_unlearned = { "advisor_overhaul_ui_polymath_counted_unlearned", "Disciplines counted if learned now:" },
	--- Words of a discipline's line in the Polymath box: "Memory: 1 of 5 skills".
	polymath_of = { "advisor_overhaul_ui_polymath_of", "of" },
	polymath_skills = { "advisor_overhaul_ui_polymath_skills", "skills" },
	--- Name of each Polymath discipline, by `discipline_` and its key in `ADVISOR_OVERHAUL_RIGS.polymath.disciplines`.
	discipline_arts = { "advisor_overhaul_ui_discipline_arts", "Arts" },
	discipline_memory = { "advisor_overhaul_ui_discipline_memory", "Memory" },
	discipline_magic = { "advisor_overhaul_ui_discipline_magic", "Magic" },
	discipline_hero_work = { "advisor_overhaul_ui_discipline_hero_work", "Hero work" },
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- What each art card's box last showed, by skill key, so the log notes each change. Kept for the next rebuild.
local art_card_tips = {}

--- Unlock skill key -> { kind, key } of the item it unlocks, built once from the generated lists by `skill_items`.
local unlock_skills = nil

--- True while `grant_by_rank` is giving skills. Each `add_skill` fires the skill listener at once, and a grant from inside it crashed the game.
local granting = false

--- Every rig ancillary key, sorted, built once by `rig_keys`.
local sorted_rigs = nil


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Data

--- The generated pair data. Read when used, since script load order does not promise the data file loads first.
--- @returns table The `ADVISOR_OVERHAUL_RIGS` table.
local function rig_data()
	return ADVISOR_OVERHAUL_RIGS
end

--- Whether a character is an Advisor, of any faction.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @returns boolean True when his subtype is the Advisor's.
local function is_advisor(character)
	return character:character_subtype_key() == rig_data().subtype
end

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end


--- The saved value key holding one of an Advisor's choices.
--- @param cqi number The Advisor's command queue index.
--- @param kind string `weapon` or `mount`.
--- @returns string The key.
local function choice_key(cqi, kind)
	return TAG .. "_" .. kind .. "_" .. cqi
end

--- The saved value key holding the turn an Advisor last changed his loadout.
--- @param cqi number The Advisor's command queue index.
--- @returns string The key.
local function changed_turn_key(cqi)
	return TAG .. "_loadout_turn_" .. cqi
end

--- The Advisor's saved weapon and mount, or the defaults when nothing is saved. Not checked against what he has unlocked.
--- @param cqi number The Advisor's command queue index.
--- @returns string The weapon key.
--- @returns string The mount key.
local function saved_pair(cqi)
	local rigs = rig_data()
	return cm:get_saved_value(choice_key(cqi, "weapon")) or rigs.default_weapon, cm:get_saved_value(choice_key(cqi, "mount")) or rigs.default_mount
end

--- Saves the Advisor's weapon and mount.
--- @param cqi number The Advisor's command queue index.
--- @param weapon string The weapon key.
--- @param mount string The mount key.
--- @param mark_turn boolean Whether this counts as his change for this turn.
local function save_pair(cqi, weapon, mount, mark_turn)
	cm:set_saved_value(choice_key(cqi, "weapon"), weapon)
	cm:set_saved_value(choice_key(cqi, "mount"), mount)
	if mark_turn then
		cm:set_saved_value(changed_turn_key(cqi), cm:model():turn_number())
	end
end

--- The item list of a kind.
--- @param kind string `weapon` or `mount`.
--- @returns table The `weapons` or `mounts` list of `ADVISOR_OVERHAUL_RIGS`.
local function items_of(kind)
	return kind == "weapon" and rig_data().weapons or rig_data().mounts
end

--- The item each unlock skill unlocks, built from the generated weapon and mount lists on first use.
--- @returns table Unlock skill key -> { kind, key }.
local function skill_items()
	if not unlock_skills then
		unlock_skills = {}
		for _, kind in ipairs({ "weapon", "mount" }) do
			for _, item in ipairs(items_of(kind)) do
				if item.skill ~= "" then
					unlock_skills[item.skill] = { kind = kind, key = item.key }
				end
			end
		end
	end
	return unlock_skills
end

--- Every rig ancillary key, sorted, so the pool sync and its log run in a fixed order. Built on first use.
--- @returns table The ancillary keys.
local function rig_keys()
	if not sorted_rigs then
		sorted_rigs = {}
		for ancillary in pairs(rig_data().rigs) do
			table.insert(sorted_rigs, ancillary)
		end
		table.sort(sorted_rigs)
	end
	return sorted_rigs
end

--- Finds a weapon or mount by key.
--- @param kind string `weapon` or `mount`.
--- @param key string The item key.
--- @returns table|nil The item row, or nil when the key is unknown.
local function find_item(kind, key)
	for _, item in ipairs(items_of(kind)) do
		if item.key == key then
			return item
		end
	end
	return nil
end

--- Whether the Advisor has unlocked a weapon or mount. Defaults have no skill and are always unlocked.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param item table The item row.
--- @returns boolean True when unlocked.
local function is_unlocked(character, item)
	return item.skill == "" or character:has_skill(item.skill)
end

--- The keys of every unlocked item of a kind, for the log.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param kind string `weapon` or `mount`.
--- @returns string The keys joined by commas.
local function unlocked_list(character, kind)
	local keys = {}
	for _, item in ipairs(items_of(kind)) do
		if is_unlocked(character, item) then
			table.insert(keys, item.key)
		end
	end
	return table.concat(keys, ", ")
end

--- Whether a weapon and mount pair has a unit.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when the pair has a mount ancillary.
local function has_unit(weapon, mount)
	return rig_data().ancillaries[weapon .. "|" .. mount] ~= nil
end

--- The rig that gives the Advisor a pair's unit: the upgrade's rig (an apex form) once he owns its skill, else the pair's own.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns string|nil The ancillary key, or nil when the pair has no unit.
local function pair_rig(character, weapon, mount)
	local upgrade = (rig_data().upgrades or {})[weapon .. "|" .. mount]
	if upgrade and character:has_skill(upgrade.skill) then
		return upgrade.ancillary
	end
	return rig_data().ancillaries[weapon .. "|" .. mount]
end

--- The weapon and mount to use: the saved choices while still unlocked (a respec can take them away), else the defaults. A pair with no unit falls
--- back first to the default weapon and then to the default mount.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns string The weapon key.
--- @returns string The mount key.
local function current_pair(character)
	local rigs = rig_data()
	local cqi = character:command_queue_index()
	local weapon, mount = saved_pair(cqi)
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	if not weapon_item or not is_unlocked(character, weapon_item) then
		log("cqi " .. cqi .. " saved weapon " .. weapon .. " is unknown or locked, using " .. rigs.default_weapon)
		weapon = rigs.default_weapon
	end
	if not mount_item or not is_unlocked(character, mount_item) then
		log("cqi " .. cqi .. " saved mount " .. mount .. " is unknown or locked, using " .. rigs.default_mount)
		mount = rigs.default_mount
	end
	if has_unit(weapon, mount) then
		return weapon, mount
	end
	log("no unit for " .. weapon .. " on " .. mount .. ", trying " .. rigs.default_weapon)
	if has_unit(rigs.default_weapon, mount) then
		return rigs.default_weapon, mount
	end
	return weapon, rigs.default_mount
end

--- Switches the Advisor's art set to his weapon's, so the character panel model shows it. The panel follows only the art set. The override is
--- set again every time his loadout is applied, which includes each load.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon key.
local function apply_art_set(character, weapon)
	local item = find_item("weapon", weapon)
	local art_set = item and item.art_set
	if not art_set then
		log("cqi " .. character:command_queue_index() .. " has no art set for " .. weapon .. ", character panel model left as is")
		return
	end
	local ok, err = pcall(function()
		cm:add_character_model_override(character, art_set)
	end)
	log("cqi " .. character:command_queue_index() .. " character panel model set to " .. art_set .. (ok and "" or (", error: " .. tostring(err))))
end

--- The arts of a weapon whose slot skill the Advisor owns.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon key.
--- @returns table The owned art rows of `ADVISOR_OVERHAUL_RIGS.arts`.
local function owned_arts(character, weapon)
	local owned = {}
	for _, art in ipairs((rig_data().arts or {})[weapon] or {}) do
		if character:has_skill(art.skill) then
			table.insert(owned, art)
		end
	end
	return owned
end

--- Puts on the Advisor the art bundles of the weapon he holds, for each art slot skill he owns, and takes every other art bundle off. Runs each
--- time his loadout is applied: a loadout change, a skill point, each load and each turn start.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon he holds.
--- @returns boolean True when a bundle was put on or taken off.
local function sync_arts(character, weapon)
	local wanted = {}
	for _, art in ipairs(owned_arts(character, weapon)) do
		wanted[art.bundle] = true
	end
	local added, removed = {}, {}
	for _, arts in pairs(rig_data().arts or {}) do
		for _, art in ipairs(arts) do
			local has = character:has_effect_bundle(art.bundle)
			if wanted[art.bundle] and not has then
				cm:apply_effect_bundle_to_character(art.bundle, character, 0)
				table.insert(added, art.bundle)
			elseif has and not wanted[art.bundle] then
				cm:remove_effect_bundle_from_character(art.bundle, character)
				table.insert(removed, art.bundle)
			end
		end
	end
	if #added > 0 or #removed > 0 then
		log("cqi " .. character:command_queue_index() .. " arts for " .. weapon .. ": added " .. table.concat(added, ", ") .. "; removed "
			.. table.concat(removed, ", "))
	end
	return #added > 0 or #removed > 0
end

--- How many skills the Advisor knows in each Polymath discipline, and the disciplines in which he knows enough for them to count.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param data table The Polymath, from `ADVISOR_OVERHAUL_RIGS.polymath`.
--- @returns table Each discipline's `name` and `owned` skills, in tree order.
--- @returns table Names of the disciplines that count, in tree order.
local function polymath_progress(character, data)
	local progress, counted = {}, {}
	for _, discipline in ipairs(data.disciplines) do
		local owned = 0
		for _, key in ipairs(discipline.skills) do
			if character:has_skill(key) then
				owned = owned + 1
			end
		end
		table.insert(progress, { name = discipline.name, owned = owned })
		if owned >= data.needed then
			table.insert(counted, discipline.name)
		end
	end
	return progress, counted
end

--- Puts on the Advisor the Polymath bundle for the number of disciplines in which he has enough skills, while he owns the Polymath, and takes every
--- other Polymath bundle off. Runs with `sync_arts`, and on every skill point.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when a bundle was put on or taken off.
local function sync_polymath(character)
	local data = rig_data().polymath
	if not data then
		return false
	end
	local counted, wanted = {}, nil
	if character:has_skill(data.skill) then
		local _, owned = polymath_progress(character, data)
		-- The first bundle is for no disciplines, so he has one whenever he owns the Polymath.
		counted, wanted = owned, data.bundles[#owned + 1]
	end
	local changed = false
	for _, bundle in ipairs(data.bundles) do
		local has = character:has_effect_bundle(bundle)
		if bundle == wanted and not has then
			cm:apply_effect_bundle_to_character(bundle, character, 0)
			changed = true
		elseif has and bundle ~= wanted then
			cm:remove_effect_bundle_from_character(bundle, character)
			changed = true
		end
	end
	if changed then
		log("cqi " .. character:command_queue_index() .. " Polymath counts " .. #counted .. " disciplines (" .. table.concat(counted, ", ") .. "), bundle "
			.. tostring(wanted))
	end
	return changed
end

--- Whether the once-per-turn rule blocks a change for this Advisor.
--- @param cqi number The Advisor's command queue index.
--- @returns boolean True when he already changed this turn and the rule is on.
local function used_this_turn(cqi)
	return ONE_CHANGE_PER_TURN and cm:get_saved_value(changed_turn_key(cqi)) == cm:model():turn_number()
end

--- The weapon and mount of a rig ancillary.
--- @param ancillary string The ancillary key.
--- @returns string|nil The weapon key, or nil when it is not a rig.
--- @returns string|nil The mount key.
local function rig_pair(ancillary)
	local pair = rig_data().rigs[ancillary]
	if not pair then
		return nil, nil
	end
	return pair.weapon, pair.mount
end

--- Whether the Advisor has unlocked both items of a pair.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when both are unlocked.
local function pair_unlocked(character, weapon, mount)
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	return weapon_item ~= nil and mount_item ~= nil and is_unlocked(character, weapon_item) and is_unlocked(character, mount_item)
end

--- The rig ancillaries the Advisor wears, sorted. Normally one. None after the Mount box's "None" entry.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table The ancillary keys.
local function worn_rigs(character)
	local worn = {}
	for _, ancillary in ipairs(rig_keys()) do
		if character:has_ancillary(ancillary) then
			table.insert(worn, ancillary)
		end
	end
	return worn
end

--- The Advisors of a faction.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @returns table The Advisors.
local function faction_advisors(faction)
	local found = {}
	local characters = faction:character_list()
	for i = 0, characters:num_items() - 1 do
		local character = characters:item_at(i)
		if is_advisor(character) then
			table.insert(found, character)
		end
	end
	return found
end

--- Whether any of the Advisors wears an ancillary.
--- @param advisors table The faction's Advisors.
--- @param ancillary string The ancillary key.
--- @returns boolean True when one wears it.
local function worn_by_any(advisors, ancillary)
	for _, advisor in ipairs(advisors) do
		if advisor:has_ancillary(ancillary) then
			return true
		end
	end
	return false
end

--- Whether the faction owns an ancillary, worn or in its pool. `ancillary_exists` cannot tell a pool copy from a worn one.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param ancillary string The ancillary key.
--- @returns boolean True when the faction owns it.
local function faction_owns(faction, ancillary)
	local ok, exists = pcall(function()
		return faction:ancillary_exists(ancillary)
	end)
	return ok and exists == true
end

--- Whether an unworn copy of an ancillary sits in the faction's pool: the faction owns it and no Advisor wears it.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param advisors table The faction's Advisors.
--- @param ancillary string The ancillary key.
--- @returns boolean True when a copy is in the pool.
local function in_pool(faction, advisors, ancillary)
	return not worn_by_any(advisors, ancillary) and faction_owns(faction, ancillary)
end

--- Makes the faction's pool hold one copy of every unlocked pair's rig that no Advisor wears, and no locked pair's rig. The
--- character panel's Mount box lists exactly those pool copies. A worn rig is never removed from the faction, since that strips the worn copy too.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param why string What asked for it, for the log.
local function sync_pool(faction, why)
	local advisors = faction_advisors(faction)
	if #advisors == 0 then
		return
	end
	local changes = {}
	for _, ancillary in ipairs(rig_keys()) do
		-- A worn rig is left alone.
		if not worn_by_any(advisors, ancillary) then
			local weapon, mount = rig_pair(ancillary)
			local unlocked = false
			for _, advisor in ipairs(advisors) do
				-- A pair's own rig stays out of the pool while his upgrade replaces it, and the upgrade's rig until then.
				unlocked = unlocked or (pair_unlocked(advisor, weapon, mount) and pair_rig(advisor, weapon, mount) == ancillary)
			end
			local pooled = faction_owns(faction, ancillary)
			if unlocked and not pooled then
				cm:add_ancillary_to_faction(faction, ancillary, true)
				table.insert(changes, "added " .. ancillary)
			elseif not unlocked and pooled then
				cm:force_remove_ancillary_from_faction(faction, ancillary)
				table.insert(changes, "removed " .. ancillary)
			end
		end
	end
	log("pool " .. faction:name() .. " (" .. why .. "): " .. (#changes > 0 and table.concat(changes, ", ") or "no change"))
end

--- Equips the mount ancillary of the Advisor's current pair. Every other pair's rig goes back to the faction pool, so the Mount box lists it. The
--- pair is saved back, so a choice a respec took away does not return when he learns the skill again. Also sets his weapon's art set. The caller
--- syncs the pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when an ancillary was equipped or removed.
local function apply_pair(character)
	local weapon, mount = current_pair(character)
	local cqi = character:command_queue_index()
	local faction = character:faction()
	save_pair(cqi, weapon, mount, false)
	local wanted = pair_rig(character, weapon, mount)
	apply_art_set(character, weapon)
	sync_arts(character, weapon)
	sync_polymath(character)
	if not wanted then
		log("cqi " .. cqi .. " has no unit for " .. weapon .. " on " .. mount .. ", nothing equipped")
		return false
	end
	local stale = {}
	for _, ancillary in ipairs(rig_keys()) do
		if ancillary ~= wanted and character:has_ancillary(ancillary) then
			table.insert(stale, ancillary)
		end
	end
	if character:has_ancillary(wanted) and #stale == 0 then
		return false
	end
	for _, ancillary in ipairs(stale) do
		-- A rig goes back to the pool, so the Mount box lists it.
		cm:force_remove_ancillary(character, ancillary, true, true)
	end
	local from_pool = false
	if not character:has_ancillary(wanted) then
		-- The pool copy is removed first, so equipping does not leave a second one. The vanilla Sword of Khaine script does the same.
		from_pool = in_pool(faction, faction_advisors(faction), wanted)
		if from_pool then
			cm:force_remove_ancillary_from_faction(faction, wanted)
		end
		cm:force_add_ancillary(character, wanted, true, true)
	end
	log("cqi " .. cqi .. " now " .. weapon .. " on " .. mount .. " (" .. wanted .. "), returned or removed: " .. table.concat(stale, ", ")
		.. ", pool copy taken: " .. tostring(from_pool) .. ", has it now: " .. tostring(character:has_ancillary(wanted)))
	return true
end

--- Teleports the Advisor onto the spot he stands on, so the game works out his stats again. A bundle put on by script leaves his unit card stale
--- until he moves on the map. Reselecting or putting his rig back on did not refresh it. Skipped inside an army or a settlement.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
local function refresh_stats(character)
	local cqi = character:command_queue_index()
	if character:is_embedded_in_military_force() or character:has_garrison_residence() then
		log("cqi " .. cqi .. " stats refresh skipped: he is in an army or a settlement")
		return
	end
	local x, y = character:logical_position_x(), character:logical_position_y()
	local ok, err = pcall(function()
		cm:teleport_to(cm:char_lookup_str(cqi), x, y)
	end)
	log("cqi " .. cqi .. " teleported onto his own spot " .. x .. "," .. y .. " to refresh his stats" .. (ok and "" or (", error: " .. tostring(err))))
end

--- Gives the Advisor each weapon or mount skill that has a `grant_rank` once he has reached that rank. Runs from game events only, so every client
--- grants the same skills. A call from inside a grant does nothing, so the outer loop gives each skill in turn.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when a skill was given.
local function grant_by_rank(character)
	if granting then
		return false
	end
	granting = true
	local granted = false
	-- A raised error must not leave `granting` set, or he would never be given another skill.
	local ok, err = pcall(function()
		for _, kind in ipairs({ "weapon", "mount" }) do
			for _, item in ipairs(items_of(kind)) do
				if item.grant_rank and item.skill ~= "" and character:rank() >= item.grant_rank and not character:has_skill(item.skill) then
					cm:add_skill(character, item.skill, true, true)
					log("cqi " .. character:command_queue_index() .. " reached rank " .. character:rank() .. ", granted " .. kind .. " " .. item.key)
					granted = true
				end
			end
		end
	end)
	granting = false
	if not ok then
		log("grant by rank failed: " .. tostring(err))
	end
	return granted
end

--- Reads which rig the Advisor wears and makes it his loadout, so a pick in the character panel's Mount box sticks. With exactly one worn rig of an
--- unlocked pair, that pair is saved as his choice. With none (the Mount box's "None"), a locked one or several, the saved pair is equipped again.
--- Runs from game events and UI triggers only, so every client saves the same values. The caller syncs the pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for it, for the log.
--- @returns boolean True when his loadout or ancillaries changed.
local function reconcile_pair(character, why)
	grant_by_rank(character)
	local cqi = character:command_queue_index()
	local worn = worn_rigs(character)
	local saved_weapon, saved_mount = saved_pair(cqi)
	local changed = false
	local weapon, mount = nil, nil
	if #worn == 1 then
		weapon, mount = rig_pair(worn[1])
	end
	if weapon and pair_unlocked(character, weapon, mount) then
		local differs = weapon ~= saved_weapon or mount ~= saved_mount
		if differs and used_this_turn(cqi) then
			log("cqi " .. cqi .. " wears " .. worn[1] .. " but already changed this turn, putting back " .. saved_weapon .. " on " .. saved_mount
				.. " (check: " .. why .. ")")
		else
			if differs then
				save_pair(cqi, weapon, mount, true)
				changed = true
			end
			log("cqi " .. cqi .. " loadout taken from the worn rig " .. worn[1] .. ": " .. weapon .. " on " .. mount
				.. (differs and (", was " .. saved_weapon .. " on " .. saved_mount) or ", unchanged") .. " (check: " .. why .. ")")
		end
	elseif #worn == 0 then
		log("cqi " .. cqi .. " wears no rig (the Mount box None entry or a new campaign), equipping the saved pair " .. saved_weapon
			.. " on " .. saved_mount .. " (check: " .. why .. ")")
	else
		log("cqi " .. cqi .. " wears " .. table.concat(worn, ", ") .. ", not one rig of an unlocked pair, equipping the saved pair " .. saved_weapon
			.. " on " .. saved_mount .. " (check: " .. why .. ")")
	end
	local equipped = apply_pair(character)
	return changed or equipped
end

--- Reconciles one Advisor and syncs his faction's pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for it, for the log.
--- @returns boolean True when his loadout or ancillaries changed.
local function reconcile(character, why)
	local changed = reconcile_pair(character, why)
	sync_pool(character:faction(), why)
	return changed
end

--- Reconciles every living Advisor of a faction, then syncs its pool once.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param why string What asked for it, for the log.
local function reconcile_faction(faction, why)
	for _, character in ipairs(faction_advisors(faction)) do
		if not character:is_wounded() then
			reconcile_pair(character, why)
		end
	end
	sync_pool(faction, why)
end

--- Reconciles every living Advisor of every human faction.
--- @param why string What asked for it, for the log.
local function apply_all(why)
	for _, faction_key in ipairs(cm:get_human_factions()) do
		reconcile_faction(cm:get_faction(faction_key), why)
	end
end

--- Checks whether the Advisor may switch to a pair.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when allowed.
--- @returns string Why not, or an empty string when allowed.
local function can_choose(character, weapon, mount)
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	if not weapon_item or not mount_item then
		return false, "unknown weapon or mount"
	end
	if not is_unlocked(character, weapon_item) then
		return false, "weapon " .. weapon .. " is locked"
	end
	if not is_unlocked(character, mount_item) then
		return false, "mount " .. mount .. " is locked"
	end
	if not has_unit(weapon, mount) then
		return false, "no unit for " .. weapon .. " on " .. mount
	end
	if used_this_turn(character:command_queue_index()) then
		return false, "already changed this turn"
	end
	return true, ""
end

--- Saves a picked pair and equips it. Runs on every client from the UI trigger.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
local function choose_pair(character, weapon, mount)
	local cqi = character:command_queue_index()
	local old_weapon, old_mount = current_pair(character)
	log("cqi " .. cqi .. " asked for " .. weapon .. " on " .. mount .. ", was " .. old_weapon .. " on " .. old_mount .. ", unlocked weapons: "
		.. unlocked_list(character, "weapon") .. ", unlocked mounts: " .. unlocked_list(character, "mount"))
	local ok, reason = can_choose(character, weapon, mount)
	if not ok then
		log("cqi " .. cqi .. " change refused: " .. reason)
		return
	end
	save_pair(cqi, weapon, mount, true)
	apply_pair(character)
	sync_pool(character:faction(), "cqi " .. cqi .. " picked " .. weapon .. " on " .. mount)
	local new_weapon, new_mount = current_pair(character)
	log("cqi " .. cqi .. " loadout is now " .. new_weapon .. " on " .. new_mount .. " (turn " .. cm:model():turn_number() .. ")")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI text

--- A loc text, or a fallback when its key does not resolve.
--- @param key string The loc key.
--- @param fallback string The text to use when the key does not resolve.
--- @returns string The text.
local function localised(key, fallback)
	local text = common.get_localised_string(key)
	if not text or text == "" then
		return fallback
	end
	return text
end

--- A UI text, localised when its key resolves.
--- @param id string Key of `TEXT`.
--- @returns string The text.
local function ui_text(id)
	local entry = TEXT[id]
	return localised(entry[1], entry[2])
end

--- A box's flavour text with only its first paragraph in italics, so the notes after it read as plain text like a vanilla skill's.
--- @param text string The flavour text, its paragraphs split by a blank line.
--- @returns string The text in the game's markup.
local function italic_lead(text)
	local lead, notes = text:match("^(.-)(\n\n.*)$")
	if not lead then
		return "[[i]]" .. text .. "[[/i]]"
	end
	return "[[i]]" .. lead .. "[[/i]]" .. notes
end

--- An item's display name, localised when its key resolves.
--- @param item table The item row.
--- @returns string The name.
local function item_name(item)
	return localised(item.name, item.fallback)
end

--- Whether a character is an Advisor of the local player's faction.
--- @param character CHARACTER_SCRIPT_INTERFACE|nil|boolean The character, or nil or false when there is none.
--- @returns boolean True for the local player's Advisor.
local function is_local_advisor(character)
	if not character then
		return false
	end
	return is_advisor(character) and character:faction():name() == cm:get_local_faction_name(true)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI components

--- A component's name, or nil when the handle is dead or not a component.
--- @param uic UIC|nil The component.
--- @returns string|nil The name.
local function component_id(uic)
	if not uic then
		return nil
	end
	local ok, id = pcall(function()
		return uic:Id()
	end)
	if ok and type(id) == "string" then
		return id
	end
	return nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Change Loadout button

--- The Change Loadout picker's columns: his unlocked weapons, then his unlocked mounts. Each is the one he uses, one he can switch to, or one with
--- no unit for the other half of his pair.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table The columns, as `UI_PANEL_BUTTON_PICKER.register` takes them.
local function loadout_columns(character)
	local weapon, mount = current_pair(character)
	local columns = {}
	for _, kind in ipairs({ "weapon", "mount" }) do
		local options = {}
		for _, item in ipairs(items_of(kind)) do
			if is_unlocked(character, item) then
				local is_current = item.key == (kind == "weapon" and weapon or mount)
				local fits = kind == "weapon" and has_unit(item.key, mount) or kind == "mount" and has_unit(weapon, item.key)
				local state = is_current and "current" or fits and "pick" or "blocked"
				local label = ui_text(kind) .. " " .. item_name(item)
				local reason = ui_text("pick")
				if state == "current" then
					label = label .. " " .. ui_text("current")
					reason = ui_text("in_use")
				elseif state == "blocked" then
					reason = ui_text(kind .. "_blocked")
				end
				table.insert(options, { key = item.key, icon = item.icon, tooltip = label .. "||" .. reason, state = state })
			end
		end
		table.insert(columns, { key = kind, options = options })
	end
	log("loadout picker cqi " .. character:command_queue_index() .. " on " .. weapon .. " / " .. mount)
	return columns
end

--- Switches the Advisor to a picked weapon or mount, keeping the other half of his pair. Runs on every client from the picker's UI trigger.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param kind string `weapon` or `mount`.
--- @param key string The picked item's key.
local function apply_loadout_pick(character, kind, key)
	local weapon, mount = current_pair(character)
	if kind == "weapon" then
		weapon = key
	elseif kind == "mount" then
		mount = key
	else
		log("loadout pick of an unknown kind " .. tostring(kind) .. " ignored")
		return
	end
	choose_pair(character, weapon, mount)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Mount box

--- Whether a clicked component sits inside the character panel's Mount box list, found by following its parents up to `MOUNT_BOX`. Read only.
--- @param address any The clicked component's address from the click event.
--- @returns boolean True when it is inside the Mount box.
local function in_mount_box(address)
	if not address then
		return false
	end
	local uic = UIComponent(address)
	for _ = 1, MOUNT_BOX_DEPTH do
		if component_id(uic) == MOUNT_BOX then
			return true
		end
		local ok, parent = pcall(function()
			return uic:Parent()
		end)
		if not ok or not parent then
			return false
		end
		uic = UIComponent(parent)
	end
	return false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Art skill boxes

--- What an art slot skill's card box shows, in the game's text markup: the skill name as its title, then the skill's flavour text and the art of
--- the weapon he holds with its description, and the skills it still needs. The effect list draws the art's effects.
--- @param art table The art row.
--- @param weapon string The weapon key.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table `title`, `text` (up to the effects), `foot` ("" for none) and `bundle`.
local function art_card_tooltip(art, weapon, character)
	local item = find_item("weapon", weapon)
	local head = {
		italic_lead(art.flavour),
		"",
		"[[col:yellow]]" .. ui_text("art_with") .. " " .. (item and item_name(item) or weapon) .. ": "
			.. localised("effect_bundles_localised_title_" .. art.bundle, art.name) .. "[[/col]]",
	}
	if art.about ~= "" then
		table.insert(head, "[[i]]" .. art.about .. "[[/i]]")
	end
	local foot = {}
	for _, required in ipairs(art.requires) do
		if not character:has_skill(required.skill) then
			table.insert(foot, "[[col:red]]" .. ui_text("art_locked") .. " \"" .. localised("character_skills_localised_name_" .. required.skill, required.name) .. "\".[[/col]]")
		end
	end
	local tip = {
		title = localised("character_skills_localised_name_" .. art.skill, art.skill_name),
		text = table.concat(head, "\n"),
		foot = table.concat(foot, "\n\n"),
		bundle = art.bundle,
	}
	return tip
end

--- What the Polymath card's box shows, in the game's text markup: its name as the title, its flavour, then how many skills he knows in each
--- discipline. The effect list draws the Polymath bundle he has now, or the one he would get if he learned it now.
--- @param data table The Polymath, from `ADVISOR_OVERHAUL_RIGS.polymath`.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table `title`, `text`, `foot` (always "") and `bundle`, like `art_card_tooltip`.
local function polymath_card_tooltip(data, character)
	local progress, counted = polymath_progress(character, data)
	local head = { italic_lead(data.flavour), "" }
	for _, discipline in ipairs(progress) do
		local name = ui_text("discipline_" .. discipline.name)
		if discipline.owned >= data.needed then
			table.insert(head, "[[col:green]]" .. name .. ": " .. discipline.owned .. " " .. ui_text("polymath_skills") .. "[[/col]]")
		else
			table.insert(head, name .. ": " .. discipline.owned .. " " .. ui_text("polymath_of") .. " " .. data.needed .. " " .. ui_text("polymath_skills"))
		end
	end
	local line = character:has_skill(data.skill) and "polymath_counted" or "polymath_counted_unlearned"
	table.insert(head, "")
	table.insert(head, "[[col:yellow]]" .. ui_text(line) .. " " .. #counted .. " " .. ui_text("polymath_of") .. " " .. #data.disciplines .. "[[/col]]")
	local tip = {
		title = localised("character_skills_localised_name_" .. data.skill, data.name),
		text = table.concat(head, "\n"),
		foot = "",
		bundle = data.bundles[#counted + 1],
	}
	return tip
end

--- Builds the box of each art slot skill from the art of the weapon the Advisor holds, and the Polymath's box from his skills, so a weapon switch
--- or a learned skill shows up. The skill panel asks for them again every few looks while its cards show.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table Skill key -> what its box shows, as `UI_SKILL_PANEL.add_card_boxes` takes them.
local function update_art_card_tips(character)
	local weapon = current_pair(character)
	local tips = {}
	--- Keeps a card's box and logs it when it differs from the one shown so far.
	--- @param skill string The card's skill key.
	--- @param tip table What the box shows.
	--- @param what string What it shows, for the log.
	local function keep(skill, tip, what)
		tips[skill] = tip
		local old = art_card_tips[skill]
		if not old or old.title ~= tip.title or old.text ~= tip.text or old.foot ~= tip.foot or old.bundle ~= tip.bundle then
			log("art tooltip: " .. skill .. " shows " .. what)
		end
	end
	for _, art in ipairs((rig_data().arts or {})[weapon] or {}) do
		keep(art.skill, art_card_tooltip(art, weapon, character), "art " .. art.name .. " of " .. weapon)
	end
	local polymath = rig_data().polymath
	if polymath then
		local tip = polymath_card_tooltip(polymath, character)
		keep(polymath.skill, tip, tip.bundle)
	end
	art_card_tips = tips
	return tips
end

--- After a click in the Mount box, reads the shown Advisor's worn rig without changing anything. When it no longer matches his saved pair (a pick
--- the ancillary event missed, or "None"), it sends a UI trigger so every client reconciles him the same way.
local function check_mount_pick()
	local character, seen = UI_PANEL_BUTTON_PICKER.panel_character()
	if not is_local_advisor(character) then
		log("Mount box check skipped: " .. seen)
		return
	end
	local cqi = character:command_queue_index()
	local worn = worn_rigs(character)
	local weapon, mount = current_pair(character)
	local wanted = pair_rig(character, weapon, mount)
	if #worn == 1 and worn[1] == wanted then
		log("Mount box check cqi " .. cqi .. ": wears " .. wanted .. ", which is his saved pair, nothing to do")
		return
	end
	local trigger = RECONCILE_PREFIX .. cqi
	log("Mount box check cqi " .. cqi .. ": wears " .. (#worn > 0 and table.concat(worn, ", ") or "no rig") .. ", saved pair " .. tostring(wanted)
		.. ", sending " .. trigger)
	CampaignUI.TriggerCampaignScriptEvent(character:faction():command_queue_index(), trigger)
end

--- Tells the picker the local Advisor's loadout changed outside it, so it closes his picker, selects him again to refresh his map unit card (once
--- the character panel is closed) and re-checks the button.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What changed it, for the log.
local function loadout_changed(character, why)
	if is_local_advisor(character) and UI_PANEL_BUTTON_PICKER then
		UI_PANEL_BUTTON_PICKER.changed(LOADOUT_ID, character:command_queue_index(), why)
	end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Event helpers

--- Reads a Mount box reconcile trigger and checks it: it must name an Advisor of the faction that sent it.
--- @param context table The `UITrigger` event context.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The Advisor, or nil when the trigger is refused.
local function read_reconcile_trigger(context)
	local trigger = context:trigger()
	local cqi = string.match(string.sub(trigger, #RECONCILE_PREFIX + 1), "^(%d+)$")
	local character = cqi and cm:get_character_by_cqi(tonumber(cqi))
	if not character or not is_advisor(character) then
		log("reconcile trigger " .. trigger .. " names no Advisor")
		return nil
	end
	if character:faction():command_queue_index() ~= context:faction_cqi() then
		log("reconcile trigger " .. trigger .. " came from another faction (cqi " .. tostring(context:faction_cqi()) .. ")")
		return nil
	end
	return character
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_ancillary_gained",
	"CharacterAncillaryGained",
	function(context)
		return is_advisor(context:character()) and rig_data().rigs[tostring(context:ancillary())] ~= nil
	end,
	function(context)
		local character = context:character()
		local ancillary = tostring(context:ancillary())
		log("CharacterAncillaryGained cqi " .. character:command_queue_index() .. " " .. ancillary)
		local changed = reconcile(character, "gained " .. ancillary)
		if changed then
			loadout_changed(character, "the loadout changed in the Mount box")
		end
	end,
	true
)

core:add_listener(
	TAG .. "_mount_box_click",
	"ComponentLClickUp",
	function()
		-- Cheap checks first, so most clicks never walk the parents: the panel must show the local Advisor, which shows the button in its row.
		return UI_PANEL_BUTTON_PICKER ~= nil and UI_PANEL_BUTTON_PICKER.shown_in_panel(LOADOUT_ID)
	end,
	function(context)
		if not in_mount_box(context.component) then
			return
		end
		log("click on " .. tostring(context.string) .. " inside the Mount box, checking the worn rig in " .. MOUNT_PICK_MS .. " ms")
		cm:remove_real_callback(MOUNT_PICK_NAME)
		cm:real_callback(function()
			local ok, err = pcall(check_mount_pick)
			if not ok then
				log("Mount box check failed: " .. tostring(err))
			end
		end, MOUNT_PICK_MS, MOUNT_PICK_NAME)
	end,
	true
)

core:add_listener(
	TAG .. "_reconcile_trigger",
	"UITrigger",
	function(context)
		return string.sub(context:trigger(), 1, #RECONCILE_PREFIX) == RECONCILE_PREFIX
	end,
	function(context)
		local character = read_reconcile_trigger(context)
		if not character then
			return
		end
		local changed = reconcile(character, "Mount box pick")
		if changed then
			loadout_changed(character, "the loadout changed in the Mount box")
		end
	end,
	true
)

core:add_listener(
	TAG .. "_skill_unlock",
	"CharacterSkillPointAllocated",
	function(context)
		return is_advisor(context:character())
	end,
	function(context)
		local character = context:character()
		local skill = context:skill_point_spent_on()
		local unlocked = skill_items()[skill]
		-- Any skill may change how many disciplines the Polymath counts.
		local changed = sync_polymath(character)
		if not unlocked then
			-- An art slot skill puts on his held weapon's art, and an upgrade skill (an apex form) swaps his rig, both at once.
			changed = sync_arts(character, current_pair(character)) or changed
			changed = reconcile(character, "skill " .. skill) or changed
			if changed then
				refresh_stats(character)
				loadout_changed(character, "skill " .. skill .. " changed his rig")
			end
			return
		end
		local cqi = character:command_queue_index()
		log("cqi " .. cqi .. " unlocked " .. unlocked.kind .. " " .. unlocked.key .. ", unlocked weapons: "
			.. unlocked_list(character, "weapon") .. ", unlocked mounts: " .. unlocked_list(character, "mount"))
		-- The newly unlocked pairs go into the pool.
		reconcile(character, "skill " .. skill)
		loadout_changed(character, "a new item was unlocked")
	end,
	true
)

core:add_listener(
	TAG .. "_rank_up",
	"CharacterRankUp",
	function(context)
		return is_advisor(context:character())
	end,
	function(context)
		local character = context:character()
		if grant_by_rank(character) then
			reconcile(character, "rank up")
		end
	end,
	true
)

core:add_listener(
	TAG .. "_turn_start",
	"FactionTurnStart",
	function(context)
		return context:faction():is_human()
	end,
	function(context)
		reconcile_faction(context:faction(), "turn start of " .. context:faction():name())
	end,
	true
)

--- Helpers the spawn and quest scripts share. They read them when they run, since script load order is not promised.
ADVISOR_OVERHAUL = {
	--- Whether a character is an Advisor.
	is_advisor = is_advisor,
	--- Lists the Advisors of a faction.
	faction_advisors = faction_advisors,
	--- The weapon and mount an Advisor uses now.
	current_pair = current_pair,
}

cm:add_first_tick_callback(function()
	-- The button and the card boxes come from the UI mods this pack bundles, so a missing one only leaves its part out.
	if UI_PANEL_BUTTON_PICKER then
		UI_PANEL_BUTTON_PICKER.register({
			id = LOADOUT_ID,
			icon = BUTTON_ICON,
			is_for = is_advisor,
			tooltip = function(character)
				return ui_text(used_this_turn(character:command_queue_index()) and "button_used" or "button")
			end,
			locked = function(character)
				return used_this_turn(character:command_queue_index())
			end,
			columns = loadout_columns,
			apply = apply_loadout_pick,
			reselect = true,
		})
	else
		log("no Change Loadout button: UI_PANEL_BUTTON_PICKER is missing")
	end
	if UI_SKILL_PANEL then
		UI_SKILL_PANEL.add_card_boxes({ id = TAG, show_for = is_local_advisor, tips = update_art_card_tips })
	else
		log("no art card boxes: UI_SKILL_PANEL is missing")
	end
	-- advisor_overhaul_spawn.lua spawns the Advisors on the first tick of a new campaign, so this waits until they exist.
	cm:callback(function()
		apply_all("first tick")
	end, 2)
end)
