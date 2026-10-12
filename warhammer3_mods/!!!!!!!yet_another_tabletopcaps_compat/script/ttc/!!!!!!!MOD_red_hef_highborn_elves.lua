-- Highborn Elves - Unit Pack
local caps = {
    -- High Elves
    {"wh2_main_hbe_inf_silverhelm_spears", "special", 1},
    {"wh2_main_hbe_inf_silverhelm_swords", "special", 1},
    {"wh2_main_hbe_inf_white_lions_spear_company", "core"},
    {"wh2_main_hbe_inf_white_lions_sword_company", "core"},
    {"wh2_main_hef_elven_paladins", "special", 2},
    {"wh2_main_hef_elven_paladins_dismounted", "special", 2},
    {"wh2_main_hef_gol_spear", "special", 2},
    {"wh2_main_hef_gol_swords", "special", 2},
    {"wh2_main_hef_highborn_archers", "special", 1},
    {"wh2_main_hef_highborn_axes", "special", 1},
    {"wh2_main_hef_highborn_guard", "special", 2},
    {"wh2_main_hef_highborn_knights", "special", 2},
    {"wh2_main_hef_highborn_spears", "special", 1},
    {"wh2_main_hef_highborn_swords", "special", 1},
    {"wh2_main_hef_shadow_warriors", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
