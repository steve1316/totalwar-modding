-- cth_undead_legion
local caps = {
    -- Vampire Counts
    {"cth_ghost_01", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end