-- SCM's LCCP, 15 new factions for IEE!
local caps = {
    -- High Elves
    {"hef_calith_gatekeepers", "special", 2},
    -- Vampire Counts
    {"rhox_lccp_vmp_giant", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
