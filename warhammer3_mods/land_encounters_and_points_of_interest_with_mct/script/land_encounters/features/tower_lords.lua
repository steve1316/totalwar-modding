--- Tower lords and heroes: frees heroes for the delving faction and gives the delving lord the tower's traits and title.

require("script/land_encounters/utils/random")

local factions_data = require("script/land_encounters/configs/factions_data")
local tower_army = require("script/land_encounters/features/tower_army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- How far from the delving lord a freed hero is placed.
local HERO_SPAWN_DISTANCE = 5

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- The vanilla heroes of a faction shorthand, which exist in every game.
--- @param shorthand string A 3-letter faction shorthand.
--- @returns table Its factions_data hero records from vanilla.
local function vanilla_heroes(shorthand)
    local heroes = {}
    for _, hero in ipairs(factions_data[shorthand] and factions_data[shorthand].allowed_heroes or {}) do
        if hero.origin == "vanilla" then heroes[#heroes + 1] = hero end
    end
    return heroes
end

--- Finds a living character by command queue index.
local character = tower_army.character

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- API

--- Frees a hero for the delving faction beside the delving lord and raises it to `rank`. The heroes of each shorthand are tried in turn, one
--- random hero each, until one can be created. The hero joins the lord's army when it has a free slot, and waits beside it otherwise.
--- @param general_cqi number The delving lord's command queue index.
--- @param faction_name string The delving faction.
--- @param shorthands table Faction shorthands to take the hero from, in order of preference.
--- @param rank number The hero's rank.
--- @returns string|nil The freed hero's agent subtype, or nil when none could be created.
function M.free_hero(general_cqi, faction_name, shorthands, rank)
    local general = character(general_cqi)
    if not general then
        log("tower: no hero freed, lord " .. general_cqi .. " is gone")
        return nil
    end
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, general:logical_position_x(), general:logical_position_y(), true,
        HERO_SPAWN_DISTANCE)
    if x == -1 then
        log("tower: no room beside lord " .. general_cqi .. " to free a hero")
        return nil
    end
    for _, shorthand in ipairs(shorthands) do
        local heroes = vanilla_heroes(shorthand)
        if #heroes > 0 then
            local hero = heroes[random_number(#heroes)]
            local agent = cm:create_agent(faction_name, hero.agent_type, hero.agent_subtype, x, y)
            if agent and not agent:is_null_interface() then
                cm:add_agent_experience(cm:char_lookup_str(agent), rank, true)
                local force = tower_army.delving_force(general_cqi)
                local joined = force ~= nil and tower_army.free_slots(force) > 0
                if joined then cm:embed_agent_in_force(agent, force) end
                log("tower: freed a rank " .. rank .. " " .. hero.agent_subtype .. " (" .. shorthand .. ") for " .. faction_name .. ", "
                    .. (joined and "joined the army" or "waits beside the army"))
                return hero.agent_subtype
            end
            log("tower: could not create a " .. hero.agent_subtype .. " hero for " .. faction_name)
        end
    end
    return nil
end

--- Adds trait points to the delving lord.
--- @param general_cqi number The lord's command queue index.
--- @param trait string The trait key.
--- @param points number How many points to add.
--- @param show boolean True to tell the player.
function M.add_trait(general_cqi, trait, points, show)
    local general = character(general_cqi)
    if not general then return end
    cm:force_add_trait(cm:char_lookup_str(general), trait, show, points)
    log("tower: lord " .. general_cqi .. " gains " .. points .. " point(s) of " .. trait)
end

--- True when the lord has a trait.
--- @param general_cqi number The lord's command queue index.
--- @param trait string The trait key.
--- @returns boolean True when the lord has it.
function M.has_trait(general_cqi, trait)
    local general = character(general_cqi)
    return general ~= nil and general:has_trait(trait)
end

--- Puts a title after the lord's name, e.g. "Oxyotl the Towerbreaker". A lord whose name cannot be read keeps it.
--- @param general_cqi number The lord's command queue index.
--- @param title string The localised title.
function M.add_title(general_cqi, title)
    local general = character(general_cqi)
    if not general then return end
    local forename = common.get_localised_string(general:get_forename())
    local surname = common.get_localised_string(general:get_surname())
    if forename == "" or title == "" then
        log("tower: lord " .. general_cqi .. " has no readable name or title, the title '" .. title .. "' is not added")
        return
    end
    surname = (surname ~= "" and surname .. " " or "") .. title
    cm:change_character_custom_name(general, forename, surname, "", "")
    log("tower: lord " .. general_cqi .. " is now " .. forename .. " " .. surname)
end

return M
