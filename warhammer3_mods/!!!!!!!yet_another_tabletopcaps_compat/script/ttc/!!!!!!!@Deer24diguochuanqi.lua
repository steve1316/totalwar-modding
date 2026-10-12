-- 【Deer24帝国单位包】帝国传奇 ( Units patch：Empire Romance)
local caps = {
    -- Empire
    {"agesiqishi", "special", 2},
    {"bailang", "rare", 3},
    {"buxingqishi", "special", 1},
    {"buxingqishi1", "special", 1},
    {"diguohuoqiangshou", "special", 1},
    {"dihuangqishi", "special", 2},
    {"gaositianshi", "rare", 1},
    {"huangjinzituan", "special", 1},
    {"jiaozongqishi", "special", 1},
    {"judunnubing", "special", 1},
    {"liebing", "special", 1},
    {"mishenheiwei", "special", 2},
    {"neihuanqishi", "rare", 2},
    {"rongyaoqishi", "special", 3},
    {"ruikeqishi", "special", 1},
    {"shenxue", "special", 2},
    {"sheshou", "special", 2},
    {"syr", "special", 1},
    {"xigemachui", "special", 1},
    {"youlikezhanshi", "special", 1},
    {"yulintiewei", "rare", 2},
    {"zhandouxiunv", "special", 2},
    {"zhenqiqishi", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
