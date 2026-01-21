-- snek_dawi_thunder
local caps = {
    -- Dwarfs
    {"snek_dwf_cycle", "special", 2},
    {"snek_dwf_grudgesolvers", "special", 2},
    {"snek_dwf_ironguard", "special", 2},
    {"snek_dwf_drop_chopper_regiment", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end