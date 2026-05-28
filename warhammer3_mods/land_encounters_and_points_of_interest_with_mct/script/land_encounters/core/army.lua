-- TODO: Pass a is_player flag in the constructor to double check units and pass alternatives in case they are needed.
-- Make logic to check dlc ownership given subculture. Should a Unit or Lord type be DLC only, replace those units with its more close main variant or pass it in its constructor.
require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

require("script/land_encounters/core/managers")

-- factions_data drives the randomization pipeline. Used here only to validate that a smithy's
-- subculture-derived shorthand has a faction-data entry before we call into the randomizer.
local factions_data = require("script/land_encounters/configs/factions_data")

-- Cultural alliance pools for the Allied Reinforcement intervention.
local alliances = require("script/land_encounters/configs/alliances")

-- Picks a random intervention type from the user's MCT-enabled set. The MCT anchor enforces
-- at-least-one via set_locked, so the enabled list is never empty in normal operation. The
-- defensive fallback to INTERCEPTION_TYPE handles any save-load race or MCT bypass.
local function pick_intervention_type()
    local settings = get_mct_settings()
    local enabled = settings and settings.enabled_intervention_types
    if not enabled or #enabled == 0 then
        return INTERCEPTION_TYPE
    end
    return enabled[random_number(#enabled)]
end

-- Returns the player faction's subculture key, or nil if no human faction can be resolved.
local function get_player_subculture()
    local human_factions = cm:get_human_factions()
    if not human_factions or #human_factions == 0 then return nil end
    local player_faction = cm:get_faction(human_factions[1])
    if not player_faction then return nil end
    return player_faction:subculture()
end

-- Picks a random ally faction key based on the player's subculture. Returns nil if no ally can be sourced.
local function pick_ally_faction()
    local player_subculture = get_player_subculture()
    if player_subculture == nil then return nil end
    return alliances.pick_for_subculture(player_subculture)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- ArmyUnit
-- (from models/battle/army_unit.lua)

-------------------------
--- Properties definition
-------------------------
local ArmyUnit = {
    id = "none",
    quantity = 0,
    chance = 0,
    alternative_chance = 0,
    alternative_id = nil
}


-------------------------
--- Class Methods
-------------------------
function ArmyUnit:generate_winner_unit()
    if self.chance >= random_number(100) then
        return { id = self.id, count = self.quantity }
    elseif self.alternative_chance >= random_number(100) then
        return { id = self.alternative_id, count = self.quantity }
    end
    return nil
end

-------------------------
--- Constructors
-------------------------
function ArmyUnit:newFrom(unit_data)
    local t = {
        id= unit_data[1],
        quantity= unit_data[2],
        chance= unit_data[3],
        alternative_chance= unit_data[4],
        alternative_id= unit_data[5]
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- LordUnit
-- (from models/battle/lord_unit.lua)

-------------------------
--- Properties definition
-------------------------
local LordUnit = {
    level_ranges = {},
    possible_subtypes = {},
    possible_forenames = {},
    possible_clan_names = {},
    possible_family_names = {},
    possible_other_names = {},
    possible_skills = {},
    possible_ancillaries = {},
    possible_traits = {}
}


-------------------------
--- Class Methods
-------------------------
function LordUnit:generate_random_level()
    out("DEBUG - random_number(): " .. self.level_ranges[2] .. " - " .. self.level_ranges[1])
    return random_number(self.level_ranges[2], self.level_ranges[1])
end


function LordUnit:generate_subtype()
    if #self.possible_subtypes > 0 then
        local random_subtype = self.possible_subtypes[random_number(#self.possible_subtypes)]
        return random_subtype
    end
    return ""
end


function LordUnit:generate_random_forename()
    if #self.possible_forenames > 0 then
        return self.possible_forenames[random_number(#self.possible_forenames)]
    end
    return ""
end


function LordUnit:generate_random_clan_name()
    if #self.possible_clan_names > 0 then
        return self.possible_clan_names[random_number(#self.possible_clan_names)]
    end
    return ""
end


function LordUnit:generate_random_family_name()
    if #self.possible_family_names > 0 then
        return self.possible_family_names[random_number(#self.possible_family_names)]
    end
    return ""
end


function LordUnit:generate_random_other_name()
    if #self.possible_other_names > 0 then
        return self.possible_other_names[random_number(#self.possible_other_names)]
    end
    return ""
end

function LordUnit:generate_ancillaries(selected_lord_subtype)
    if next(self.possible_ancillaries) ~= nil and next(self.possible_ancillaries[selected_lord_subtype]) ~= nil then
        local active_ancillaries = {}
        for i = 1, #self.possible_ancillaries[selected_lord_subtype] do
            if self.possible_ancillaries[selected_lord_subtype][i][2] >= random_number(100) then
                table.insert(active_ancillaries, self.possible_ancillaries[selected_lord_subtype][i][1])
            end
        end
        return active_ancillaries
    else
        return {}
    end
end

function LordUnit:generate_trait(selected_lord_subtype)
    if next(self.possible_traits) ~= nil then
        return self.possible_traits[selected_lord_subtype]
    end
    return nil
end

-------------------------
--- Constructors
-------------------------
function LordUnit:newFrom(lord_data)
    local t = {
        subtype= nil,
        level_ranges= lord_data.level_ranges,
        possible_subtypes = lord_data.possible_subtypes,
        possible_forenames= lord_data.possible_forenames,
        possible_clan_names= lord_data.possible_clan_names,
        possible_family_names= lord_data.possible_family_names,
        possible_other_names= lord_data.possible_other_names,
        possible_skills = lord_data.skills,
        possible_ancillaries = lord_data.ancillaries,
        possible_traits = lord_data.traits
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Army
-- (from models/battle/army.lua)

-------------------------
--- Properties definition
-------------------------
local Army = {
    faction = "",
    force_identifier = "",
    invasion_identifier = "",
    -- units of the army base and generators
    units_pool = {},
    units = {},
    unit_experience_amount = 0,
    -- lords of the army generator
    lord_pool = {},
    lord = {},
    -- Reinforcements
    reinforcing_ally_armies = {},
    reinforcing_enemy_armies = {},
    ---
    heroes = {},
    skill_overrides = {},
}

-------------------------
--- Class Methods
-------------------------
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


function Army:randomize_army_composition_and_declare(random_army_manager)
    random_army_manager:remove_force(self.force_identifier)
    random_army_manager:new_force(self.force_identifier)

    local randomized_units = {}
    for i=1, #self.units_pool do
        local randomized_unit = self.units_pool[i]:generate_winner_unit()
        if randomized_unit ~= nil then
            self:declare_army_unit(random_army_manager, randomized_unit.id, randomized_unit.count)
        end
        table.insert(randomized_units, randomized_unit)
    end
    self.units = randomized_units
end


function Army:randomize_lord()
    self.lord.subtype = self.lord_pool:generate_subtype()
    self.lord.level = self.lord_pool:generate_random_level()
    out("DEBUG - Lord level: " .. self.lord.level)
    self.lord.forename = self.lord_pool:generate_random_forename()
    self.lord.clan_name = self.lord_pool:generate_random_clan_name()
    self.lord.family_name = self.lord_pool:generate_random_family_name()
    self.lord.other_name = self.lord_pool:generate_random_other_name()
    self.lord.ancillaries = self.lord_pool:generate_ancillaries(self.lord.subtype)
    self.lord.trait = self.lord_pool:generate_trait(self.lord.subtype)
end


function Army:declare_army_unit(random_army_manager, unit_id, unit_count)
    random_army_manager:add_mandatory_unit(self.force_identifier, unit_id, unit_count)
end


function Army:has_ally_reinforcements()
    return next(self.reinforcing_ally_armies) ~= nil
end


function Army:has_offensive_reinforcements()
    return next(self.reinforcing_enemy_armies) ~= nil
end


function Army:size()
    return #self.units
end


---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------

function Army:get_heroes()
    return self.heroes
end

function Army:get_skill_overrides()
    return self.skill_overrides
end

function Army:get_hero_agent_subtypes()
    local hero_agent_subtypes = {}
    for _, hero in ipairs(self.heroes) do
        table.insert(hero_agent_subtypes, hero.agent_subtype)
    end
    return hero_agent_subtypes
end


-------------------------
--- Constructors
-------------------------
function Army:new_from_event(battle_event)
    out("DEBUG - new_from_event battle_event: " .. battle_event)

    -- Difficulty comes from the MCT dropdown unless progressive scaling is enabled, in which
    -- case it ramps up with the current turn number.
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

    -- Pick the intervention type once so we can branch on it below for ally setup.
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

    -- if reinforcement armies are present we declare them here
    -- we declare allied armies
    local reinforcing_ally_armies = {}
    if force_data.reinforcing_ally_armies ~= false then
        for i=1, #force_data.reinforcing_ally_armies do
            table.insert(reinforcing_ally_armies, Army:create_from(force_data.reinforcing_ally_armies[i]))
        end
    end

    -- we declare enemy armies
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


-- Create the invasion army
function Army:create_from(force)
    local t = {
        faction = force.faction,
        force_identifier = force.identifier,
        invasion_identifier = force.invasion_identifier,
        intervention_type = force.intervention_type,
        units_pool = {},
        units = {},
        unit_experience_amount = force.unit_experience_amount,
        lord_pool = {},
        lord = {},
        reinforcing_ally_armies = {},
        reinforcing_enemy_armies = {},
    }
    t.lord_pool = LordUnit:newFrom(force.lord)

    for i=1, #force.units do
        local unit = ArmyUnit:newFrom(force.units[i])
        table.insert(t.units_pool, unit)
    end

    t.heroes = force.heroes or {}
    t.skill_overrides = force.skill_overrides or {}

    setmetatable(t, self)
    self.__index = self

    return t
end


-- If the subculture is not found in the registered defenders table we just return an empty table
-- Maps the smithy upgrade level (1, 2, 3) to a randomization difficulty key.
local SMITHY_LEVEL_TO_DIFFICULTY = { [1] = "easy", [2] = "medium", [3] = "hard" }

-- Extracts the 3-letter faction shorthand from a subculture key (e.g. "wh_main_sc_emp_empire" -> "emp").
-- Returns nil if the subculture does not match the expected pattern.
local function shorthand_from_subculture(subculture)
    if subculture == nil then return nil end
    return subculture:match("sc_(%w+)_")
end

-- Builds a smithy defender Army by running the same randomization pipeline as random encounters.
-- The defender faction matches the smithy's controlling-faction subculture when possible, and
-- falls back to a random faction if the subculture has no shorthand mapping. The smithy upgrade
-- level drives difficulty. Intervention type is picked via the MCT-toggled picker, so smithy
-- battles participate in the same Ambush / Interception / Allied Reinforcements selection as
-- random encounters.
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
