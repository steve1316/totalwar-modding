-- jade_vamp_pol
local caps = {
    -- Jade-Blooded Vampires
    {"jbv_nugui_01", "special", 2},
    {"jbv_darkwater_ghost", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end