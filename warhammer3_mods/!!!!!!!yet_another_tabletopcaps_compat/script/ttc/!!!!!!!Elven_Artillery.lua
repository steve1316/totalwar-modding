-- Elven_Artillery
local caps = {
    -- High Elves
    {"phoenix_cannon", "rare", 2},
    {"light_rain", "rare", 2},
    -- Dark Elves
    {"dread_cannon", "rare", 2},
    {"death_rain", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end