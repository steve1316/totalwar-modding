-- The Jade-Blooded Vampires: Islanders of the Moon
local caps = {
    -- Vampire Counts
    {"jbv_doctor", "special", 2},
    {"jbv_islanders", "core"},
    {"jbv_lady_yayi", "rare", 2},
    {"jbv_nurses", "special", 1},
    {"jbv_nurses_2", "special", 1},
    {"jbv_patient_man", "rare", 2},
    {"jbv_patient_mob", "special", 2},
    {"jbv_patient_woman", "rare", 2},
    {"jbv_wraith", "special", 1},
    -- High Elves
    {"hef_iotm_islanders", "core"},
    {"hef_iotm_islanders_hb", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
