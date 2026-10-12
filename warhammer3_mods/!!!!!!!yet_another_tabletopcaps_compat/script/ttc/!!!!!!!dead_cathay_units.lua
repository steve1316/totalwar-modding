-- Dead's Cathay Unit Pack
local caps = {
    -- Grand Cathay
    {"bannerman", "rare", 1},
    {"battle_turtle", "rare", 2},
    {"cth_juggernaut_crew", "special", 2},
    {"cth_tiger", "special", 1},
    {"cth_war_elephant", "special", 2},
    {"dead_firelancers", "special", 2},
    {"nangau_rifles", "core"},
    {"peasant_cav_archers", "core"},
    {"rocket_troops", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
