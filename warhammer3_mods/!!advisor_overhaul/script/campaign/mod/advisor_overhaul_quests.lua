--- Advisor Overhaul quest script: gives every human faction with an Advisor his six item quests as script missions, counts their progress and
--- hands him the item when one succeeds.
---
--- A quest opens once one of the faction's Advisors reaches its rank. The kill quest is counted by the game itself (kills made by his unit set).
--- The others are `SCRIPTED` objectives this script raises: spells of his learned lores cast in his battles, his successful hero actions, wins
--- with each weapon in hand, heroic victories and wins against different races. Progress is saved per faction, so a quest that is issued again
--- (after a failure or a cancel) starts from the saved count. The quest data comes from `ADVISOR_OVERHAUL_RIGS`, written by
--- generators/advisor_overhaul.py, and the Advisor helpers from `ADVISOR_OVERHAUL` in advisor_overhaul.lua.
---
--- A debug pack may set `ADVISOR_OVERHAUL_QUEST_DEBUG` to `{ rank = n, targets = { kind = n, ... }, per_race = n }` to open every quest at a lower
--- rank with smaller targets.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul_quests"

--- Hero action abilities that are no action against a target: embedding in an army or a province, or a passive one.
local NOT_TARGET_ACTIONS = { assist_army = true, assist_province = true, command_force = true, passive_ability = true }

--- The battle result of a heroic victory.
local HEROIC_RESULT = "heroic_victory"

--- Objective layout of the `races` quest. A mission issued with an older layout is cancelled on load and issued again with its saved wins.
local RACES_LAYOUT = 2

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Data

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end

--- The generated data. Read when used, since script load order does not promise the data file loads first.
--- @returns table The `ADVISOR_OVERHAUL_RIGS` table.
local function rig_data()
	return ADVISOR_OVERHAUL_RIGS
end

--- The debug settings of a debug pack, or nil.
--- @returns table|nil `ADVISOR_OVERHAUL_QUEST_DEBUG`.
local function debug_settings()
	return ADVISOR_OVERHAUL_QUEST_DEBUG
end

--- The rank a quest opens at, lowered by a debug pack.
--- @param quest table The quest.
--- @returns number The shown rank.
local function quest_rank(quest)
	local debug = debug_settings()
	return debug and debug.rank or quest.rank
end

--- A quest's target, lowered by a debug pack. For `weapon_wins` it is the wins needed per weapon, for `races` the races needed.
--- @param quest table The quest.
--- @returns number The target.
local function quest_target(quest)
	local debug = debug_settings()
	return debug and debug.targets and debug.targets[quest.kind] or quest.target
end

--- The wins needed against one race for the `races` quest, lowered by a debug pack.
--- @param quest table The quest.
--- @returns number The wins.
local function quest_per_race(quest)
	local debug = debug_settings()
	return debug and debug.per_race or quest.per_race
end

--- The quest of a mission key, or nil.
--- @param key string The mission key.
--- @returns table|nil The quest.
local function quest_of(key)
	for _, quest in ipairs(rig_data().quests) do
		if quest.key == key then
			return quest
		end
	end
	return nil
end

--- The saved value key of a faction's quest state.
--- @param faction_name string The faction.
--- @returns string The key.
local function state_key(faction_name)
	return TAG .. "_" .. faction_name
end

--- A faction's quest state: `issued` and `done` (mission key -> true), `progress` (mission key -> count, races done for the `races` quest),
--- `weapons` (weapon -> wins), `races` (subculture -> wins), `race_order` (subcultures in the order first beaten) and `races_layout`
--- (objective layout the `races` quest was issued with, nil for the first).
--- @param faction_name string The faction.
--- @returns table The state. Changes are kept only after `save_state`.
local function state_of(faction_name)
	local state = cm:get_saved_value(state_key(faction_name)) or {}
	for _, field in ipairs({ "issued", "done", "progress", "weapons", "races", "race_order" }) do
		state[field] = state[field] or {}
	end
	return state
end

--- Saves a faction's quest state.
--- @param faction_name string The faction.
--- @param state table The state.
local function save_state(faction_name, state)
	cm:set_saved_value(state_key(faction_name), state)
end

