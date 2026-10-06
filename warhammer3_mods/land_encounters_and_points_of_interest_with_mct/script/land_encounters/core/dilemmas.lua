--- Custom dilemmas built in script: each choice shows text lines and can pay gold, items and units when chosen, and chosen buttons can be
--- greyed out. Shared by the tower, the treasure sites and the battle offers.

--- Prefix of each choice's row id in the dilemma panel's list, followed by the dilemma key and the choice key.
local CHOICE_ROW_PREFIX = "CcoCdirEventsDilemmaChoiceDetailRecord"

local M = {}

--- The choice keys of a dilemma in order, as the DB names them.
M.CHOICE_KEYS = { "FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH" }

--- Launches a custom dilemma. Each choice shows text lines and can pay gold, items and units when chosen.
--- @param key string The dilemma key.
--- @param choices table An array of { key = "FIRST", lines = { `dummy_` keys }, gold = number or nil (paid when positive, charged when
--- negative), items = { ancillary keys } or nil, units = { force = military force, keys = { unit keys } } or nil }. Units show as cards and
--- join that army.
--- @param faction_name string The faction to show the dilemma to.
function M.launch(key, choices, faction_name)
    local faction = cm:get_faction(faction_name)
    local builder = cm:create_dilemma_builder(key)
    local payload = cm:create_payload()
    for _, choice in ipairs(choices) do
        if choice.gold and choice.gold ~= 0 then
            payload:treasury_adjustment(choice.gold)
        end
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
        for _, line in ipairs(choice.lines or {}) do
            payload:text_display(line)
        end
        builder:add_choice_payload(choice.key, payload)
        payload:clear()
    end
    cm:launch_custom_dilemma_from_builder(builder, faction)
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

return M
