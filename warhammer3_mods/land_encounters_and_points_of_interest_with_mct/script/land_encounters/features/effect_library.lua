--- Effect library (helper_scripts/generators/leapoi_effect_library.py): the debug hook that puts library bundles on the player's armies
--- for in-game checks, at each turn start and when a game loads. The enemy's side is put on in `InvasionBattleManager:weaken_invasion_force`
--- (core/managers.lua).

require("script/land_encounters/utils/common")

local debug_config = require("script/land_encounters/configs/debug")

local M = {}

--- Puts the debug `test_bundles` bundles on every army of a human faction, for 2 turns so they never lapse between turns.
--- @param faction faction The faction whose turn starts.
function M.apply_test_bundles(faction)
    if not debug_config.test_bundles[1] then return end
    local forces = faction:military_force_list()
    for i = 0, forces:num_items() - 1 do
        local force = forces:item_at(i)
        if not force:is_armed_citizenry() and force:has_general() then
            for _, bundle in ipairs(debug_config.test_bundles) do cm:apply_effect_bundle_to_force(bundle, force:command_queue_index(), 2) end
        end
    end
    log("effect library: debug test_bundles " .. table.concat(debug_config.test_bundles, ", ") .. " on " .. faction:name() .. "'s armies")
end

--- A new test build is live as soon as a save loads, without waiting for the next turn.
if debug_config.test_bundles[1] then
    cm:add_first_tick_callback(function()
        for _, faction_name in ipairs(cm:get_human_factions()) do M.apply_test_bundles(cm:get_faction(faction_name)) end
    end)
end

return M
