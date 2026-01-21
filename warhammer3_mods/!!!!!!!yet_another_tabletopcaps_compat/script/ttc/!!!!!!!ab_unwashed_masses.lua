-- ab_unwashed_masses
local caps = {
    -- Ogres
    {"calm_rustbuckets", "special", 1},
    {"calm_rustbuckets_greatweapons", "special", 1},
    {"gnob_inf_powder_sniffers", "core"},
    {"gnob_cav_sabretusk_riders", "special", 2},
    -- Gnoblar Hordes
    {"gnob_ror_empire_gunners", "special", 1},
    {"gnob_mon_great_scarlet_iiwi", "special", 1},
    {"gnob_mon_arachnarok_spider", "rare", 3},
    {"gnob_ror_kings_treasure_guards", "core", 1},
    {"gnob_mon_lava_spiders", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end