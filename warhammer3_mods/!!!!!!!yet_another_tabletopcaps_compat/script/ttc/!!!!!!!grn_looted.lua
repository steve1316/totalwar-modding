-- derpy_grn_looted
local caps = {
    -- Greenskins
    {"derpy_grn_looted_dwf_tank_ror", "rare", 3},
    {"derpy_grn_looted_rune_boyz", "special", 2},
    {"derpy_grn_looted_dwf_tank", "rare", 3},
    {"derpy_grn_looted_emp_tank", "rare", 3},
    {"derpy_grn_looted_chd_tank", "rare", 3},
    {"derpy_grn_looted_burnin_boyz", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end