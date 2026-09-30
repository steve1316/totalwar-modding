--- Central manager module. Bundles: random_encounter_force_generation_system, IncidentManager (free-function globals),
--- InvasionBattleManager (spawn + invasion lifecycle), SpotEventManager, and PointOfInterestEventManager.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local army_generator = require("script/land_encounters/core/army_generator")

--- Feature delegates are lazy-loaded inside the manager constructors below to avoid a circular
--- require (the delegates pull core/managers back in for the incident globals).
local BattleEventDelegate
local TreasureEventDelegate
local SmithyEventDelegate
local TowerEventDelegate

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- random_encounter_force_generation_system
--- (from algorithms/random_encounter_force_generation_system.lua)

--- Pulls the MCT-configured difficulty definitions into a local for hot-path access.
local difficulties = get_mct_settings().difficulties

--- Maps the 3-letter faction shorthand used internally to the qb1 quick-battle faction key the engine expects.
local faction_shorthand_key_to_full_key = {
    tmb = "wh2_dlc09_tmb_tombking_qb1",
    cst = "wh2_dlc11_cst_vampire_coast_qb1",
    def = "wh2_main_def_dark_elves_qb1",
    hef = "wh2_main_hef_high_elves_qb1",
    lzd = "wh2_main_lzd_lizardmen_qb1",
    skv = "wh2_main_skv_skaven_qb1",
    chd = "wh3_dlc23_chd_chaos_dwarfs_qb1",
    kho = "wh3_main_kho_khorne_qb1",
    ksl = "wh3_main_ksl_kislev_qb1",
    tze = "wh3_main_tze_tzeentch_qb1",
    cth = "wh3_main_cth_cathay_qb1",
    nur = "wh3_main_nur_nurgle_qb1",
    ogr = "wh3_main_ogr_ogre_kingdoms_qb1",
    sla = "wh3_main_sla_slaanesh_qb1",
    bst = "wh_dlc03_bst_beastmen_qb1",
    wef = "wh_dlc05_wef_wood_elves_qb1",
    nor = "wh2_dlc11_nor_norsca_qb4",
    brt = "wh_main_brt_bretonnia_qb1",
    chs = "wh_main_chs_chaos_qb1",
    dwf = "wh_main_dwf_dwarfs_qb1",
    emp = "wh_main_emp_empire_qb1",
    grn = "wh_main_grn_greenskins_qb1",
    vmp = "wh_main_vmp_vampire_counts_qb1",
    --- teb = "wh_main_teb_border_princes_rebels",
    --- mar = "wh_main_emp_marienburg_rebels",
    --- dmd = "wh3_dlc21_vmp_jiangshi_rebels",
    --- jbv = "mixer_vmp_the_curse_of_nongchang_rebels", -- This is custom for Land Encounters.
    --- nag = "mixer_nag_nagash_rebels", -- This is custom for Land Encounters.
    --- alb = "ovn_alb_rebel",
    --- arb = "ovn_arb_araby_rebels",
    --- dk = "ovn_tmb_dread_king_rebels", -- This is custom for Land Encounters.
    --- fim = "ovn_fim_fimir_rebel",
}

