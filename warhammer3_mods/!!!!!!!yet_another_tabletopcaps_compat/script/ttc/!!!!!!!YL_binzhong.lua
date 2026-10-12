-- 『龙战于野』震旦兵种包(Cathay Units Patch:Dragons Battle in the Field)
local caps = {
    -- Grand Cathay
    {"YL_cgs", "core"},
    {"YL_chlw", "special", 1},
    {"YL_hytj", "special", 2},
    {"YL_lycs", "core"},
    {"YL_lysw", "rare", 2},
    {"YL_pjcw", "rare", 2},
    {"YL_sxdw", "special", 2},
    {"YL_xtw", "special", 2},
    {"YL_yhcf", "rare", 3},
    {"YL_zsyw", "special", 3},
    {"YL_zyxj", "special", 2},
    {"YLlyxw", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
