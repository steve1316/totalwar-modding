--- All spot classes for the mod: the abstract Spot base, EventSpot (random encounter),
--- SmithySpot, SpotDelegate, PointOfInterestDelegate, and the Zone aggregate. Also exports
--- seven doc-only placeholder classes (EmitterSpot, DungeonSpot, InvasionSpot, ResourceSpot,
--- RiftSpot, TavernSpot, TowerSpot) that the original mod never implemented.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Spot (abstract base)
--- (from models/spots/abstract_classes/spot.lua)

--- Cooldown counter for automatic spot expiration (in turns).
local AUTOMATIC_DEACTIVATION_COOLDOWN = 10

local Spot = {
    index = 0,
    coordinates = {0, 0},
    is_active = false,
    --- Spot disappears automatically after this many turns.
    automatic_deactivation_countdown = 0,
    marker_id = ""
}

--- Returns the class identifier. The base Spot intentionally returns a warning string - subclasses override this.
--- @returns string A class-identifier string. Subclasses override this.
function Spot:get_class()
    return "Spot. You shouldn't be using this class but it's children!"
end

--- Initializes a fresh Spot from a 1-indexed slot and a {lat, lng} coordinate pair.
--- @param index number 1-based slot index for this spot inside its zone.
--- @param lat_lng table A {x, y} coordinate pair.
function Spot:initialize_from_coordinates(index, lat_lng)
    self.index = index
    self.coordinates = lat_lng
    self.is_active = false
    self.automatic_deactivation_countdown = 0
end

--- Activates this spot. Picks a random encounter-marker skin from the user's MCT-enabled set
--- (falling back to skin 42 if none are enabled), then places the marker on the campaign map.
--- @param zone_name string The region key for the zone this spot belongs to.
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

--- Writes this spot's data into the flat save-state table keyed by `flattened_key`.
--- @param state_info table The accumulating flat-state table to mutate.
--- @param flattened_key string The prefix to use for each field of this spot.
function Spot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_marker"] = self.marker_id
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_active"] = self.is_active
end

--- Restores this spot's fields from a saved flat-state table.
--- @param state_info table The flat save-state table to read from.
--- @param flattened_key string The prefix used by flatten_info for this spot.
function Spot:reinstate(state_info, flattened_key)
    self.marker_id = state_info[flattened_key .. "_marker"]
    self.coordinates = state_info[flattened_key .. "_coordinates"]
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
end

--- Marks the spot active and primes its deactivation countdown.
function Spot:set_logical_data()
    self.is_active = true
    self.automatic_deactivation_countdown = AUTOMATIC_DEACTIVATION_COOLDOWN
end

--- Places this spot's marker on the campaign map. Marker skin keys come from the
--- campaign_interactable_marker_infos table (numbers 33-44 are the 12 available skins).
--- @param marker_id string The unique marker id to register with the engine.
--- @param marker_key string The marker-skin key (e.g. "encounter_marker_42").
--- @param interaction_radius number The interaction radius in campaign units.
function Spot:set_marker_on_map(marker_id, marker_key, interaction_radius)
    self.marker_id = marker_id
    local radius = interaction_radius
    --- Empty strings mean any faction/subculture can activate the marker.
    local faction_key = ""
    local subculture_key = ""
    cm:add_interactable_campaign_marker(self.marker_id, marker_key, self.coordinates[1], self.coordinates[2], radius, faction_key, subculture_key)
    log("Added landmark marker_id=" .. tostring(self.marker_id) .. ", marker_key=" .. tostring(marker_key) .. ", coordinates_x=" .. tostring(self.coordinates[1]) .. ", coordinates_y=" .. tostring(self.coordinates[2]) .. ", radius=" .. tostring(radius) .. ".")
end

--- Returns true once an active spot's countdown has reached zero. Side-effect: ticks the countdown each turn.
--- @returns boolean True when the spot is active and the countdown has fully elapsed.
function Spot:check_if_active_and_countdown_reached()
    if self.is_active == true and self.automatic_deactivation_countdown == 0 then
        return true
    elseif self.is_active == true then
        self.automatic_deactivation_countdown = self.automatic_deactivation_countdown - 1
    end
    return false
end