--- The script key of one counter of a faction's quest. Every faction holds the same mission key, so the script key names the faction.
--- @param quest table The quest.
--- @param faction_name string The faction.
--- @param part string|nil The weapon of a `weapon_wins` objective, `line_<n>` for a race line of the `races` quest, or nil.
--- @returns string The script key.
local function script_key(quest, faction_name, part)
	return quest.key .. "_" .. faction_name .. (part and ("_" .. part) or "")
end

--- The script key of one race line of a faction's `races` quest.
--- @param quest table The quest.
--- @param faction_name string The faction.
--- @param index number The line, from 1.
--- @returns string The script key.
local function line_key(quest, faction_name, index)
	return script_key(quest, faction_name, "line_" .. index)
end

--- Whether a faction's quest is issued and not yet done.
--- @param state table The faction's state.
--- @param quest table The quest.
--- @returns boolean True while it counts.
local function is_active(state, quest)
	return state.issued[quest.key] and not state.done[quest.key]
end

--- The Advisors of a faction, through the loadout script.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @returns table The Advisors.
local function faction_advisors(faction)
	return ADVISOR_OVERHAUL.faction_advisors(faction)
end

--- The races the `races` quest shows, one per line and sorted by name. Races beaten enough always show, the other lines go to the races
--- beaten first. Lines no race holds yet come last.
--- @param state table The faction's state.
--- @param quest table The quest.
--- @returns table Per line `{ race = subculture or nil, wins = n }`.
local function race_lines(state, quest)
	-- Saves from before `race_order` keep their races, in key order.
	local listed, missing = {}, {}
	for _, race in ipairs(state.race_order) do
		listed[race] = true
	end
	for race in pairs(state.races) do
		if not listed[race] then
			table.insert(missing, race)
		end
	end
	table.sort(missing)
	for _, race in ipairs(missing) do
		table.insert(state.race_order, race)
	end
	local per_race, total, lines = quest_per_race(quest), quest_target(quest), {}
	for _, finished in ipairs({ true, false }) do
		for _, race in ipairs(state.race_order) do
			if #lines < total and (state.races[race] >= per_race) == finished then
				table.insert(lines, { race = race, wins = state.races[race] })
			end
		end
	end
	-- Races the registry does not name sort after the named ones, by key.
	local order = {}
	for index, race in ipairs(quest.races) do
		order[race] = index
	end
	table.sort(lines, function(a, b)
		local left, right = order[a.race] or #quest.races + 1, order[b.race] or #quest.races + 1
		if left ~= right then
			return left < right
		end
		return a.race < b.race
	end)
	while #lines < total do
		table.insert(lines, { wins = 0 })
	end
	return lines
end

--- The text key of one race line.
--- @param quest table The `races` quest.
--- @param race string|nil The subculture, or nil for a line no race holds yet.
--- @returns string The objective text key.
local function race_text(quest, race)
	if not race then
		return quest.objectives.race_open
	end
	return quest.objectives["race_" .. race] or quest.objectives.race_other
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Missions

--- Adds one counted `SCRIPTED` objective to a mission. It completes itself once its count reaches the total, unless it is left open.
--- @param mm table The mission manager.
--- @param key string The script key.
--- @param text string The objective text key.
--- @param total number The total.
--- @param count number The count so far.
--- @param open boolean|nil True to leave it open until the script completes it, for a race line whose race can change.
local function add_counter(mm, key, text, total, count, open)
	mm:add_new_objective("SCRIPTED")
	mm:add_condition("script_key " .. key)
	mm:add_condition("override_text " .. text)
	mm:add_condition("total " .. total)
	mm:add_condition("count " .. math.min(count, total))
	if not open then
		mm:add_condition("count_completion")
	end
end

