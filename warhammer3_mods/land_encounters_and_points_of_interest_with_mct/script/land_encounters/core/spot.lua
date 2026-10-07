--- All spot classes for the mod: the abstract Spot base, EventSpot (random encounter),
--- SmithySpot, TowerSpot, SpotDelegate, PointOfInterestDelegate, and the Zone aggregate. TavernSpot holds the Tavern marker helpers.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

--- Smithy marker skin per forge level (1-3). Level 1 keeps the original key so markers from older saves stay valid.
local SMITHY_MARKER_KEY_BY_LEVEL = { "encounter_marker_smithy", "encounter_marker_smithy_level_2", "encounter_marker_smithy_level_3" }

--- Interaction radius of smithy markers.
local SMITHY_MARKER_RADIUS = 3

--- Interaction radius of battle and treasure spot markers.
local ENCOUNTER_MARKER_RADIUS = 2.5

--- Marker skin shared by every tower.
local TOWER_MARKER_KEY = "encounter_marker_tower"

--- Interaction radius of tower markers, kept tight around the tower model.
local TOWER_MARKER_RADIUS = 2.5

--- Marker key per Tavern level (index = level). Each skin's tooltip states the level.
local TAVERN_MARKER_KEY_BY_LEVEL = { "encounter_marker_tavern", "encounter_marker_tavern_level_2", "encounter_marker_tavern_level_3" }

--- Interaction radius of a Tavern marker, the same as a Smithy's.
local TAVERN_MARKER_RADIUS = 3

--- Replaces a marker with the skin for a level, for points of interest whose marker changes with their level (Smithies and Taverns).
--- @param marker_id string The marker id.
--- @param keys_by_level table The marker key per level.
--- @param coordinates table The {x, y} position.
--- @param level number The level.
--- @param radius number The interaction radius.
local function replace_levelled_marker(marker_id, keys_by_level, coordinates, level, radius)
    cm:remove_interactable_campaign_marker(marker_id)
    cm:add_interactable_campaign_marker(marker_id, keys_by_level[level], coordinates[1], coordinates[2], radius, "", "")
end

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
    marker_id = "",
    --- True when the coordinate entry is marked `disabled = true`. A disabled spot keeps its index (towers and marker ids use it) but never
    --- becomes an encounter or a new tower.
    disabled = false,
    --- True when the coordinate entry is marked `tower = true`: the zone's new tower stands here instead of on a random spot.
    tower_site = false
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
    self.disabled = lat_lng.disabled == true
    self.tower_site = lat_lng.tower == true
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
    local interaction_radius = ENCOUNTER_MARKER_RADIUS
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

--- Returns the marker id of a smithy.
--- @param zone_name string The region key for the zone the smithy belongs to.
--- @param index number The 1-based smithy slot in the zone.
--- @returns string The marker id.
function SmithySpot.marker_id(zone_name, index)
    return "land_enc_marker_" .. zone_name .. "_smithy_" .. index
end

--- Replaces a smithy's marker with the skin for its forge level.
--- @param zone_name string The region key for the zone the smithy belongs to.
--- @param index number The 1-based smithy slot in the zone.
--- @param coordinates table The smithy's {x, y} position.
--- @param level number The forge level (1-3).
function SmithySpot.replace_marker(zone_name, index, coordinates, level)
    replace_levelled_marker(SmithySpot.marker_id(zone_name, index), SMITHY_MARKER_KEY_BY_LEVEL, coordinates, level, SMITHY_MARKER_RADIUS)
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
--- @returns SmithySpot The same instance with its metatable replaced.
function SmithySpot:new_from_coordinates(old_spot)
    SmithySpot.__index = SmithySpot
    setmetatable(SmithySpot, {__index = Spot})
    local t = old_spot
    setmetatable(t, SmithySpot)
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TavernSpot

--- Marker helpers for Taverns. A Tavern's state lives in features/tavern.lua, keyed by its slot in its zone's `taverns` list, so its marker is
--- keyed by that slot too.
local TavernSpot = {}

--- Returns the marker id of a Tavern.
--- @param zone_name string The region key for the zone the Tavern stands in.
--- @param index number The 1-based Tavern slot in the zone.
--- @returns string The marker id.
function TavernSpot.marker_id(zone_name, index)
    return "land_enc_marker_" .. zone_name .. "_tavern_" .. index
