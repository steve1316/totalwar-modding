-- !alshua_go_squig_or_go_home
local caps = {
    -- Greenskins
    {"als_squig_horned", "special", 1},
    {"als_squig_tomb", "special", 1},
    {"als_squig_spike", "special", 1},
    {"als_squig_gas", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end