-- @xou_emp
local caps = {
    -- Empire
    {"emp_inf_stevedore", "core", 1},
    {"emp_inf_company_of_honour", "core", 1},
    {"emp_inf_dwarf_warrior_1", "core", 1},
    {"emp_inf_carroburg_greatswords_ror", "special", 1},
    {"emp_inf_dwarf_warrior_0", "core", 1},
    {"emp_inf_hammerers", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end