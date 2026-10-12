-- Valen - Legendary Ranger Lord
local caps = {
    -- High Elves
    {"moe_rangers_ror", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
