-- !derpy_noinruneguardian
local caps = {
    -- Dwarfs
    {"derpy_expi_dwarf_rune_golem", "rare", 3},
    {"derpy_expi_dwarf_rune_golem_hammer", "rare", 3},
    {"derpy_expi_dwarf_rune_golem_hand", "rare", 3},
    {"derpy_expi_dwarf_rune_golem_cannon", "rare", 3},
    {"derpy_expi_dwarf_rune_golem_hand_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end