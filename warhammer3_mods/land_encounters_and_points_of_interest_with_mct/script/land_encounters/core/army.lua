--- Army class. Represents a random-encounter or smithy-defender army built from the
--- randomization pipeline. Holds the unit pool, lord pool, and reinforcement armies, and
--- exposes the constructors new_from_event (for spot battles) and new_from_subculture_and_level
--- (for smithy defenders).

--- TODO: Pass an is_player flag in the constructor to double check units and pass alternatives in case they are needed.
--- Make logic to check dlc ownership given subculture. Should a Unit or Lord type be DLC only, replace those units with its
--- more close main variant or pass it in its constructor.
require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

require("script/land_encounters/core/managers")

--- factions_data drives the randomization pipeline. Used here only to validate that a smithy's
--- subculture-derived shorthand has a faction-data entry before we call into the randomizer.
local factions_data = require("script/land_encounters/configs/factions_data")

--- Cultural alliance pools for the Allied Reinforcement intervention.
local alliances = require("script/land_encounters/configs/alliances")

--- Picks a random intervention type from the user's MCT-enabled set. The MCT anchor enforces
--- at-least-one via set_locked, so the enabled list is never empty in normal operation. The
--- defensive fallback to INTERCEPTION_TYPE handles any save-load race or MCT bypass.
--- @returns number One of AMBUSH_TYPE, INTERCEPTION_TYPE, or ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
local function pick_intervention_type()
    local settings = get_mct_settings()
    local enabled = settings and settings.enabled_intervention_types
    if not enabled or #enabled == 0 then
        return INTERCEPTION_TYPE
    end
    return enabled[random_number(#enabled)]
end

--- Returns the player faction's subculture key, or nil if no human faction can be resolved.
--- @returns string The player's subculture key, or nil when no human faction is available.
local function get_player_subculture()
    local human_factions = cm:get_human_factions()
    if not human_factions or #human_factions == 0 then return nil end
    local player_faction = cm:get_faction(human_factions[1])
    if not player_faction then return nil end
    return player_faction:subculture()
end

--- Picks a random ally faction key based on the player's subculture. Returns nil if no ally can be sourced.
--- @returns string A 3-letter faction shorthand for the chosen ally, or nil when none is available.
local function pick_ally_faction()
    local player_subculture = get_player_subculture()
    if player_subculture == nil then return nil end
    return alliances.pick_for_subculture(player_subculture)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Army class (from models/battle/army.lua)

local Army = {
    faction = "",
    force_identifier = "",
    invasion_identifier = "",
    --- Unit pool / resolved units
    units_pool = {},
    units = {},
    unit_experience_amount = 0,
    --- Lord pool / resolved lord
    lord_pool = {},
    lord = {},
    --- Reinforcement armies
    reinforcing_ally_armies = {},
    reinforcing_enemy_armies = {},
    heroes = {},
    skill_overrides = {},
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Class methods

--- Randomizes the army's units, lord, and any offensive reinforcement armies in one shot.
--- @param random_army_manager table The CA random_army_manager global used to register forces.
function Army:randomize_units(random_army_manager)
    out("DEBUG - randomize_units coming from InvasionBattleManager")
    self:randomize_army_composition_and_declare(random_army_manager)
    self:randomize_lord()

    if self:has_offensive_reinforcements() then
        for i=1, #self.reinforcing_enemy_armies do
            self.reinforcing_enemy_armies[i]:randomize_army_composition_and_declare(random_army_manager)
            self.reinforcing_enemy_armies[i]:randomize_lord()
        end
    end
end


--- Declares every unit from the pool to the random army manager. With the randomization-only
--- pipeline every unit appears unconditionally, so units_pool is copied straight into units.
--- @param random_army_manager table The CA random_army_manager global used to register forces.
function Army:randomize_army_composition_and_declare(random_army_manager)
    random_army_manager:remove_force(self.force_identifier)
    random_army_manager:new_force(self.force_identifier)

    self.units = {}
    for i = 1, #self.units_pool do
        local unit_row = self.units_pool[i]
        self:declare_army_unit(random_army_manager, unit_row.id, unit_row.count)
        table.insert(self.units, unit_row)
    end
end


--- Picks a concrete lord subtype and level from the pool. Names, ancillaries, and traits are
--- not generated in the randomization-only pipeline - they keep their empty defaults that
--- create_from sets on the lord table.
function Army:randomize_lord()
    self.lord.subtype = self.lord_pool.agent_subtype
    self.lord.level = random_number(self.lord_pool.level_range[2], self.lord_pool.level_range[1])
    out("DEBUG - Lord level: " .. self.lord.level)
end


--- Adds the unit as a mandatory entry to this army's random-army-manager force.
--- @param random_army_manager table The CA random_army_manager global.
--- @param unit_id string The unit key to enlist (e.g. "wh_main_emp_inf_spearmen").
--- @param unit_count number The number of copies of this unit to add as mandatory.
function Army:declare_army_unit(random_army_manager, unit_id, unit_count)
    random_army_manager:add_mandatory_unit(self.force_identifier, unit_id, unit_count)
end


--- True when an allied reinforcement army is attached (only set when intervention is ALLIED_REINFORCEMENTS_PERMITTED_TYPE).
--- @returns boolean True when reinforcing_ally_armies has at least one entry.
function Army:has_ally_reinforcements()
    return next(self.reinforcing_ally_armies) ~= nil
end


--- True when at least one enemy reinforcement army is attached. Not currently produced by the randomization pipeline.
--- @returns boolean True when reinforcing_enemy_armies has at least one entry.
function Army:has_offensive_reinforcements()
    return next(self.reinforcing_enemy_armies) ~= nil
end


--- Number of resolved (post-randomize) units in this army.
--- @returns number Count of entries currently in the units array.
function Army:size()
    return #self.units
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Hero accessors

--- Returns the array of hero entries attached to this army (each entry has agent_subtype + optional traits).
--- @returns table The heroes array stored on this Army.
function Army:get_heroes()
    return self.heroes
end

--- Returns the skill-override table for the lord (skill key -> level).
--- @returns table A map of skill keys to override levels.
function Army:get_skill_overrides()
    return self.skill_overrides
end

--- Returns a flat list of every hero's agent_subtype.
--- @returns table An array of agent_subtype strings, one per hero entry.
function Army:get_hero_agent_subtypes()
    local hero_agent_subtypes = {}
    for _, hero in ipairs(self.heroes) do
        table.insert(hero_agent_subtypes, hero.agent_subtype)
    end
    return hero_agent_subtypes
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Builds an Army for a random-encounter battle spot. Picks difficulty, faction, intervention type,
--- optional allied reinforcements, and then materializes the encounter + any reinforcement armies.
--- @param battle_event string An identifier label for the spawning event (used for logging only).
--- @returns Army A new Army instance with units_pool, lord_pool, and reinforcement arrays populated.
function Army:new_from_event(battle_event)
    out("DEBUG - new_from_event battle_event: " .. battle_event)

    --- Difficulty comes from the MCT dropdown unless progressive scaling is enabled, in which
    --- case it ramps up with the current turn number.
    local difficulty = get_mct_settings().randomized_encounter_force_generation_difficulty
    if get_mct_settings().enable_basic_progressive_difficulty then
        if cm:turn_number() < get_mct_settings().turn_number_from_easy_to_medium then
            difficulty = "easy"
        elseif cm:turn_number() < get_mct_settings().turn_number_from_medium_to_hard then
            difficulty = "medium"
        else
            difficulty = "hard"
        end
    end

    local faction = get_random_faction()
    out("DEBUG - Starting force makeup generation for faction: " .. faction .. " and difficulty: " .. difficulty)
    local force_data = start_force_makeup_generation(difficulty, faction)

    --- Pick the intervention type once so we can branch on it below for ally setup.
    local intervention_type = pick_intervention_type()
    local ally_force_data = nil
    if intervention_type == ALLIED_REINFORCEMENTS_PERMITTED_TYPE then
        local ally_faction = pick_ally_faction()
        if ally_faction == nil then
            out("DEBUG - Allied intervention picked but no ally faction available; demoting to INTERCEPTION_TYPE.")
            intervention_type = INTERCEPTION_TYPE
        else
            out("DEBUG - Allied intervention picked; generating ally force from faction: " .. ally_faction)
            local ally_makeup = start_force_makeup_generation(difficulty, ally_faction)
            ally_force_data = convert_force_makeup_to_usable_format(difficulty, ally_makeup, ally_faction, "ally_force", "ally_invasion", INTERCEPTION_TYPE)
        end
    end

    force_data = convert_force_makeup_to_usable_format(difficulty, force_data, faction, "encounter_force", "encounter_invasion", intervention_type)
    if ally_force_data ~= nil then
        force_data.reinforcing_ally_armies = { ally_force_data }
    end

    --- Materialize any reinforcement armies (allied first, then enemy) as Army instances.
    local reinforcing_ally_armies = {}
    if force_data.reinforcing_ally_armies ~= false then
        for i=1, #force_data.reinforcing_ally_armies do
            table.insert(reinforcing_ally_armies, Army:create_from(force_data.reinforcing_ally_armies[i]))
        end
    end

    local reinforcing_enemy_armies = {}
    if force_data.reinforcing_enemy_armies ~= false then
        for i=1, #force_data.reinforcing_enemy_armies do
            table.insert(reinforcing_enemy_armies, Army:create_from(force_data.reinforcing_enemy_armies[i]))
        end
    end

    local army = Army:create_from(force_data)
    army.reinforcing_ally_armies = reinforcing_ally_armies
    army.reinforcing_enemy_armies = reinforcing_enemy_armies

    return army
end


--- Builds an Army instance from a flat force record produced by convert_force_makeup_to_usable_format.
--- The units pool and lord pool are stored by reference. randomize_units and randomize_lord later
--- resolve them into the concrete units and lord that the engine spawns.
--- @param force table A force record with faction, identifier, invasion_identifier, intervention_type, units, lord, heroes, and skill_overrides.
--- @returns Army A new Army instance with default-empty lord fields ready for randomize_lord.
function Army:create_from(force)
    local t = {
        faction = force.faction,
        force_identifier = force.identifier,
        invasion_identifier = force.invasion_identifier,
        intervention_type = force.intervention_type,
        units_pool = force.units,
        units = {},
        unit_experience_amount = force.unit_experience_amount,
        lord_pool = force.lord,
        --- Lord fields are populated later by randomize_lord (subtype + level). The name and
        --- equipment fields are kept at empty defaults so downstream consumers can read them
        --- unconditionally - the engine falls back to its own defaults when these are empty.
        lord = {
            subtype = nil,
            level = nil,
            forename = "",
            clan_name = "",
            family_name = "",
            other_name = "",
            ancillaries = {},
            trait = nil,
        },
        reinforcing_ally_armies = {},
        reinforcing_enemy_armies = {},
        heroes = force.heroes or {},
        skill_overrides = force.skill_overrides or {},
    }

    setmetatable(t, self)
    self.__index = self

    return t
end


--- Maps smithy upgrade level (1, 2, 3) to a randomization difficulty key.
local SMITHY_LEVEL_TO_DIFFICULTY = { [1] = "easy", [2] = "medium", [3] = "hard" }

--- Extracts the 3-letter faction shorthand from a subculture key (e.g. "wh_main_sc_emp_empire" -> "emp").
--- Returns nil if the subculture does not match the expected pattern.
--- @param subculture string The full subculture key, or nil.
--- @returns string The captured 3-letter shorthand, or nil when no match is found.
local function shorthand_from_subculture(subculture)
    if subculture == nil then return nil end
    return subculture:match("sc_(%w+)_")
end

--- Builds a smithy defender Army by running the same randomization pipeline as random encounters.
--- The defender faction matches the smithy's controlling-faction subculture when possible, and
--- falls back to a random faction if the subculture has no shorthand mapping. The smithy upgrade
--- level drives difficulty. Intervention type is picked via the MCT-toggled picker, so smithy
--- battles participate in the same Ambush / Interception / Allied Reinforcements selection as
--- random encounters.
--- @param subculture string The controlling faction's subculture key (may be nil).
--- @param level number Smithy upgrade level (1, 2, or 3). Drives difficulty selection.
--- @returns Army A new Army instance ready for randomize_units and randomize_lord.
function Army:new_from_subculture_and_level(subculture, level)
    local shorthand = shorthand_from_subculture(subculture)
    if shorthand == nil or factions_data[shorthand] == nil then
        out("DEBUG - smithy: subculture '" .. tostring(subculture) .. "' has no faction-shorthand mapping; using random faction.")
        shorthand = get_random_faction()
    end

    local difficulty = SMITHY_LEVEL_TO_DIFFICULTY[level] or "easy"
    out("DEBUG - smithy: generating defender for shorthand=" .. shorthand .. ", level=" .. tostring(level) .. ", difficulty=" .. difficulty)

    local force_data = start_force_makeup_generation(difficulty, shorthand)
    force_data = convert_force_makeup_to_usable_format(difficulty, force_data, shorthand, "smithy_defender_force", "smithy_defender_invasion", pick_intervention_type())

    return Army:create_from(force_data)
end


return Army
