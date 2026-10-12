-- Iron Scorpion
local caps = {
    -- Khorne
    {"iron_scorpion", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