--- Removes the campaign marker for this spot and resets its lifecycle fields.
--- @param zone_name string The region key for the zone this spot belongs to.
--- @param spot_index number The 1-based slot index used to rebuild the marker id.
function Spot:deactivate(zone_name, spot_index)
    if self.marker_id == "" then
        self.marker_id = "land_enc_marker_" .. zone_name .. "_" .. spot_index
    end
    cm:remove_interactable_campaign_marker(self.marker_id)

    self.is_active = false
    self.automatic_deactivation_countdown = 0
    self.marker_id = ""
end

--- Constructs a fresh Spot with default-zero coordinates / countdown and an empty marker id.
--- @returns Spot A new base-Spot instance.
function Spot:new()
    local t = { index = 0, coordinates = {0, 0}, is_active = false, automatic_deactivation_countdown = 0, marker_id = "", event = nil }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- EmitterSpot (abstract, extends Spot)
--- (from models/spots/abstract_classes/emitter_spot.lua - file was empty)

local EmitterSpot = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- DungeonSpot
--- (from models/spots/dungeon_spot.lua - file was empty)

local DungeonSpot = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- EventSpot
--- (from models/spots/event_spot.lua)

local base_spot = Spot

local EventSpot = {
    index = 0,
    coordinates = {0, 0},
    is_active = false,
    automatic_deactivation_countdown = 0,
    marker_id = ""
}

--- Returns the EventSpot class identifier used by the save-state dispatch.
--- @returns string The literal "EventSpot".
function EventSpot:get_class()
    return "EventSpot"
end

--- Writes this spot's data into the flat save-state table keyed by `flattened_key`.
--- @param state_info table The accumulating flat-state table to mutate.
--- @param flattened_key string The prefix to use for each field of this spot.
function EventSpot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_active"] = self.is_active
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_marker"] = self.marker_id
end

--- Restores this spot's fields from a saved flat-state table.
--- @param state_info table The flat save-state table to read from.
--- @param flattened_key string The prefix used by flatten_info for this spot.
function EventSpot:reinstate(state_info, flattened_key)
    self.coordinates = state_info[flattened_key .. "_coordinates"]
    self.is_active = state_info[flattened_key .. "_active"]
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
    self.marker_id = state_info[flattened_key .. "_marker"]
end

--- Promotes an existing Spot in place to an EventSpot via metatable rewiring.
--- See https://stackoverflow.com/questions/65961478 for the inheritance pattern.
--- @param old_spot Spot The existing base-Spot instance to upcast.
--- @returns EventSpot The same instance with its metatable replaced.
function EventSpot:newFrom(old_spot)
    EventSpot.__index = EventSpot
    setmetatable(EventSpot, {__index = base_spot})
    setmetatable(old_spot, EventSpot)
    return old_spot
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- InvasionSpot
--- (from models/spots/invasion_spot.lua - file was a doc-only comment block)

--[[

An invasion of an enemy

- Skarsnik, Queek, Belegar: controlling karak eight peeks and eliminating opposing factions generates a doomstack for respective faction.
- Dark Elves: Controling x amount of Ulthuan generates a doomstack.
- Chaos: % of chaos corruption across the world surpasses an amount -> doomstack.

So if I'm playing as the Empire I get a notification that Ulthuan will soon fall when say DE have 50% regions. I will then want to send an army to help them cause if the donut falls surely the old world will be next. Or chaos factions are doing well. I will then want to send armies to make recover land for Kislev. Or maybe I don't and chose to deal with their armies if they come.

--]]

local InvasionSpot = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- ResourceSpot
--- (from models/spots/resource_spot.lua - file was a doc-only comment block)

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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- RiftSpot
--- (from models/spots/rift_spot.lua - file was a doc-only comment block)

--[[

A daemonic invasion fills suddenly part of the territory. If beaten. A rift will unite to remote places in the map. Both AI and player can use it

--]]

local RiftSpot = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- SmithySpot
--- (from models/spots/smithy_spot.lua)

local SmithySpot = {
    index = 0,
    coordinates = {0, 0},
    --- Marker id is fixed across the smithy's lifetime.
    marker_id = ""
}

--- Returns the SmithySpot class identifier used by the save-state dispatch.
--- @returns string The literal "SmithySpot".
function SmithySpot:get_class()
    return "SmithySpot"
end