--- Issues one quest's mission to a faction, with its saved progress, and marks it issued.
--- @param faction_name string The faction.
--- @param state table The faction's state, saved after.
--- @param quest table The quest.
--- @param why string What caused it, for the log.
local function issue(faction_name, state, quest, why)
	local target = quest_target(quest)
	local mm = mission_manager:new(faction_name, quest.key)
	mm:set_mission_issuer(rig_data().mission_issuer)
	-- Without this every objective after the first needs its own payload, and the game refuses the mission.
	mm:set_all_objectives_are_primary()
	local counts
	if quest.kind == "kills" then
		mm:add_new_objective("KILL_X_ENTITIES_BY")
		mm:add_condition("total " .. target)
		mm:add_condition("unit_set " .. rig_data().unit_set)
		mm:add_condition("override_text " .. quest.objectives[""])
		counts = "kills counted by the game"
	elseif quest.kind == "weapon_wins" then
		local parts = {}
		for _, weapon in ipairs(rig_data().weapons) do
			local wins = state.weapons[weapon.key] or 0
			add_counter(mm, script_key(quest, faction_name, weapon.key), quest.objectives[weapon.key], target, wins)
			table.insert(parts, weapon.key .. " " .. wins)
		end
		counts = table.concat(parts, ", ")
	else
		local count = state.progress[quest.key] or 0
		add_counter(mm, script_key(quest, faction_name), quest.objectives[""], target, count)
		counts = tostring(count)
		if quest.kind == "races" then
			local parts = { counts }
			for index, line in ipairs(race_lines(state, quest)) do
				add_counter(mm, line_key(quest, faction_name, index), race_text(quest, line.race), quest_per_race(quest), line.wins, true)
				table.insert(parts, (line.race or "open") .. " " .. line.wins)
			end
			counts = table.concat(parts, ", ")
		end
	end
	-- The vanilla item payload, so the reward shows the item card. It lands in the faction pool and `equip_reward` moves it onto him.
	mm:add_payload("add_ancillary_to_faction_pool{ancillary_key " .. quest.item .. ";}")
	mm:set_should_whitelist(false)
	mm:trigger()
	if not mm:has_been_triggered() then
		log(faction_name .. " could not get " .. quest.key .. ", the game refused the mission, it is tried again at the next turn start")
		return
	end
	state.issued[quest.key] = true
	if quest.kind == "races" then
		state.races_layout = RACES_LAYOUT
	end
	save_state(faction_name, state)
	log(faction_name .. " gets " .. quest.key .. " (" .. quest.kind .. ", target " .. target .. ", so far " .. counts .. ") on " .. why)
end

--- Issues every quest a faction has not got yet whose rank one of its Advisors has reached.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param why string What caused the check, for the log.
local function issue_due(faction, why)
	if not faction:is_human() then
		return
	end
	local faction_name = faction:name()
	local state = state_of(faction_name)
	local pending = {}
	for _, quest in ipairs(rig_data().quests) do
		if not state.issued[quest.key] and not state.done[quest.key] then
			table.insert(pending, quest)
		end
	end
	-- Most of a campaign every quest is out already, so the character list is only walked while one is still to come.
	if #pending == 0 then
		return
	end
	local top = 0
	for _, advisor in ipairs(faction_advisors(faction)) do
		top = math.max(top, advisor:rank())
	end
	for _, quest in ipairs(pending) do
		if top >= quest_rank(quest) then
			issue(faction_name, state, quest, why .. " (top Advisor rank " .. top .. ")")
		end
	end
end

--- Raises one counter of a faction's active quest, never past its target, and raises its mission objective by the same amount.
--- @param faction_name string The faction.
--- @param state table The faction's state, saved after.
--- @param quest table The quest.
--- @param counts table The saved counts holding this counter: `state.progress` or `state.weapons`.
--- @param part string|nil The weapon of a `weapon_wins` counter, or nil for the quest's only counter.
--- @param amount number How much it rose.
--- @param why string What it counted, for the log.
local function raise(faction_name, state, quest, counts, part, amount, why)
	local slot = part or quest.key
	local target = quest_target(quest)
	local before = counts[slot] or 0
	local after = math.min(before + amount, target)
	log(faction_name .. " " .. script_key(quest, faction_name, part) .. ": " .. before .. " -> " .. after .. " of " .. target .. " (" .. why .. ")")
	if after == before then
		return
	end
	counts[slot] = after
	save_state(faction_name, state)
	-- The race lines stay open, so they are completed before the last race completes the quest.
	if quest.kind == "races" and after == target then
		for index = 1, target do
			cm:complete_scripted_mission_objective(faction_name, quest.key, line_key(quest, faction_name, index), true)
		end
	end
	cm:increase_scripted_mission_count(quest.key, script_key(quest, faction_name, part), after - before)
