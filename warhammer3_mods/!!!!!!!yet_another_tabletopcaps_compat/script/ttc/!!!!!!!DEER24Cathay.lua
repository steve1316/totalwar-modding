-- DEER24Cathay
local caps = {
    -- Grand Cathay
    {"wwd_jinjun_huben", "rare", 2},
    {"wwd_jinjun_cennter_chiwei", "rare", 2},
    {"wwd_jinjun_tianshi", "rare", 2},
    {"wwd_jinjun_fengyunlan", "rare", 2},
    {"wwd_jinjun_north_tiewei", "rare", 2},
    {"wwd_jinjun_west_baier", "rare", 2},
    {"wwd_jinjun_longdijinjun", "rare", 2},
    {"wwd_jinjun_east_chaoting", "rare", 2},
    {"wwd_jinjun_celest_yayu", "rare", 2},
    {"wh3_deer24_gau_ogr", "special", 2},
    {"wwd_jinjun_longdijinjun_terminator", "rare", 2},
    {"wwd_jinjun_yueshenyuan", "rare", 2},
    {"wwd_jinjun_south_zhushou", "rare", 2},
    {"wh3_deer24_fubing_guard", "rare", 1},
    {"wh3_deer24_fubing_sword", "core", 1},
    {"deer_baochuan", "rare", 3},
    {"wh3_deer24_bianjun_2", "core", 1},
    {"wh3_deer24_bianjun_1", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end