--- Activates the smithy POI by placing its fixed marker (encounter_marker_smithy) on the campaign map.
--- @param zone_name string The region key for the zone this smithy belongs to.
function SmithySpot:activate(zone_name)
    local marker_id = "land_enc_marker_" .. zone_name .. "_smithy_" .. self.index
    local marker_key = "encounter_marker_smithy"
    local interaction_radius = 8
    self:set_marker_on_map(marker_id, marker_key, interaction_radius)
end

--- Writes this smithy's data into the flat save-state table under a per-zone smithy key.
--- @param state_info table The accumulating flat-state table to mutate.
--- @param zone_name string The region key for the zone this smithy belongs to.
function SmithySpot:flatten_info(state_info, zone_name)
    local flattened_key = zone_name .. "_smithy_" .. tostring(self.index)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_marker"] = self.marker_id
end

--- Restores this smithy's fields from a saved flat-state table.
--- @param flattened_key string The prefix used by flatten_info for this smithy.
--- @param previous_state table The flat save-state table to read from.
function SmithySpot:reinstate(flattened_key, previous_state)
    self.coordinates = previous_state[flattened_key .. "_coordinates"]
    self.marker_id = previous_state[flattened_key .. "_marker"]
end

--- Promotes a base Spot to a SmithySpot in place via metatable rewiring.
--- @param old_spot Spot The existing base-Spot instance to upcast.
--- @param index number The 1-based smithy slot index (currently unused by the upcast).
--- @param initial_owning_faction string The starting owning-faction key (currently unused by the upcast).
--- @returns SmithySpot The same instance with its metatable replaced.
function SmithySpot:new_from_coordinates(old_spot, index, initial_owning_faction)
    SmithySpot.__index = SmithySpot
    setmetatable(SmithySpot, {__index = Spot})
    local t = old_spot
    setmetatable(t, SmithySpot)
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TavernSpot
--- (from models/spots/tavern_spot.lua - file was a doc-only comment block)

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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerSpot
--- (from models/spots/tower_spot.lua - file was a doc-only comment block)