end

--- Replaces a Tavern's marker with the skin for its level.
--- @param zone_name string The region key for the zone the Tavern stands in.
--- @param index number The 1-based Tavern slot in the zone.
--- @param coordinates table The Tavern's {x, y} position.
--- @param level number The Tavern level (1-3).
function TavernSpot.replace_marker(zone_name, index, coordinates, level)
    replace_levelled_marker(TavernSpot.marker_id(zone_name, index), TAVERN_MARKER_KEY_BY_LEVEL, coordinates, level, TAVERN_MARKER_RADIUS)
end

--- Removes a Tavern's marker from the campaign map.
--- @param zone_name string The region key for the zone the Tavern stands in.
--- @param index number The 1-based Tavern slot in the zone.
function TavernSpot.remove_marker(zone_name, index)
    cm:remove_interactable_campaign_marker(TavernSpot.marker_id(zone_name, index))
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerSpot

--- Marker helpers for towers. A tower sits on one of its zone's encounter spots, so its marker is keyed by that spot's index.
local TowerSpot = {}

--- Returns the marker id of a tower.
--- @param zone_name string The region key for the zone the tower stands in.
--- @param spot_index number The index of the encounter spot the tower occupies.
--- @returns string The marker id.
function TowerSpot.marker_id(zone_name, spot_index)
    return "land_enc_marker_" .. zone_name .. "_tower_" .. spot_index
end

--- Places a tower's marker on the campaign map, replacing any marker already under that id.
--- @param zone_name string The region key for the zone the tower stands in.
--- @param spot_index number The index of the encounter spot the tower occupies.
--- @param coordinates table The tower's {x, y} position.
function TowerSpot.place_marker(zone_name, spot_index, coordinates)
    local marker_id = TowerSpot.marker_id(zone_name, spot_index)
    cm:remove_interactable_campaign_marker(marker_id)
    cm:add_interactable_campaign_marker(marker_id, TOWER_MARKER_KEY, coordinates[1], coordinates[2], TOWER_MARKER_RADIUS, "", "")
end

--- Removes a tower's marker from the campaign map.
--- @param zone_name string The region key for the zone the tower stands in.
--- @param spot_index number The index of the encounter spot the tower occupies.
function TowerSpot.remove_marker(zone_name, spot_index)
    cm:remove_interactable_campaign_marker(TowerSpot.marker_id(zone_name, spot_index))
end

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
    --- Spot indexes held by a tower. They never activate as encounters. Rebuilt from tower state on every load, so not saved here.
    reserved_spots = {},
    --- Indexes of the zone's spots that are not marked `disabled = true`, in order. Encounters, towers and tower battlefields only use these.
    enabled_indexes = {},
    --- The enabled spots marked `tower = true`, in order. A new tower picks among these when there are any.
    tower_sites = {},

    max_active_spots_count = 0
}


--- True while the zone has room for more active land encounters under its spawn-percentage cap.
--- `active_spots` is keyed by spot index with gaps, so it is counted with `Count_keys` rather than the `#` length operator.
--- @returns boolean True when the active-spot count is below the cap.
function SpotDelegate:can_add_land_encounters()
    return self.max_active_spots_count > Count_keys(self.active_spots)
end

--- Walks the zone's enabled spots in random order and activates inactive ones until the active cap is hit.
--- @param zone_name string The region key used to build marker ids.
function SpotDelegate:try_add_land_encounters(zone_name)
    --- The shuffle works in place, so it gets a copy.
    local disordered_indexes = {}
    for i, index in ipairs(self.enabled_indexes) do disordered_indexes[i] = index end
    randomic_shuffle(disordered_indexes)
    for i= 1, #disordered_indexes do
        --- Stop once the active-spot cap is reached.
        if not self:can_add_land_encounters() then
            log("Cannot add more land encounter")
            break
        end

        --- Skip indexes that are currently active or in cooldown.
        local candidate_spot_to_activate_index = disordered_indexes[i]
        local is_free = self.prohibited_spots[candidate_spot_to_activate_index] == nil and self.active_spots[candidate_spot_to_activate_index] == nil
        if is_free and not self.reserved_spots[candidate_spot_to_activate_index] then
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


