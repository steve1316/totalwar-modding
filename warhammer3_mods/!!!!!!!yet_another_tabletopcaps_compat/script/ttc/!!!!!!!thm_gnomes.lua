-- thm_gnomes
local caps = {
    -- Wood Elves
    {"hilldwf_gnome_badger_riders", "core"},
    {"hilldwf_gnome_fox_riders", "core"},
    {"hilldwf_toad_ranged", "special", 2},
    {"hilldwf_gnome_lord_fox", "special", 2},
    {"hilldwf_gnome_lord_toad", "special", 2},
    {"hilldwf_gnome_lord_owl", "special", 2},
    {"hilldwf_gnome_lord_molebear", "special", 2},
    {"hilldwf_gnome_rabble", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end