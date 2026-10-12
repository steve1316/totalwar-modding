-- CF-Chaos_Dragon
local caps = {
    -- Warriors of Chaos
    {"cf_chs_dragon", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
