-- !!!!!!Champions_of_undeath_merged_fun_tyme
local caps = {
    -- Vampire Coast
    {"vmp_teb_marines", "rare", 1},
    {"vmp_teb_first_company_marines", "rare", 1},
    {"vmp_teb_first_company", "rare", 1},
    {"vigpro_vmp_mon_carnosaur", "rare", 2},
    -- Vampire Counts
    {"jur_faris_royal_guards", "rare", 1},
    {"the_emptied_base_ror", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end