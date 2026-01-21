-- @whc_cth_unit_wuh_7
local caps = {
    -- Grand Cathay
    {"cth_south_songyuan_cav_jade", "special", 1},
    {"cth_west_qinhan_jade_wuzu_3", "special", 1},
    {"cth_west_pagoda_rider", "rare", 1},
    {"cth_south_tiger_rider", "rare", 1},
    {"cth_east_mingqing_cav_peasant", "core", 1},
    {"cth_east_mingqing_longwei_pro_jingying_2", "special", 3},
    {"cth_north_suitang_cav_jade", "special", 2},
    {"cth_west_qinhan_longwei_yulin_1", "special", 2},
    {"cth_east_jiaolong_rider", "rare", 2},
    {"cth_east_mingqing_jade_qijun_3", "special", 1},
    {"cth_central_tianting_crow_guard", "special", 2},
    {"cth_south_songyuan_jade_xiangbing_3", "special", 1},
    {"cth_south_ox_rider", "core", 1},
    {"cth_central_jade_lion_rider", "rare", 2},
    {"cth_north_bian_rider", "rare", 2},
    {"cth_south_songyuan_longwei_pro_shenbi_2", "special", 2},
    {"cth_east_mingqing_gunner_shenji", "special", 3},
    {"cth_east_mingqing_jade_qijun_4", "special", 1},
    {"cth_west_qinhan_cav_longma", "special", 2},
    {"cth_north_suitang_cav_longma", "special", 3},
    {"cth_north_suitang_jade_shuwei_3", "special", 1},
    {"cth_central_tianting_ogr_swordsmaster", "special", 2},
    {"cth_inf_onna_bushi", "special", 1},
    {"cth_samurai_shun", "special", 1},
    {"cth_matchlock_samurai", "special", 1},
    {"cth_inf_onna_bushi_archers", "special", 1},
    {"cth_inf_heralds_bwinds", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end