--- Builds the guide text the MCT pages show, from the same configs and loc text the game uses, so a guide never drifts from what a feature does.
--- Loaded by the MCT anchor in every game mode, so it only reads pure-data configs and loc.

local guides = require("script/land_encounters/configs/mct_guides")
local tower_offers = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local battle_categories = require("script/land_encounters/configs/battle_categories")
local smithy_data = require("script/land_encounters/configs/smithy_data")
local tavern_data = require("script/land_encounters/configs/tavern_data")
local spot_offers = require("script/land_encounters/configs/spot_offers")
local archetypes = require("script/land_encounters/configs/archetypes")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Loc key prefix of an offer line's text. The line key follows.
local LINE_LOC_PREFIX = "campaign_payload_ui_details_description_"

--- Loc key prefix of a tower offer's choice name on the floor 1 go-deeper dilemma. The offer's upper-case key follows it. Every offer has a
--- choice on that dilemma.
local OFFER_NAME_PREFIX = "cdir_events_dilemma_choice_details_localised_choice_label_land_enc_dilemma_tower_deeper_floor_1LEAPOI_TWR_"

--- Loc key prefix of a spot offer's choice name on the first treasure site's dilemma and on the first battle category's neutral dilemma. The
--- offer's choice key follows it. Every site offer has a choice on every site dilemma, and every battle pool offer on every battle dilemma.
local CHOICE_LABEL_PREFIX = "cdir_events_dilemma_choice_details_localised_choice_label_"
local SITE_OFFER_NAME_PREFIX = CHOICE_LABEL_PREFIX .. spot_offers.dilemma_prefix .. spot_offers.sites[1].key
local BATTLE_OFFER_NAME_PREFIX = CHOICE_LABEL_PREFIX .. battle_categories.list[1].neutral.dilemma

--- Loc key prefix of a dilemma's title.
local DILEMMA_TITLE_PREFIX = "dilemmas_localised_title_"

--- Name of each battle category tier (1-4).
local TIER_NAMES = { "common", "uncommon", "rare", "very rare" }

--- Name of each forced battle type. A category without one uses any battle type enabled on this page.
local BATTLE_TYPE_NAMES = { ambush = "ambush", interception = "interception", allied = "allied reinforcements" }

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Reads a loc string, falling back to the key itself so a missing string shows up in the guide instead of a blank line.
--- @param key string The loc key.
--- @returns string The localised text, or `key` when it has none.
local function loc(key)
    local text = common.get_localised_string(key)
    if text == nil or text == "" then return key end
    return text
end

