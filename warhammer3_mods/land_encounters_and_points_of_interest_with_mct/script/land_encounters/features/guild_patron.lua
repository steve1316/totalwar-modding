--- The guilds' patrons. Every Tavern belongs to the Tavern Keepers' Guild and every Smithy to the Smiths' Association. A faction that makes a
--- guild a Generous Donation at one of its places raises every one of them on the map to the donation's level and gains a lasting blessing:
--- a faction bundle (the Guild's includes experience for every lord and hero each turn). A Guild patron also no longer pays the Guild's
--- surcharge after a failed or dropped contract. Each guild's donations come in order (`donations` in its config), each replacing the last
--- one's blessing. features/tavern.lua and features/smithy.lua offer the donations and save each guild's patrons with their places.

require("script/land_encounters/utils/common")

local tavern_data = require("script/land_encounters/configs/tavern_data")
local smithy_data = require("script/land_encounters/configs/smithy_data")

--- Each guild's donations, by guild key.
local DONATIONS = { tavern = tavern_data.donations, smithy = smithy_data.donations }

--- Incident key prefix of a donation's blessing, followed by the guild and the donation, e.g. land_enc_incident_tavern_patron_1. Its payload
--- carries the bundle, so the incident shows the bundle's card as it applies it. The event feed message of the same name is the fallback.
local INCIDENT_PREFIX = "land_enc_incident_"

--- Payload text prefix of a guild's donation choice. The guild key and "_donation_" follow, then which donation it is, or "done".
local DONATION_LINE_PREFIX = "dummy_land_enc_"

local M = {
    --- Guild key -> faction key -> how many donations it has made. A faction that made none is not listed.
    level_by_guild = { tavern = {}, smithy = {} },
}

--- How many donations a faction has made to a guild, 0 when none.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction key.
--- @returns number The donations made.
function M.level(guild, faction_name)
    return M.level_by_guild[guild][faction_name] or 0
end

--- The donation a faction can make to a guild next.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction key.
--- @returns table|nil The donation, or nil when it has made them all.
function M.next_donation(guild, faction_name)
    return DONATIONS[guild][M.level(guild, faction_name) + 1]
end

--- What a guild's donation choice offers a faction: its payload `line`, and the `price` with whether the treasury is `affordable`, or no
--- price once every donation is made.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction key.
--- @param treasury number The faction's treasury.
--- @returns table { line, price, affordable }.
function M.donation_offer(guild, faction_name, treasury)
    local prefix = DONATION_LINE_PREFIX .. guild .. "_donation_"
    local donation = M.next_donation(guild, faction_name)
    if donation == nil then return { line = prefix .. "done" } end
    return { line = prefix .. (M.level(guild, faction_name) + 1), price = donation.price, affordable = treasury >= donation.price }
end

--- True when a faction has made a guild a donation.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction key.
--- @returns boolean True for a patron.
function M.is_patron(guild, faction_name)
    return M.level(guild, faction_name) > 0
end

--- Gives a faction a donation's bundle for good through the donation's incident, whose card shows the bundle. When the incident cannot be
--- built, the bundle is applied directly and the donation's message shows instead.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction donating.
--- @param number number Which donation it is.
--- @param position table The { x, y } of the place it was made at, for the fallback message.
local function bless(guild, faction_name, number, position)
    local donation = DONATIONS[guild][number]
    local name = guild .. "_patron_" .. number
    local ok, err = pcall(function()
        local bundle = cm:create_new_custom_effect_bundle(donation.bundle)
        bundle:set_duration(0)
        local payload = cm:create_payload()
        payload:effect_bundle_to_faction(bundle)
        local builder = cm:create_incident_builder(INCIDENT_PREFIX .. name)
        builder:set_payload(payload)
        cm:launch_custom_incident_from_builder(builder, cm:get_faction(faction_name))
    end)
    if ok then
        log(guild .. ": " .. faction_name .. " is blessed with " .. donation.bundle .. " through its incident")
        return
    end
    log(guild .. ": the blessing incident could not be built (" .. tostring(err) .. "), so " .. donation.bundle .. " is applied directly")
    cm:apply_effect_bundle(donation.bundle, faction_name, 0)
    show_located_message(faction_name, name, position)
end

--- Makes a faction's next donation to a guild, whose price the dilemma's payload already charged: every one of the guild's places below the
--- donation's level rises to it, and the donation's bundle replaces the last one's.
--- @param guild string "tavern" or "smithy".
--- @param faction_name string The faction donating.
--- @param places table Every TavernState or SmithyState on the map.
--- @param position table The { x, y } of the place the donation was made at.
--- @returns table|nil The donation made, or nil when none was left.
function M.donate(guild, faction_name, places, position)
    local level = M.level(guild, faction_name)
    local donations = DONATIONS[guild]
    local donation = donations[level + 1]
    if donation == nil then return nil end
    if level > 0 then cm:remove_effect_bundle(donations[level].bundle, faction_name) end
    bless(guild, faction_name, level + 1, position)
    M.level_by_guild[guild][faction_name] = level + 1
    local raised = 0
    for _, place in ipairs(places) do
        if place.level < donation.place_level then
            place:set_level(donation.place_level)
            raised = raised + 1
        end
    end
    log(guild .. ": " .. faction_name .. " makes donation " .. (level + 1) .. " for " .. donation.price .. " gold: " .. raised .. " places rise to level "
        .. donation.place_level .. ", bundle " .. donation.bundle)
    return donation
end

--- At a faction's turn start, gives a patron back any blessing it is missing (lost, or never applied).
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(faction_name)
    local faction = cm:get_faction(faction_name)
    if not faction then return end
    for guild, donations in pairs(DONATIONS) do
        local level = M.level(guild, faction_name)
        if level > 0 and not faction:has_effect_bundle(donations[level].bundle) then
            cm:apply_effect_bundle(donations[level].bundle, faction_name, 0)
            log(guild .. ": " .. faction_name .. " was missing " .. donations[level].bundle .. ", so it is applied again")
        end
    end
end

--- Exports a guild's patrons for the save file.
--- @param guild string "tavern" or "smithy".
--- @returns table Faction key -> donations made.
function M.export_state(guild)
    return M.level_by_guild[guild]
end

--- Restores a guild's patrons from the save file. A save from before donations restores none.
--- @param guild string "tavern" or "smithy".
--- @param saved table|nil The saved state.
function M.restore_state(guild, saved)
    M.level_by_guild[guild] = saved or {}
end

return M
