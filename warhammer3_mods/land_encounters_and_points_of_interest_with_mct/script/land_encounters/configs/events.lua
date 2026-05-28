local M = {}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- battle_spot (from constants/events/battle_spot_events.lua)

--[[
The types of battles one can encounter with this mod. There will always be a variation given an extra _modifier in the name. The Bandits, Incursions, Surprise attacks are common armies. If I can the battlefields will be a multi army battle.

Every dilemma needs:
=============================
DILEMMA
=============================
Use this if you want the player to have more agency in their decision making.

== DB
1. cdir_events_dilemma_choice_details_tables (Binds the choices of a dilemma to such dilemma. Without this table you cannot declare the .loc and describe the dilemmas that appear on screen).
2. cdir_events_dilemma_option_junctions_tables (Chance to trigger, conditions, follow up and target)
3. cdir_events_dilemma_payloads_tables (The X choice keys and their effects)
4. dilemmas_tables (Declare the dilemma here)

== LOC
1. cdir_events_dilemma_choice_details.loc (Describe the text that the options will hold)
- Format
cdir_events_dilemma_choice_details_localised_choice_label_ (fixed) + land_enc_dilemma_bandits_emp (dilemma id) + FIRST/SECOND/THIRD (number of choice)

2. dilemmas.loc
Here goes the description and title of the declared dilemma. In combination with the details, this declares all the strings in a dilemmma.
dilemmas_localised_description_ + <dilemman_key: land_enc_dilemma_bandits_emp>
dilemmas_localised_title_ + <land_enc_dilemma_bandits_emp>

TODO:
1. Variations of this events, more varied armies
--]]
M.battle_spot = {
    [1] = { -- 9 events
        ---------------------------------------------------------------------------
        -- (Easiest) Skirmishes
        ---------------------------------------------------------------------------
        {
           dilemma = "land_enc_dilemma_skirmish_cth",
           victory_incident = "land_enc_incident_battle_won_skirmish",
           avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
           is_exclusive_to_zone = true,
           zone = "cathay",
           victory_targets = { character = true, force = false, faction = false, region = false },
           avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_skirmish_kis",
            victory_incident = "land_enc_incident_battle_won_skirmish",
            avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
            is_exclusive_to_zone = true,
            zone = "kislev",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_skirmish_ogr",
            victory_incident = "land_enc_incident_battle_won_skirmish",
            avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
            is_exclusive_to_zone = true,
            zone = "mountainsofmourn",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_skirmish_nur",
            victory_incident = "land_enc_incident_battle_won_skirmish",
            avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
            is_exclusive_to_zone = true,
            zone = "chaoswastes",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_skirmish_tze",
            victory_incident = "land_enc_incident_battle_won_skirmish",
            avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
            is_exclusive_to_zone = true,
            zone = "chaoswastes",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        ---------------------------------------------------------------------------
        -- (Easier) Underground Rebellions
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_underground_cth",
            victory_incident = "land_enc_incident_battle_won_underground",
            avoidance_incident = "land_enc_incident_battle_avoided_underground",
            is_exclusive_to_zone = true,
            zone = "cathay",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_underground_kis",
            victory_incident = "land_enc_incident_battle_won_underground",
            avoidance_incident = "land_enc_incident_battle_avoided_underground",
            is_exclusive_to_zone = true,
            zone = "kislev",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_underground_ogr",
            victory_incident = "land_enc_incident_battle_won_underground",
            avoidance_incident = "land_enc_incident_battle_avoided_underground",
            is_exclusive_to_zone = true,
            zone = "mountainsofmourn",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_underground_tze",
            victory_incident = "land_enc_incident_battle_won_underground",
            avoidance_incident = "land_enc_incident_battle_avoided_underground",
            is_exclusive_to_zone = true,
            zone = "chaoswastes",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        }
    },

    [2] = { -- 8 events
        ---------------------------------------------------------------------------
        -- (Easy) Bandits can be Empire, Wood Elves, Norscans, Chaos dwarfs
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_bandits_emp",
            victory_incident = "land_enc_incident_battle_won_bandits",
            avoidance_incident = "land_enc_incident_battle_avoided_bandits",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_bandits_wef",
            victory_incident = "land_enc_incident_battle_won_bandits",
            avoidance_incident = "land_enc_incident_battle_avoided_bandits",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_bandits_nor",
            victory_incident = "land_enc_incident_battle_won_bandits",
            avoidance_incident = "land_enc_incident_battle_avoided_bandits",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_bandits_chads",
            victory_incident = "land_enc_incident_battle_won_bandits",
            avoidance_incident = "land_enc_incident_battle_avoided_bandits",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = true, force = false, faction = false, region = false }
        },
        ---------------------------------------------------------------------------
        -- (Mid) Incursions can be High Elves, Lizardmen, Vampire Coast
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_incursion_army_hef",
            victory_incident = "land_enc_incident_battle_won_incursion_hef",
            avoidance_incident = "land_enc_incident_battle_avoided_incursion",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = true, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_incursion_army_lzd",
            victory_incident = "land_enc_incident_battle_won_incursion_lzd",
            avoidance_incident = "land_enc_incident_battle_avoided_incursion",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = true, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_incursion_army_vco",
            victory_incident = "land_enc_incident_battle_won_incursion_vco",
            avoidance_incident = "land_enc_incident_battle_avoided_incursion",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = true, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        ---------------------------------------------------------------------------
        -- (Mid) Waystone defenses can be High Elves only. Knife ears will try to defend their places of power
        -- Differences: Makes the region in which the battle was fought tempestous. Chaos corruption + 5 in the area. Gives army buff that grants magic regeneration by +30 to the beater army
        ---------------------------------------------------------------------------
        --{
        --    difficulty_level = 2,
        --    dilemma = "land_enc_dilemma_waystone_defense_army_hef",
        --    is_exclusive_to_zone = false,
        --    victory_incident = "land_enc_waystone_defense_won_incursion_hef",
        --    avoidance_incident = "land_enc_waystone_defense_avoided_incursion"
        --},

        ---------------------------------------------------------------------------
        -- (Mid Upper) Surprise Attacks can be Beastmen, Skaven
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_surprise_attack_bst",
            victory_incident = "land_enc_incident_battle_won_surprise_bst",
            avoidance_incident = "land_enc_incident_battle_avoided_surprise",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = true, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_surprise_attack_skv",
            victory_incident = "land_enc_incident_battle_won_surprise_skv",
            avoidance_incident = "land_enc_incident_battle_avoided_surprise",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = true, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        }
    },

    [3] = { -- 5 events
        ---------------------------------------------------------------------------
        -- (Mid Upper) Daemonic Invasion
        ---------------------------------------------------------------------------
        --{ TODO
        --    difficulty_level = 2,
        --    dilemma = "land_enc_dilemma_surprise_attack_skv",
        --    is_exclusive_to_zone = false,
        --    victory_incident = "land_enc_incident_battle_won_surprise_skv",
        --    losing_incident = "",
        --    avoidance_incident = "land_enc_incident_battle_avoided_surprise"
        --},

        ---------------------------------------------------------------------------
        -- (Hard) Battlefields can be Greenskins, Dark Elves, Vampires, Tomb Kings, Warriors of Chaos, Daemons Undivided and Demons of Khorne (for the ancillaries IM ONLY), Demons of Slaneesh (for the ancillaries IM ONLY)
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_battlefield_grn",
            victory_incident = "land_enc_incident_battle_won_battlefield_grn",
            avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_battlefield_def",
            victory_incident = "land_enc_incident_battle_won_battlefield_def",
            avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_battlefield_vmp",
            victory_incident = "land_enc_incident_battle_won_battlefield_vmp",
            avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_battlefield_tmb",
            victory_incident = "land_enc_incident_battle_won_battlefield_tmb",
            avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_battlefield_dwf",
            victory_incident = "land_enc_incident_battle_won_battlefield_dwf",
            avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },

        --{ --TODO
        --    dilemma = "land_enc_dilemma_battlefield_wco",
        --    victory_incident = "land_enc_incident_battle_won_battlefield_wco",
        --    avoidance_incident = "land_enc_incident_battle_avoided_battlefield"
        --    is_exclusive_to_zone = false,
        --    zone = "_",
        --    victory_targets = { character = true, force = false, faction = false, region = false },
        --    avoidance_targets = { character = false, force = true, faction = false, region = false }
        --},

        --{ --TODO
        --    dilemma = "land_enc_dilemma_battlefield_doc",
        --    victory_incident = "land_enc_incident_battle_won_battlefield_doc",
        --    avoidance_incident = "land_enc_incident_battle_avoided_battlefield"
        --    is_exclusive_to_zone = false,
        --    zone = "_",
        --    victory_targets = { character = true, force = false, faction = false, region = false },
        --    avoidance_targets = { character = false, force = true, faction = false, region = false }
        --},

        --{ --TODO
        --    dilemma = "land_enc_dilemma_battlefield_kho",
        --    victory_incident = "land_enc_incident_battle_won_battlefield_kho",
        --    avoidance_incident = "land_enc_incident_battle_avoided_battlefield"
        --    is_exclusive_to_zone = false,
        --    zone = "_",
        --    victory_targets = { character = true, force = false, faction = false, region = false },
        --    avoidance_targets = { character = false, force = true, faction = false, region = false }
        --},

        --{ --TODO
        --    dilemma = "land_enc_dilemma_battlefield_sla",
        --    victory_incident = "land_enc_incident_battle_won_battlefield_sla",
        --    avoidance_incident = "land_enc_incident_battle_avoided_battlefield"
        --    is_exclusive_to_zone = false,
        --    zone = "_",
        --    victory_targets = { character = true, force = false, faction = false, region = false },
        --    avoidance_targets = { character = false, force = true, faction = false, region = false }
        --}
    },

    [4] = { -- 7 events
        ---------------------------------------------------------------------------
        -- (Harder) Daemoic Gifts battlefields
        ---------------------------------------------------------------------------
        {
            dilemma = "land_enc_dilemma_daemonic_gift_chainsword",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_chainsword",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_daemonic_gift_the_bane_spear",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_the_bane_spear",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_daemonic_gift_skars_kraken_killer",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_skars_kraken_killer",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_daemonic_gift_gilellions_soulnetter",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_daemonic_gift_slaaneshs_blade",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_slaaneshs_blade",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            id = 28,
            dilemma = "land_enc_dilemma_daemonic_gift_personal_sycophant",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_personal_sycophant",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh",
            difficulty_level = 4,
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        },
        {
            dilemma = "land_enc_dilemma_daemonic_gift_dark_princes_paramour",
            victory_incident = "land_enc_incident_battle_won_daemonic_gift_dark_princes_paramour",
            avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh",
            is_exclusive_to_zone = false,
            zone = "_",
            victory_targets = { character = true, force = false, faction = false, region = false },
            avoidance_targets = { character = false, force = true, faction = false, region = false }
        }
    },
    ---------------------------------------------------------------------------
    -- (Harder) Three way battlefields
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- (Extreme) Last stand: Give a trait: The ultimate fighter
    ---------------------------------------------------------------------------

}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- tavern (from constants/events/tavern_events.lua)
-- Source file is empty (stub).

