require("script/land_encounters/utils/logger")
require("script/land_encounters/constants/utils/common")

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local IS_NOT_PERSISTENT_LISTENER = false

-------------------------
--- Properties definition
-------------------------
local InvasionBattleManager = {
    -- Core is the main manager for listeners.
    core = false,
    -- For managing invasions
    random_army_manager = false,
    invasion_manager = false,
    --  the current army fighting
    event_army = false 
}

-------------------------
--- Class Methods
-------------------------
-- Preconditions: is defending army
-- Enemy_character: is at war with the player faction or is the player faction at war with the defending faction. 
-- Army: Is a template of the army of the player faction or the controlling faction that is defending the defendable spot.
-- Defender_lat_lng: is the defender army spawning point
function InvasionBattleManager:generate_defense_battle(defender_army, enemy_character, spot_coordinates)
    local x, y = self:find_location_for_character_to_spawn(defender_army.faction, spot_coordinates)
    -- we try to correct the problem if we cannot find another place to spawn the enemy armies    
    local force_cqi = enemy_character:military_force():command_queue_index()
    
    self.event_army = defender_army
    self.event_army:randomize_units(self.random_army_manager)
    
    local defender_force = self.random_army_manager:generate_force(defender_army.force_identifier)
    local defence = self:setup_invasion(defender_army, enemy_character, defender_force, {x, y})
    defence:start_invasion(
        function(created_defender_force)
            cm:force_attack_of_opportunity(created_defender_force:get_general():military_force():command_queue_index(), force_cqi, false)
        end,
        false,
        false,
        false
    )
end


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


function InvasionBattleManager:generate_battle(offensive_army, player_character, spot_coordinates)
    self.event_army = offensive_army
    out("DEBUG - testing randomize_units")
    self.event_army:randomize_units(self.random_army_manager)
    out("DEBUG - event army randomized in generate_battle")
    
    local force_cqi = player_character:military_force():command_queue_index()
    local player_faction_name = player_character:faction():name()
    
    -- if event army has reinforcements
    if self.event_army:has_offensive_reinforcements() then
        self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, 1)
    else
        self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
    end
end


-- we generate the enemy reinforcements first and the main force is the one that triggers the battle
function InvasionBattleManager:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, army_number)
    local reinforcing_army = self.event_army.reinforcing_enemy_armies[army_number]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, player_character, invader_force, {x, y})
        
    invasion:start_invasion(
        function(invasion_force)
            -- we force war with this faction for the player
            local call_player_allies_to_war = false
            local call_faction_allies_to_war = false
            cm:force_declare_war(reinforcing_army.faction, player_faction_name, call_player_allies_to_war, call_faction_allies_to_war)
            -- all enemies have been declared
            if army_number == #self.event_army.reinforcing_enemy_armies then
                if self.event_army:has_ally_reinforcements() then
                    local enemy_character = cm:get_closest_character_to_position_from_faction(reinforcing_army.faction, spot_coordinates[1], spot_coordinates[2])
                    self:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
                else
                    -- Last: we declare the main attacker and begin the battle
                    self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)                    
                end
            else    
                local next_army_number = army_number + 1
                self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, next_army_number)
            end
            --
        end,
        false,
        false,
        false
    )
end


function InvasionBattleManager:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
    local reinforcing_army = self.event_army.reinforcing_ally_armies[1]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, enemy_character, invader_force, {x, y})
    invasion:start_invasion(
        function(invasion_force)
            -- we force war with the other reinformcement enemy armies
            self:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(reinforcing_army.faction)
            -- we invoke the main attacker
            self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
        end,
        false,
        false,
        false
    )
end


function InvasionBattleManager:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(allied_faction)
    if self.event_army:has_offensive_reinforcements() then 
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        for i=1, #self.event_army.reinforcing_enemy_armies do
            cm:force_declare_war(allied_faction, self.event_army.reinforcing_enemy_armies[i].faction, call_player_allies_to_war, call_faction_allies_to_war)
        end
    end
end