end

--- Rewrites every race line of a faction's `races` quest from its saved wins, since a new race can move the others between lines.
--- @param faction_name string The faction.
--- @param state table The faction's state.
--- @param quest table The `races` quest.
local function refresh_race_lines(faction_name, state, quest)
	local per_race, parts = quest_per_race(quest), {}
	for index, line in ipairs(race_lines(state, quest)) do
		cm:set_scripted_mission_text(quest.key, line_key(quest, faction_name, index), race_text(quest, line.race), math.min(line.wins, per_race), per_race)
		table.insert(parts, (line.race or "open") .. " " .. line.wins)
	end
	log(faction_name .. " race lines: " .. table.concat(parts, ", "))
end

--- Repairs a faction's saved quests on load. A quest marked issued with no active mission is cleared, so it is issued again. A `races`
--- mission from an older layout is cancelled, so it comes back with its race lines and saved wins.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
local function repair_quests(faction)
	local faction_name = faction:name()
	local state = state_of(faction_name)
	local outdated = {}
	for _, quest in ipairs(rig_data().quests) do
		if is_active(state, quest) then
			if not cm:mission_is_active_for_faction(faction, quest.key) then
				state.issued[quest.key] = nil
				log(faction_name .. " has " .. quest.key .. " marked issued but no such mission, it is issued again")
			elseif quest.kind == "races" and (state.races_layout or 1) < RACES_LAYOUT then
				table.insert(outdated, quest.key)
			end
		end
	end
	save_state(faction_name, state)
	-- Cancelling fires `MissionCancelled`, whose listener clears the issued mark, so the state is saved first.
	for _, key in ipairs(outdated) do
		log(faction_name .. " has " .. key .. " from an older layout, it is cancelled and issued again")
		cm:cancel_custom_mission(faction_name, key)
	end
end

--- Moves a quest item the mission payload put in the faction pool onto a faction's Advisor: the first at the quest's rank, else any. With no
--- Advisor it stays in the pool.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param quest table The quest.
local function equip_reward(faction, quest)
	local advisors = faction_advisors(faction)
	local chosen = advisors[1]
	for _, advisor in ipairs(advisors) do
		if advisor:rank() >= quest_rank(quest) then
			chosen = advisor
			break
		end
	end
	if not chosen then
		log(faction:name() .. " got " .. quest.item .. " with no Advisor, it stays in the faction pool")
		return
	end
	cm:force_remove_ancillary_from_faction(faction, quest.item)
	cm:force_add_ancillary(chosen, quest.item, true, true)
	log(faction:name() .. " got " .. quest.item .. ", moved from the pool to Advisor cqi " .. chosen:command_queue_index() .. " (rank " .. chosen:rank()
		.. "), he has it now: " .. tostring(chosen:has_ancillary(quest.item)))
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Battles

--- The military force an Advisor fights with: his own as a general, or the one he is embedded in.
--- @param advisor CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns number|nil The force's cqi, or nil when he is in neither.
local function advisor_force(advisor)
	if advisor:has_military_force() then
		return advisor:military_force():command_queue_index()
	end
	if advisor:is_embedded_in_military_force() then
		return advisor:embedded_in_military_force():command_queue_index()
	end
	return nil
end

--- The armies of one side of the cached battle.
--- @param attackers boolean True for the attackers, false for the defenders.
--- @returns table A list of `{ mf_cqi, faction_name }`.
local function side_entries(attackers)
	local entries = {}
	local count = attackers and cm:pending_battle_cache_num_attackers() or cm:pending_battle_cache_num_defenders()
	for i = 1, count do
		local _, mf_cqi, faction_name
		if attackers then
			_, mf_cqi, faction_name = cm:pending_battle_cache_get_attacker(i)
		else
			_, mf_cqi, faction_name = cm:pending_battle_cache_get_defender(i)
		end
		table.insert(entries, { mf_cqi = mf_cqi, faction_name = faction_name })
	end
	return entries
end

