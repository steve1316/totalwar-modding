--- Spot offers: the treasure sites a treasure spot rolls and the offers their dilemmas draw. Pure data. features/spot_offers.lua reads it,
--- and helper_scripts/generators/update_leapoi_spot_offers.py writes the DB rows and loc for every site and offer listed here.
---
--- Offer fields, all optional apart from `key`, `pool` and `tags`:
---   cost            Gold paid from the treasury (Easy value, scaled by difficulty). An offer the treasury cannot pay is not drawn.
---   gold            Gold gained (Easy value, scaled). A negative value inside a gamble outcome is a loss.
---   fixed_gold      True when `cost` and `gold` do not scale with difficulty.
---   items           { rarities, count }: random items of those rarities.
---   unique          How many legendary items.
---   recruit         { count, tiers, unit_types }: units of the lord's culture join the army.
---   renown          How many Regiments of Renown of the lord's culture join.
---   hero_rank       A freed hero of this rank joins.
---   xp              Experience for the lord.
---   army_bundle     { bundle, turns } on the lord's army.
---   faction_bundle  { bundle, turns } on the lord's faction.
---   trait           A trait the lord gains for good. Not drawn when the lord has it.
---   wound           The lord is wounded for this many turns at the faction's next turn start.
---   camp            True: the army cannot move again this turn.
---   heal            True: every unit is healed to full.
---   sacrifice       { ranks }: the weakest regular unit is removed and every other unit gains that many ranks.
---   daemon_army     True: a hard Chaos army marches on the faction's capital.
---   dividends       { per_turn, turns, effect_bundle }: gold each turn start.
---   incident        A site's old incident, fired as the signature reward.
---   gamble          A list of outcomes { weight, name, ...fields }. One is rolled when the offer is taken, and its fields apply.
---   realm           The realm target kind, see `M.realm_kinds`. The offer is not drawn when it has no target.
---   region_bundle, province_bundle, target_faction_bundle  { bundle, turns } on the realm target.
---   relations       Relations change for the realm target (see `M.realm_kinds`).
---   points          Development points for the realm target.
---   heal_garrison   True: the realm target's garrison is healed to full.
---   count           How many realm targets.
---
--- Pre-battle offer fields (pool "pre_battle"). Taking one pays its cost and the battle starts with it:
---   budget          Multiplies the enemy army's gold budget, e.g. 0.75.
---   fewer_units     The enemy army fields this many fewer units.
---   no_heroes       True: the enemy army has no heroes.
---   max_tier        The enemy army's units are at most this tier.
---   enemy_strength  The enemy's units start at this share of full strength.
---   enemy_bundle    A bundle on the enemy army for the battle.
---   traitor         { count, tiers }: units of the enemy's faction join our army, and the enemy fields that many fewer.
---   battle_bundle   A bundle on our army for this battle only, taken off when it ends. Its notice is the tower's for that bundle.
---   allies          { min, max } regular units in an allied army that joins the battle, with its lord.
---   own_strength    Our units start the battle at this share of their strength (a gamble outcome).

--- Key prefix of the spot offers' own effect bundles.
local SPOT_BUNDLE = "land_enc_effect_spot_"

--- The tower's attrition bundle for 3 turns, shared by the plague offers.
local PLAGUE = { "land_enc_effect_tower_plague_bearer", 3 }

local M = {}

--- Gold multiplier by difficulty, for `cost` and `gold`.
M.gold_multiplier = { easy = 1, medium = 1.5, hard = 2 }

--- Scaled gold is rounded to this step.
M.gold_step = 50

--- Offers drawn on top of a site's signature offer.
M.extras_per_site = 2

--- Weight of an offer sharing a tag with the site, against 1 for any other eligible offer.
M.tag_weight = 4

--- Choice key prefix of an offer on a site dilemma, e.g. LEAPOI_SPT_TAKE_THE_GOLD.
M.choice_key_prefix = "LEAPOI_SPT_"

