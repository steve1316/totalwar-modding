-- Zayli_Complete_Mod_Compilation
local caps = {
    -- Bretonnia
    {"zayli_peasant_bowmen_ror_1", "core", 1},
    {"zayli_peasant_mob_ror_1", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end