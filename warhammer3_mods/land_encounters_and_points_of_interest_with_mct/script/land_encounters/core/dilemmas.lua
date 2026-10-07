--- Custom dilemmas built in script: each choice shows text lines and can pay gold, items and units when chosen, and chosen buttons can be
--- greyed out. Shared by the tower, the treasure sites, the battle offers, the Taverns and the Smithy forge. Each launched dilemma registers
--- the choices to grey out and the prices to refund, by faction, until it is answered.

require("script/land_encounters/utils/common")

--- Prefix of each choice's row id in the dilemma panel's list, followed by the dilemma key and the choice key.
local CHOICE_ROW_PREFIX = "CcoCdirEventsDilemmaChoiceDetailRecord"

local M = {
    --- Faction key -> dilemma key -> the choice keys greyed out on that dilemma while it is open. Saved, so a reloaded panel is greyed too.
    closed_by_faction = {},
    --- Faction key -> dilemma key -> choice key -> the gold a greyed-out paid choice was charged by its price card, refunded when it is
    --- clicked anyway. Saved with the closed choices.
    refunds_by_faction = {},
}

--- The choice keys of a dilemma in order, as the DB names them.
M.CHOICE_KEYS = { "FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH" }

--- Sets or clears one dilemma's entry in a per-faction registry.
--- @param registry table `M.closed_by_faction` or `M.refunds_by_faction`.
--- @param faction_name string The faction key.
--- @param dilemma_key string The dilemma key.
--- @param value table|nil The entry, or nil to clear it.
local function set_entry(registry, faction_name, dilemma_key, value)
    if value == nil and registry[faction_name] == nil then return end
    registry[faction_name] = registry[faction_name] or {}
    registry[faction_name][dilemma_key] = value
end

