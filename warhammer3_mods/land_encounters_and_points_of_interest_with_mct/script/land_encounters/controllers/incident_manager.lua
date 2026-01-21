local IGNORE_INCIDENT_PARAMETER_FLAG = 0

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

function is_human_and_it_is_its_turn(faction)
    return faction:is_human() and cm:is_human_factions_turn()
end

function get_player_faction_character_closest_to_spot(spot_info)
    local faction_name = cm:get_local_faction_name()
    local only_general = true
    local is_garrison_commander = false
    local local_character, distance = cm:get_closest_character_to_position_from_faction(faction_name, spot_info.coordinates[1], spot_info.coordinates[2], only_general, is_garrison_commander)    
    return local_character
end

function trigger_incident(incident_key, targets, spot_info, player_character)
    -- if the campaign has been reloaded from a battle and we don't have the current player we have to obtain it 
    -- back from the cm as we already know the faction, we get the closest character to the point. It may gives 
    -- an incorrect one but still the player faction should get the rewards so is a half win
    if player_character == nil or (type(player_character) == "table" and next(player_character) == nil) then
        player_character = get_player_faction_character_closest_to_spot(spot_info)
    end
    
    -- Only for the human it should trigger. Otherwise ignore
    if is_human_and_it_is_its_turn(player_character:faction()) then 
        trigger_incident_for_character(incident_key, targets, player_character)
    end
end