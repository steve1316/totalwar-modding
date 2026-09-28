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

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picking

--- Picks up to `count` distinct items the faction can use and does not already own. Each item rolls one rarity from `rarities`.
--- @param faction_key string The receiving faction's key.
--- @param rarities table An array of CA rarity keys ("common", "uncommon", "rare").
--- @param count number How many items to pick.
--- @returns table An array of ancillary keys. Shorter than `count` (or empty) when CA's pool runs dry or is unavailable.
function M.pick_items(faction_key, rarities, count)
    if type(get_random_ancillary_key_for_faction) ~= "function" then
        out("DEBUG - item_pool: CA's get_random_ancillary_key_for_faction is not loaded, so no item is given.")
        return {}
    end
    local faction = cm:get_faction(faction_key)
    local picked, seen = {}, {}
    for _ = 1, count do
        for _ = 1, MAX_ATTEMPTS_PER_ITEM do
            local key = get_random_ancillary_key_for_faction(faction_key, nil, rarities[random_number(#rarities)])
            if key and not seen[key] and not (faction and faction:ancillary_exists(key)) then
                seen[key] = true
                table.insert(picked, key)
                break
            end
        end
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
