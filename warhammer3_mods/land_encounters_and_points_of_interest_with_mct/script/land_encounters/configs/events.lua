--- Event tables for the Land Encounters and Points of Interest mod. Defines the dilemma / incident event keys grouped by category
--- (treasure_type, complex_continuity, smithy, tower_spot) and their targets / effect bindings. Battle-spot dilemmas live in configs/battle_categories.lua.
--- Pure data - no runtime logic.

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- tavern (from constants/events/tavern_events.lua)
--- Source file is empty (stub).

M.tavern = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- tower_spot: the tower dilemmas, built at runtime by features/tower.lua.

M.tower_spot = {
    "land_enc_dilemma_tower_enter",
    "land_enc_dilemma_tower_deeper_floor_1",
    "land_enc_dilemma_tower_deeper_floor_2",
    "land_enc_dilemma_tower_deeper_floor_3",
    "land_enc_dilemma_tower_deeper_floor_4",
    "land_enc_dilemma_tower_claim",
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- treasure_type (from constants/events/treasure_type_events.lua)

--[[
Treasure-type incidents (no dilemma - just fire-and-grant). No variations.

Each entry below pairs an incident key with the targets bitmask and an optional effect_bundle key.
Adding a new treasure requires DB rows in incidents_tables, cdir_events_incident_option_junctions_tables,
and cdir_events_incident_payloads_tables, plus matching .loc entries for the incident title/description.
Effects (when set) additionally need effect_bundles_tables + effect_bundles_to_effects_junctions_tables rows
and effect_bundles .loc entries.
--]]
M.treasure_type = {
    --"land_enc_incident_clean_up_event" SPECIAL: Only used for the abstract class spot to eliminate bugged points
    {
        incident = "land_enc_incident_tomb_robbing",
        targets =  { character = true, force = false, faction = false, region = false },
        effect = false -- for AI
    },
    {
        incident = "land_enc_incident_abandoned_camp",
        targets = { character = false, force = true, faction = false, region = false },
        effect = "land_enc_effect_abandoned_camp"
    },
    {
        incident = "land_enc_incident_buried_relics",
        targets = { character = false, force = true, faction = false, region = false },
        effect = false
    },
    {
        incident = "land_enc_incident_hidden_temple",
        targets = { character = false, force = true, faction = false, region = false },
        effect = "land_enc_effect_hidden_temple"
    },
    {
        incident = "land_enc_incident_caravan_remnants",
        targets = { character = true, force = false, faction = false, region = false },
        effect = false
    },
    {
        incident = "land_enc_incident_whispers_of_the_gods",
        targets = { character = false, force = true, faction = false, region = false },
        effect = "land_enc_effect_whispers_of_the_gods"
    },
    {
        incident = "land_enc_incident_the_explorer",
        targets = { character = false, force = true, faction = false, region = false },
        effect = "land_enc_effect_the_explorer"
    },
    {
        incident = "land_enc_incident_legendary_bard",
        targets = { character = false, force = false, faction = true, region = false },
        effect = false
    }
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- complex_continuity (from constants/events/complex_continuity_events.lua)

local WEAPON_CHAINSWORD = "wh3_main_anc_weapon_chainsword"
local WEAPON_BANE_SPEAR = "wh3_main_anc_weapon_the_bane_spear"
local WEAPON_KRAKEN_KILLER = "wh3_main_anc_weapon_skars_kraken_killer"
local WEAPON_SOULNETTER = "wh3_main_anc_weapon_gilellions_soulnetter"
local WEAPON_SLAAANESH_BLADE = "wh3_main_anc_weapon_slaaneshs_blade"
local WEAPON_SYCOPHANT = "wh3_main_anc_follower_personal_sycophant"
local WEAPON_PARAMOUR = "wh3_main_anc_follower_the_dark_princes_paramour"

M.complex_continuity = {
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
                ["does_not_have_ancillary"] = WEAPON_SOULNETTER
            },
            result = {
                incident = "land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter_granted",
                targets = { character = true, force = false, faction = false, region = false },
                balance = { ["give_ancillary"] = { ancillary = WEAPON_SOULNETTER, faction = "random" } }
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- smithy (from constants/events/smithy_events.lua)

M.smithy = {
    "land_enc_dilemma_smithy_forge",
    "land_enc_dilemma_smithy_forge_level_1",
    "land_enc_dilemma_smithy_forge_level_2",
    "land_enc_dilemma_smithy_forge_level_3",
    "land_enc_dilemma_smithy_reclamation",
    "land_enc_dilemma_smithy_defense",
    "land_enc_dilemma_smithy_visit_level_1",
    "land_enc_dilemma_smithy_visit_level_2",
    "land_enc_dilemma_smithy_visit_level_3"
}

return M
