-- Children of the Woods (Immortal Empires Edition)
local caps = {
    -- Wood Elves
    {"celebrant_wef01", "core"},
    -- Beastmen
    {"werewolf_bst01", "special", 2},
    {"woodbeast_bst01", "rare", 2},
    -- Kislev
    {"forest_wolves01", "special", 1},
    {"werewolf_wef01", "special", 2},
    {"leshen_wef01", "rare", 3},
    {"woodbeast_wef01", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end