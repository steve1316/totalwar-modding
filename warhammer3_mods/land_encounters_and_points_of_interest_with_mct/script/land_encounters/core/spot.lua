require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/shared/mct_settings")

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Spot (abstract base)
-- (from models/spots/abstract_classes/spot.lua)

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local AUTOMATIC_DEACTIVATION_COOLDOWN = 10

-------------------------
--- Properties definition
-------------------------
local Spot = {
    -- logic properties
    index = 0, -- its almost hardcoded given that
    coordinates = {0, 0},
    is_active = false,
    automatic_deactivation_countdown = 0, -- Should automatically dissapear after X turn
    -- marker properties
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
function Spot:get_class()
    return "Spot. You shouldn't be using this class but it's children!"
end

function Spot:initialize_from_coordinates(index, lat_lng)
    self.index = index
    self.coordinates = lat_lng
    self.is_active = false
    self.automatic_deactivation_countdown = 0
end

function Spot:activate(zone_name)
    self:set_logical_data()

    local mct_settings = get_mct_settings()
    local marker_id = "land_enc_marker_" .. zone_name .. "_" .. self.index
    local available_skins = {}
    for i = 33, 44 do
        if mct_settings.enable_all_encounter_skins or table.contains(mct_settings.enabled_encounter_skin_ids, i) then
            table.insert(available_skins, i)
        end
    end

    local marker_number
    if #available_skins == 0 then
        marker_number = 42
    else
        local random_index = random_number(#available_skins, 1)
        marker_number = available_skins[random_index]
    end

    local marker_key = "encounter_marker_"..tostring(marker_number)
    local interaction_radius = 4
    self:set_marker_on_map(marker_id, marker_key, interaction_radius)
end

function Spot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_marker"] = self.marker_id
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_active"] = self.is_active
end

function Spot:reinstate(state_info, flattened_key)
    self.marker_id = state_info[flattened_key .. "_marker"]
    self.coordinates = state_info[flattened_key .. "_coordinates"]
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
end

function Spot:set_logical_data()
    self.is_active = true
    self.automatic_deactivation_countdown = AUTOMATIC_DEACTIVATION_COOLDOWN
end

function Spot:set_marker_on_map(marker_id, marker_key, interaction_radius)
    self.marker_id = marker_id
    -- from campaign_interactable_marker_infos table
    -- there are 12 possible skins for the markers. From number 33 to 44 up
    local radius = interaction_radius
    local faction_key = "" -- anyone can activate the marker
    local subculture_key = "" -- anyone can activate the marker
    cm:add_interactable_campaign_marker(self.marker_id, marker_key, self.coordinates[1], self.coordinates[2], radius, faction_key, subculture_key)
    log("Added landmark marker_id=" .. tostring(self.marker_id) .. ", marker_key=" .. tostring(marker_key) .. ", coordinates_x=" .. tostring(self.coordinates[1]) .. ", coordinates_y=" .. tostring(self.coordinates[2]) .. ", radius=" .. tostring(radius) .. ".")
end

function Spot:check_if_active_and_countdown_reached()
    if self.is_active == true and self.automatic_deactivation_countdown == 0 then
        return true
    elseif self.is_active == true then
        self.automatic_deactivation_countdown = self.automatic_deactivation_countdown - 1
    end
    return false
end

function Spot:deactivate(zone_name, spot_index)
    if self.marker_id == "" then
        self.marker_id = "land_enc_marker_" .. zone_name .. "_" .. spot_index
    end
    cm:remove_interactable_campaign_marker(self.marker_id)

    self.is_active = false
    self.automatic_deactivation_countdown = 0
    self.marker_id = ""
end

-------------------------
--- Constructors
-------------------------
function Spot:new()
    local t = { index = 0, coordinates = {0, 0}, is_active = false, automatic_deactivation_countdown = 0, marker_id = "", event = nil }
    setmetatable(t, self)
    self.__index = self
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- EmitterSpot (abstract, extends Spot)
-- (from models/spots/abstract_classes/emitter_spot.lua - file was empty)

local EmitterSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- DungeonSpot
-- (from models/spots/dungeon_spot.lua - file was empty)

local DungeonSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- EventSpot
-- (from models/spots/event_spot.lua)

local base_spot = Spot

------------------------------------------------
--- Constant values of the class
------------------------------------------------


-------------------------
--- Properties definition
-------------------------
local EventSpot = {
    -- logic properties
    index = 0,
    coordinates = {0, 0},
    is_active = false,
    automatic_deactivation_countdown = 0, -- Should automatically dissapear after X turn
    -- marker properties
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
-- Overriden Methods
function EventSpot:get_class()
    return "EventSpot"
end

function EventSpot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_active"] = self.is_active
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_marker"] = self.marker_id
end

function EventSpot:reinstate(state_info, flattened_key)
    self.coordinates = state_info[flattened_key .. "_coordinates"]
    self.is_active = state_info[flattened_key .. "_active"]
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
    self.marker_id = state_info[flattened_key .. "_marker"]
end

-------------------------
--- Constructors
-------------------------
-- https://stackoverflow.com/questions/65961478/how-to-mimic-simple-inheritance-with-base-and-child-class-constructors-in-lua-t
function EventSpot:newFrom(old_spot)
    EventSpot.__index = EventSpot
    setmetatable(EventSpot, {__index = base_spot})
    setmetatable(old_spot, EventSpot)
    return old_spot
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- InvasionSpot
-- (from models/spots/invasion_spot.lua - file was a doc-only comment block)

--[[

An invasion of an enemy

- Skarsnik, Queek, Belegar: controlling karak eight peeks and eliminating opposing factions generates a doomstack for respective faction.
- Dark Elves: Controling x amount of Ulthuan generates a doomstack.
- Chaos: % of chaos corruption across the world surpasses an amount -> doomstack.

So if I'm playing as the Empire I get a notification that Ulthuan will soon fall when say DE have 50% regions. I will then want to send an army to help them cause if the donut falls surely the old world will be next. Or chaos factions are doing well. I will then want to send armies to make recover land for Kislev. Or maybe I don't and chose to deal with their armies if they come.

--]]

local InvasionSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- ResourceSpot
-- (from models/spots/resource_spot.lua - file was a doc-only comment block)

--[[ Specification
For the player:
- The thematic resource spot will grant some of a resource and money for their faction.
- It will be attacked every so often by a random enemy faction.
- Can be upgraded 3 times
- May also randomly give buffs to their zone or a visiting army.
- Several thematic types

For the AI:
- Gives a random amount of treasury for the faction every 5 turns
- 3 levels of defense

]]--

local ResourceSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- RiftSpot
-- (from models/spots/rift_spot.lua - file was a doc-only comment block)

--[[

A daemonic invasion fills suddenly part of the territory. If beaten. A rift will unite to remote places in the map. Both AI and player can use it

--]]

local RiftSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- SmithySpot
-- (from models/spots/smithy_spot.lua)

-------------------------
--- Properties definition
-------------------------
local SmithySpot = {
    -- logic properties
    index = 0,
    coordinates = {0, 0},
    -- marker properties
    -- they are fixed
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
-- Overriden Methods
function SmithySpot:get_class()
    return "SmithySpot"
end

function SmithySpot:activate(zone_name)
    local marker_id = "land_enc_marker_" .. zone_name .. "_smithy_" .. self.index
    local marker_key = "encounter_marker_smithy"
    local interaction_radius = 8
    self:set_marker_on_map(marker_id, marker_key, interaction_radius)
end

function SmithySpot:flatten_info(state_info, zone_name)
    local flattened_key = zone_name .. "_smithy_" .. tostring(self.index)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_marker"] = self.marker_id
end

function SmithySpot:reinstate(flattened_key, previous_state)
    self.coordinates = previous_state[flattened_key .. "_coordinates"]
    self.marker_id = previous_state[flattened_key .. "_marker"]
end

-------------------------
--- Constructors
-------------------------
function SmithySpot:new_from_coordinates(old_spot, index, initial_owning_faction)
    SmithySpot.__index = SmithySpot
    setmetatable(SmithySpot, {__index = Spot})
    local t = old_spot
    -- initalize variables related only to smithy spot
    setmetatable(t, SmithySpot)
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- TavernSpot
-- (from models/spots/tavern_spot.lua - file was a doc-only comment block)

--[[ Specification
For the player only:
- Story quests: the tavern emits quests chains for legendary characters or legendary factionwide buffs unlocked by the level.
- Garrison upgraded by level.
- Can recruit special unit types every X turn given level. Special units examples: For High Elves Eltharion units or Averlonian units. RORs in cases there are not special units.
- 5 levels

For the AI:
- Every 20 turns spawn an army of the controlling faction if it can permit it with 0 upkeep for 100 turns.
- The more time passes in the campaign the better the tavern armies spawned becomes.
- Doomstack garrison


For all
- Corrupts the zone with the controlling faction
- Serves as a patrol for the region like Oxyotl stuff

- At least 1 racial tavern and 1 neutral tavern per logical zone.

]]--

local TavernSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- TowerSpot
-- (from models/spots/tower_spot.lua - file was a doc-only comment block)

--[[
I was thinking special-encounter (not auto-resolveable combat) could be a "tower" or "dungeon"

Starting up, it would give you a super-easy encounter, like fighting lordless zombies, empire-troops, darkspears/darkshards, skinks, nurglings, or skavenslaves.

If you manage to suceed that battle, another dilemma would trigger that asks if you would like to leave the dungeon/tower or dwell deeper/higher; every tower/dungeon is based around a single faction for enemies you face, and every time you decide to "go higher/deeper" it gives you a harder encounter, but with increased reward rarity at each turn, or even potentialy if possible get you 1-5 random units (potentialy from other factions you arent playing) as that swear fealty to you.

(power of mercs would scale on the cleared dungeon-level's strength, so if you beat skeleton-warriors you might get 2-4 skeleton-warriors or equalivent-cost units from other roosters)

On the final or later floor, you would fight an actual-lord with spells/mounts and abilities that boost their troops refered to as the "Master of the Dungeon/Warren", and if you beat them it could give some cool item/rewards, or mayhap even a random hero from a random faction, where the roleplay is that you free-prisoners that swear fealty to you, or that you broke the curse of bla bla whatever n so on.
]]--

local TowerSpot = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- SpotDelegate (shared spot lifecycle behavior)
-- (from delegates/spots/physical/spot_delegate.lua)

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local SPOT_TURN_ACTIVATION_COOLDOWN = 5
local ERASE_SPOT_FLAG = nil


-------------------------
--- Properties definition
-------------------------
local SpotDelegate = {
    spots = {},

    active_spots = {},
    prohibited_spots = {},

    max_active_spots_count = 0
}


function SpotDelegate:can_add_land_encounters()
    return self.max_active_spots_count > #self.active_spots
end

function SpotDelegate:try_add_land_encounters(zone_name)
    local disordered_indexes = randomic_length_shuffle(#self.spots)
    for i= 1, #disordered_indexes do
        -- after every land encounter added we should check that the total count does not surpass
        -- the total amount of encounters permitted
        if not self:can_add_land_encounters() then
            log("Cannot add more land encounter")
            break
        end

        -- check if the current index is not registered as a treasure or battle spot
        local candidate_spot_to_activate_index = disordered_indexes[i]
        if self.prohibited_spots[candidate_spot_to_activate_index] == nil and self.active_spots[candidate_spot_to_activate_index] == nil then
            log("Adding land encounter in " .. zone_name .. "[" .. tostring(candidate_spot_to_activate_index) .. "]")
            self.active_spots[candidate_spot_to_activate_index] = true
            self.spots[candidate_spot_to_activate_index] = EventSpot:newFrom(self.spots[candidate_spot_to_activate_index])
            self.spots[candidate_spot_to_activate_index]:activate(zone_name)
            log("Land encounter was supposedly activated")
        end
    end
end

function SpotDelegate:update_occupied_and_prohibited_spot_states(zone_name)
    self:release_prohibited_spots_if_able()
    self:try_deactivate_spots_due_to_life_expiration(zone_name)
end


function SpotDelegate:release_prohibited_spots_if_able()
    for spot_index, cooldown in pairs(self.prohibited_spots) do
        self.prohibited_spots[spot_index] = cooldown - 1
        if self.prohibited_spots[spot_index] <= 0 then
            self.prohibited_spots[spot_index] = ERASE_SPOT_FLAG
        end
    end
end


function SpotDelegate:try_deactivate_spots_due_to_life_expiration(zone_name)
    for spot_index, state in pairs(self.active_spots) do
        if self.spots[spot_index]:check_if_active_and_countdown_reached() then
            self.active_spots[spot_index] = nil
            self:deactivate_spot_in_zone(zone_name, spot_index)
        end
    end
end


-- DESTRUCTION RELATED METHODS
function SpotDelegate:deactivate_spot_in_zone(zone_name, spot_index)
    self.prohibited_spots[spot_index] = SPOT_TURN_ACTIVATION_COOLDOWN -- entering cooldown till 0 and can be reselected
    self.active_spots[spot_index] = ERASE_SPOT_FLAG

    self.spots[spot_index]:deactivate(zone_name, spot_index)
end


function SpotDelegate:reinstate_from_previous_state(zone_name, previous_state)
    for i=1, #self.spots do
        local flattened_key = zone_name .. "_" .. tostring(self.spots[i].coordinates[1]) .. "_" .. tostring(self.spots[i].coordinates[2])
        local spot_type = previous_state[flattened_key .. "_type"]
        if spot_type ~= nil then
            if spot_type == "EventSpot" and previous_state[flattened_key .. "_active"] then
                self.spots[i] = EventSpot:newFrom(self.spots[i])
                self.spots[i]:reinstate(previous_state, flattened_key)
            end

            self.active_spots[i] = previous_state[flattened_key .. "_active_spot_flag"]
            self.prohibited_spots[i] = previous_state[flattened_key .. "_prohibited_spot_flag"]
        end
    end
end


-------------------------
--- Constructors
-------------------------
function SpotDelegate:new(zone_coordinates, active_spot_percentage)
    local zone_spots = {}
    for i = 1, #zone_coordinates do
        local spot = Spot:new()
        spot:initialize_from_coordinates(i, zone_coordinates[i])
        table.insert(zone_spots, spot)
    end

    local t = {
        spots = zone_spots,
        active_spots = {},
        prohibited_spots = {},
        max_active_spots_count = active_spot_percentage * #zone_coordinates
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- PointOfInterestDelegate (shared POI lifecycle behavior)
-- (from delegates/points_of_interests/physical/point_of_interest_delegate.lua)

-------------------------
--- Properties definition
-------------------------
local PointOfInterestDelegate = {
    points_of_interest = {}, -- Smithy / Resource / Tavern
}

function PointOfInterestDelegate:initialize(points_of_interest_data)
    if not get_mct_settings().disable_smithies then
        self:initialize_smithies(points_of_interest_data["smithies"])
    end
    self:initialize_taverns(points_of_interest_data["taverns"])
    self:initialize_resources(points_of_interest_data["resources"])
end

function PointOfInterestDelegate:initialize_smithies(smithies_data)
    self.points_of_interest = {}
    -- we get the player faction so that we never give him the smithy or any other poi initially
    local player_faction_name = cm:get_local_faction_name()
    if #smithies_data > 0 then
        for i=1, #smithies_data do
            local spot = Spot:new()
            spot:initialize_from_coordinates(i, smithies_data[i].coordinates)

            local initial_owner = ""
            if player_faction_name == smithies_data[i].initial_owner then
                initial_owner = smithies_data[i].owner_if_player
            else
                initial_owner = smithies_data[i].initial_owner
            end

            local smithy = SmithySpot:new_from_coordinates(spot, i, initial_owner)
            table.insert(self.points_of_interest, smithy)
        end
    end
end


function PointOfInterestDelegate:initialize_taverns(taverns_data)
    if #taverns_data > 0 then
        for i=1, #taverns_data do
            --TODO table.insert(self.points_of_interest, TavernSpot:newFrom(taverns_data[i]))
        end
    end
end


function PointOfInterestDelegate:initialize_resources(resources_data)
    if #resources_data > 0 then
        for i=1, #resources_data do
            --TODO table.insert(self.points_of_interest, ResourceSpot:newFrom(resources_data[i]))
        end
    end
end


function PointOfInterestDelegate:activate_points_of_interest(zone_name)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:activate(zone_name)
    end
end


function PointOfInterestDelegate:update_points_of_interest_by_turn(mission_manager)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:update_state_through_turn_passing(mission_manager)
    end
end


function PointOfInterestDelegate:reinstate_points_of_interest(zone_name, previous_state)
    local poi_index_triggered = nil
    for i=1, #self.points_of_interest do
        local poi_type = self.points_of_interest[i]:get_class()
        if poi_type == "SmithySpot" then
            local flattened_key = zone_name .. "_smithy_" .. tostring(self.points_of_interest[i].index)
            -- it could be that we have added a new poi. So we need to check wether if it previously existed.
            local is_battle_triggered = false
            if previous_state[flattened_key .. "_active"] ~= nil then
                is_battle_triggered = self.points_of_interest[i]:reinstate(flattened_key, previous_state)
            end
            -- the battle type is irrelevant as we will delegate to the poi its logic
            if is_battle_triggered then
                poi_index_triggered = i
            end
        end
    end
    return poi_index_triggered
end

-------------------------
--- Constructors
-------------------------
function PointOfInterestDelegate:new()
    local t = { }
    setmetatable(t, self)
    self.__index = self
    return t
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Zone
-- (from models/zone.lua)

-------------------------
--- Properties definition
-------------------------
local Zone = {
    name = "Unknown",
    point_of_interest_delegate = {},
    spot_delegate = {}
}

-------------------------
--- Class Methods
-------------------------

--
-- EVENT SPOTS (DYNAMIC SPOT)
--

function Zone:update_occupied_and_prohibited_spot_states()
    self.spot_delegate:update_occupied_and_prohibited_spot_states(self.name)
end


function Zone:try_add_land_encounters()
    self.spot_delegate:try_add_land_encounters(self.name)
end


function Zone:reinstate_from_previous_state(previous_state)
    self.spot_delegate:reinstate_from_previous_state(self.name, previous_state)
end


-- DESTRUCTION RELATED METHODS
function Zone:deactivate_spot_in_zone(spot_index)
    self.spot_delegate:deactivate_spot_in_zone(self.name, spot_index)
end


--
-- POINTS OF INTEREST (PERMANENT CONTROL SPOT)
--
function Zone:initialize_points_of_interest(points_of_interest_data, mctSettings)
    self.point_of_interest_delegate:initialize(points_of_interest_data, mctSettings)
end


function Zone:update_points_of_interest_by_turn(mission_manager)
    self.point_of_interest_delegate:update_points_of_interest_by_turn(mission_manager)
end


function Zone:activate_points_of_interest()
    self.point_of_interest_delegate:activate_points_of_interest(self.name)
end


function Zone:reinstate_points_of_interest(previous_state)
    self.point_of_interest_delegate:reinstate_points_of_interest(self.name, previous_state)
end


-------------------------
--- Constructors
-------------------------
function Zone:new(zone_name, zone_coordinates, active_spot_percentage)
    local t = {
        name = zone_name,
        spot_delegate = SpotDelegate:new(zone_coordinates, active_spot_percentage),
        point_of_interest_delegate = PointOfInterestDelegate:new()
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return {
    Spot = Spot,
    EmitterSpot = EmitterSpot,
    DungeonSpot = DungeonSpot,
    EventSpot = EventSpot,
    InvasionSpot = InvasionSpot,
    ResourceSpot = ResourceSpot,
    RiftSpot = RiftSpot,
    SmithySpot = SmithySpot,
    TavernSpot = TavernSpot,
    TowerSpot = TowerSpot,
    SpotDelegate = SpotDelegate,
    PointOfInterestDelegate = PointOfInterestDelegate,
    Zone = Zone,
}