--- Launches a custom dilemma. Each choice shows text lines and can pay gold, items and units when chosen. The choices marked `closed` or
--- `unaffordable` are registered to be greyed out once the panel opens, and an unaffordable choice's price card is registered for `M.refund`.
--- @param key string The dilemma key.
--- @param choices table An array of { key = "FIRST", lines = { `dummy_` keys }, gold = number or nil (paid when positive, charged when
--- negative), items = { ancillary keys } or nil, units = { force = military force, keys = { unit keys } } or nil, lines_first = true to show
--- the lines before the item and unit cards, closed = true to grey it out, unaffordable = true to grey it out and refund its negative `gold`
--- when it is clicked anyway }. Units show as cards and join that army.
--- @param faction_name string The faction to show the dilemma to.
function M.launch(key, choices, faction_name)
    local faction = cm:get_faction(faction_name)
    local builder = cm:create_dilemma_builder(key)
    local payload = cm:create_payload()
    local closed, refunds = {}, {}
    --- Adds a choice's text lines to the payload.
    --- @param choice table The choice record.
    local function add_lines(choice)
        for _, line in ipairs(choice.lines or {}) do
            payload:text_display(line)
        end
    end
    for _, choice in ipairs(choices) do
        if choice.gold and choice.gold ~= 0 then
            payload:treasury_adjustment(choice.gold)
        end
        if choice.lines_first then add_lines(choice) end
        for _, item in ipairs(choice.items or {}) do
            payload:faction_ancillary_gain(faction, item)
        end
        if choice.units then
            --- One card per unit key, with the number of copies, in the order the units were sworn.
            local counts, order = {}, {}
            for _, unit in ipairs(choice.units.keys) do
                if not counts[unit] then order[#order + 1] = unit end
                counts[unit] = (counts[unit] or 0) + 1
            end
            for _, unit in ipairs(order) do
                payload:add_unit(choice.units.force, unit, counts[unit], 0)
            end
        end
        if not choice.lines_first then add_lines(choice) end
        builder:add_choice_payload(choice.key, payload)
        payload:clear()
        if choice.closed or choice.unaffordable then closed[#closed + 1] = choice.key end
        if choice.unaffordable and (choice.gold or 0) < 0 then refunds[choice.key] = -choice.gold end
    end
    set_entry(M.closed_by_faction, faction_name, key, #closed > 0 and closed or nil)
    set_entry(M.refunds_by_faction, faction_name, key, next(refunds) and refunds or nil)
    cm:launch_custom_dilemma_from_builder(builder, faction)
end

--- Finds the slot a choice key belongs to, for a dilemma built from slots (records with a `choice` key and an `ok` flag).
--- @param slots table The slots the dilemma showed.
--- @param choice_key string The chosen choice key.
--- @returns table|nil The slot, or nil when no slot has that key (Back, or a choice of another dilemma).
function M.find_slot(slots, choice_key)
    for _, slot in ipairs(slots) do
        if slot.choice == choice_key then return slot end
    end
    return nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Refunds

--- Hands back the price a greyed-out paid choice was charged by its payload when it is clicked anyway. The dilemma's refunds are forgotten
--- either way, since it has been answered. Each feature calls this as it resolves the choice, before it reopens anything.
--- @param faction_name string The faction that chose.
--- @param dilemma_key string The answered dilemma's key.
--- @param choice_key string The chosen choice key.
--- @returns number|nil The gold refunded, or nil when the choice had nothing to refund.
function M.refund(faction_name, dilemma_key, choice_key)
    local refunds = (M.refunds_by_faction[faction_name] or {})[dilemma_key]
    if refunds == nil then return nil end
    set_entry(M.refunds_by_faction, faction_name, dilemma_key, nil)
    local gold = refunds[choice_key]
    if gold == nil then return nil end
    cm:treasury_mod(faction_name, gold)
    log("dilemmas: " .. faction_name .. " chose " .. tostring(choice_key) .. " on " .. dilemma_key .. " without the gold, so " .. gold .. " is refunded")
    return gold
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Greying out

--- The choice keys registered to be greyed out on a faction's open dilemma.
--- @param faction_name string The faction key.
--- @param dilemma_key string The dilemma key.
--- @returns table The choice keys, empty when none are registered.
function M.closed_choices(faction_name, dilemma_key)
    return (M.closed_by_faction[faction_name] or {})[dilemma_key] or {}
end

--- Greys out choice buttons on the open dilemma panel, so each keeps its slot but cannot be clicked. UI only: the local player's panel is
--- changed, and a greyed choice clicked anyway still reaches the script.
--- @param dilemma_key string The open dilemma's key.
--- @param choice_keys table The choice keys to grey out.
function M.grey_out(dilemma_key, choice_keys)
    if #choice_keys == 0 then return end
    local rows = {}
    for _, choice_key in ipairs(choice_keys) do rows[CHOICE_ROW_PREFIX .. dilemma_key .. choice_key] = true end
    --- The game's UI helpers live in the script environment, not in a required module's globals.
    local env = core:get_env()
    local list = env.find_uicomponent(core:get_ui_root(), "events", "event_layouts", "dilemma_active", "dilemma", "background", "dilemma_list")
    if not list then return end
    for i = 0, list:ChildCount() - 1 do
        local row = env.UIComponent(list:Find(i))
        local button = rows[row:Id()] and env.find_uicomponent(row, "choice_button")
        if button then
            button:SetState("inactive")
            button:SetDisabled(true)
        end
    end
end

--- Greys out the registered choices of every dilemma a faction has open. Only the open panel's rows match, since each row id names its
--- dilemma.
--- @param faction_name string The local player's faction.
function M.grey_out_open(faction_name)
    for dilemma_key, choice_keys in pairs(M.closed_by_faction[faction_name] or {}) do
        M.grey_out(dilemma_key, choice_keys)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Saves

--- Exports the registered closed choices and refunds for the save file.
--- @returns table { closed_by_faction, refunds_by_faction }.
function M.export_state()
    return { closed_by_faction = M.closed_by_faction, refunds_by_faction = M.refunds_by_faction }
end

--- Restores the state saved by `M.export_state`, from the load callback. A save from before the registry restores nothing.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.closed_by_faction = saved.closed_by_faction or {}
    M.refunds_by_faction = saved.refunds_by_faction or {}
end

return M
