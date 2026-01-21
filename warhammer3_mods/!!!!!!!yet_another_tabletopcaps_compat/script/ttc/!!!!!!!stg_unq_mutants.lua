-- stg_unq_mutants
local caps = {
    -- Beastmen
    {"stg_chos_unq_mutants_bst", "core", 1},
    -- Khorne
    {"stg_ch_cult_kho_corrupted_valkia", "core", 1},
    {"stg_chos_unq_mutants_valkia", "core", 1},
    {"stg_ch_cult_kho_monnik_pit_fighter_valkia", "core", 1},
    {"stg_ch_cult_kho_blacksmiths_of_blood_valkia", "special", 2},
    -- Nurgle
    {"stg_ch_cult_nur_carnival_festus", "special", 1},
    {"stg_ch_cult_nur_children_doom_festus", "core", 1},
    {"stg_chos_unq_mutants_festus", "core", 1},
    {"stg_ch_cult_nur_maggot_king_chosen_festus", "rare", 1},
    -- Slaanesh
    {"stg_ch_cult_sla_main_sybarites_azael", "special", 1},
    {"stg_chos_unq_mutants_azael", "core", 1},
    {"stg_ch_cult_sla_jade_spectre_azael", "core", 1},
    {"stg_ch_cult_sla_bleak_society_azael", "special", 1},
    -- Tzeentch
    {"stg_ch_cult_tze_fthaktoi_bkah_vilitch", "special", 1},
    {"stg_ch_cult_tze_purple_hand_vilitch", "core", 1},
    {"stg_ch_cult_tze_broken_wheel_vilitch", "special", 2},
    {"stg_chos_unq_mutants_vilitch", "core", 1},
    -- Warriors of Chaos
    {"stg_chos_unq_mutants", "core", 1},
    {"stg_ch_cult_tze_purple_hand", "core", 1},
    {"stg_ch_cult_tze_broken_wheel", "special", 2},
    {"stg_ch_cult_tze_fthaktoi_bkah", "special", 1},
    {"stg_ch_cult_kho_corrupted_crossbow", "core", 1},
    {"stg_ch_cult_sla_jade_spectre", "core", 1},
    {"stg_ch_cult_nur_carnival", "special", 1},
    {"stg_ch_cult_nur_children_doom", "core", 1},
    {"stg_ch_cult_sla_main_sybarites", "special", 1},
    {"stg_ch_cult_kho_monnik_pit_fighter", "core", 1},
    {"stg_ch_cult_sla_bleak_society", "special", 1},
    {"stg_ch_cult_nur_maggot_king_chosen", "rare", 1},
    {"stig_chs_cult_spawned_swarm_of_flies", "core", 1},
    {"stg_ch_cult_kho_blacksmiths_of_blood", "special", 2},
    {"stg_ch_cult_kho_corrupted", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end