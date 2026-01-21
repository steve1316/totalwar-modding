-- MAMMOTH_Mods
local caps = {
    -- Norsca
    {"zerg_nor_full_armoured_mammoth", "rare", 3},
    {"chonky_nor_mon_war_mammoth_1", "rare", 3},
    {"chonky_nor_mon_war_mammoth_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end