--- Item rewards. Draws from CA's runtime pool of randomly dropped ancillaries (`get_random_ancillary_key_for_faction` in
--- wh3_campaign_magic_items.lua), which covers every loaded mod and only returns items the faction can use.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local legendary_items = require("script/land_encounters/configs/legendary_items")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- How many times one item slot is re-rolled when CA's helper returns a duplicate, an owned item or nothing.
local MAX_ATTEMPTS_PER_ITEM = 5

--- Rarity weights for item rewards by encounter difficulty: harder fights drop rarer items. Each entry is {rarity, weight}.
local RARITY_WEIGHTS_BY_DIFFICULTY = {
    easy = { { "common", 50 }, { "uncommon", 40 }, { "rare", 10 } },
    medium = { { "uncommon", 60 }, { "rare", 40 } },
    hard = { { "rare", 100 } },
}

--- Environment of the LEAPOI mod entry script, set by `M.set_script_environment`. CA's campaign globals such as
--- `get_random_ancillary_key_for_faction` are visible there but not in the `_G` that required modules use.
local script_environment = nil

local M = {}

--- Remembers the environment of the mod entry script so CA's item helper can be found there.
--- @param environment table The entry script's `getfenv(1)`.
function M.set_script_environment(environment)
    script_environment = environment
end

--- Returns one of CA's campaign script functions, looking in this module's globals first and then in the mod entry script's environment.
--- @param name string The global function name, e.g. "get_random_ancillary_key_for_faction".
--- @returns function The function, or nil when neither has it.
local function ca_function(name)
    local helper = _G[name]
    if type(helper) ~= "function" and script_environment then
        helper = script_environment[name]
    end
    return type(helper) == "function" and helper or nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picking

--- Picks up to `count` distinct items the faction can use and does not already own. Each item rolls one rarity from `rarities`.
--- @param faction_key string The receiving faction's key.
--- @param rarities table An array of CA rarity keys ("common", "uncommon", "rare").
--- @param count number How many items to pick.
--- @returns table An array of ancillary keys. Shorter than `count` (or empty) when CA's pool runs dry or is unavailable.
function M.pick_items(faction_key, rarities, count)
    local random_ancillary = ca_function("get_random_ancillary_key_for_faction")
    if random_ancillary == nil then
        out("DEBUG - item_pool: CA's get_random_ancillary_key_for_faction is not loaded, so no item is given.")
        return {}
    end
    local faction = cm:get_faction(faction_key)
    local picked, seen = {}, {}
    for _ = 1, count do
        local found = false
        for _ = 1, MAX_ATTEMPTS_PER_ITEM do
            local key = random_ancillary(faction_key, nil, rarities[random_number(#rarities)])
            if key and not seen[key] and not (faction and faction:ancillary_exists(key)) then
                seen[key] = true
                table.insert(picked, key)
                found = true
                break
            end
        end
        --- A slot that found nothing means the pool is dry for these rarities, so later slots would fail the same way.
        if not found then break end
    end
    return picked
end

--- Picks one legendary item from configs/legendary_items.lua that the faction can use (CA's `ancillary_is_available_to_faction`), does not own,
--- and whose DLC it has. The scan starts at a random item so every client picks the same one.
--- @param faction_key string The receiving faction's key.
--- @returns string An ancillary key, or nil when no legendary item qualifies.
function M.pick_legendary_item(faction_key)
    local is_available = ca_function("ancillary_is_available_to_faction")
    local faction = cm:get_faction(faction_key)
    if is_available == nil or not faction then
        out("DEBUG - item_pool: no legendary item given (CA's ancillary_is_available_to_faction or the faction is missing).")
        return nil
    end
    local start = random_number(#legendary_items)
    for offset = 0, #legendary_items - 1 do
        local item = legendary_items[(start + offset - 1) % #legendary_items + 1]
        if not faction:ancillary_exists(item.key)
            and (item.dlc == nil or cm:faction_has_dlc_or_is_ai(item.dlc, faction_key))
            and is_available(item.key, faction_key) then
            return item.key
        end
    end
    return nil
end

--- Picks one item whose rarity is weighted by the encounter difficulty.
--- @param faction_key string The receiving faction's key.
--- @param difficulty string The difficulty key. Defaults to `get_current_difficulty()`.
--- @returns string An ancillary key, or nil when none could be picked.
function M.pick_item_for_difficulty(faction_key, difficulty)
    local rarity = pick_weighted(RARITY_WEIGHTS_BY_DIFFICULTY[difficulty or get_current_difficulty()])
    return M.pick_items(faction_key, { rarity }, 1)[1]
end

return M
