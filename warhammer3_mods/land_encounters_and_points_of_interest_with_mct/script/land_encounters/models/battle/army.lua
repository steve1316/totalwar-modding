-- TODO: Pass a is_player flag in the constructor to double check units and pass alternatives in case they are needed.
-- Make logic to check dlc ownership given subculture. Should a Unit or Lord type be DLC only, replace those units with its more close main variant or pass it in its constructor.
require("script/land_encounters/utils/logger")

-- Mod libs
local ArmyUnit = require("script/land_encounters/models/battle/army_unit")
local LordUnit = require("script/land_encounters/models/battle/lord_unit")

-- smithy defenders
local smithy_defenders = require("script/land_encounters/constants/battles/smithy/defenders")

-- battle spots battle types
local bandits = require("script/land_encounters/constants/battles/bandits")
local battlefields = require("script/land_encounters/constants/battles/battlefields")
local daemonic_gifts = require("script/land_encounters/constants/battles/daemonic_gifts")
local incursions = require("script/land_encounters/constants/battles/incursions")
local relic_defenses = require("script/land_encounters/constants/battles/relic_defenses")
local rebellions = require("script/land_encounters/constants/battles/nascent_rebellions")
local skirmishes = require("script/land_encounters/constants/battles/skirmishes")
local surprise_attacks = require("script/land_encounters/constants/battles/surprise_attacks")
local waystones = require("script/land_encounters/constants/battles/waystones")

require("script/land_encounters/algorithms/random_encounter_force_generation_system")

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
    -- out("DEBUG - new_from_event player_force_cqi: " .. player_force_cqi)
    -- local gold_value = cm:force_gold_value(player_force_cqi)
    -- out("DEBUG - gold value of player force: " .. gold_value)
    -- Determine the force
    local force_data = {}

    if get_mct_settings().enable_randomized_encounter_force_generation then
        out("DEBUG - enabling randomized encounter force generation.")

        -- Get the difficulty either based on the difficulty dropdown or the basic progressive difficulty using turn numbers.
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
        -- local faction = "ogr"
        out("DEBUG - Starting force makeup generation for faction: " .. faction .. " and difficulty: " .. difficulty)
        force_data = start_force_makeup_generation(difficulty, faction)
        force_data = convert_force_makeup_to_usable_format(difficulty, force_data, faction, "encounter_force", "encounter_invasion", 2)
        out("DEBUG - force experience amount: " .. force_data.unit_experience_amount)
        out("DEBUG - force_data:")
        print_table(force_data)
        out("DEBUG - force_data done.")
    else
        if string.find(battle_event, "bandit") then
            force_data = bandits[battle_event]
        elseif string.find(battle_event, "battlefield") then
            force_data = battlefields[battle_event]
        elseif string.find(battle_event, "daemonic_gift") then
            force_data = daemonic_gifts[battle_event]
        elseif string.find(battle_event, "incursion") then
            force_data = incursions[battle_event]
        elseif string.find(battle_event, "stands") then
            force_data = relic_defenses[battle_event]
        elseif string.find(battle_event, "underground") then
            force_data = rebellions[battle_event]
        elseif string.find(battle_event, "skirmish") then
            force_data = skirmishes[battle_event]
        elseif string.find(battle_event, "surprise") then
            force_data = surprise_attacks[battle_event]
        elseif string.find(battle_event, "waystone") then
            force_data = waystones[battle_event]
        end
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
    
    setmetatable(t, self)
    self.__index = self

    self.heroes = force.heroes or {}
    self.skill_overrides = force.skill_overrides or {}

    return t
end


-- If the subculture is not found in the registered defenders table we just return an empty table
function Army:new_from_faction_and_subculture_and_level(faction_name, subculture, level)
    local force_data = smithy_defenders[subculture]

    if force_data == nil or next(force_data) == nil then
        return {}
    end

    local forces_of_level = force_data.armies_by_level[level]
    
    -- Create the defender army
    local t = {
        faction = faction_name,
        force_identifier = force_data.identifier,
        invasion_identifier = force_data.invasion_identifier,
        intervention_type = force_data.intervention_type,
        units_pool = {},
        units = {},
        unit_experience_amount = forces_of_level.unit_experience_amount,
        lord_pool = {},
        lord = {},
        reinforcing_ally_armies = {},
        reinforcing_enemy_armies = {},
    }
    t.lord_pool = LordUnit:newFrom(force_data.lord)
    
    for i=1, #forces_of_level.units do
        local unit = ArmyUnit:newFrom(forces_of_level.units[i])
        table.insert(t.units_pool, unit)
    end
    
    setmetatable(t, self)
    self.__index = self

    return t
end


return Army