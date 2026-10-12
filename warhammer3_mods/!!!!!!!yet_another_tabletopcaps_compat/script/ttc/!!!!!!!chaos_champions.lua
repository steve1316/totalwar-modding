-- Mono God Aspiring Champions
local caps = {
    -- Nurgle
    {"nurgle_champions", "special", 2},
    -- Warriors of Chaos
    {"khorne_berzerker_champions", "special", 2},
    {"slaanesh_champions", "special", 2},
    {"tzeentch_champions", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
