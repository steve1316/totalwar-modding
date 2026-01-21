-- CF-Chaos_Dragon
local caps = {
    -- Khorne
    {"cf_kho_chs_dragon", "rare", 3},
    -- Nurgle
    {"cf_nur_chs_dragon", "rare", 3},
    -- Slaanesh
    {"cf_sla_chs_dragon", "rare", 3},
    -- Tzeentch
    {"cf_tze_chs_dragon", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end