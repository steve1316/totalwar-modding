-- Kossar_Riflemen_Unit
local caps = {
    -- Kislev
    {"wh3_dlc24_ksl_inf_kislevite_warriors_rifle", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end