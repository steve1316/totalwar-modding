-- scm_beasts_most_foul
local caps = {
    -- Khorne
    {"khorngor_shld", "special", 1},
    {"khorngor", "special", 1},
    -- Slaanesh
    {"theak_slaangor_jav", "core"},
    -- Beastmen
    {"gp_kho_mon_khornataurs_0", "special", 2},
    {"gp_kho_mon_khornataurs_1", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end