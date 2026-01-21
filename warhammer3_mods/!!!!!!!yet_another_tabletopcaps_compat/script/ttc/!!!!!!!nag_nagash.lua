-- nag_nagash
local caps = {
    -- Undead Legions
    {"nag_vanilla_cst_inf_syreen", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end