--- Joins words as "a", "a or b", or "a, b or c".
--- @param words table The words to join.
--- @param conjunction string The last joining word, e.g. "or".
--- @returns string The joined words.
local function join_words(words, conjunction)
    if #words <= 1 then return words[1] or "" end
    return table.concat(words, ", ", 1, #words - 1) .. " " .. conjunction .. " " .. words[#words]
end

--- Puts "a" or "an" before a phrase.
--- @param phrase string The phrase.
--- @returns string The phrase with its article.
local function with_article(phrase)
    return (phrase:match("^[aeiou]") and "an " or "a ") .. phrase
end

--- Names the items a reward gives, e.g. "2 common or uncommon items".
--- @param count number How many items.
--- @param rarities table CA rarity keys the items roll from.
--- @returns string The item phrase.
local function items_phrase(count, rarities)
    return count .. " " .. join_words(rarities, "or") .. (count == 1 and " item" or " items")
end

--- Writes a guide line with its name highlighted.
--- @param name string The highlighted name.
--- @param text string The rest of the line.
--- @returns string The line.
local function guide_line(name, text)
    return "[[col:yellow]]" .. name .. "[[/col]]: " .. text
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Guides

--- Builds the Towers page guide on how towers work: the intro, then one line per floor with its difficulty and rewards.
--- @returns string The guide text.
function M.towers_text()
    local lines = { guides.towers_intro, "" }
    for number, floor in ipairs(tower_data.floors) do
        local rewards = { floor.gold .. " gold" }
        if floor.legendary_count then
            table.insert(rewards, floor.legendary_count .. " legendary items")
        elseif floor.item_count then
            table.insert(rewards, items_phrase(floor.item_count, floor.item_rarities))
        end
        if floor.sworn_units > 0 then table.insert(rewards, floor.sworn_units .. " sworn units") end
        if floor.freed_hero_rank then table.insert(rewards, "a freed rank " .. floor.freed_hero_rank .. " hero") end
        local name = number == #tower_data.floors and "The Master's floor" or "Floor " .. number
        lines[#lines + 1] = guide_line(name, floor.difficulty .. ", " .. join_words(rewards, "and") .. ".")
    end
    return table.concat(lines, "\n")
end

--- Builds the Towers page offer sections in page order: each lists the name and description of its offers, as the go-deeper dilemma shows
--- them. An offer whose text changes per floor shows its floor 1 text.
--- @returns table An array of { key, title, text }.
function M.tower_offer_sections()
    local lines_by_section = {}
    for _, offer in ipairs(tower_offers.offers) do
        local lines = lines_by_section[offer.guide_section] or {}
        lines[#lines + 1] = guide_line(loc(OFFER_NAME_PREFIX .. offer.key:upper()), loc(LINE_LOC_PREFIX .. tower_offers.line(offer.key, "easy", 1)))
        lines_by_section[offer.guide_section] = lines
    end
    local sections = {}
    for _, section in ipairs(guides.tower_offer_sections) do
        sections[#sections + 1] = { key = section.key, title = section.title, text = table.concat(lines_by_section[section.key] or {}, "\n") }
    end
    return sections
end

--- Builds the Encounters page battle spot guide: the intro, then one line per battle category with its rarity, army, battle type and reward.
--- @returns string The guide text.
function M.battle_spots_text()
    local lines = { guides.battle_spots_intro, "" }
    for _, category in ipairs(battle_categories.list) do
        local army_names = {}
        for _, key in ipairs(category.archetypes) do army_names[#army_names + 1] = archetypes.by_key[key].text:lower() end
        local facts = {
            category.guide,
            "Rarity: " .. TIER_NAMES[category.tier] .. ". Fights " .. with_article(join_words(army_names, "or")) .. " army with "
                .. math.floor(category.budget_multiplier * 100 + 0.5) .. "% of the difficulty's gold budget.",
        }
        if category.min_difficulty then facts[#facts + 1] = "Always at least " .. category.min_difficulty .. " difficulty." end
        if category.ally then
            facts[#facts + 1] = "Only appears while " .. BATTLE_TYPE_NAMES[category.intervention] .. " battles are enabled."
        elseif category.intervention then
            facts[#facts + 1] = "Fought as " .. BATTLE_TYPE_NAMES[category.intervention] .. " when that is enabled."
        end
        if category.victory_items then
            facts[#facts + 1] = "Winning adds " .. items_phrase(category.victory_items.count, category.victory_items.rarities) .. "."
        end
        lines[#lines + 1] = guide_line(category.text, table.concat(facts, " "))
    end
    return table.concat(lines, "\n")
end

--- Names a spot offer as its dilemma choice shows it.
--- @param offer table The offer record.
--- @returns string The offer's name.
local function spot_offer_name(offer)
    local prefix = spot_offers.battle_pools[offer.pool] and BATTLE_OFFER_NAME_PREFIX or SITE_OFFER_NAME_PREFIX
    return loc(prefix .. spot_offers.choice_key_prefix .. offer.key:upper())
end

--- Builds the Encounters page treasure site guide: the intro, then each site's title and the special offer it always shows.
--- @returns string The guide text.
function M.treasure_spots_text()
    local lines = { guides.treasure_spots_intro, "" }
    for _, site in ipairs(spot_offers.sites) do
        local special = spot_offers.by_key[site.signature]
        lines[#lines + 1] = guide_line(loc(DILEMMA_TITLE_PREFIX .. spot_offers.dilemma_prefix .. site.key), "always offers " .. spot_offer_name(special) .. ".")
    end
    return table.concat(lines, "\n")
end

--- Builds the Encounters page spot offer sections in page order: each lists the name and Easy line of every offer in its pool, as the
--- dilemmas show them.
--- @returns table An array of { key, title, text }.
function M.spot_offer_sections()
    local lines_by_pool = {}
    for _, offer in ipairs(spot_offers.offers) do
        local lines = lines_by_pool[offer.pool] or {}
        lines[#lines + 1] = guide_line(spot_offer_name(offer), loc(LINE_LOC_PREFIX .. spot_offers.line_prefix .. offer.key .. "_easy"))
        lines_by_pool[offer.pool] = lines
    end
    local sections = {}
    for _, section in ipairs(guides.spot_offer_sections) do
        sections[#sections + 1] = { key = section.key, title = section.title, text = table.concat(lines_by_pool[section.key] or {}, "\n") }
    end
    return sections
end

--- Builds the Smithies page guide: the intro, then one line per forge level with its free picks, cooldown, commission and upgrade price.
--- @returns string The guide text.
function M.smithy_text()
    local lines = { guides.smithy_intro, "" }
    for number, level in ipairs(smithy_data.levels) do
        local facts = { "free picks of " .. join_words(level.free_pick_rarities, "or") .. " items" }
        if level.cooldown_offset > 0 then facts[#facts + 1] = level.cooldown_offset .. " extra cooldown turns" end
        facts[#facts + 1] = "a commission of " .. items_phrase(level.commission.count, level.commission.rarities) .. " for " .. level.commission.price .. " gold"
        if level.legendary_commission then facts[#facts + 1] = "a legendary item for " .. level.legendary_commission.price .. " gold" end
        if level.upgrade_price then facts[#facts + 1] = "upgrades for " .. level.upgrade_price .. " gold" end
        lines[#lines + 1] = guide_line("Level " .. number, join_words(facts, "and") .. ".")
    end
    return table.concat(lines, "\n")
end

--- Builds the Taverns page guide: the intro, each level's mercenary hall and what it costs to reach the next, then the name and level 1 line
--- of every bar offer.
--- @returns string The guide text.
function M.taverns_text()
    local lines = { guides.tavern_intro, "" }
    for number, level in ipairs(tavern_data.levels) do
        local hall = level.hall
        local stock = { hall.units .. " units of tiers " .. hall.tiers[1] .. "-" .. hall.tiers[#hall.tiers] }
        if hall.renown[2] > 0 then
            stock[#stock + 1] = (hall.renown[1] == hall.renown[2] and hall.renown[1] or hall.renown[1] .. "-" .. hall.renown[2]) .. (hall.renown[2] == 1 and " famous regiment" or " famous regiments")
        end
        if hall.hero_rank then stock[#stock + 1] = "a rank " .. hall.hero_rank .. " hero" end
        stock[#stock + 1] = hall.own .. " of your own kind"
        local upgrade = level.upgrade_price and ("Upgrades to level " .. (number + 1) .. " for " .. level.upgrade_price .. " gold.") or "This is the top level."
        lines[#lines + 1] = guide_line("Level " .. number, "the hall hires out " .. join_words(stock, "and") .. ". " .. upgrade)
    end
    lines[#lines + 1] = ""
    for _, offer in ipairs(spot_offers.offers) do
        if offer.pool == "tavern" then
            lines[#lines + 1] = guide_line(spot_offer_name(offer), loc(LINE_LOC_PREFIX .. spot_offers.line_prefix .. offer.key .. "_easy"))
        end
    end
    return table.concat(lines, "\n")
end

return M
