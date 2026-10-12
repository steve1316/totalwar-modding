-- The Phoenix Court (High Elf Politics)
local caps = {
    -- High Elves
    {"cr_als_hef_mon_merwyrm_0", "rare", 2},
    {"cr_als_hef_mon_merwyrm_summoned", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