--- Recursively prints any Lua value to `out()` for debugging.
--- @param tbl any The value to print. Non-tables are stringified directly.
--- @param indent number Current indent depth. Defaults to 0 when nil.
function print_table(tbl, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)

    if type(tbl) ~= "table" then
        out(indent_str .. tostring(tbl))
        return
    end

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            out(indent_str .. tostring(key) .. ":")
            print_table(value, indent + 1)
        else
            out(indent_str .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

--- Lists the faction shorthands encounters may use: the MCT-enabled set (every faction when none are picked), minus modded factions
--- whose parent mod is not loaded.
--- @returns table An array of 3-letter faction shorthand keys.
function get_enabled_faction_keys()
    local faction_keys = {}

    if get_mct_settings().enable_all_factions then
        out("DEBUG - get_random_faction Enabling all factions.")
        for key, _ in pairs(faction_shorthand_key_to_full_key) do
            table.insert(faction_keys, key)
        end
    else
        out("DEBUG - get_random_faction Enabling selected factions.")
        for _, key in ipairs(get_mct_settings().enabled_faction_keys) do
            table.insert(faction_keys, key)
        end

        if #faction_keys == 0 then
            out("DEBUG - get_random_faction No factions are enabled, enabling all factions.")
            for key, _ in pairs(faction_shorthand_key_to_full_key) do
                table.insert(faction_keys, key)
            end
        end
    end

    out("DEBUG - get_random_faction Faction keys:")
    print_table(faction_keys)

    --- Modded factions are only eligible if their parent mod is in the enabled-mods list.
    local modded_factions = {
        teb = "!ak_teb3",
        mar = "!scm_marienburg",
        dmd = "AAA_dynasty_of_the_damned",
        jbv = "jade_vamp_pol",
        nag = "nag_nagash",
        alb = "ovn_albion",
        arb = "ovn_araby",
        dk = "ovn_dread_king",
        fim = "ovn_fimir",
    }

    --- Drop modded factions whose parent mod is not loaded.
    local enabled_mods = get_mct_settings().enabled_mods
    local filtered_faction_keys = {}

    for _, key in ipairs(faction_keys) do
        local mod = modded_factions[key]
        if not mod or contains(enabled_mods, mod, false) then
            table.insert(filtered_faction_keys, key)
        end
    end

    return filtered_faction_keys
end

--- Picks a random faction shorthand from `get_enabled_faction_keys`.
--- @returns string A 3-letter faction shorthand key (e.g. "emp", "grn").
function get_random_faction()
    local faction_keys = get_enabled_faction_keys()
    return faction_keys[random_number(#faction_keys)]
end

--- Reports whether a faction fought in the battle that just completed, and whether it won.
--- @param faction_name string The faction key to look for in the pending battle cache.
--- @returns boolean True when the faction was the attacker or the defender.
--- @returns boolean True when the faction's side won.
function pending_battle_result_for_faction(faction_name)
    if cm:pending_battle_cache_faction_is_attacker(faction_name) then
        return true, cm:pending_battle_cache_attacker_victory()
    elseif cm:pending_battle_cache_faction_is_defender(faction_name) then
        return true, cm:pending_battle_cache_defender_victory()
    end
    return false, false
end

--- True when a military force with this cqi still exists.
--- @param force_cqi number The force's command queue index, or nil.
--- @returns boolean True when the force can be found.
function force_exists(force_cqi)
    if not force_cqi then return false end
    local force = cm:get_military_force_by_cqi(force_cqi)
    return force ~= nil and force ~= false and not force:is_null_interface()
end

--- Runs `kill` with the character-death and faction-destroyed event feeds muted, so scripted forces vanish without notices.
--- @param kill function The function that removes the force.
function with_death_feed_muted(kill)
    cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
    cm:disable_event_feed_events(true, "wh_event_category_character", "", "")
    kill()
    cm:callback(function() cm:disable_event_feed_events(false, "", "", "diplomacy_faction_destroyed") end, 1)
    cm:callback(function() cm:disable_event_feed_events(false, "wh_event_category_character", "", "") end, 1)
end

--- Removes a character and its army without death notices.
--- @param character_cqi number The general's command queue index.
function kill_character_quietly(character_cqi)
    with_death_feed_muted(function() cm:kill_character_and_commanded_unit(cm:char_lookup_str(character_cqi), true) end)
end

--- Returns true if `tbl` contains `element`. If `key_first` is true, checks keys; otherwise checks values.
--- @param tbl table The table to search. nil is treated as empty.
--- @param element any The value or key to search for.
--- @param key_first boolean When true, matches against keys instead of values.
--- @returns boolean True when the element is found.
function contains(tbl, element, key_first)
    if tbl == nil then
        return false
    end
    for k, v in pairs(tbl) do
        if key_first and k == element then
            return true
        elseif not key_first and v == element then
            return true
        end
    end
    return false
end

--- Returns the current encounter difficulty as one of "easy", "medium", or "hard". Uses the MCT
--- dropdown unless progressive scaling is enabled, in which case difficulty ramps up by turn.
--- @returns string The current difficulty key.
function get_current_difficulty()
    local mct = get_mct_settings()
    if not mct.enable_basic_progressive_difficulty then
        return mct.randomized_encounter_force_generation_difficulty
    end
    if cm:turn_number() < mct.turn_number_from_easy_to_medium then
        return "easy"
    elseif cm:turn_number() < mct.turn_number_from_medium_to_hard then
        return "medium"
    else
        return "hard"
    end
end

--- Entry point for the force-makeup pipeline. Builds the army from the difficulty's gold budget and a rolled archetype.
--- @param difficulty_key string The difficulty key ("easy", "medium", or "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param options table Optional battle-category overrides passed to `army_generator.generate` (`archetype_keys`, `budget_multiplier`). A
--- `battle_picker` event record works as-is.
--- @returns table A force_makeup with lord, heroes, per-type units arrays, and the archetype key.
function start_force_makeup_generation(difficulty_key, faction_shorthand_key, options)
    return army_generator.generate(difficulty_key, faction_shorthand_key, options)
end

--- Converts the raw force makeup into the flat record the InvasionBattleManager + Army constructors expect.
--- @param difficulty string The difficulty key (used to read level + experience ranges).
--- @param force_makeup table The output of start_force_makeup_generation.
--- @param faction_key string A 3-letter faction shorthand.
--- @param identifier string A unique force identifier (e.g. "encounter_force").
--- @param invasion_identifier string A unique invasion identifier (e.g. "encounter_invasion").
--- @param intervention_type number One of AMBUSH_TYPE, INTERCEPTION_TYPE, ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
--- @returns table A flat converted_force record ready for Army:create_from.
function convert_force_makeup_to_usable_format(difficulty, force_makeup, faction_key, identifier, invasion_identifier, intervention_type)
    local converted_force = {
        faction = faction_shorthand_key_to_full_key[faction_key],
        identifier = identifier,
        invasion_identifier = invasion_identifier,
        intervention_type = intervention_type,
        archetype = force_makeup.archetype,
        --- The lord pool is now a flat record. The randomization-only pipeline picks a single
        --- agent_subtype up front and a level within the difficulty's lord_level_range. Names,
        --- ancillaries, and traits are not generated for randomized lords - they default to
        --- empty strings / empty tables in Army:create_from.
        lord = {
            agent_subtype = force_makeup.lord.agent_subtype,
            level_range = { difficulties[difficulty].lord_level_range[1], difficulties[difficulty].lord_level_range[2] },
        },
        heroes = {},
        unit_experience_amount = random_range(difficulties[difficulty].unit_experience_amount[1], difficulties[difficulty].unit_experience_amount[2]),
        units = {},
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false,
        skill_overrides = {},
    }

    --- Save the skill overrides for the lord if available.
    if contains(force_makeup.lord, "skill_overrides", true) and #force_makeup.lord.skill_overrides > 0 then
        converted_force.skill_overrides[force_makeup.lord.agent_subtype] = {}
        for _, skill in ipairs(force_makeup.lord.skill_overrides) do
            table.insert(converted_force.skill_overrides[force_makeup.lord.agent_subtype], skill)
        end
    end

    --- Add the heroes if there are any and the skill overrides for them.
    if #force_makeup.heroes > 0 then
        for _, hero in ipairs(force_makeup.heroes) do
            table.insert(converted_force.heroes, {
                --- Create a copy of the hero without skill_overrides.
                land_unit = hero.land_unit,
                agent_subtype = hero.agent_subtype,
                agent_type = hero.agent_type,
                origin = hero.origin
            })

            if contains(hero, "skill_overrides", true) and #hero.skill_overrides > 0 then
                converted_force.skill_overrides[hero.agent_subtype] = {}
                for _, skill in ipairs(hero.skill_overrides) do
                    table.insert(converted_force.skill_overrides[hero.agent_subtype], skill)
                end
            end
        end
    end

    --- Insert the units into the table as flat { id, count } records.
    for unit_type, units in pairs(force_makeup.units) do
        for _, unit in ipairs(units) do
            table.insert(converted_force.units, { id = unit, count = 1 })
        end
    end

    return converted_force
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- IncidentManager
--- (from controllers/incident_manager.lua)

local IGNORE_INCIDENT_PARAMETER_FLAG = 0

--- Fires an incident for the given player character, populating only the CQI slots indicated by `targets`.
--- @param incident_key string The incident key from the db.
--- @param targets table A flag map with optional faction, character, force, and region booleans.
--- @param player_character character The player character to receive the incident.
function trigger_incident_for_character(incident_key, targets, player_character)
    local faction_cqi = player_character:faction():command_queue_index()

    local target_faction_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.faction then
        target_faction_cqi = faction_cqi
    end

    local secondary_faction_cqi = IGNORE_INCIDENT_PARAMETER_FLAG

    local character_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.character then
        character_cqi = player_character:command_queue_index()
    end

    local military_force_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.force then
        military_force_cqi = player_character:military_force():command_queue_index()
    end

    local region_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.region then
    end

    local settlement_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    cm:trigger_incident_with_targets(faction_cqi, incident_key, target_faction_cqi, secondary_faction_cqi, character_cqi, military_force_cqi, region_cqi, settlement_cqi)
end

--- True if the faction is human-controlled and the human turn is currently active.
--- @param faction faction The faction object to check.
--- @returns boolean True when the faction is human and its turn is active.
function is_human_and_it_is_its_turn(faction)
    return faction:is_human() and cm:is_human_factions_turn()
end

--- Returns the general closest to the given spot's coordinates. Searches the human factions whose turn it is, or every human faction
--- when none is, so all multiplayer clients agree and the reward goes to the player who triggered it.
--- @param spot_info table A spot_info record with a coordinates {x, y} field.
--- @returns character The closest player general, or nil when none is found.
function get_player_faction_character_closest_to_spot(spot_info)
    local only_general = true
    local is_garrison_commander = false
    local candidate_factions = {}
    for _, faction_name in ipairs(cm:get_human_factions()) do
        if cm:is_factions_turn_by_key(faction_name) then
            table.insert(candidate_factions, faction_name)
        end
    end
    if #candidate_factions == 0 then
        candidate_factions = cm:get_human_factions()
    end
    local closest_character, closest_distance = nil, nil
    for _, faction_name in ipairs(candidate_factions) do
        local character, distance = cm:get_closest_character_to_position_from_faction(faction_name, spot_info.coordinates[1], spot_info.coordinates[2], only_general, is_garrison_commander)
        if character and (closest_distance == nil or distance < closest_distance) then
            closest_character, closest_distance = character, distance
        end
    end
    return closest_character
end

--- Resolves the player character (falling back to closest-to-spot after a post-battle reload) and fires the incident, but only for humans on their turn.
--- @param incident_key string The incident key from the db.
--- @param targets table A flag map with optional faction, character, force, and region booleans.
--- @param spot_info table A spot_info record used as a fallback location for character lookup.
--- @param player_character character The triggering player character. May be nil after a reload.
function trigger_incident(incident_key, targets, spot_info, player_character)
    --- If the campaign was reloaded from a battle, the live player_character may be missing.
    --- Use the closest player general to the spot as a best-effort substitute. The rewards still
    --- go to the right faction even if the specific character is wrong.
    if player_character == nil or (type(player_character) == "table" and next(player_character) == nil) then
        player_character = get_player_faction_character_closest_to_spot(spot_info)
    end

    if is_human_and_it_is_its_turn(player_character:faction()) then
        trigger_incident_for_character(incident_key, targets, player_character)
    end
end

--- IncidentManager is a free-functions module. Expose an empty marker table so the return statement
--- at the end of this merged file can publish a stable handle.
local IncidentManager = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- InvasionBattleManager
--- (from controllers/invasion_battle_manager.lua)

local IS_NOT_PERSISTENT_LISTENER = false
--- svr key holding the encounter ally's faction key, so the battle script calls that army in as soon as the battle starts. Mirrored in script/battle/mod.
local ALLY_ARRIVES_NOW_SVR_KEY = "land_enc_ally_arrives_now"

local InvasionBattleManager = {
    --- Main listener manager.
    core = false,
    --- Engine managers used to spawn random armies and run invasions.
    random_army_manager = false,
    invasion_manager = false,
    --- The army currently engaging the player.
    event_army = false
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Class methods

--- True if a valid spawn location exists for the offensive army near the spot.
--- @param offensive_army Army The attacking Army instance.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @returns boolean True when find_location_for_character_to_spawn returns valid coordinates.
function InvasionBattleManager:can_generate_battle(offensive_army, spot_coordinates)
    if offensive_army then
        out("DEBUG - can_generate_battle checking if we can find a location to spawn the army")
        local x, y = self:find_location_for_character_to_spawn(offensive_army.faction, spot_coordinates)
        if x ~= -1 and y ~= -1 then
            return true
        end
    end
    out("DEBUG - can_generate_battle could not find a location to spawn the army")
    return false
end


--- Generates an offensive battle. Routes through enemy reinforcement / ally reinforcement / direct attack
--- paths depending on which reinforcement data the encounter carries.
--- @param offensive_army Army The attacking Army instance.
--- @param player_character character The player character being attacked.
--- @param spot_coordinates table A {x, y} table for the spot center.
function InvasionBattleManager:generate_battle(offensive_army, player_character, spot_coordinates)
    self.event_army = offensive_army
    out("DEBUG - testing randomize_units")
    self.event_army:randomize_units(self.random_army_manager)
    out("DEBUG - event army randomized in generate_battle")

    local force_cqi = player_character:military_force():command_queue_index()
    local player_faction_name = player_character:faction():name()

    --- Dispatch based on which reinforcement data the encounter carries.
    if self.event_army:has_offensive_reinforcements() then
        --- Enemy reinforcement path also chains into ally spawning inside the recursive callback
        --- (create_enemy_reinforcements_before_attack -> create_allied_reinforcements_before_attack).
        self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, 1)
    elseif self.event_army:has_ally_reinforcements() then
        --- Ally-only path. No enemy reinforcements exist yet, so we pass player_character as the
        --- ally's objective_character. set_target("CHARACTER", ...) is a movement target, not a
        --- hostility marker - no war is declared between ally and player. The ally just moves toward
        --- the player to be in range. The ally-vs-main-enemy war is declared later by
        --- declare_war_on_ally_reinforcement_if_available inside main_attacker_attacks_player_and_allies.
        self:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, player_character)
    else
        self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
    end
end


--- Spawns enemy reinforcement armies first. The main attacker is launched after the last
--- reinforcement is in place (and any ally reinforcements are spawned in between if present).
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @param army_number number 1-based index of the reinforcement army being spawned.
function InvasionBattleManager:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, army_number)
    local reinforcing_army = self.event_army.reinforcing_enemy_armies[army_number]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, player_character, invader_force, {x, y})

    invasion:start_invasion(
        function(invasion_force)
            --- Force war with this faction for the player.
            local call_player_allies_to_war = false
            local call_faction_allies_to_war = false
            cm:force_declare_war(reinforcing_army.faction, player_faction_name, call_player_allies_to_war, call_faction_allies_to_war)
            if army_number == #self.event_army.reinforcing_enemy_armies then
                --- All enemy reinforcements have been spawned.
                if self.event_army:has_ally_reinforcements() then
                    local enemy_character = cm:get_closest_character_to_position_from_faction(reinforcing_army.faction, spot_coordinates[1], spot_coordinates[2])
                    self:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
                else
                    self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
                end
            else
                local next_army_number = army_number + 1
                self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, next_army_number)
            end
        end,
        false,
        false,
        false
    )
