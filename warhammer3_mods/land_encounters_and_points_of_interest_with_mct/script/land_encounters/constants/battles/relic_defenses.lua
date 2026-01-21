require("script/land_encounters/constants/utils/common")
--[[
Creates the battle forces to fight in the battles 

Every force needs:
==================
BATTLE FORCE
==================
== DB
faction_agent_permitted_subtypes_tables (declares the hero units the faction can use [Reuse old factions in this case])
faction_rebellion_units_junctions_tables (declares the common units the faction can use)
(get names from campaign_rogue_army_leaders_table)
== LOC
None

--]]

-- Cathay
-- Miao Ying -> But gives frostbite attacks to whole army
--> Use this to avoid breaking the game -> wh3_main_trait_blessed_by_ind_blades

-- Lizardmen
-- Kroggaar
-- gorrok

-- Empire
-- Volkmar