--- Choice key of Walk away, last on every site dilemma.
M.walk_away_choice_key = "LEAPOI_SPT_WALK_AWAY"

--- Choice key of a site's signature offer. The vanilla FIRST key sorts first, and each site dilemma labels it with its signature's name.
M.signature_choice_key = "FIRST"

--- Bundle on an army that cannot move until its next turn, after Search every corner.
M.camp_bundle = "land_enc_effect_spot_camping"

--- Bundle prefix, followed by the turns, showing on an army that its lord will be wounded at the next turn start, e.g. ..._wound_owed_5.
M.wound_bundle_prefix = "land_enc_effect_spot_wound_owed_"

--- Dilemma key prefix of a site, e.g. land_enc_dilemma_site_hidden_tomb.
M.dilemma_prefix = "land_enc_dilemma_site_"

--- Text line prefix of an offer, followed by the offer key and the difficulty, e.g. dummy_land_enc_spot_take_the_gold_easy.
M.line_prefix = "dummy_land_enc_spot_"

--- Line under an offer the treasury cannot pay, the same for every offer.
M.unaffordable_line = "dummy_land_enc_spot_unaffordable"

--- Event feed message prefix after `land_enc_`, e.g. spot_roll_the_bones_won.
M.message_prefix = "spot_"

--- Percent chance a battle spot opens with pre-battle offers instead of its plain Fight or Avoid dilemma.
M.pre_battle_chance = 30

--- Pre-battle offers drawn between Fight and Avoid.
M.offers_per_battle = 2

--- Choice key of Avoid on a battle dilemma with offers. It sorts last, as the tower's Leave does, and carries the dilemma's own Avoid label.
M.avoid_choice_key = "LEAPOI_SPT_AVOID"

--- Choice key of Fight, the vanilla FIRST key the battle dilemmas already use.
M.fight_choice_key = "FIRST"

--- Gold per unit of a hired allied army, { min, max }, as the tower's allies use.
M.ally_gold_per_unit = { 700, 1000 }

--- Realm target kinds, measured from the spot:
---   own_region       Your nearest region.
---   raise_region     Your nearest region whose main building can go up a level.
---   own_province     Your nearest region's province.
---   enemy_region     The nearest region of a faction at war with you.
---   enemy_regions    The `count` nearest such regions.
---   enemy_province   The nearest such region's province.
---   enemy_capital    The capital of the nearest faction at war with you.
---   friend           The nearest faction at peace with you.
---   biggest_faction  The faction with the most regions, other than yours.
---   neighbours       Every faction at peace with you that owns a region next to one of yours.
---   rival_pair       The two biggest of the 6 nearest factions, set against each other.
---   enemy_friends    The nearest enemy, made friendlier with your other enemies.
M.realm_kinds = { "own_region", "raise_region", "own_province", "enemy_region", "enemy_regions", "enemy_province", "enemy_capital", "friend",
    "biggest_faction", "neighbours", "rival_pair", "enemy_friends" }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Sites

