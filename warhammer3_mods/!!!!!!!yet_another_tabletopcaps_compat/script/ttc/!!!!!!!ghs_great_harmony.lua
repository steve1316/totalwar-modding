-- 万世天朝/Great Harmony Sentinel Overhaul Beta
local caps = {
    -- Grand Cathay
    {"ghs_main_cth_inf_iron_dragon_modao", "special", 2},
    {"ghs_main_cth_inf_iron_dragon_modao_ror", "rare", 1},
    -- Khorne
    {"ghs_main_kho_mon_titan", "rare", 3},
    -- Slaanesh
    {"ghs_main_sla_mon_titan", "rare", 3},
    -- Tomb Kings
    {"ghs_main_tmb_cav_ostrich_rider_summon", "core"},
    {"ghs_main_tmb_mon_flying_necrosphinx_usirian", "rare", 3},
    {"ghs_main_tmb_mon_heirotitan_0_summoned", "rare", 3},
    -- Tzeentch
    {"ghs_main_tze_mon_titan", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
