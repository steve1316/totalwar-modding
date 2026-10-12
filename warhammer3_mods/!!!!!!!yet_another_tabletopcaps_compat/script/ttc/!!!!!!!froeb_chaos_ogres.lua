-- Chaos Ogres
local caps = {
    -- Chaos Dwarfs
    {"frb_chaos_ogre_brawlers_0_chd", "core"},
    {"frb_chaos_ogre_brawlers_1_chd", "core"},
    {"frb_chaos_ogre_fighters_0_chd", "special", 2},
    {"frb_chaos_ogre_fighters_1_chd", "special", 2},
    {"frb_chaos_ogre_fighters_2_chd", "special", 2},
    {"frb_chaos_ogre_warmongers_0_chd", "special", 2},
    {"frb_chaos_ogre_warmongers_1_chd", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
