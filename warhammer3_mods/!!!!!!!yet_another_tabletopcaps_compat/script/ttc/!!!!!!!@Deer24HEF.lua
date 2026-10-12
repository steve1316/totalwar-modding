-- 【Deer24高等精灵单位包】荣光国度（ HEF UNITS PATCH Glorious Nation）
local caps = {
    -- High Elves
    {"DEERHEF_AISAANGQISHI", "special", 3},
    {"DEERHEF_BAISHILIECHANG", "special", 2},
    {"DEERHEF_BAITAJIANSHENG", "special", 2},
    {"DEERHEF_DIGONGTONGWEI", "special", 2},
    {"DEERHEF_FENGHUANGSHOUWEI", "special", 2},
    {"DEERHEF_HAIMEN", "special", 1},
    {"DEERHEF_LONGZHU", "rare", 3},
    {"DEERHEF_NAJIARUISIHEIWEI", "special", 2},
    {"DEERHEF_NVQISHI", "special", 1},
    {"DEERHEF_NVQISHI1", "special", 2},
    {"DEERHEF_SHOUWANGZHE", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