function InvasionBattleManager:main_attacker_attacks_player_and_allies(player_character, player_faction_name, player_force_cqi, spot_coordinates)
    local x, y = self:find_location_for_character_to_spawn(self.event_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(self.event_army.force_identifier)
    local invasion = self:setup_invasion(self.event_army, player_character, invader_force, {x, y})

    out("DEBUG - invasion setup complete. Now starting invasion")

    invasion:start_invasion(
        function(invasion_force)
            self.core:add_listener(
                "land_enc_and_poi_encounter_engage_invader",
                "FactionLeaderDeclaresWar",
                true,
                function(local_context)
                    -- force declare war on reinforcement allies of player
                    self:declare_war_on_ally_reinforcement_if_available()

                    ---------------------------------------------------------
                    ---------------------------------------------------------
                    ---------------------------------------------------------
                    -- We need to spawn in the heroes if available then embed them into the invasion army.
                    local skill_overrides = self.event_army:get_skill_overrides()
                    local heroes = self.event_army:get_heroes()
                    for _, hero_object in ipairs(heroes) do
                        out("DEBUG - spawning invasion hero " .. hero_object.agent_subtype .. ".")
                        -- Find a valid spawn location for the hero or else the spawn will fail.
                        local agent_x, agent_y = cm:find_valid_spawn_location_for_character_from_settlement(self.event_army.faction, "wh3_main_combi_region_ubersreik", false, true, 10)
                        out("DEBUG - agent_x: " .. agent_x .. " agent_y: " .. agent_y)
                        out("DEBUG - faction: " .. self.event_army.faction)
                        out("DEBUG - hero_object.agent_subtype: " .. hero_object.agent_subtype)
                        out("DEBUG - hero_object.agent_type: " .. hero_object.agent_type)
                        local new_invasion_hero_agent = cm:create_agent(self.event_army.faction, hero_object.agent_type, hero_object.agent_subtype, agent_x, agent_y)

                        out("DEBUG - new_invasion_hero_agent spawned with cqi: " .. new_invasion_hero_agent:command_queue_index())
                        -- Also apply any skill overrides to the hero.
                        for temp_hero_agent_subtype, skill_override in pairs(skill_overrides) do
                            if hero_object.agent_subtype == temp_hero_agent_subtype then
                                out("DEBUG - adding skills to invasion force hero " .. temp_hero_agent_subtype .. " of cqi " .. new_invasion_hero_agent:command_queue_index())
                                for _, skill in ipairs(skill_override) do
                                    cm:add_skill(new_invasion_hero_agent, skill, true, true)
                                end
                            end
                        end

                        -- Embed the hero into the invasion force.
                        cm:embed_agent_in_force(new_invasion_hero_agent, invasion_force:get_general():military_force())
                    end

                    -- Now we apply any skill overrides to the invasion force lord.
                    out("DEBUG - invasion force lord cqi: " .. invasion_force:get_general():command_queue_index())
                    for lord_agent_subtype, skill_override in pairs(skill_overrides) do
                        if self.event_army.lord.subtype == lord_agent_subtype then
                            out("DEBUG - adding skills to invasion force lord of cqi " .. invasion_force:get_general():command_queue_index())
                            for _, skill in ipairs(skill_override) do
                                cm:add_skill(invasion_force:get_general(), skill, true, true)
                            end
                            break
                        end
                    end
                    ---------------------------------------------------------
                    ---------------------------------------------------------
                    ---------------------------------------------------------


                    local faction_being_declared_war_to = local_context:character():faction():name()
                    if faction_being_declared_war_to == self.event_army.faction then
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
                end,
                IS_NOT_PERSISTENT_LISTENER
            )
        
            -- Add traits to general as one cannot directly give it skills 
            -- Add ancillaries to general and other characters if able.
            cm:callback(
                function()
                    self:try_add_trait_to_invading_lord(invasion_force:get_general())
                    self:try_add_ancillaries_to_invading_lord(invasion_force:get_general())
                end,
            0.1)
            -- Force declare war
            
            cm:callback(
                function()
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

function InvasionBattleManager:try_add_trait_to_invading_lord(invasion_general)
    local lord_lookup = cm:char_lookup_str(invasion_general)
    local lord_trait = self.event_army.lord.trait
    if lord_trait ~= nil then
        cm:force_add_trait(lord_lookup, lord_trait, false , 1)
    end
end

function InvasionBattleManager:try_add_ancillaries_to_invading_lord(invasion_general)
    for i = 1, #self.event_army.lord.ancillaries do
        cm:force_add_ancillary(invasion_general, self.event_army.lord.ancillaries[i], true, true)
    end
end

-- For now the maximum number of allies that a player has is 1
function InvasionBattleManager:declare_war_on_ally_reinforcement_if_available()
    if self.event_army:has_ally_reinforcements() then
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        cm:force_declare_war(self.event_army.faction, self.event_army.reinforcing_ally_armies[1].faction, call_player_allies_to_war, call_faction_allies_to_war)
    end
end


function InvasionBattleManager:setup_invasion(army, objective_character, force, force_lat_lng)
    if self.invasion_manager:get_invasion(army.invasion_identifier) then
        self.invasion_manager:remove_invasion(army.invasion_identifier)
    end

    -- https://chadvandy.github.io/tw_modding_resources/WH3/campaign/invasion_manager.html#function:invasion:start_invasion

    local new_invasion = self.invasion_manager:new_invasion(army.invasion_identifier, army.faction, force, force_lat_lng)

    -- Apply the military upkeep free force effect.
    new_invasion:apply_effect("wh_main_bundle_military_upkeep_free_force", -1)

    -- Set the target to the player character.
    new_invasion:set_target("CHARACTER", objective_character:command_queue_index(), objective_character:faction():name())

    -- Create the general for the invasion. Agent subtypes come from the agent_subtypes_tables.
    out("DEBUG - creating general for invasion with the following data: " .. army.lord.subtype .. " " .. army.lord.forename .. " " .. army.lord.clan_name .. " " .. army.lord.family_name .. " " .. army.lord.other_name)
    new_invasion:create_general(false, army.lord.subtype, army.lord.forename, army.lord.clan_name, army.lord.family_name, army.lord.other_name)

    -- add an experience level to the invasion forces
    local by_level = true
    new_invasion:add_character_experience(army.lord.level, by_level)

    -- Add experience to the unit
    new_invasion:add_unit_experience(army.unit_experience_amount)

    return new_invasion
end

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


function InvasionBattleManager:set_auxiliary_army_for_reset(army)
    self.event_army = army
end


function InvasionBattleManager:reset_state_post_battle(delegate, spot_type, spot_info, army)
	self.core:add_listener(
        "land_enc_and_poi_encounter_post_battle",
        "BattleCompleted", 
        true,
        function(context)
            local found_encounter_faction = false
            local player_won_battle = false
    
            local attacker_was_victorious = cm:pending_battle_cache_attacker_victory()
            local defender_was_victorious = cm:pending_battle_cache_defender_victory()

            local player_faction_name = cm:get_local_faction_name()
            local encounter_invasion = self.invasion_manager:get_invasion(army.invasion_identifier)
            -- Changed because defensive type battles cannot be tracked easily
            if cm:pending_battle_cache_faction_is_attacker(player_faction_name) then
                found_encounter_faction = true
                if attacker_was_victorious then
                    player_won_battle = true
                end
                if encounter_invasion then
                    self:remove_invasion_forces(army)
                end
            elseif cm:pending_battle_cache_faction_is_defender(player_faction_name) then
                found_encounter_faction = true
                if defender_was_victorious then
                    player_won_battle = true
                end
                if encounter_invasion then
                    self:remove_invasion_forces(army)
                end
            end
            
            if found_encounter_faction == true then
                if spot_type == "BattleSpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle, spot_info)
                elseif spot_type == "SmithySpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle)
                end
            end
        end,
        IS_NOT_PERSISTENT_LISTENER
	)
end


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


function InvasionBattleManager:remove_invasion_force_by_identifier(invasion_identifier)
    local force = self.invasion_manager:get_invasion(invasion_identifier)
    if force then
        cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
        cm:disable_event_feed_events(true, "wh_event_category_character", "", "")
        force:kill()
        cm:callback(function() cm:disable_event_feed_events(false, "", "", "diplomacy_faction_destroyed") end, 1)
        cm:callback(function() cm:disable_event_feed_events(false, "wh_event_category_character", "", "") end, 1)
    end
end


function InvasionBattleManager:find_location_for_character_to_spawn(faction_name, center_coordinates)
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false)
    -- we check in the center and then X logical meters around
    for i = 0, 4 do
        -- we check in the same region
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], true, i*2)
        else 
            break
        end
        
        -- we check in another region
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false, i*2)
        else 
            break
        end
    end
    
    -- can be x = -1 and y = -1. The battle will not trigger if so.
    return x, y
end


-------------------------
--- Constructors
-------------------------
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

return InvasionBattleManager