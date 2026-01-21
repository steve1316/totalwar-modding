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
local treasures = {
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

return treasures