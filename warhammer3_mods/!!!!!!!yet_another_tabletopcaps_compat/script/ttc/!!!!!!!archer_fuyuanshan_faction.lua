-- Dragon General Fu Yuanshan:Faction Overhaul【Reforged】/龙将傅远山:震旦新派系【重铸版】
local caps = {
    -- Grand Cathay
    {"cth_mon_yaksha", "rare", 3},
    {"f_cth_cav_bastion", "special", 2},
    {"f_cth_inf_scout", "special", 1},
    {"f_cth_sky_keeper", "rare", 2},
    {"jade_banner", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
