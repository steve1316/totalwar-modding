-- sartosa_overhaul
local caps = {
    -- Vampire Coast
    {"sartosa_pirate_artillery_culverin", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end