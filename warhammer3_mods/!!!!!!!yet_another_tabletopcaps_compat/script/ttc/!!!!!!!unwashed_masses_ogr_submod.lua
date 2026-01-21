-- !!!_unwashed_masses_ogr_submod
local caps = {
    -- Gnoblar Hordes
    {"gnob_inf_rustbuckets", "special", 1},
    {"gnob_inf_rustbuckets_greatweapons", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end