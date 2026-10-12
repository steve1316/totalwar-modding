-- Dawi Additional GP Units
local caps = {
    -- Dwarfs
    {"derpy_dwf_vault_sweepers_deploy", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
