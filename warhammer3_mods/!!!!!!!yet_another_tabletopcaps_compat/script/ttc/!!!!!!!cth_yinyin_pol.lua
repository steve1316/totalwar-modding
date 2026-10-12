-- Roar of the Jade Sea : Yin-Yin, the Sea Dragon
local caps = {
    -- Vampire Coast
    {"npn_umibozu", "rare", 3},
    -- Grand Cathay
    {"cth_wokou_spears", "core"},
    {"cth_wokou_ds", "core"},
    {"cth_wokou", "core"},
    {"cth_wokou_guns", "core"},
    {"cth_marines", "core"},
    {"cth_wokou_cannon", "special", 2},
    {"cth_whalers", "rare", 1},
    {"cth_ronin", "special", 1},
    {"cth_yicha_fghter", "special", 1},
    {"cth_sam", "special", 2},
    {"npn_ansatsu", "special", 2},
    {"cth_marines_ror", "special", 1},
    {"cth_golden_heron", "rare", 3},
    {"cth_golden_heron_zhuque", "rare", 3},
    {"cth_golden_heron_upgraded", "rare", 3},
    -- Lizardmen
    {"lzd_raptor_0", "special", 1},
    {"lzd_pachy_0", "special", 1},
    {"lzd_styracosaur", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end