--[[
I was thinking special-encounter (not auto-resolveable combat) could be a "tower" or "dungeon"

Starting up, it would give you a super-easy encounter, like fighting lordless zombies, empire-troops, darkspears/darkshards, skinks, nurglings, or skavenslaves.

If you manage to suceed that battle, another dilemma would trigger that asks if you would like to leave the dungeon/tower or dwell deeper/higher; every tower/dungeon is based around a single faction for enemies you face, and every time you decide to "go higher/deeper" it gives you a harder encounter, but with increased reward rarity at each turn, or even potentialy if possible get you 1-5 random units (potentialy from other factions you arent playing) as that swear fealty to you.

(power of mercs would scale on the cleared dungeon-level's strength, so if you beat skeleton-warriors you might get 2-4 skeleton-warriors or equalivent-cost units from other roosters)

On the final or later floor, you would fight an actual-lord with spells/mounts and abilities that boost their troops refered to as the "Master of the Dungeon/Warren", and if you beat them it could give some cool item/rewards, or mayhap even a random hero from a random faction, where the roleplay is that you free-prisoners that swear fealty to you, or that you broke the curse of bla bla whatever n so on.
]]--

local TowerSpot = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- SpotDelegate (shared spot lifecycle behavior)
--- (from delegates/spots/physical/spot_delegate.lua)

--- Turns a recently used spot stays in the prohibited list before it can be picked again.
local SPOT_TURN_ACTIVATION_COOLDOWN = 5
local ERASE_SPOT_FLAG = nil


local SpotDelegate = {
    spots = {},

    active_spots = {},
    prohibited_spots = {},

    max_active_spots_count = 0
}


--- True while the zone has room for more active land encounters under its spawn-percentage cap.
--- @returns boolean True when the active-spot count is below the cap.
function SpotDelegate:can_add_land_encounters()
    return self.max_active_spots_count > #self.active_spots
end

--- Walks the zone's spots in random order and activates inactive ones until the active cap is hit.
--- @param zone_name string The region key used to build marker ids.
function SpotDelegate:try_add_land_encounters(zone_name)
    local disordered_indexes = randomic_length_shuffle(#self.spots)
    for i= 1, #disordered_indexes do
        --- Stop once the active-spot cap is reached.
        if not self:can_add_land_encounters() then
            log("Cannot add more land encounter")
            break
        end

        --- Skip indexes that are currently active or in cooldown.
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

--- Per-turn maintenance: tick cooldowns on prohibited spots and expire any active spots whose countdown ran out.
--- @param zone_name string The region key for the zone being updated.
function SpotDelegate:update_occupied_and_prohibited_spot_states(zone_name)
    self:release_prohibited_spots_if_able()
    self:try_deactivate_spots_due_to_life_expiration(zone_name)
end


--- Decrements every prohibited-spot cooldown and frees spots that reach zero.
function SpotDelegate:release_prohibited_spots_if_able()
    for spot_index, cooldown in pairs(self.prohibited_spots) do
        self.prohibited_spots[spot_index] = cooldown - 1
        if self.prohibited_spots[spot_index] <= 0 then
            self.prohibited_spots[spot_index] = ERASE_SPOT_FLAG
        end
    end
end


--- Expires any active spot whose lifetime countdown has hit zero.
--- @param zone_name string The region key for the zone being updated.
function SpotDelegate:try_deactivate_spots_due_to_life_expiration(zone_name)
    for spot_index, state in pairs(self.active_spots) do
        if self.spots[spot_index]:check_if_active_and_countdown_reached() then
            self.active_spots[spot_index] = nil
            self:deactivate_spot_in_zone(zone_name, spot_index)
        end
    end
end


--- Moves a spot from active to cooldown and removes its on-map marker.
--- @param zone_name string The region key for the zone this spot belongs to.
--- @param spot_index number The 1-based slot index for the spot.
function SpotDelegate:deactivate_spot_in_zone(zone_name, spot_index)
    self.prohibited_spots[spot_index] = SPOT_TURN_ACTIVATION_COOLDOWN
    self.active_spots[spot_index] = ERASE_SPOT_FLAG

    self.spots[spot_index]:deactivate(zone_name, spot_index)
end


--- Restores active and prohibited spots from a previously saved campaign state.
--- @param zone_name string The region key for the zone being restored.
--- @param previous_state table Flattened save state previously produced by export_state_as_a_table.
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


--- Builds a SpotDelegate over the given zone coordinates. `active_spot_percentage` caps how
--- many of the zone's spots can be active at once.
--- @param zone_coordinates table An array of {x, y} coordinate pairs.
--- @param active_spot_percentage number Fraction (0..1) of spots that may be active at once.
--- @returns SpotDelegate A new delegate with one Spot per coordinate.
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- PointOfInterestDelegate (shared POI lifecycle behavior)
--- (from delegates/points_of_interests/physical/point_of_interest_delegate.lua)

local PointOfInterestDelegate = {
    --- Holds Smithy / Resource / Tavern POIs.
    points_of_interest = {},
}

--- Initializes the POI table from the configs (smithies, taverns, resources). Honors the MCT
--- disable_smithies toggle.
--- @param points_of_interest_data table A keyed table with smithies, taverns, and resources arrays.
function PointOfInterestDelegate:initialize(points_of_interest_data)
    if not get_mct_settings().disable_smithies then
        self:initialize_smithies(points_of_interest_data["smithies"])
    end
    self:initialize_taverns(points_of_interest_data["taverns"])
    self:initialize_resources(points_of_interest_data["resources"])
end

--- Creates a SmithySpot for each entry in `smithies_data`. The player never starts as the owner.
--- @param smithies_data table An array of { coordinates, initial_owner, owner_if_player } records.
function PointOfInterestDelegate:initialize_smithies(smithies_data)
    self.points_of_interest = {}
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


--- Placeholder for future tavern POI initialization. TavernSpot is not implemented yet.
--- @param taverns_data table An array of tavern POI records. Currently iterated only as a no-op.
function PointOfInterestDelegate:initialize_taverns(taverns_data)
    if #taverns_data > 0 then
        for i=1, #taverns_data do
            --TODO table.insert(self.points_of_interest, TavernSpot:newFrom(taverns_data[i]))
        end
    end
end


--- Placeholder for future resource POI initialization. ResourceSpot is not implemented yet.
--- @param resources_data table An array of resource POI records. Currently iterated only as a no-op.
function PointOfInterestDelegate:initialize_resources(resources_data)
    if #resources_data > 0 then
        for i=1, #resources_data do
            --TODO table.insert(self.points_of_interest, ResourceSpot:newFrom(resources_data[i]))
        end
    end
end


--- Activates the on-map marker for every POI in this zone.
--- @param zone_name string The region key for the zone.
function PointOfInterestDelegate:activate_points_of_interest(zone_name)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:activate(zone_name)
    end
end


--- Ticks per-turn state updates for every POI in this zone.
--- @param mission_manager table The CA mission_manager handle forwarded to each POI.
function PointOfInterestDelegate:update_points_of_interest_by_turn(mission_manager)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:update_state_through_turn_passing(mission_manager)
    end
end


--- Restores per-POI state from a previously saved campaign. New POIs added since the save are left at their fresh defaults.
--- @param zone_name string The region key for the zone being restored.
--- @param previous_state table Flattened save state previously produced for this zone.
--- @returns number The index of any POI flagged with an in-flight battle, or nil if none.
function PointOfInterestDelegate:reinstate_points_of_interest(zone_name, previous_state)
    local poi_index_triggered = nil
    for i=1, #self.points_of_interest do
        local poi_type = self.points_of_interest[i]:get_class()
        if poi_type == "SmithySpot" then
            local flattened_key = zone_name .. "_smithy_" .. tostring(self.points_of_interest[i].index)
            local is_battle_triggered = false
            if previous_state[flattened_key .. "_active"] ~= nil then
                is_battle_triggered = self.points_of_interest[i]:reinstate(flattened_key, previous_state)
            end
            if is_battle_triggered then
                poi_index_triggered = i
            end
        end
    end
    return poi_index_triggered
end

--- Constructs an empty PointOfInterestDelegate. Initialize is called separately to load the actual POIs.
--- @returns PointOfInterestDelegate A new empty delegate.
function PointOfInterestDelegate:new()
    local t = { }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Zone
--- (from models/zone.lua)

local Zone = {
    name = "Unknown",
    point_of_interest_delegate = {},
    spot_delegate = {}
}

--- Zone methods are thin wrappers that forward to the spot or POI delegate with the zone name attached.

--- Per-turn maintenance: ticks cooldowns and expires lifetime-exhausted spots.
function Zone:update_occupied_and_prohibited_spot_states()
    self.spot_delegate:update_occupied_and_prohibited_spot_states(self.name)
end


--- Adds new land encounters into the zone (up to the spawn-percentage cap).
function Zone:try_add_land_encounters()
    self.spot_delegate:try_add_land_encounters(self.name)
end


--- Restores per-zone spot state from a previously saved campaign.
--- @param previous_state table Flattened save state previously produced by export_state_as_a_table.
function Zone:reinstate_from_previous_state(previous_state)
    self.spot_delegate:reinstate_from_previous_state(self.name, previous_state)
end


--- Moves the spot at `spot_index` from active to cooldown and removes its on-map marker.
--- @param spot_index number The 1-based slot index for the spot.
function Zone:deactivate_spot_in_zone(spot_index)
    self.spot_delegate:deactivate_spot_in_zone(self.name, spot_index)
end


--- Initializes the zone's POIs (smithies / taverns / resources) from the configured coordinates.
--- @param points_of_interest_data table A keyed table with smithies, taverns, and resources arrays.
--- @param mctSettings table Live MCT settings forwarded to the POI delegate (legacy parameter, currently unused).
function Zone:initialize_points_of_interest(points_of_interest_data, mctSettings)
    self.point_of_interest_delegate:initialize(points_of_interest_data, mctSettings)
end


--- Ticks per-turn POI state updates.
--- @param mission_manager table The CA mission_manager handle forwarded to each POI.
function Zone:update_points_of_interest_by_turn(mission_manager)
    self.point_of_interest_delegate:update_points_of_interest_by_turn(mission_manager)
end


--- Activates the on-map markers for every POI in this zone.
function Zone:activate_points_of_interest()
    self.point_of_interest_delegate:activate_points_of_interest(self.name)
end


--- Restores per-POI state from a previously saved campaign.
--- @param previous_state table Flattened save state previously produced for this zone.
function Zone:reinstate_points_of_interest(previous_state)
    self.point_of_interest_delegate:reinstate_points_of_interest(self.name, previous_state)
end


--- Builds a Zone with its SpotDelegate and PointOfInterestDelegate.
--- @param zone_name string The region key for the zone.
--- @param zone_coordinates table An array of {x, y} coordinate pairs.
--- @param active_spot_percentage number Fraction (0..1) of spots that may be active at once.
--- @returns Zone A new Zone instance with both delegates initialized.
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