M.tavern = {}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- tower_spot (from constants/events/tower_spot_events.lua)
-- Source file is empty (stub).

M.tower_spot = {}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- treasure_type (from constants/events/treasure_type_events.lua)

--[[
The types of treasures one can encounter with this mod. There are no variations.
Using incidents because no decision is needed to trigger a battle.

Every incident needs data in:
=============================
INCIDENT
=============================
=== DB
[Describes the incident data]
1. cdir_events_incident_option_junctions_tables (Objective + chance)
2. cdir_events_incident_payloads_tables (Rewards)
3. incidents_tables (Declaration of incidents)

=== LOC
1.incidents
(join together then incidents_ key + required info + event_key (ex: land_enc_incident_tomb_robbing)
incidents_ localised_title_
           localised_description_

=============================
INCIDENT EFFECT (IF IT GIVES AN EFFECT NOT TREASURES OR ANCILLARIES)
=============================
=== DB
[If you want custom effects you need the following tables]
1. effect_bundles_tables (_NONE = automatically to all your faction / _)
2. effect_bundles_to_effects_junctions_tables

=== LOC
1. effect_bundles
(join together then incidents_ key + required info + effect_key (ex: land_enc_incident_tomb_robbing)
effect_bundles_ localised_title_
                localised_description_
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
    }
}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- complex_continuity (from constants/events/complex_continuity_events.lua)

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

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- smithy (from constants/events/smithy_events.lua)

M.smithy = {
    "land_enc_dilemma_smithy_reclamation",
    "land_enc_dilemma_smithy_defense",
    "land_enc_dilemma_smithy_visit_level_1",
    "land_enc_dilemma_smithy_visit_level_2",
    "land_enc_dilemma_smithy_visit_level_3"
}

return M
