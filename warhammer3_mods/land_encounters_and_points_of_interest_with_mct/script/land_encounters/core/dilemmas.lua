--- Custom dilemmas built in script: each choice shows text lines and can pay gold, items and units when chosen. Shared by the tower and the
--- treasure sites.

local M = {}

--- Launches a custom dilemma. Each choice shows text lines and can pay gold, items and units when chosen.
--- @param key string The dilemma key.
--- @param choices table An array of { key = "FIRST", lines = { `dummy_` keys }, gold = number or nil, items = { ancillary keys } or nil,
--- units = { force = military force, keys = { unit keys } } or nil }. Units show as cards and join that army.
--- @param faction_name string The faction to show the dilemma to.
function M.launch(key, choices, faction_name)
    local faction = cm:get_faction(faction_name)
    local builder = cm:create_dilemma_builder(key)
    local payload = cm:create_payload()
    for _, choice in ipairs(choices) do
        if choice.gold and choice.gold > 0 then
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

return M