--- Spells of his learned lores the faction cast in this battle, overcasts included. Other casters of the same lores in the battle count too.
--- @param pb PENDING_BATTLE_SCRIPT_INTERFACE The battle.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param advisor CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns number The casts.
--- @returns string The lores counted, for the log.
local function lore_casts(pb, faction, advisor)
	local casts, lores = 0, {}
	for _, lore in ipairs(rig_data().lore_spells) do
		local learned = false
		for _, skill in ipairs(lore.skills) do
			learned = learned or advisor:has_skill(skill)
		end
		if learned then
			table.insert(lores, lore.skills[1])
			for _, ability in ipairs(lore.abilities) do
				casts = casts + pb:get_how_many_times_ability_has_been_used_in_battle(faction:command_queue_index(), ability)
			end
		end
	end
	return casts, table.concat(lores, ", ")
end

--- Counts one fought battle for one faction's Advisor: spells, a weapon win, a heroic victory and the races beaten.
--- @param pb PENDING_BATTLE_SCRIPT_INTERFACE The battle.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param advisor CHARACTER_SCRIPT_INTERFACE The Advisor, who was in the battle.
--- @param attacker boolean Whether his side attacked.
local function count_battle(pb, faction, advisor, attacker)
	local faction_name = faction:name()
	local state = state_of(faction_name)
	local won, result
	if attacker then
		won, result = cm:pending_battle_cache_attacker_victory(), pb:attacker_battle_result()
	else
		won, result = cm:pending_battle_cache_defender_victory(), pb:defender_battle_result()
	end
	log("battle for " .. faction_name .. ": Advisor cqi " .. advisor:command_queue_index() .. " " .. (attacker and "attacking" or "defending")
		.. ", won " .. tostring(won) .. " (" .. tostring(result) .. ")")
	for _, quest in ipairs(rig_data().quests) do
		if is_active(state, quest) then
			if quest.kind == "spells" then
				local casts, lores = lore_casts(pb, faction, advisor)
				raise(faction_name, state, quest, state.progress, nil, casts, casts .. " casts from his lores [" .. lores .. "]")
			elseif quest.kind == "heroic" and won and result == HEROIC_RESULT then
				raise(faction_name, state, quest, state.progress, nil, 1, "heroic victory")
			elseif quest.kind == "weapon_wins" and won then
				local weapon = ADVISOR_OVERHAUL.current_pair(advisor)
				raise(faction_name, state, quest, state.weapons, weapon, 1, "win with " .. weapon)
			elseif quest.kind == "races" and won then
				-- Each race is counted once per battle. A race counts toward the quest once it is beaten `per_race` times.
				local per_race, seen, finished, changed = quest_per_race(quest), {}, {}, false
				for _, entry in ipairs(side_entries(not attacker)) do
					local enemy = cm:get_faction(entry.faction_name)
					local race = enemy and entry.faction_name ~= "rebels" and enemy:subculture()
					if race and not seen[race] then
						seen[race] = true
						local before = state.races[race] or 0
						if before == 0 then
							table.insert(state.race_order, race)
						end
						if before < per_race then
							state.races[race] = before + 1
							changed = true
						end
						log("  wins against " .. race .. " (" .. entry.faction_name .. "): " .. before .. " -> " .. state.races[race] .. " of " .. per_race)
						if before + 1 == per_race then
							table.insert(finished, race)
						end
					end
				end
				if changed then
					save_state(faction_name, state)
					refresh_race_lines(faction_name, state, quest)
				end
				for _, race in ipairs(finished) do
					raise(faction_name, state, quest, state.progress, nil, 1, race .. " beaten " .. per_race .. " times")
				end
			end
		end
	end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_battle",
	"BattleCompleted",
	function()
		return cm:model():pending_battle():has_been_fought()
	end,
	function()
		local pb = cm:model():pending_battle()
		-- A faction can field several armies in one battle, so its Advisors are listed once.
		local advisors_of = {}
		for _, attacker in ipairs({ true, false }) do
			for _, entry in ipairs(side_entries(attacker)) do
				local faction = cm:get_faction(entry.faction_name)
				if faction and faction:is_human() then
					advisors_of[entry.faction_name] = advisors_of[entry.faction_name] or faction_advisors(faction)
					for _, advisor in ipairs(advisors_of[entry.faction_name]) do
						if advisor_force(advisor) == entry.mf_cqi then
							count_battle(pb, faction, advisor, attacker)
						end
					end
				end
			end
		end
	end,
	true
)

