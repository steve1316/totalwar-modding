-- Dragon General Fu Yuanshan:Faction Overhaul【Reforged】/龙将傅远山:震旦新派系【重铸版】
local caps = {
    -- Grand Cathay
    {"cth_fys_peasant_firelancer", "core"},
    {"cth_fys_jade_warrior_lancer", "special", 1},
    {"cth_fys_cav_rhino_rider", "rare", 2}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end