--- Treasure sites. `signature` is always offered when eligible. `ui_image` is the dilemma picture. The first 8 are the old treasure incidents.
M.sites = {
    { key = "hidden_tomb", tags = { "loot", "curse" }, signature = "tomb_robbing", ui_image = "books_of_nagash" },
    { key = "abandoned_camp", tags = { "recovery", "deal" }, signature = "abandoned_camp", ui_image = "wh2_rogue_army_encountered" },
    { key = "buried_relics", tags = { "loot", "lore" }, signature = "buried_relics", ui_image = "wh2_sea_encounters_2" },
    { key = "hidden_temple", tags = { "blessing" }, signature = "hidden_temple", ui_image = "old_ones_temples_up" },
    { key = "caravan_remnants", tags = { "loot", "deal" }, signature = "caravan_remnants", ui_image = "ivory_road" },
    { key = "whispers_of_our_god", tags = { "blessing", "curse" }, signature = "whispers_of_the_gods", ui_image = "winds_of_magic_change" },
    { key = "the_explorer", tags = { "lore", "realm" }, signature = "the_explorer", ui_image = "minor_cult" },
    { key = "legendary_bard", tags = { "realm", "deal" }, signature = "legendary_bard", ui_image = "wulfhart_hunters" },
    { key = "ruined_shrine", tags = { "blessing", "curse" }, signature = "holy_water", ui_image = "old_ones_temples_down" },
    { key = "smugglers_cache", tags = { "deal", "realm_others" }, signature = "pay_the_smugglers", ui_image = "wh2_sea_encounters_1" },
    { key = "beast_lair", tags = { "recruit", "gamble" }, signature = "tame_the_beast", ui_image = "attrition_swamp" },
    { key = "old_battlefield", tags = { "recruit", "loot" }, signature = "salvage_a_war_machine", ui_image = "carnage_weapons" },
    { key = "witchs_hut", tags = { "gamble", "curse" }, signature = "dark_pact", ui_image = "ai_wins_soul" },
    { key = "collapsed_mine", tags = { "loot", "gamble" }, signature = "search_every_corner", ui_image = "under_empire_discovered" },
    { key = "merchants_wagon", tags = { "deal" }, signature = "buy_from_the_trader", ui_image = "imperial_supplies" },
    { key = "sunken_library", tags = { "lore", "realm" }, signature = "read_the_scrolls", ui_image = "story_panels/chd_drill_machinations" },
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Offers

M.offers = {
    --- Signature rewards of the old treasure sites: the old incident fires.
    { key = "tomb_robbing", pool = "signature", tags = {}, incident = "land_enc_incident_tomb_robbing" },
    { key = "abandoned_camp", pool = "signature", tags = {}, incident = "land_enc_incident_abandoned_camp" },
    { key = "buried_relics", pool = "signature", tags = {}, incident = "land_enc_incident_buried_relics" },
    { key = "hidden_temple", pool = "signature", tags = {}, incident = "land_enc_incident_hidden_temple" },
    { key = "caravan_remnants", pool = "signature", tags = {}, incident = "land_enc_incident_caravan_remnants" },
    { key = "whispers_of_the_gods", pool = "signature", tags = {}, incident = "land_enc_incident_whispers_of_the_gods" },
    { key = "the_explorer", pool = "signature", tags = {}, incident = "land_enc_incident_the_explorer" },
    { key = "legendary_bard", pool = "signature", tags = {}, incident = "land_enc_incident_legendary_bard" },

    --- Treasure: loot.
    { key = "take_the_gold", pool = "treasure", tags = { "loot" }, gold = 1500 },
    { key = "strip_the_valuables", pool = "treasure", tags = { "loot", "curse" }, gold = 3000, army_bundle = { SPOT_BUNDLE .. "strip_the_valuables", 5 } },
    { key = "pry_open_the_reliquary", pool = "treasure", tags = { "loot", "curse" }, items = { rarities = { "rare" }, count = 1 }, wound = 2 },
    { key = "search_every_corner", pool = "treasure", tags = { "loot" }, items = { rarities = { "common", "uncommon", "rare" }, count = 2 }, camp = true },
    { key = "the_hidden_vault", pool = "treasure", tags = { "loot" }, cost = 2500, unique = 1 },

    --- Treasure: gambles.
    { key = "roll_the_bones", pool = "treasure", tags = { "gamble" }, gamble = {
        { 1, "won", items = { rarities = { "rare" }, count = 1 } },
        { 1, "lost", gold = -1000 },
    } },
    { key = "drink_from_the_spring", pool = "treasure", tags = { "gamble", "recovery" }, gamble = {
        { 1, "won", heal = true },
        { 1, "lost", army_bundle = PLAGUE },
    } },
    { key = "open_the_sealed_door", pool = "treasure", tags = { "gamble" }, gamble = {
        { 1, "won", unique = 1 },
        { 1, "lost", wound = 3 },
    } },
    { key = "stake_the_treasury", pool = "treasure", tags = { "gamble", "deal" }, cost = 1000, gamble = {
        { 1, "won", gold = 2500 },
        { 1, "lost" },
    } },
    { key = "touch_the_relic", pool = "treasure", tags = { "gamble", "blessing", "curse" }, gamble = {
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "bless_the_banners", 5 } },
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "holy_water", 5 } },
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "ancient_tactics", 5 } },
        { 1, "cursed", army_bundle = { SPOT_BUNDLE .. "strip_the_valuables", 5 } },
        { 1, "cursed", army_bundle = { PLAGUE[1], 5 } },
        { 1, "cursed", army_bundle = { SPOT_BUNDLE .. "touch_the_relic_frailty", 5 } },
    } },
    { key = "gamble_with_the_hermit", pool = "treasure", tags = { "gamble" }, cost = 500, gamble = {
        { 1, "won", unique = 1 },
        { 2, "lost" },
    } },

    --- Treasure: blessings.
    { key = "leave_an_offering", pool = "treasure", tags = { "blessing" }, cost = 500, army_bundle = { SPOT_BUNDLE .. "leave_an_offering", 5 } },
    { key = "bless_the_banners", pool = "treasure", tags = { "blessing" }, cost = 1000, army_bundle = { SPOT_BUNDLE .. "bless_the_banners", 8 } },
    { key = "holy_water", pool = "treasure", tags = { "blessing" }, cost = 1000, army_bundle = { SPOT_BUNDLE .. "holy_water", 5 } },
    { key = "oath_at_the_altar", pool = "treasure", tags = { "blessing" }, trait = "land_enc_trait_spot_shrine_sworn" },
    { key = "sanctified_weapons", pool = "treasure", tags = { "blessing" }, cost = 1000, army_bundle = { SPOT_BUNDLE .. "sanctified_weapons", 5 } },

    --- Treasure: curses and pacts.
    { key = "dark_pact", pool = "treasure", tags = { "curse" }, trait = "land_enc_trait_spot_pact_bound", wound = 5 },
    { key = "cursed_hoard", pool = "treasure", tags = { "curse", "loot" }, gold = 4000, army_bundle = PLAGUE },
    { key = "bloodstained_blades", pool = "treasure", tags = { "curse" }, army_bundle = { SPOT_BUNDLE .. "bloodstained_blades", 5 } },
    { key = "feed_the_shadows", pool = "treasure", tags = { "curse" }, sacrifice = { ranks = 1 } },
    { key = "daemons_bargain", pool = "treasure", tags = { "curse", "gamble" }, unique = 2, daemon_army = true },

    --- Treasure: recruits.
    { key = "recruit_the_survivors", pool = "treasure", tags = { "recruit" }, recruit = { count = 2, tiers = { 1, 2 } } },
    { key = "hire_sellswords", pool = "treasure", tags = { "recruit", "deal" }, cost = 2000, recruit = { count = 1, tiers = { 3, 4 } } },
    { key = "free_the_prisoner", pool = "treasure", tags = { "recruit" }, hero_rank = 5 },
    { key = "tame_the_beast", pool = "treasure", tags = { "recruit", "gamble" },
        recruit = { count = 1, tiers = { 1, 2, 3, 4, 5 }, unit_types = { "monster", "war_beast", "monstrous_infantry", "monstrous_cavalry" } } },
    { key = "hire_a_regiment_of_renown", pool = "treasure", tags = { "recruit", "deal" }, cost = 3000, renown = 1 },
    { key = "salvage_a_war_machine", pool = "treasure", tags = { "recruit", "loot" }, cost = 1500, recruit = { count = 1, tiers = { 1, 2, 3, 4, 5 }, unit_types = { "warmachine" } } },

    --- Treasure: deals.
    { key = "buy_from_the_trader", pool = "treasure", tags = { "deal", "loot" }, cost = 2000, items = { rarities = { "rare" }, count = 1 } },
    { key = "pay_the_smugglers", pool = "treasure", tags = { "deal" }, cost = 1000, faction_bundle = { "land_enc_effect_tower_recruitment_cache", 5 } },
    { key = "invest_in_the_caravan", pool = "treasure", tags = { "deal" }, cost = 1500, fixed_gold = true,
        dividends = { per_turn = 250, turns = 10, effect_bundle = "land_enc_effect_tower_dividends" } },
    { key = "hire_guides", pool = "treasure", tags = { "deal", "lore" }, cost = 500, army_bundle = { SPOT_BUNDLE .. "hire_guides", 5 } },
    { key = "buy_supplies", pool = "treasure", tags = { "deal", "recovery" }, cost = 800, army_bundle = { SPOT_BUNDLE .. "buy_supplies", 5 } },

    --- Treasure: lore.
    { key = "read_the_scrolls", pool = "treasure", tags = { "lore" }, faction_bundle = { SPOT_BUNDLE .. "read_the_scrolls", 5 } },
    { key = "map_the_passes", pool = "treasure", tags = { "lore" }, army_bundle = { SPOT_BUNDLE .. "map_the_passes", 10 } },
    { key = "ancient_tactics", pool = "treasure", tags = { "lore" }, army_bundle = { SPOT_BUNDLE .. "ancient_tactics", 5 } },

    --- Realm: your own lands.
    { key = "endow_the_province", pool = "realm", tags = { "realm" }, cost = 2000, realm = "own_region", points = 50 },
    { key = "shore_up_the_walls", pool = "realm", tags = { "realm" }, cost = 1500, realm = "own_region", heal_garrison = true, region_bundle = { SPOT_BUNDLE .. "shore_up_the_walls", 10 } },
    { key = "raise_the_settlement", pool = "realm", tags = { "realm" }, cost = 5000, realm = "raise_region" },
    { key = "quell_the_unrest", pool = "realm", tags = { "realm" }, realm = "own_province", province_bundle = { SPOT_BUNDLE .. "quell_the_unrest", 10 } },
    { key = "bountiful_harvest", pool = "realm", tags = { "realm" }, cost = 1000, realm = "own_province", province_bundle = { SPOT_BUNDLE .. "bountiful_harvest", 10 } },
    { key = "hidden_mint", pool = "realm", tags = { "realm", "loot" }, faction_bundle = { SPOT_BUNDLE .. "hidden_mint", 10 } },

    --- Realm: rivals nearby.
    { key = "stir_their_rebels", pool = "realm", tags = { "realm_others" }, cost = 1500, realm = "enemy_province", province_bundle = { SPOT_BUNDLE .. "stir_their_rebels", 5 } },
    { key = "poison_their_wells", pool = "realm", tags = { "realm_others" }, cost = 2000, realm = "enemy_region", region_bundle = { SPOT_BUNDLE .. "poison_their_wells", 5 } },
    { key = "undermine_their_walls", pool = "realm", tags = { "realm_others" }, cost = 1500, realm = "enemy_region",
        region_bundle = { SPOT_BUNDLE .. "undermine_their_walls", 5 } },
    { key = "spread_the_plague", pool = "realm", tags = { "realm_others", "curse" }, realm = "enemy_regions", count = 3,
        region_bundle = { SPOT_BUNDLE .. "spread_the_plague", 5 }, army_bundle = { PLAGUE[1], 2 } },
    { key = "send_gifts", pool = "realm", tags = { "realm_others", "deal" }, cost = 1000, realm = "friend", relations = 3 },
    { key = "spy_on_their_capital", pool = "realm", tags = { "realm_others", "lore" }, cost = 500, realm = "enemy_capital" },

    --- Realm: far-off factions.
    { key = "curse_a_distant_king", pool = "realm", tags = { "realm_others", "curse" }, cost = 1500, realm = "biggest_faction",
        target_faction_bundle = { SPOT_BUNDLE .. "curse_a_distant_king", 10 } },
    { key = "share_the_find", pool = "realm", tags = { "realm_others", "lore" }, realm = "neighbours", relations = 2,
        faction_bundle = { SPOT_BUNDLE .. "share_the_find", 5 }, target_faction_bundle = { SPOT_BUNDLE .. "share_the_find", 5 } },
    { key = "point_them_at_each_other", pool = "realm", tags = { "realm_others" }, cost = 2000, realm = "rival_pair", relations = -3 },
    { key = "sell_their_secrets", pool = "realm", tags = { "realm_others", "deal" }, gold = 2000, realm = "enemy_friends", relations = 2 },

    --- Pre-battle: sabotage on the enemy army.
    { key = "bribe_a_scout", pool = "pre_battle", tags = { "sabotage" }, cost = 1500, budget = 0.75 },
    { key = "thin_their_ranks", pool = "pre_battle", tags = { "sabotage" }, cost = 1000, fewer_units = 3 },
    { key = "poison_their_stores", pool = "pre_battle", tags = { "sabotage" }, cost = 1000, enemy_strength = 0.75 },
    { key = "kill_the_captain", pool = "pre_battle", tags = { "sabotage" }, cost = 1500, no_heroes = true },
    { key = "keep_the_veterans_away", pool = "pre_battle", tags = { "sabotage" }, cost = 1000, max_tier = 2 },
    { key = "spread_dread", pool = "pre_battle", tags = { "sabotage" }, cost = 1500, enemy_bundle = "land_enc_effect_tower_break_their_spirit" },
    { key = "turn_a_traitor", pool = "pre_battle", tags = { "sabotage" }, cost = 2000, traitor = { count = 1, tiers = { 2, 3, 4 } } },

    --- Pre-battle: buffs on our army for this battle.
    { key = "hold_war_rites", pool = "pre_battle", tags = { "buff" }, cost = 1500, battle_bundle = "land_enc_effect_tower_war_rites" },
    { key = "hone_the_blades", pool = "pre_battle", tags = { "buff" }, cost = 1000, battle_bundle = "land_enc_effect_tower_whetstones_and_oil" },
    { key = "paint_warding_sigils", pool = "pre_battle", tags = { "buff" }, cost = 1500, battle_bundle = "land_enc_effect_tower_warding_sigils" },
    { key = "fire_kissed_blades", pool = "pre_battle", tags = { "buff" }, cost = 1000, battle_bundle = "land_enc_effect_tower_fire_kissed_blades" },
    { key = "steel_our_resolve", pool = "pre_battle", tags = { "buff" }, cost = 1000, battle_bundle = "land_enc_effect_tower_iron_resolve" },
    { key = "call_the_winds", pool = "pre_battle", tags = { "buff" }, cost = 1000, battle_bundle = "land_enc_effect_tower_call_the_winds" },
    { key = "raid_the_quartermaster", pool = "pre_battle", tags = { "buff" }, cost = 1000, battle_bundle = "land_enc_effect_tower_quartermasters_cache" },

    --- Pre-battle: allies and gambles.
    { key = "hire_local_allies", pool = "pre_battle", tags = { "allies" }, cost = 3000, allies = { 5, 7 } },
    { key = "night_raid", pool = "pre_battle", tags = { "gamble" }, gamble = {
        { 1, "won", budget = 0.75 },
        { 1, "lost", own_strength = 0.9 },
    } },
}

--- Offer key -> offer record.
M.by_key = {}
for _, offer in ipairs(M.offers) do
    M.by_key[offer.key] = offer
end

--- Site key -> site record.
M.site_by_key = {}
for _, site in ipairs(M.sites) do
    M.site_by_key[site.key] = site
end

return M