--- Counts a successful hero action of an Advisor against a character or a garrison.
--- @param context table The event context.
local function on_action(context)
	local character = context:character()
	local faction = character:faction()
	local state = state_of(faction:name())
	for _, quest in ipairs(rig_data().quests) do
		if quest.kind == "actions" and is_active(state, quest) then
			raise(faction:name(), state, quest, state.progress, nil, 1, "hero action " .. tostring(context:agent_action_key()) .. " (" .. tostring(context:ability()) .. ")")
		end
	end
end

--- Whether an event is a successful target action by a human faction's Advisor.
--- @param context table The event context.
--- @returns boolean True to count it.
local function is_advisor_action(context)
	local character = context:character()
	return ADVISOR_OVERHAUL.is_advisor(character) and character:faction():is_human() and not NOT_TARGET_ACTIONS[context:ability()]
		and (context:mission_result_success() or context:mission_result_critial_success())
end

core:add_listener(TAG .. "_character_action", "CharacterCharacterTargetAction", is_advisor_action, on_action, true)
core:add_listener(TAG .. "_garrison_action", "CharacterGarrisonTargetAction", is_advisor_action, on_action, true)

core:add_listener(
	TAG .. "_mission_succeeded",
	"MissionSucceeded",
	function(context)
		return quest_of(context:mission():mission_record_key()) ~= nil
	end,
	function(context)
		local key = context:mission():mission_record_key()
		local state = state_of(context:faction():name())
		state.done[key] = true
		save_state(context:faction():name(), state)
		log(context:faction():name() .. " finished " .. key)
	end,
	true
)

--- The quest whose item this is, or nil.
--- @param item string The ancillary key.
--- @returns table|nil The quest.
local function quest_of_item(item)
	for _, quest in ipairs(rig_data().quests) do
		if quest.item == item then
			return quest
		end
	end
	return nil
end

core:add_listener(
	TAG .. "_item_gained",
	"FactionGainedAncillary",
	function(context)
		return context:faction():is_human() and quest_of_item(context:ancillary()) ~= nil
	end,
	function(context)
		equip_reward(context:faction(), quest_of_item(context:ancillary()))
	end,
	true
)

--- Clears the issued mark of a failed or cancelled quest, so the next turn start issues it again with its saved progress.
--- @param context table The event context.
local function on_mission_lost(context)
	local key = context:mission():mission_record_key()
	-- A late event for a mission that `repair_quests` already issued again leaves the new one alone.
	if cm:mission_is_active_for_faction(context:faction(), key) then
		log(context:faction():name() .. " lost an older " .. key .. ", the new one stays")
		return
	end
	local state = state_of(context:faction():name())
	state.issued[key] = nil
	save_state(context:faction():name(), state)
	log(context:faction():name() .. " lost " .. key .. ", it is issued again at the next turn start")
end

for _, event in ipairs({ "MissionFailed", "MissionCancelled" }) do
	core:add_listener(TAG .. "_" .. event, event, function(context)
		return quest_of(context:mission():mission_record_key()) ~= nil
	end, on_mission_lost, true)
end

core:add_listener(
	TAG .. "_rank_up",
	"CharacterRankUp",
	function(context)
		return ADVISOR_OVERHAUL.is_advisor(context:character())
	end,
	function(context)
		issue_due(context:character():faction(), "rank up")
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
		issue_due(context:faction(), "turn start")
	end,
	true
)

cm:add_first_tick_callback(function()
	-- advisor_overhaul_spawn.lua spawns the Advisors on the first tick of a new campaign, so this waits until they exist.
	cm:callback(function()
		if debug_settings() then
			log("debug pack loaded: " .. tostring(debug_settings().rank) .. " rank, smaller targets")
		end
		local humans = cm:get_human_factions()
		for _, faction_name in ipairs(humans) do
			repair_quests(cm:get_faction(faction_name))
			issue_due(cm:get_faction(faction_name), "first tick")
		end
	end, 3)
end)
