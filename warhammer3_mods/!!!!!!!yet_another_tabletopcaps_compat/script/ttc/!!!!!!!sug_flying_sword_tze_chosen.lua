-- sug_flying_sword_tze_chosen
local caps = {
    -- Tzeentch
    {"wh3_dlc20mod_chs_inf_chosen_mtze_flyingswords", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end