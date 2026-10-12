-- Dead's Jade Army Expansion
local caps = {
    -- Grand Cathay
    {"jade_archers", "core"},
    {"jade_cataphract", "special", 2},
    {"jade_chariot", "special", 2},
    {"jade_repeaters", "core"},
    {"jade_warriors_glaive", "core"},
    {"jade_warriors_spear", "core"},
    {"jade_warriors_spear_shield", "core"},
    {"jade_zhanmadao", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