end


--- Spawns the allied reinforcement army (if any) and then launches the main attacker.
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @param enemy_character character The enemy whose army the ally targets for movement.
function InvasionBattleManager:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
    local reinforcing_army = self.event_army.reinforcing_ally_armies[1]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, enemy_character, invader_force, {x, y})
    invasion:start_invasion(
        function(invasion_force)
            --- Force war with the enemy reinforcement armies.
            self:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(reinforcing_army.faction)
            self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
        end,
        false,
        false,
        false
    )
end


--- Declares war from `allied_faction` against every enemy reinforcement army on the encounter, if any.
--- @param allied_faction string The faction key of the allied reinforcement army.
function InvasionBattleManager:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(allied_faction)
    if self.event_army:has_offensive_reinforcements() then
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        for i=1, #self.event_army.reinforcing_enemy_armies do
            cm:force_declare_war(allied_faction, self.event_army.reinforcing_enemy_armies[i].faction, call_player_allies_to_war, call_faction_allies_to_war)
        end
    end
end


--- Spawns the main attacker, embeds heroes + skill overrides, declares war on the player and any
--- allied reinforcements, then dispatches the engagement (ambush, interception, or allied reinforcements).
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param player_force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
function InvasionBattleManager:main_attacker_attacks_player_and_allies(player_character, player_faction_name, player_force_cqi, spot_coordinates)
    local x, y = self:find_location_for_character_to_spawn(self.event_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(self.event_army.force_identifier)
    local invasion = self:setup_invasion(self.event_army, player_character, invader_force, {x, y})

    out("DEBUG - invasion setup complete. Now starting invasion")

    invasion:start_invasion(
        function(invasion_force)
            local engaged = false
            --- Embeds heroes and skills, then starts the battle. Runs once, from the war declaration or directly when the factions are already at war.
            --- @param declaring_faction_name string The faction named by the war declaration.
            local function engage(declaring_faction_name)
                if engaged then return end
                engaged = true
                --- Force-declare war on any reinforcement allies of the player.
                self:declare_war_on_ally_reinforcement_if_available()

                --- Spawn any heroes and embed them into the invasion army.
                local skill_overrides = self.event_army:get_skill_overrides()
                local heroes = self.event_army:get_heroes()
                local invasion_general = invasion_force:get_general()
                for _, hero_object in ipairs(heroes) do
                    out("DEBUG - spawning invasion hero " .. hero_object.agent_subtype .. ".")
                    --- A valid spawn location is required or the agent creation call fails. Search beside the invasion army so it works on every campaign map.
                    local agent_x, agent_y = cm:find_valid_spawn_location_for_character_from_position(self.event_army.faction, invasion_general:logical_position_x(), invasion_general:logical_position_y(), false, 5)
                    out("DEBUG - agent_x: " .. agent_x .. " agent_y: " .. agent_y)
                    out("DEBUG - faction: " .. self.event_army.faction)
                    out("DEBUG - hero_object.agent_subtype: " .. hero_object.agent_subtype)
                    out("DEBUG - hero_object.agent_type: " .. hero_object.agent_type)
                    local new_invasion_hero_agent = cm:create_agent(self.event_army.faction, hero_object.agent_type, hero_object.agent_subtype, agent_x, agent_y)

                    out("DEBUG - new_invasion_hero_agent spawned with cqi: " .. new_invasion_hero_agent:command_queue_index())
                    for temp_hero_agent_subtype, skill_override in pairs(skill_overrides) do
                        if hero_object.agent_subtype == temp_hero_agent_subtype then
                            out("DEBUG - adding skills to invasion force hero " .. temp_hero_agent_subtype .. " of cqi " .. new_invasion_hero_agent:command_queue_index())
                            for _, skill in ipairs(skill_override) do
                                cm:add_skill(cm:char_lookup_str(new_invasion_hero_agent), skill, true, true)
                            end
                        end
                    end

                    cm:embed_agent_in_force(new_invasion_hero_agent, invasion_general:military_force())
                end

                --- Apply skill overrides to the invasion force lord.
                out("DEBUG - invasion force lord cqi: " .. invasion_general:command_queue_index())
                for lord_agent_subtype, skill_override in pairs(skill_overrides) do
                    if self.event_army.lord.subtype == lord_agent_subtype then
                        out("DEBUG - adding skills to invasion force lord of cqi " .. invasion_general:command_queue_index())
                        for _, skill in ipairs(skill_override) do
                            cm:add_skill(cm:char_lookup_str(invasion_general), skill, true, true)
                        end
                        break
                    end
                end

                self:weaken_invasion_force(invasion_general:military_force())

                local faction_being_declared_war_to = declaring_faction_name
                if faction_being_declared_war_to == self.event_army.faction then
                    --- The flag stays set until BattleCompleted, so a restarted battle keeps it.
                    if self.event_army:has_ally_reinforcements() then
                        self.core:svr_save_string(ALLY_ARRIVES_NOW_SVR_KEY, self.event_army.reinforcing_ally_armies[1].faction)
                    end
                    if self.event_army.intervention_type == AMBUSH_TYPE then
                        out("DEBUG - AMBUSH_TYPE called.")
                        cm:force_attack_of_opportunity(invasion_force:get_general():military_force():command_queue_index(), player_force_cqi, true)
                    elseif self.event_army.intervention_type == INTERCEPTION_TYPE then
                        out("DEBUG - INTERCEPTION_TYPE called.")

                        cm:force_attack_of_opportunity(invasion_force:get_general():military_force():command_queue_index(), player_force_cqi, false)
                    else -- ALLIED_REINFORCEMENTS_PERMITTED_TYPE
                        out("DEBUG - ALLIED_REINFORCEMENTS_PERMITTED_TYPE called.")
                        cm:force_attack_of_opportunity(player_force_cqi, invasion_force:get_general():military_force():command_queue_index(), false)
                    end
                end

                out("DEBUG - attack initiated")
            end
            self.core:add_listener(
                "land_enc_and_poi_encounter_engage_invader",
                "FactionLeaderDeclaresWar",
                true,
                function(local_context) engage(local_context:character():faction():name()) end,
                IS_NOT_PERSISTENT_LISTENER
            )

            --- Apply lord trait + ancillaries on a short delay so the general object exists.
            cm:callback(
                function()
                    self:try_add_trait_to_invading_lord(invasion_force:get_general())
                    self:try_add_ancillaries_to_invading_lord(invasion_force:get_general())
                end,
            0.1)

            --- Force-declare war between the encounter faction and the player on a slightly longer delay.
            cm:callback(
                function()
                    --- No war declaration fires between factions already at war, such as a tower's second floor, so the battle starts directly.
                    if cm:get_faction(player_faction_name):at_war_with(cm:get_faction(self.event_army.faction)) then
                        self.core:remove_listener("land_enc_and_poi_encounter_engage_invader")
                        engage(self.event_army.faction)
                        return
                    end
                    local call_player_allies_to_war = false
                    local call_faction_allies_to_war = false
                    cm:force_declare_war(self.event_army.faction, player_faction_name, call_player_allies_to_war, call_faction_allies_to_war)
                end,
            0.5)
        end,
        false,
        false,
        false
    )
end

--- Puts the event army's sabotage on its spawned force: each of `enemy_bundles`, and every unit but the characters at `enemy_strength` of full
--- strength. Armies without them are left alone.
--- @param force military_force The spawned invasion force.
function InvasionBattleManager:weaken_invasion_force(force)
    local army = self.event_army
    for _, bundle in ipairs(army.enemy_bundles or {}) do
        cm:apply_effect_bundle_to_force(bundle, force:command_queue_index(), 0)
    end
    if not army.enemy_strength then return end
    local units = force:unit_list()
    for i = 0, units:num_items() - 1 do
        local unit = units:item_at(i)
        if unit:unit_class() ~= "com" then cm:set_unit_hp_to_unary_of_maximum(unit, army.enemy_strength) end
    end
end

--- Applies the encounter lord's trait (if any) to the invasion general.
--- @param invasion_general character The newly spawned invasion general.
function InvasionBattleManager:try_add_trait_to_invading_lord(invasion_general)
    local lord_lookup = cm:char_lookup_str(invasion_general)
    local lord_trait = self.event_army.lord.trait
    if lord_trait ~= nil then
        cm:force_add_trait(lord_lookup, lord_trait, false , 1)
    end
end

--- Applies all of the encounter lord's ancillaries to the invasion general.
--- @param invasion_general character The newly spawned invasion general.
function InvasionBattleManager:try_add_ancillaries_to_invading_lord(invasion_general)
    for i = 1, #self.event_army.lord.ancillaries do
        cm:force_add_ancillary(invasion_general, self.event_army.lord.ancillaries[i], true, true)
    end
end

--- Force-declares war from the encounter faction onto the first allied reinforcement (player allies max out at 1 for now).
function InvasionBattleManager:declare_war_on_ally_reinforcement_if_available()
    if self.event_army:has_ally_reinforcements() then
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        cm:force_declare_war(self.event_army.faction, self.event_army.reinforcing_ally_armies[1].faction, call_player_allies_to_war, call_faction_allies_to_war)
    end
end


--- Builds a new invasion for the given army, sets its target, creates the general, and applies
--- experience + the upkeep-free effect. See invasion_manager docs at
--- https://chadvandy.github.io/tw_modding_resources/WH3/campaign/invasion_manager.html.
--- @param army Army The Army instance whose data populates the invasion.
--- @param objective_character character The character the new invasion targets for movement.
--- @param force table The random-army-manager force descriptor (output of generate_force).
--- @param force_lat_lng table A {x, y} table where the invasion spawns.
--- @returns table The new invasion handle returned by invasion_manager:new_invasion.
function InvasionBattleManager:setup_invasion(army, objective_character, force, force_lat_lng)
    if self.invasion_manager:get_invasion(army.invasion_identifier) then
        self.invasion_manager:remove_invasion(army.invasion_identifier)
    end

    local new_invasion = self.invasion_manager:new_invasion(army.invasion_identifier, army.faction, force, force_lat_lng)

    new_invasion:apply_effect("wh_main_bundle_military_upkeep_free_force", -1)

    new_invasion:set_target("CHARACTER", objective_character:command_queue_index(), objective_character:faction():name())

    --- Agent subtypes come from the agent_subtypes_tables.
    out("DEBUG - creating general for invasion with the following data: " .. army.lord.subtype .. " " .. army.lord.forename .. " " .. army.lord.clan_name .. " " .. army.lord.family_name .. " " .. army.lord.other_name)
    new_invasion:create_general(false, army.lord.subtype, army.lord.forename, army.lord.clan_name, army.lord.family_name, army.lord.other_name)

    local by_level = true
    new_invasion:add_character_experience(army.lord.level, by_level)
    new_invasion:add_unit_experience(army.unit_experience_amount)

    return new_invasion
end

--- Queues a one-off FactionTurnStart listener that removes the invasion's forces next turn.
--- @param army Army The Army whose invasion forces should be removed at next turn start.
function InvasionBattleManager:mark_battle_forces_for_removal(army)
    self.core:add_listener(
        "land_enc_and_poi_encounter_removal",
        "FactionTurnStart",
        true,
        function(context)
            self:remove_invasion_forces(army)
        end,
        IS_NOT_PERSISTENT_LISTENER
	)
end


--- Stashes `army` as the manager's current event_army so a later reset_state_post_battle can clean it up.
--- @param army Army The Army to remember for cleanup.
function InvasionBattleManager:set_auxiliary_army_for_reset(army)
    self.event_army = army
end


--- Registers a one-off BattleCompleted listener that cleans up the invasion forces and routes the result to the delegate.
--- @param delegate table The delegate (BattleSpotEventDelegate or SmithyEventDelegate) that receives the battle outcome.
--- @param spot_type string "BattleSpot", "SmithySpot" or "TowerSpot" - controls how the result is forwarded.
--- @param spot_info table A spot_info record for the spot that triggered the battle.
--- @param army Army The encounter Army whose invasion forces will be cleaned up.
function InvasionBattleManager:reset_state_post_battle(delegate, spot_type, spot_info, army)
	self.core:add_listener(
        "land_enc_and_poi_encounter_post_battle",
        "BattleCompleted",
        true,
        function(context)
            self.core:svr_save_string(ALLY_ARRIVES_NOW_SVR_KEY, "")
            local found_encounter_faction = false
            local player_won_battle = false
            local battle_faction_name = nil

            local encounter_invasion = self.invasion_manager:get_invasion(army.invasion_identifier)
            --- Defensive-type battles cannot be tracked easily, so we only branch on player attacker/defender.
            --- Check every human faction rather than the local one, so all multiplayer clients agree on the result.
            for _, player_faction_name in ipairs(cm:get_human_factions()) do
                found_encounter_faction, player_won_battle = pending_battle_result_for_faction(player_faction_name)
                if found_encounter_faction then
                    battle_faction_name = player_faction_name
                    break
                end
            end
            if found_encounter_faction and encounter_invasion then
                self:remove_invasion_forces(army)
            end

            if found_encounter_faction == true then
                if spot_type == "BattleSpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle, spot_info)
                elseif spot_type == "SmithySpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle)
                elseif spot_type == "TowerSpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle, battle_faction_name)
                end
            end
        end,
        IS_NOT_PERSISTENT_LISTENER
	)
end


--- Kills the main encounter invasion force plus any enemy + ally reinforcement forces.
--- @param army Army The encounter Army to clean up.
function InvasionBattleManager:remove_invasion_forces(army)
    self:remove_invasion_force_by_identifier(army.invasion_identifier)
    if army:has_offensive_reinforcements() then
        for i=1, #army.reinforcing_enemy_armies do
            self:remove_invasion_force_by_identifier(army.reinforcing_enemy_armies[i].invasion_identifier)
        end
    end

    if army:has_ally_reinforcements() then
        for i=1, #army.reinforcing_ally_armies do
            self:remove_invasion_force_by_identifier(army.reinforcing_ally_armies[i].invasion_identifier)
        end
    end
end


--- Kills a single invasion force by id, temporarily suppressing the related event-feed entries.
--- @param invasion_identifier string The invasion identifier registered with invasion_manager.
function InvasionBattleManager:remove_invasion_force_by_identifier(invasion_identifier)
    local force = self.invasion_manager:get_invasion(invasion_identifier)
    if force then
        with_death_feed_muted(function() force:kill() end)
    end
end

--- Declares an Army's units to the random army manager and returns them as the comma-separated list `cm:create_force` takes.
--- @param army Army An Army built by one of the Army constructors.
--- @returns string The unit list.
function InvasionBattleManager:build_unit_list(army)
    army:randomize_army_composition_and_declare(self.random_army_manager)
    return self.random_army_manager:generate_force(army.force_identifier)
end


--- Finds a valid spawn location near `center_coordinates`. Walks outward in 2-meter steps up to 4 iterations,
--- alternating between same-region and other-region checks. Returns (-1, -1) on failure - the battle will not trigger.
--- @param faction_name string The faction key that needs a spawn location.
--- @param center_coordinates table A {x, y} table around which to search.
--- @returns number, number The found x, y coordinates. Returns (-1, -1) when no valid spot exists.
function InvasionBattleManager:find_location_for_character_to_spawn(faction_name, center_coordinates)
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false)
    for i = 0, 4 do
        --- Same-region check.
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], true, i*2)
        else
            break
        end

        --- Other-region check.
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false, i*2)
        else
            break
        end
    end

    return x, y
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Constructs a new InvasionBattleManager wired to the given engine managers.
--- @param core table The CA core listener-manager handle.
--- @param random_army_manager table The CA random_army_manager handle.
--- @param invasion_manager table The CA invasion_manager handle.
--- @returns InvasionBattleManager A new instance with the supplied managers wired in.
function InvasionBattleManager:newFrom(core, random_army_manager, invasion_manager)
    local t = {
        core = core,
        random_army_manager = random_army_manager,
        invasion_manager = invasion_manager
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- SpotEventManager
--- (from controllers/spot_event_manager.lua)

local SpotEventManager = {
    treasure_event_delegate = {},
    battle_event_delegate = {},
    current_spot_info = {}
}

--- Stores the live spot info so subsequent dilemma-choice callbacks know which spot to use.
--- @param spot_info table A spot_info record for the spot currently being triggered.
function SpotEventManager:set_current_spot_info(spot_info)
    self.current_spot_info = spot_info
end


--- Rolls battle vs treasure for the current spot using the MCT battle chance and dispatches to the matching delegate.
--- Returns true when the spot should be removed from the map.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @returns boolean True when the spot should be deactivated after dispatch.
function SpotEventManager:trigger_spot_event(area_and_character_info)
    if not random_chance(get_mct_settings().battle_chance) then
        self.treasure_event_delegate:trigger_event(area_and_character_info)
        return true
    else
        return self.battle_event_delegate:trigger_pre_battle_dilemma(area_and_character_info, self.current_spot_info)
    end
end


--- Forwards a dilemma-choice event to the battle delegate with the stored spot info.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function SpotEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    self.battle_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.current_spot_info)
end


