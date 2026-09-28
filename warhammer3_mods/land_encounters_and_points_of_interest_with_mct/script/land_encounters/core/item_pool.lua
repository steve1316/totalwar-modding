--- Item rewards. Draws from CA's runtime pool of randomly dropped ancillaries (`get_random_ancillary_key_for_faction` in
--- wh3_campaign_magic_items.lua), which covers every loaded mod and only returns items the faction can use.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

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

--- Returns CA's `get_random_ancillary_key_for_faction`, looking in this module's globals first and then in the mod entry script's environment.
--- @returns function The helper, or nil when neither has it.
local function ca_random_ancillary_helper()
    if type(get_random_ancillary_key_for_faction) == "function" then
        return get_random_ancillary_key_for_faction
    end
    local helper = script_environment and script_environment.get_random_ancillary_key_for_faction
    if type(helper) == "function" then
        return helper
    end
    return nil
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
    local random_ancillary = ca_random_ancillary_helper()
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

--- Picks one item whose rarity is weighted by the encounter difficulty.
--- @param faction_key string The receiving faction's key.
--- @param difficulty string The difficulty key. Defaults to `get_current_difficulty()`.
--- @returns string An ancillary key, or nil when none could be picked.
function M.pick_item_for_difficulty(faction_key, difficulty)
    local rarity = pick_weighted(RARITY_WEIGHTS_BY_DIFFICULTY[difficulty or get_current_difficulty()])
    return M.pick_items(faction_key, { rarity }, 1)[1]
end

return M
