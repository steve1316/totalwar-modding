-- @exp_roster_compilation
local caps = {
    -- Chaos Dwarfs
    {"deco_chd_gnoblar_slaves", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end