--- Exports the battle delegate's in-flight event for save/load.
--- @returns table A flat record describing the active battle event, suitable for the save state.
function SpotEventManager:export_state_as_a_table()
    return self.battle_event_delegate:export_state_as_a_table(self.current_spot_info)
end

--- Restores an in-flight battle delegate event from previously saved state.
--- @param previou_state table Previously exported battle delegate state.
function SpotEventManager:reinstate_event_if_able(previou_state)
    self.battle_event_delegate:reinstate_event_if_able(previou_state)
end

--- Lazy-loads the battle + treasure delegate modules (avoiding the circular require) and builds the manager.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns SpotEventManager A new manager with battle + treasure delegates wired in.
function SpotEventManager:new(invasion_battle_manager)
    TreasureEventDelegate = TreasureEventDelegate or require("script/land_encounters/features/treasure_spot")
    BattleEventDelegate = BattleEventDelegate or require("script/land_encounters/features/battle_spot")
    local t = {
        treasure_event_delegate = TreasureEventDelegate:new(),
        battle_event_delegate = BattleEventDelegate:new(invasion_battle_manager)
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- PointOfInterestEventManager
--- (from controllers/point_of_interest_event_manager.lua)

local PointOfInterestEventManager = {
    smithy_event_delegate = {},
    --- Places, saves and ticks the towers.
    tower_event_delegate = {},
    --- Tower records from the save, held until the zones exist and `initialize_towers` runs.
    saved_towers = nil,
}


--- Asks each POI delegate to bootstrap its per-zone state from the configured coordinates.
--- State is built even when smithies are disabled, so turning them back on later finds every smithy ready.
--- @param points_of_interest_by_zone table Region-keyed table of POI coordinate data.
function PointOfInterestEventManager:generate_points_of_interests_states(points_of_interest_by_zone)
    for zone_name, coordinates in pairs(points_of_interest_by_zone) do
        self.smithy_event_delegate:generate_states(zone_name, coordinates["smithies"])
    end
end


--- Places or restores the towers. Runs at first tick once the land manager has built its zones.
--- @param zones table The land manager's zones.
function PointOfInterestEventManager:initialize_towers(zones)
    self.tower_event_delegate:initialize(zones, self.saved_towers)
    self.saved_towers = nil
end


--- Shows or removes the smithy markers to match the Remove Smithies setting. Runs at first tick once the smithy states exist.
function PointOfInterestEventManager:sync_smithy_markers()
    self.smithy_event_delegate:sync_markers()
end


--- Forwards per-turn state updates to each POI delegate. Hidden smithies must not keep paying tributes or issuing missions.
function PointOfInterestEventManager:update_state_given_turn_passing()
    self.tower_event_delegate:update_state_given_turn_passing()
    if get_mct_settings().disable_smithies then return end
    self.smithy_event_delegate:update_state_given_turn_passing()
end

--- Runs the per-faction part of a human turn start: closing a delve left from last turn, and smithy sieges unless smithies are disabled.
--- @param faction_name string The human faction whose turn is starting.
function PointOfInterestEventManager:on_faction_turn_start(faction_name)
    self.tower_event_delegate:on_faction_turn_start(faction_name)
    if get_mct_settings().disable_smithies then return end
    self.smithy_event_delegate:on_faction_turn_start(faction_name)
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Event management

--- Dispatches a POI event to the matching delegate.
--- @param poi_type string The POI type tag ("SmithySpot" or "TowerSpot").
--- @param area_and_character_info table The AreaEntered context.
--- @param spot_info table The spot_info record for the triggered POI.
function PointOfInterestEventManager:trigger_poi_event(poi_type, area_and_character_info, spot_info)
    if poi_type == "SmithySpot" then
        --- A removed smithy's marker is taken off the map on load. This guards the turn it is still shown.
        if get_mct_settings().disable_smithies then return end
        self.smithy_event_delegate:trigger_event(area_and_character_info, spot_info)
    elseif poi_type == "TowerSpot" then
        self.tower_event_delegate:trigger_event(area_and_character_info, spot_info)
    end
end

--- Forwards a tower dilemma choice to the tower delegate.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function PointOfInterestEventManager:trigger_tower_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    self.tower_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
end

--- Greys out the taken tower offers on the local player's open go-deeper dilemma.
--- @param faction_name string The local player's faction.
function PointOfInterestEventManager:grey_out_taken_tower_offers(faction_name)
    self.tower_event_delegate:grey_out_taken_offers(faction_name)
end

--- Forwards a dilemma-choice event to the smithy POI delegate, which finds the smithy by the choosing faction.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param spot_info table The spot_info record for the triggered POI.
function PointOfInterestEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    self.smithy_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
end


--- Exports the smithy delegate's per-zone POI state for save/load.
--- @returns table A table keyed by POI type whose values are delegate-specific save records.
function PointOfInterestEventManager:export_state_as_table()
    local points_of_interests_data = {}
    points_of_interests_data["smithies"] = self.smithy_event_delegate:export_state_as_table()
    points_of_interests_data["towers"] = self.tower_event_delegate:export_state_as_table()
    return points_of_interests_data
end


--- Restores the smithy delegate's per-zone POI state from previously saved data, and keeps the saved towers for `initialize_towers`.
--- @param previous_state table The keyed save record previously produced by export_state_as_table.
function PointOfInterestEventManager:reinstate_event_if_able(previous_state)
    self.smithy_event_delegate:reinstate_event_if_able(previous_state["smithies"])
    self.saved_towers = previous_state["towers"]
end


--- Lazy-loads the smithy and tower delegate modules (avoiding the circular require) and builds the manager.
--- @param mission_manager table The CA mission_manager handle.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns PointOfInterestEventManager A new manager with the smithy and tower delegates wired in.
function PointOfInterestEventManager:new(mission_manager, invasion_battle_manager)
    SmithyEventDelegate = SmithyEventDelegate or require("script/land_encounters/features/smithy")
    TowerEventDelegate = TowerEventDelegate or require("script/land_encounters/features/tower")
    local t = {
        smithy_event_delegate = SmithyEventDelegate:new(mission_manager, invasion_battle_manager),
        tower_event_delegate = TowerEventDelegate:new(invasion_battle_manager),
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return {
    IncidentManager = IncidentManager,
    InvasionBattleManager = InvasionBattleManager,
    SpotEventManager = SpotEventManager,
    PointOfInterestEventManager = PointOfInterestEventManager,
}
