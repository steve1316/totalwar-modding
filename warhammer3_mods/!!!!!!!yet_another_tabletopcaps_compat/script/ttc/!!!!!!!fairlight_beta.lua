-- fairlight_beta
local caps = {
    -- Bretonnia
    {"ML_Fairlight_LL_brt_armored_sergeants", "special", 1},
    {"ML_Fairlight_LL_brt_crossbows", "special", 1},
    {"wh_main_brt_mon_trolls_summ", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end