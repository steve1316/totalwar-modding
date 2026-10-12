-- Immortal Landmarks
local caps = {
    -- Daemons of Chaos
    {"norscan_bondsmen", "special", 2},
    -- Empire
    {"zerg_emp_zaskar_black_guard_cav", "special", 2},
    {"zerg_emp_zaskar_black_guard_inf", "special", 1},
    -- Khorne
    {"khorne_simaergul", "special", 2},
    -- Kislev
    {"gargantulzan", "rare", 3},
    -- Slaanesh
    {"shadow_guard", "special", 2},
    -- Tomb Kings
    {"tmb_scorpion_summon", "rare", 1},
    -- Tzeentch
    {"corrupted_sentinel", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
