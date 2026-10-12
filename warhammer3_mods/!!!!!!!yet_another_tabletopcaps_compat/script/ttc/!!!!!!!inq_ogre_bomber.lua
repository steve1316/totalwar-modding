-- Inquisitor's More Ogres!
local caps = {
    -- Ogre Kingdoms
    {"blood_vultures", "core"},
    {"ogr_feral_mammoth", "rare", 2},
    {"ogr_stonehorn_cannon", "rare", 3},
    {"ogre_bomber", "special", 1},
    {"ogre_gatebusters", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
