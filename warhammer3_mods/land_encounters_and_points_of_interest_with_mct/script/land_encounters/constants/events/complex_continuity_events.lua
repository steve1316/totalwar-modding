local WEAPON_CHAINSWORD = "wh3_main_anc_weapon_chainsword"
local WEAPON_BANE_SPEAR = "wh3_main_anc_weapon_the_bane_spear"
local WEAPON_KRAKEN_KILLER = "wh3_main_anc_weapon_skars_kraken_killer"
local WEAAPON_SOULNETTER = "wh3_main_anc_weapon_gilellions_soulnetter"
local WEAPON_SLAAANESH_BLADE = "wh3_main_anc_weapon_slaaneshs_blade"
local WEAPON_SYCOPHANT = "wh3_main_anc_follower_personal_sycophant"
local WEAPON_PARAMOUR = "wh3_main_anc_follower_the_dark_princes_paramour"

local chain_origin_events = {
    ["land_enc_incident_battle_won_daemonic_gift_chainsword"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_CHAINSWORD
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_chainsword_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_CHAINSWORD, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_chainsword_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },
    
    ["land_enc_incident_battle_won_daemonic_gift_the_bane_spear"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_BANE_SPEAR
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_the_bane_spear_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_BANE_SPEAR, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_the_bane_spear_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },

    ["land_enc_incident_battle_won_daemonic_gift_skars_kraken_killer"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_KRAKEN_KILLER
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_skars_kraken_killer_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_KRAKEN_KILLER, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_skars_kraken_killer_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },

    ["land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAAPON_SOULNETTER
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAAPON_SOULNETTER, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },

    ["land_enc_incident_battle_won_daemonic_gift_slaaneshs_blade"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_SLAAANESH_BLADE
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_slaaneshs_blade_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_SLAAANESH_BLADE, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_slaaneshs_blade_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },

    ["land_enc_incident_battle_won_daemonic_gift_personal_sycophant"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_SYCOPHANT
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_personal_sycophant_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_SYCOPHANT, faction = "random" } }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_personal_sycophant_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    },

    ["land_enc_incident_battle_won_daemonic_gift_dark_princes_paramour"] = {
        [1] = {
            conditions = {
                ["does_not_have_ancillary"] = WEAPON_PARAMOUR
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_dark_princes_paramour_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { 
                    ["give_ancillary"] = { 
                        ancillary = WEAPON_PARAMOUR, 
                        faction = "random" 
                    } 
                }
            }
        },
        [2] = {
            conditions = {},   
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_dark_princes_paramour_already_granted",
                targets = { character = false, force = true, faction = true, region = false },
                balance = false
            }
        }
    }
}

return chain_origin_events 