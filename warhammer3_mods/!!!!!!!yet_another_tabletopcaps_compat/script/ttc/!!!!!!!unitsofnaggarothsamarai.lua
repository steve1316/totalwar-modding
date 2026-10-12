-- Units of Naggaroth (Dark Elf unit expansion)
local caps = {
    -- Dark Elves
    {"glory_archers", "special", 1},
    {"def_pegasus_knights", "special", 2},
    {"def_black_lion", "special", 2},
    {"def_drake", "rare", 2},
    {"def_witch_knights", "core"},
    {"hawk_summoned", "special", 1},
    {"wolf_summoned", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end