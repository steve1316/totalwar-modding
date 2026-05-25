-- obsidian_lustria_rises
local caps = {
    -- Lizardmen
    {"obsidian_lzd_ancient_razordon_blessed", "rare", 2},
    {"obsidian_lzd_inf_skink_altar_guardians", "core", 1},
    {"obsidian_lzd_great_wyrm_howdah", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end