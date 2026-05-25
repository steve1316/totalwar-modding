-- The_Gunpowder_Road2.0
local caps = {
    -- Grand Cathay
    {"cth_juma", "core", 1},
    {"cth_inf_niaochong_gunners_0", "core", 1},
    {"cth_inf_sanjieshenji_gunners_0", "special", 1},
    {"cth_inf_peasant_huochong_0", "core", 1},
    {"cth_juma_mu", "core", 1},
    {"cth_inf_dragon_guard_lihuaqiang0", "rare", 2},
    {"cth_inf_xunleichong_0", "special", 2},
    {"cth_inf_jade_warrior_sanyanchong_0", "special", 1},
    {"cth_juma_dunpai", "core", 1},
    {"cth_veh_sky_lantern_ror", "special", 1},
    {"cth_inf_jade_warrior_rocket_battery", "special", 1},
    {"cth_veh_sky_junk_ror", "special", 3},
    {"cth_inf_feimengpao", "special", 1},
    {"cth_huolongchushui_fashezhendi", "rare", 3},
    {"cth_zizhongche", "special", 1},
    {"cth_dilei_ganglunzifanhuo", "core", 1},
    {"cth_pianxiangche_light_bushu", "special", 2},
    {"cth_inf_huonuliuxingjian", "core", 1},
    {"cth_zhongxingzizhongche", "special", 1},
    {"cth_huolongchushui", "rare", 3},
    {"cth_pianxiangche_heavy", "special", 3},
    {"cth_pianxiangche_fulangji", "special", 2},
    {"cth_qijiajun", "special", 1},
    {"cth_huoguigongdiche", "special", 2},
    {"cth_wankouchong", "special", 2},
    {"cth_dilei_fudichongtianlei", "core", 1},
    {"cth_baizichong", "special", 2},
    {"cth_pianxiangche_light_light_zhendi", "special", 1},
    {"cth_pianxiangche_light", "special", 2},
    {"cth_inf_dulongpenhuoshentong", "special", 2},
    {"cth_huoxiangche", "special", 2},
    {"cth_murenhuomayunzaiche", "special", 2},
    {"cth_pianxiangche_heavy_bushu", "special", 3},
    {"cth_pinfengche", "special", 2},
    {"cth_dajiangjun_canno", "special", 2},
    {"cth_pianxiangche_fulangji_bushu", "special", 2},
    {"cth_murenhuoma", "core", 1},
    {"cth_pianxiangche_light_light", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end