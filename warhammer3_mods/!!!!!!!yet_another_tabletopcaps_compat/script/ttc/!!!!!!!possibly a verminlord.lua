-- Vile Verminlords: It's Time-Time
local caps = {
    -- Skaven
    {"skv_verminlord_corruptor", "rare", 3},
    {"skv_verminlord_deceiver", "rare", 3},
    {"skv_verminlord_warbringer", "rare", 3},
    {"skv_verminlord_warpseer", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
