-- !!!cou_blood_knight_heretics_live_build
local caps = {
    -- Vampire Counts
    {"cou_kho_blood_dragons_cav", "rare", 2},
    {"cou_kho_blood_dragons_inf", "special", 2},
    {"cou_nur_depth_guard_cav", "special", 3},
    {"cou_nur_depth_guard_inf", "special", 2},
    {"cou_sla_seneschal_dame_inf_angel", "rare", 3},
    {"cou_sla_seneschal_dame_inf", "special", 2},
    {"cou_tze_drakenhof_templar_inf", "special", 2},
    {"cou_tze_drakenhof_templar_cav", "rare", 3},
    {"cou_sla_seneschal_dame_cav", "rare", 3},
    {"cou_tze_drakenhof_templar_cav_horse", "rare", 3},
    {"cou_kho_blood_dragons_bi2_rider", "rare", 3},
    {"cou_nur_depth_guard_dr5_rider", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end