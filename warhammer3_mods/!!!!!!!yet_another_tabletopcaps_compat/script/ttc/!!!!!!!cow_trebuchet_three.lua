-- cow_trebuchet_three
local caps = {
    -- Bretonnia
    {"wh_main_brt_art_cow_trebuchet", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end