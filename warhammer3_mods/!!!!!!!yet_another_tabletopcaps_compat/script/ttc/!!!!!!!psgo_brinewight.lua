-- psgo_brinewight
local caps = {
    -- Vampire Coast
    {"kys_und_necro_zombie", "core", 1},
    {"psgo_brinewight_dual", "core", 1},
    {"psgo_brinewight_flamethrower", "special", 1},
    {"psgo_brinewight_polearm", "core", 1},
    {"psgo_brinewight", "core", 1},
    {"psgo_drowned_leadbelcher", "special", 2},
    {"psgo_river_troll", "special", 2},
    {"psgo_abyssal_riders", "special", 1},
    {"psgo_haunted_vessel", "special", 3},
    {"psgo_brinewight_marksmen", "core", 1},
    {"psgo_deepfang_horror", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end