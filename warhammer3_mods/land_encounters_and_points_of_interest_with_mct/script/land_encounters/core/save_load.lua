--- Registers cm:add_saving_game_callback and cm:add_loading_game_callback for the mod's
--- three state blobs: land manager, POI event manager, and spot event manager. Manager
--- references are populated by the entry point's pre_first_tick_callback.

require("script/land_encounters/utils/common")

local FLATTENED_LAND_MANAGER_LAND_STATE = "flattened_land_encounters_land_manager_state"
local FLATTENED_POI_EVENT_STATE = "flattened_land_encounters_poi_event_manager_state"
local FLATTENED_SPOT_EVENT_STATE = "flattened_land_encounters_spot_event_manager_state"
local DEFAULT_FLATTENED_SPOTS_VALUE = {}

local M = {}

--- Populated by the entry point's pre_first_tick_callback after the manager instances are created.
M.land_manager = nil
M.point_of_interest_event_manager = nil
M.spot_event_manager = nil

--- Set by the load callback, read by the entry point's first_tick to decide bootstrap vs restore.
M.saved_land_encounters_state = {}
M.saved_spot_event_state = {}
M.saved_poi_event_state = {}

--- Wires up the save and load callbacks. Called once at module load by the entry point.
function M.register()
    --- Save: write each manager's flattened state into the save file.
    cm:add_saving_game_callback(
        function(context)
            cm:save_named_value(FLATTENED_LAND_MANAGER_LAND_STATE, M.land_manager:export_state_as_a_table(), context)
            cm:save_named_value(FLATTENED_POI_EVENT_STATE, M.point_of_interest_event_manager:export_state_as_table(), context)
            cm:save_named_value(FLATTENED_SPOT_EVENT_STATE, M.spot_event_manager:export_state_as_a_table(), context)
        end
    )

    --- Load: stash the saved blobs on M so the entry point's first_tick can read them.
    cm:add_loading_game_callback(
        function(context)
            M.saved_land_encounters_state = cm:load_named_value(FLATTENED_LAND_MANAGER_LAND_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
            M.saved_poi_event_state = cm:load_named_value(FLATTENED_POI_EVENT_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
            M.saved_spot_event_state = cm:load_named_value(FLATTENED_SPOT_EVENT_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
        end
    )
end

return M
