-- Slaanbulls & Trojan
local caps = {
    -- Warriors of Chaos
    {"slaanbull", "special", 2},
    {"slaanbulldual", "special", 2},
    {"slaanbullshield", "special", 2},
    {"slacygor", "rare", 3},
    {"trod", "rare", 2},
    {"trojan", "rare", 3},
    {"trojan_ror", "rare", 3},
    {"tror", "rare", 3},
    {"tros", "rare", 2},
    {"troy", "rare", 2},
    {"troym", "rare", 2},
    {"troym2", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
