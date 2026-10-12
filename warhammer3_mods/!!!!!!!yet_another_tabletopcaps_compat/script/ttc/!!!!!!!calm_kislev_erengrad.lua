-- Calm Kislev Erengrad
local caps = {
    -- Kislev
    {"calm_hajduks", "core", 1},
    {"calm_ryadniks", "core"},
    {"calm_kreml_guard", "special", 2},
    {"calm_kvassniks", "core"},
    {"calm_sarmatyrs", "core"},
    {"calm_straznik_blunderbuss", "special", 1},
    {"calm_storozhi", "special", 2},
    {"calm_mounted_kirasirs", "special", 2},
    {"calm_urugan_cannon", "rare", 2},
    {"calm_erengrad_mortar", "special", 2},
    {"calm_erengrad_cannon", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end