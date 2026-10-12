-- New Legendary Lord and Hero Artefacts Warhammer 3
local caps = {
    -- Lizardmen
    {"stompies_quango", "rare", 3},
    -- Tzeentch
    {"stompies_summoned_tze_spawn", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end