--- Holds a spot for a tower. An encounter already active there is removed first.
--- @param zone_name string The region key for the zone this spot belongs to.
--- @param spot_index number The 1-based slot index for the spot.
function SpotDelegate:reserve_spot(zone_name, spot_index)
    if self.active_spots[spot_index] then
        self:deactivate_spot_in_zone(zone_name, spot_index)
    end
    self.reserved_spots[spot_index] = true
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
            --- A spot disabled since this save was made loses its encounter and marker.
            if self.spots[i].disabled and self.active_spots[i] and self.spots[i].deactivate then
                log("Removing the encounter on disabled spot " .. zone_name .. "[" .. i .. "]")
                self:deactivate_spot_in_zone(zone_name, i)
            end
        end
        --- Spot state is saved by coordinates, so a spot moved in coordinates.lua since the save starts fresh. Its old marker, saved by the
        --- game under the spot's index, would stay at the old position, so every spot that is not active loses its marker. Towers and
        --- smithies use their own marker ids.
        if not self.active_spots[i] then
            cm:remove_interactable_campaign_marker("land_enc_marker_" .. zone_name .. "_" .. i)
        end
    end
end


--- Builds a SpotDelegate over the given zone coordinates. `active_spot_percentage` caps how
--- many of the zone's spots can be active at once.
--- @param zone_coordinates table An array of {x, y} coordinate pairs, some marked `disabled = true`.
--- @param active_spot_percentage number Fraction (0..1) of the zone's enabled spots that may be active at once.
--- @returns SpotDelegate A new delegate with one Spot per coordinate.
function SpotDelegate:new(zone_coordinates, active_spot_percentage)
    local zone_spots, enabled_indexes, tower_sites = {}, {}, {}
    for i = 1, #zone_coordinates do
        local spot = Spot:new()
        spot:initialize_from_coordinates(i, zone_coordinates[i])
        table.insert(zone_spots, spot)
        if not spot.disabled then
            enabled_indexes[#enabled_indexes + 1] = i
            if spot.tower_site then tower_sites[#tower_sites + 1] = i end
        end
    end

    local t = {
        spots = zone_spots,
        active_spots = {},
        prohibited_spots = {},
        reserved_spots = {},
        enabled_indexes = enabled_indexes,
        tower_sites = tower_sites,
        max_active_spots_count = active_spot_percentage * #enabled_indexes
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

--- Initializes the POI table from the configs (smithies). Taverns keep their state in features/tavern.lua, so this list holds
--- smithies only and a smithy's marker index stays its slot. Smithy spots always exist, so a smithy marker left in a save still resolves.
--- Whether their markers show follows the Enable Smithies setting, see `SmithyEventDelegate:sync_markers`. A zone, or a list in it, that
--- coordinates.lua leaves out counts as empty: the spot map only writes the lists it fills.
--- @param points_of_interest_data table A keyed table with smithies and taverns arrays, or nil for a zone with none.
function PointOfInterestDelegate:initialize(points_of_interest_data)
    local data = points_of_interest_data or {}
    self:initialize_smithies(data["smithies"] or {})
end

--- Creates a SmithySpot for each entry in `smithies_data`. Smithy ownership lives in features/smithy.lua.
--- @param smithies_data table An array of { coordinates, initial_owner, owner_if_player } records.
function PointOfInterestDelegate:initialize_smithies(smithies_data)
    self.points_of_interest = {}
    if #smithies_data > 0 then
        for i=1, #smithies_data do
            local spot = Spot:new()
            spot:initialize_from_coordinates(i, smithies_data[i].coordinates)
            local smithy = SmithySpot:new_from_coordinates(spot)
            table.insert(self.points_of_interest, smithy)
        end
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


--- Initializes the zone's POIs (smithies) from the configured coordinates.
--- @param points_of_interest_data table A keyed table with smithies and taverns arrays.
function Zone:initialize_points_of_interest(points_of_interest_data)
    self.point_of_interest_delegate:initialize(points_of_interest_data)
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
    EventSpot = EventSpot,
    SmithySpot = SmithySpot,
    TavernSpot = TavernSpot,
    TowerSpot = TowerSpot,
    SpotDelegate = SpotDelegate,
    PointOfInterestDelegate = PointOfInterestDelegate,
    Zone = Zone,
}
