-- ovn_araby
local caps = {
    -- Araby
    {"ovn_arb_mon_book_djinn", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end