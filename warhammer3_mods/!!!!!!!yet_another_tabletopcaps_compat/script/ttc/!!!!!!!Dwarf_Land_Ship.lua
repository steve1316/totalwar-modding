-- Dwarf Fortress
local caps = {
    -- Dwarfs
    {"awp_dwf_land_ship", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
