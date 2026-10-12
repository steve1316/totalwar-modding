-- 【Deer24 基斯里夫兵种包】厄孙之牙 (Deer24 Kislve Units Patc Ursuns Tooth)
local caps = {
    -- Kislev
    {"bohaguanjun", "special", 2},
    {"bohajinjun", "special", 2},
    {"fuzuijuntuan", "rare", 1},
    {"jinweijun", "special", 2},
    {"kaqiusha", "rare", 2},
    {"xianbin", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
