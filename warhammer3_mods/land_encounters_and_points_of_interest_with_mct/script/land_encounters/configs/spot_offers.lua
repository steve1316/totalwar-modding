--- Spot offers: the treasure sites a treasure spot rolls and the offers their dilemmas draw. Pure data. features/spot_offers.lua reads it,
--- and helper_scripts/generators/update_leapoi_spot_offers.py writes the DB rows and loc for every site and offer listed here.
---
--- Any field may differ by difficulty, written as `S(easy, medium, hard)` (utils/steps.lua). `tiered(key)` names a bundle with one version per
--- difficulty, e.g. land_enc_effect_spot_leave_an_offering_medium. Paid offers price on one of the cost bands below.
---
--- Offer fields, all optional apart from `key`, `pool` and `tags`:
---   cost            Gold paid from the treasury. An offer the treasury cannot pay is not drawn.
---   gold            Gold gained. A negative value inside a gamble outcome is a loss.
---   items           { rarities, count }: random items of those rarities.
---   unique          How many legendary items.
---   recruit         { count, tiers, unit_types }: units of the lord's culture join the army.
---   renown          How many Regiments of Renown of the lord's culture join.
---   hero_rank       A freed hero of this rank joins.
---   xp              Experience for the lord.
---   army_bundle     { bundle, turns } on the lord's army.
---   faction_bundle  { bundle, turns } on the lord's faction.
---   trait           A trait the lord gains for good. Not drawn when the lord has it.
---   wound           The lord is wounded for this many turns, at once.
---   camp            True: the army cannot move again this turn.
---   heal            True: every unit is healed to full.
---   sacrifice       { ranks }: the weakest regular unit is removed and every other unit gains that many ranks.
---   daemon_armies   How many hard Chaos armies march on the faction's capital.
---   guardian        A battle starts at the site, against an army that attacks the lord at once: true at the current difficulty, or a
---                   difficulty key, e.g. "hard". On an offer or a gamble outcome.
---   dividends       { per_turn, turns }: gold each turn start, shown by the `dividends_bundle_prefix` bundle for that amount.
---   incident        A site's old incident, fired as the signature reward.
---   gamble          A list of outcomes { weight, name, ...fields }. One is rolled when the offer is taken, and its fields apply.
---   realm           The realm target kind, see `M.realm_kinds`. The offer is not drawn when it has no target.
---   region_bundle, province_bundle, target_faction_bundle  { bundle, turns } on the realm target.
---   relations       Relations change for the realm target (see `M.realm_kinds`), in the game's dilemma steps (-6 to 6). Each step reads as
---                   10 relations in the offer text.
---   points          Development points for the realm target.
---   heal_garrison   True: the realm target's garrison is healed to full.
---   garrison_strength  Each unit of the realm target's garrison drops to this share of its strength.
---   reveal_turns    The realm target's region stays revealed through the shroud for this many turns, and the result lists its garrison.
---   count           How many realm targets.
---
--- Pre-battle offer fields (pool "pre_battle"). Taking one pays its cost and the battle starts with it:
---   budget          Multiplies the enemy army's gold budget, e.g. 0.75.
---   fewer_units     The enemy army fields this many fewer units.
---   no_heroes       True: the enemy army has no heroes.
---   max_tier        The enemy army's units are at most this tier.
---   enemy_strength  The enemy's units start at this share of full strength.
---   champion_strength  The enemy's most expensive unit starts at this share of full strength.
---   enemy_bundle    A bundle on the enemy army for the battle.
---   traitor         { count, tiers }: units of the enemy's faction join our army, and the enemy fields that many fewer.
---   battle_bundle   A bundle on our army for this battle only, taken off when it ends. Its notice is the tower's for that bundle.
---   allies          { min, max } units in an allied army that joins the battle, its lord included.
---   group           Offers sharing a group (the allied army sizes) are drawn at most one at a time.
---   notice          The battle notice to show instead of the offer's own.
---   own_strength    Our units start the battle at this share of their strength (a gamble outcome).
---   trick           True: the battle script does it in this battle, under the offer's key (the tower's trick names).
---   targets         Night terrors: how many of the enemy's most expensive units flee.
---   shoots          True: only drawn when our army has missile units or artillery.
---   caster          True: only drawn when our army has a spellcaster.
---   for_ally        Only drawn for a battle with an allied army (Ally in Peril, or an allied Battlefield): true for any ally, "sized" for a
---                   sized one (Turn the Tables' escort), "full" for a full army.
---   ally_bundle     A bundle on the allied army for the battle.
---   ally_ranks      The allied army's regular units gain this many ranks.
---   extra_ally_units  A sized allied army fields this many more units.
---   ally_budget     Multiplies a full allied army's gold budget.
---
--- A battle notice whose effect differs by difficulty carries the difficulty in its name, e.g. thin_the_ranks_medium (see `steps.notice`).
---
--- Mission fields (pool "mission"). A mission is a stay offer: taking it pays its cost and reopens the dilemma, so missions stack before the
--- battle. The battle script tracks it under its key (the tower's mission names). A won battle pays a mission met:
---   battle_value    The mission's target in battle, e.g. 0.4 of the enemy's soldiers or 480 seconds.
---   gold            Gold to the treasury (Easy value, scaled).
---   items           { rarities, count }: random items.
---   unique          How many unique items.
---   battle_item     True: 1 item of the battle's own victory rarities.
---   unit_ranks      Ranks for the unit Guard the standard marks.
---   lord_xp         Experience for our lord.
---   roster          Only drawn against a faction that fields one of these unit types.
---   max_units       Only drawn when our army has at most this many regular units.
---   trophy          True: a copy of the enemy's most expensive unit joins our army.
---
--- Spoils fields (pool "spoils", drawn on the spoils pick after a won battle spot, which also draws realm offers and offers marked `spoils`):
---   spoils               True on an offer of another pool that the spoils pick can draw too.
---   gold_per_enemy_unit  Gold for each unit in the army we beat (Easy value, scaled).
---   battle_item          True: 1 item of the battle's own victory rarities.
---   captive              True: a random unit of the army we beat joins our army.
---   ransom               True: worse relations (`relations`) with the nearest faction of the beaten army's culture.
---   trait_points         A trait the lord gains a point of each time, growing through its levels.
---   lord_ranks           Ranks the lord gains.
---   lord_xp              Experience the lord gains.

local steps = require("script/land_encounters/utils/steps")
local shared = require("script/land_encounters/configs/shared_offers")

--- A value per difficulty, see utils/steps.lua.
local S = steps.of

--- A bundle with one version per difficulty.
local tiered = steps.tiered

--- Key prefix of the spot offers' own effect bundles.
local SPOT_BUNDLE = "land_enc_effect_spot_"

--- The tower's attrition bundle, shared by the plague offers.
local PLAGUE = shared.plague_bearer.bundle

--- Cost bands (Easy, Medium, Hard) every paid offer prices on, from configs/shared_offers.lua.
local STANDARD = shared.STANDARD
local STRONG = shared.STRONG
local PREMIUM = shared.PREMIUM
local STRUCTURAL = shared.STRUCTURAL
local UNIQUE = shared.UNIQUE

local M = {}

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

--- Bundle prefix, followed by the gold, showing a faction's dividends each turn, e.g. land_enc_effect_spot_dividends_250.
M.dividends_bundle_prefix = "land_enc_effect_spot_dividends_"

--- Dilemma key prefix of a site, e.g. land_enc_dilemma_site_hidden_tomb.
M.dilemma_prefix = "land_enc_dilemma_site_"

--- Text line prefix of an offer, followed by the offer key and the difficulty, e.g. dummy_land_enc_spot_take_the_gold_easy.
M.line_prefix = "dummy_land_enc_spot_"

--- Line under an offer the treasury cannot pay, the same for every offer.
M.unaffordable_line = "dummy_land_enc_spot_unaffordable"

--- Incident key prefix of a result, followed by the result name, e.g. land_enc_incident_spot_cast_the_lots_won. Each result is shown as an
--- incident built in script, whose payload grants and shows its rewards.
M.result_incident_prefix = "land_enc_incident_spot_"

--- Context value read by a realm result's incident text: the name of the region or faction it touched.
M.result_place_context = "land_enc_spot_result_place"

--- Context value read by a result's incident text for what it found, e.g. the garrison Spy on Their Capital saw.
M.result_detail_context = "land_enc_spot_result_detail"

--- Event feed message prefix after `land_enc_`, e.g. spot_cast_the_lots_won. A result falls back to its message if its incident cannot be
--- built.
M.message_prefix = "spot_"

--- Line on a choice that may start a battle, from the vanilla dilemmas the battle spots already use.
M.fight_line = "dummy_wh2_dlc11_neo_counter_fight_chance"

--- Pools whose offers sit on the battle dilemmas. Every other pool's offers sit on the treasure site dilemmas.
M.battle_pools = { pre_battle = true, mission = true }

--- Rarities of the item a battle pays when its category grants no victory item.
M.default_battle_rarities = { "uncommon", "rare" }

--- Pre-battle offers drawn between Fight and Avoid.
M.offers_per_battle = 2

--- Missions drawn after the pre-battle offers, before Avoid.
M.missions_per_battle = 2

--- Line on a mission already taken on the open dilemma.
M.taken_line = "dummy_land_enc_spot_taken"

--- Line under a mission: taking it returns to the same dilemma. The tower's own line.
M.returns_line = "dummy_land_enc_tower_returns_here"

--- Script context value every battle dilemma's description starts with: the missions taken so far, one line each, or empty.
M.missions_context = "land_enc_spot_battle_missions"

--- Loc key prefix of a taken mission's line in that list, followed by the mission key and the difficulty.
M.mission_set_loc_prefix = "campaign_localised_strings_string_land_enc_spot_mission_set_"

--- Choice key of Avoid on a battle dilemma with offers. It sorts last, as the tower's Leave does, and carries the dilemma's own Avoid label.
M.avoid_choice_key = "LEAPOI_SPT_AVOID"

--- Choice key of Fight, the vanilla FIRST key the battle dilemmas already use.
M.fight_choice_key = "FIRST"


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
    { key = "ruined_shrine", tags = { "blessing", "curse" }, signature = "stoneskin", ui_image = "old_ones_temples_down" },
    { key = "smugglers_cache", tags = { "deal", "realm_others" }, signature = "recruitment_cache", ui_image = "wh2_sea_encounters_1" },
    { key = "beast_lair", tags = { "recruit", "gamble" }, signature = "tame_the_beast", ui_image = "attrition_swamp" },
    { key = "old_battlefield", tags = { "recruit", "loot" }, signature = "salvage_a_war_machine", ui_image = "carnage_weapons" },
    { key = "witchs_hut", tags = { "gamble", "curse" }, signature = "dark_bargain", ui_image = "ai_wins_soul" },
    { key = "collapsed_mine", tags = { "loot", "gamble" }, signature = "search_every_corner", ui_image = "under_empire_discovered" },
    { key = "merchants_wagon", tags = { "deal" }, signature = "buy_from_the_trader", ui_image = "imperial_supplies" },
    { key = "sunken_library", tags = { "lore", "realm" }, signature = "research_scrolls", ui_image = "story_panels/chd_drill_machinations" },
}

--- The spoils pick after a won battle spot: a site with no signature that draws from its own pools. The picture is culture-aware, so each
--- player sees their own culture's victory.
M.spoils = { key = "spoils_of_war", tags = { "loot", "recovery" }, pools = { "spoils", "realm" }, ui_image = "land_victory" }

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
    { key = "take_the_gold", pool = "treasure", tags = { "loot" }, gold = S(1000, 1500, 2000), spoils = true },
    { key = "strip_the_valuables", pool = "treasure", tags = { "loot", "curse" }, gold = S(1000, 2000, 3000), army_bundle = { SPOT_BUNDLE .. "strip_the_valuables", 3 } },
    { key = "pry_open_the_reliquary", pool = "treasure", tags = { "loot", "curse" }, items = { rarities = { "rare" }, count = 1 }, wound = 2 },
    { key = "search_every_corner", pool = "treasure", tags = { "loot" }, items = { rarities = { "common", "uncommon", "rare" }, count = 2 }, camp = true },
    { key = "the_hidden_vault", pool = "treasure", tags = { "loot" }, cost = UNIQUE, unique = 1 },

    --- Treasure: gambles.
    { key = "cast_the_lots", pool = "treasure", tags = { "gamble" }, gamble = {
        { 1, "won", items = { rarities = { "rare" }, count = 1 } },
        { 1, "lost", gold = S(-1000, -1500, -2000) },
    } },
    { key = "drink_from_the_spring", pool = "treasure", tags = { "gamble", "recovery" }, gamble = {
        { 1, "won", heal = true },
        { 1, "lost", army_bundle = { PLAGUE, S(3, 4, 5) } },
    } },
    { key = "open_the_sealed_door", pool = "treasure", tags = { "gamble" }, gamble = {
        { 1, "won", unique = 1 },
        { 1, "lost", wound = 3 },
    } },
    --- Blessings come at the low step for 5 turns, curses last 3 turns.
    { key = "touch_the_relic", pool = "treasure", tags = { "gamble", "blessing", "curse" }, gamble = {
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "bless_the_banners_easy", 5 } },
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "stoneskin_easy", 5 } },
        { 1, "blessed", army_bundle = { SPOT_BUNDLE .. "ancient_tactics", 5 } },
        { 1, "cursed", army_bundle = { SPOT_BUNDLE .. "strip_the_valuables", 3 } },
        { 1, "cursed", army_bundle = { PLAGUE, 3 } },
        { 1, "cursed", army_bundle = { SPOT_BUNDLE .. "touch_the_relic_frailty", 3 } },
    } },
    { key = "wake_the_guardian", pool = "treasure", tags = { "gamble" }, gamble = {
        { 3, "won", items = { rarities = { "rare" }, count = 1 } },
        { 2, "lost", guardian = true },
    } },
    --- The stake comes back doubled, or not at all.
    { key = "double_or_nothing", pool = "treasure", tags = { "gamble", "deal" }, cost = STANDARD, gamble = {
        { 1, "won", gold = S(3000, 4000, 5000) },
        { 1, "lost" },
    } },
    { key = "gamble_with_the_hermit", pool = "treasure", tags = { "gamble" }, cost = STRONG, gamble = {
        { 1, "won", unique = 1 },
        { 2, "lost" },
    } },

    --- Treasure: blessings.
    { key = "leave_an_offering", pool = "treasure", tags = { "blessing" }, cost = STANDARD, army_bundle = { tiered(SPOT_BUNDLE .. "leave_an_offering"), 5 } },
    { key = "bless_the_banners", pool = "treasure", tags = { "blessing" }, cost = STANDARD, army_bundle = { tiered(SPOT_BUNDLE .. "bless_the_banners"), 5 } },
    { key = "stoneskin", pool = "treasure", tags = { "blessing" }, cost = shared.stoneskin.cost, army_bundle = { tiered(SPOT_BUNDLE .. "stoneskin"), 5 } },
    --- The oath's price is the altar's keepers: a hard battle starts here.
    { key = "oath_at_the_altar", pool = "treasure", tags = { "blessing" }, trait = "land_enc_trait_spot_shrine_sworn", guardian = "hard" },
    --- Magical attacks are yes or no, so the price buys turns.
    { key = "enchanted_steel", pool = "treasure", tags = { "blessing" }, cost = shared.enchanted_steel.cost,
        army_bundle = { SPOT_BUNDLE .. "enchanted_steel", S(5, 6, 7) } },

    --- Treasure: curses and pacts.
    { key = "dark_bargain", pool = "treasure", tags = { "curse" }, trait = "land_enc_trait_tower_daemon_marked", wound = 5 },
    { key = "plague_bearer", pool = "treasure", tags = { "curse", "loot" }, gold = shared.plague_bearer.gold, army_bundle = { PLAGUE, shared.plague_bearer.turns } },
    { key = "bloodstained_blades", pool = "treasure", tags = { "curse" }, army_bundle = { SPOT_BUNDLE .. "bloodstained_blades", 5 } },
    { key = "feed_the_shadows", pool = "treasure", tags = { "curse" }, sacrifice = { ranks = 1 } },
    { key = "daemons_deal", pool = "treasure", tags = { "curse", "gamble" }, unique = shared.daemons_deal.unique, daemon_armies = shared.daemons_deal.armies },

    --- Treasure: recruits.
    { key = "conscripts", pool = "treasure", tags = { "recruit" }, recruit = { count = shared.conscripts.count, tiers = shared.conscripts.tiers } },
    { key = "hire_sellswords", pool = "treasure", tags = { "recruit", "deal" }, cost = STANDARD, recruit = { count = 1, tiers = S({ 3, 4 }, { 4 }, { 4, 5 }) } },
    { key = "free_the_prisoner", pool = "treasure", tags = { "recruit" }, hero_rank = S(1, 3, 5) },
    { key = "tame_the_beast", pool = "treasure", tags = { "recruit", "gamble" },
        recruit = { count = 1, tiers = S({ 1, 2, 3 }, { 2, 3, 4 }, { 3, 4, 5 }), unit_types = { "monster", "war_beast", "monstrous_infantry", "monstrous_cavalry" } } },
    { key = "regiment_of_renown", pool = "treasure", tags = { "recruit", "deal" }, cost = shared.regiment_of_renown.cost, renown = 1 },
    { key = "salvage_a_war_machine", pool = "treasure", tags = { "recruit", "loot" }, cost = shared.salvage_a_war_machine.cost,
        recruit = { count = 1, tiers = shared.salvage_a_war_machine.tiers, unit_types = { "warmachine" } } },

    --- Treasure: deals.
    { key = "buy_from_the_trader", pool = "treasure", tags = { "deal", "loot" }, cost = STRONG, items = { rarities = { "rare" }, count = 1 } },
    { key = "recruitment_cache", pool = "treasure", tags = { "deal" }, cost = shared.recruitment_cache.cost,
        faction_bundle = { shared.recruitment_cache.bundle, shared.recruitment_cache.turns } },
    { key = "tower_dividends", pool = "treasure", tags = { "deal" }, cost = shared.tower_dividends.cost,
        dividends = { per_turn = shared.tower_dividends.per_turn, turns = shared.tower_dividends.turns } },
    --- Our army ignoring attrition is yes or no, so the price buys turns.
    { key = "buy_supplies", pool = "treasure", tags = { "deal", "recovery" }, cost = STANDARD, army_bundle = { SPOT_BUNDLE .. "buy_supplies", S(5, 6, 7) } },

    --- Treasure: lore.
    { key = "research_scrolls", pool = "treasure", tags = { "lore" }, faction_bundle = { "land_enc_effect_tower_research_scrolls", 5 } },
    { key = "ancient_tactics", pool = "treasure", tags = { "lore" }, army_bundle = { SPOT_BUNDLE .. "ancient_tactics", 5 } },

    --- Realm: your own lands.
    { key = "endow_the_province", pool = "realm", tags = { "realm" }, cost = PREMIUM, realm = "own_region", points = S(50, 75, 100) },
    { key = "garrison_drill", pool = "realm", tags = { "realm" }, cost = 1500, realm = "own_region", heal_garrison = true,
        region_bundle = { SPOT_BUNDLE .. "garrison_drill", 5 } },
    { key = "raise_the_settlement", pool = "realm", tags = { "realm" }, cost = STRUCTURAL, realm = "raise_region" },
    { key = "quell_the_unrest", pool = "realm", tags = { "realm" }, realm = "own_province", province_bundle = { SPOT_BUNDLE .. "quell_the_unrest", 5 } },
    { key = "bountiful_harvest", pool = "realm", tags = { "realm" }, cost = STANDARD, realm = "own_province", province_bundle = { tiered(SPOT_BUNDLE .. "bountiful_harvest"), 5 } },

    --- Realm: rivals nearby.
    { key = "stir_their_rebels", pool = "realm", tags = { "realm_others" }, cost = STANDARD, realm = "enemy_province",
        province_bundle = { tiered(SPOT_BUNDLE .. "stir_their_rebels"), 5 } },
    { key = "poison_their_wells", pool = "realm", tags = { "realm_others" }, cost = STANDARD, realm = "enemy_region",
        region_bundle = { tiered(SPOT_BUNDLE .. "poison_their_wells"), 5 } },
    { key = "sap_their_garrison", pool = "realm", tags = { "realm_others" }, cost = 1500, realm = "enemy_region", garrison_strength = 0.7,
        region_bundle = { SPOT_BUNDLE .. "sap_their_garrison", 5 } },
    { key = "spread_the_plague", pool = "realm", tags = { "realm_others", "curse" }, realm = "enemy_regions", count = 3,
        region_bundle = { SPOT_BUNDLE .. "spread_the_plague", 5 }, army_bundle = { PLAGUE, 3 } },
    { key = "send_gifts", pool = "realm", tags = { "realm_others", "deal" }, cost = STANDARD, realm = "friend", relations = S(1, 2, 3) },
    { key = "spy_on_their_capital", pool = "realm", tags = { "realm_others", "lore" }, cost = 1500, realm = "enemy_capital", reveal_turns = 5 },

    --- Realm: far-off factions.
    { key = "curse_a_distant_king", pool = "realm", tags = { "realm_others", "curse" }, cost = STRONG, realm = "biggest_faction",
        target_faction_bundle = { tiered(SPOT_BUNDLE .. "curse_a_distant_king"), 5 } },
    { key = "share_the_find", pool = "realm", tags = { "realm_others", "lore" }, realm = "neighbours", relations = 1,
        faction_bundle = { SPOT_BUNDLE .. "share_the_find", 5 }, target_faction_bundle = { SPOT_BUNDLE .. "share_the_find", 5 } },
    { key = "point_them_at_each_other", pool = "realm", tags = { "realm_others" }, cost = PREMIUM, realm = "rival_pair", relations = -5 },
    { key = "sell_their_secrets", pool = "realm", tags = { "realm_others", "deal" }, gold = S(2000, 2500, 3000), realm = "enemy_friends", relations = 5 },

    --- Pre-battle: sabotage on the enemy army.
    { key = "bribe_the_guards", pool = "pre_battle", tags = { "sabotage" }, cost = shared.bribe_the_guards.cost, budget = shared.bribe_the_guards.budget },
    { key = "thin_the_ranks", pool = "pre_battle", tags = { "sabotage" }, cost = shared.thin_the_ranks.cost, fewer_units = shared.thin_the_ranks.fewer_units },
    { key = "poison_the_stores", pool = "pre_battle", tags = { "sabotage" }, cost = shared.poison_the_stores.cost,
        enemy_strength = shared.poison_the_stores.enemy_strength },
    { key = "kill_the_captain", pool = "pre_battle", tags = { "sabotage" }, cost = shared.kill_the_captain.cost, no_heroes = true },
    { key = "lower_tiers_only", pool = "pre_battle", tags = { "sabotage" }, cost = shared.lower_tiers_only.cost, max_tier = shared.lower_tiers_only.max_tier },
    { key = "break_their_spirit", pool = "pre_battle", tags = { "sabotage" }, cost = shared.break_their_spirit.cost,
        enemy_bundle = shared.break_their_spirit.enemy_bundle },
    { key = "curse_their_blades", pool = "pre_battle", tags = { "sabotage" }, cost = shared.curse_their_blades.cost,
        enemy_bundle = shared.curse_their_blades.enemy_bundle },
    { key = "turn_a_traitor", pool = "pre_battle", tags = { "sabotage" }, cost = shared.turn_a_traitor.cost,
        traitor = { count = 1, tiers = shared.turn_a_traitor.tiers } },

    { key = "cripple_their_champion", pool = "pre_battle", tags = { "sabotage" }, cost = shared.cripple_their_champion.cost,
        champion_strength = shared.cripple_their_champion.champion_strength },
    { key = "spike_the_guns", pool = "pre_battle", tags = { "sabotage" }, cost = shared.spike_the_guns.cost, enemy_bundle = shared.spike_the_guns.enemy_bundle,
        roster = shared.spike_the_guns.roster },
    { key = "bait_and_switch", pool = "pre_battle", tags = { "sabotage" }, cost = shared.bait_and_switch.cost, budget = shared.bait_and_switch.budget,
        enemy_strength = shared.bait_and_switch.enemy_strength },

    --- Pre-battle: buffs on our army for this battle.
    { key = "war_rites", pool = "pre_battle", tags = { "buff" }, cost = shared.war_rites.cost, battle_bundle = shared.war_rites.bundle },
    { key = "whetstones_and_oil", pool = "pre_battle", tags = { "buff" }, cost = shared.whetstones_and_oil.cost, battle_bundle = shared.whetstones_and_oil.bundle },
    { key = "warding_sigils", pool = "pre_battle", tags = { "buff" }, cost = shared.warding_sigils.cost, battle_bundle = shared.warding_sigils.bundle },
    { key = "fire_kissed_blades", pool = "pre_battle", tags = { "buff" }, cost = shared.fire_kissed_blades.cost, battle_bundle = shared.fire_kissed_blades.bundle },
    { key = "iron_resolve", pool = "pre_battle", tags = { "buff" }, cost = shared.iron_resolve.cost, battle_bundle = shared.iron_resolve.bundle },
    { key = "drill_sergeant", pool = "pre_battle", tags = { "buff" }, cost = shared.drill_sergeant.cost, battle_bundle = shared.drill_sergeant.bundle },
    { key = "call_the_winds", pool = "pre_battle", tags = { "buff" }, cost = shared.call_the_winds.cost, battle_bundle = shared.call_the_winds.bundle,
        caster = true },
    { key = "quartermasters_cache", pool = "pre_battle", tags = { "buff" }, cost = shared.quartermasters_cache.cost,
        battle_bundle = shared.quartermasters_cache.bundle, shoots = true },
    { key = "tower_artillery", pool = "pre_battle", tags = { "buff" }, cost = shared.tower_artillery.cost, battle_bundle = shared.tower_artillery.bundle },

    { key = "last_ditch_oath", pool = "pre_battle", tags = { "buff" }, battle_bundle = shared.last_ditch_oath.bundle },

    --- Pre-battle: allies by size, and a gamble.
    { key = "allies_in_the_dark_small", pool = "pre_battle", tags = { "allies" }, cost = shared.allies_in_the_dark_small.cost,
        allies = shared.allies_in_the_dark_small.ally_units, group = "allies", notice = "allies_in_the_dark" },
    { key = "allies_in_the_dark_medium", pool = "pre_battle", tags = { "allies" }, cost = shared.allies_in_the_dark_medium.cost,
        allies = shared.allies_in_the_dark_medium.ally_units, group = "allies", notice = "allies_in_the_dark" },
    { key = "allies_in_the_dark_large", pool = "pre_battle", tags = { "allies" }, cost = shared.allies_in_the_dark_large.cost,
        allies = shared.allies_in_the_dark_large.ally_units, group = "allies", notice = "allies_in_the_dark" },
    { key = "night_raid", pool = "pre_battle", tags = { "gamble" }, gamble = {
        { 1, "won", budget = 0.75 },
        { 1, "lost", own_strength = S(0.85, 0.8, 0.75) },
    } },

    --- Pre-battle: help for the allied army, drawn only when one fights beside us. Both Reinforce the Ally versions read the same; only the
    --- one that fits the ally can be drawn.
    { key = "arm_the_allies", pool = "pre_battle", tags = { "ally" }, cost = STANDARD, for_ally = true, ally_bundle = shared.war_rites.bundle },
    { key = "rally_their_line", pool = "pre_battle", tags = { "ally" }, cost = STANDARD, for_ally = true, trick = true },
    { key = "lend_them_veterans", pool = "pre_battle", tags = { "ally" }, cost = STANDARD, for_ally = true, ally_ranks = 2 },
    { key = "reinforce_the_ally_escort", pool = "pre_battle", tags = { "ally" }, cost = STRONG, for_ally = "sized", extra_ally_units = 3 },
    { key = "reinforce_the_ally_army", pool = "pre_battle", tags = { "ally" }, cost = STRONG, for_ally = "full", ally_budget = 1.3 },

    --- Pre-battle: tricks the battle script plays, under the tower's names.
    { key = "bottomless_quivers", pool = "pre_battle", tags = { "trick" }, cost = shared.bottomless_quivers.cost, trick = true, shoots = true },
    { key = "oath_of_no_retreat", pool = "pre_battle", tags = { "trick" }, cost = shared.oath_of_no_retreat.cost, trick = true },
    { key = "divine_shield", pool = "pre_battle", tags = { "trick" }, cost = shared.divine_shield.cost, trick = true, battle_value = shared.divine_shield.battle_value },
    { key = "night_terrors", pool = "pre_battle", tags = { "trick" }, cost = shared.night_terrors.cost, trick = true, targets = shared.night_terrors.targets },
    { key = "assassinate", pool = "pre_battle", tags = { "trick" }, cost = shared.assassinate.cost, trick = true },

    --- Spoils, picked after a won battle spot.
    { key = "strip_the_dead", pool = "spoils", tags = { "loot" }, gold_per_enemy_unit = shared.strip_the_dead.per_unit },
    { key = "ransom_the_captain", pool = "spoils", tags = { "loot", "deal" }, gold = S(2500, 3000, 3500), ransom = true, relations = -5 },
    { key = "tribute_from_the_locals", pool = "spoils", tags = { "deal" }, dividends = { per_turn = 500, turns = 5 } },
    { key = "loot_the_baggage", pool = "spoils", tags = { "loot" }, battle_item = true },
    { key = "recruit_a_captive", pool = "spoils", tags = { "recruit" }, captive = true },
    { key = "press_on", pool = "spoils", tags = { "recovery" }, army_bundle = { SPOT_BUNDLE .. "press_on", 1 } },
    { key = "victory_feast", pool = "spoils", tags = { "recovery" }, cost = STANDARD, army_bundle = { tiered(SPOT_BUNDLE .. "victory_feast"), 5 } },
    { key = "trophy_of_war", pool = "spoils", tags = { "loot" }, trait_points = "land_enc_trait_spot_trophy_hunter" },
    { key = "chase_the_routers", pool = "spoils", tags = { "gamble" }, gamble = {
        { 1, "won", items = { rarities = { "rare" }, count = 1 } },
        { 1, "lost", wound = 2 },
    } },
    { key = "dark_offering", pool = "spoils", tags = { "curse" }, sacrifice = { ranks = 0 }, lord_ranks = 1,
        army_bundle = { SPOT_BUNDLE .. "dark_offering", 5 } },

    --- Missions, tracked by the battle script under the tower's names.
    { key = "headhunt", pool = "mission", tags = {}, battle_value = 360, items = { rarities = { "rare" }, count = 1 } },
    { key = "blood_tally", pool = "mission", tags = {}, battle_value = 0.4, gold = S(1500, 2000, 2500) },
    { key = "hold_the_line", pool = "mission", tags = {}, battle_value = 2, gold = S(1500, 2000, 2500) },
    { key = "swift_victory", pool = "mission", tags = {}, battle_value = 480, battle_item = true },
    { key = "guard_the_standard", pool = "mission", tags = {}, unit_ranks = 3 },
    { key = "break_them", pool = "mission", tags = {}, battle_value = 6, gold = S(1000, 1500, 2000) },
    { key = "trophy_hunt", pool = "mission", tags = {}, trophy = true },
    { key = "silence_the_guns", pool = "mission", tags = {}, battle_value = 300, items = { rarities = { "rare" }, count = 1 } },
    { key = "bloodbath_wager", pool = "mission", tags = {}, cost = shared.bloodbath_wager.cost, battle_value = shared.bloodbath_wager.battle_value,
        gold = shared.bloodbath_wager.gold },
    { key = "duelists_challenge", pool = "mission", tags = {}, unique = 1 },
    { key = "spare_the_captain", pool = "mission", tags = {}, gold = shared.spare_the_captain.gold },
    { key = "flawless_victory", pool = "mission", tags = {}, battle_value = shared.flawless_victory.battle_value, unique = 1 },
    { key = "untouchable", pool = "mission", tags = {}, battle_value = shared.untouchable.battle_value, lord_xp = shared.untouchable.lord_xp },
    { key = "lords_glory", pool = "mission", tags = {}, battle_value = shared.lords_glory.battle_value, items = { rarities = { "rare" }, count = 1 } },
    { key = "monster_slayer", pool = "mission", tags = {}, roster = shared.monster_slayer.roster, gold = S(1500, 2000, 2500) },
    { key = "steadfast", pool = "mission", tags = {}, gold = S(1500, 2000, 2500) },
    { key = "decapitate", pool = "mission", tags = {}, unique = 1 },
    { key = "against_the_odds", pool = "mission", tags = {}, max_units = shared.against_the_odds.max_units, gold = S(2000, 2500, 3000) },
    { key = "rout_the_riders", pool = "mission", tags = {}, battle_value = shared.rout_the_riders.battle_value, roster = shared.rout_the_riders.roster,
        items = { rarities = { "rare" }, count = 1 } },
}

--- Offer key -> offer record.
M.by_key = {}
for _, offer in ipairs(M.offers) do
    M.by_key[offer.key] = offer
end

--- An offer at one difficulty, with every stepped field picked for it.
--- @param key string The offer key.
--- @param difficulty string "easy", "medium" or "hard".
--- @returns table|nil The offer record for that difficulty, or nil for an unknown key.
function M.at(key, difficulty)
    local offer = M.by_key[key]
    return offer and steps.resolve(offer, difficulty)
end

--- Every offer at one difficulty, in config order.
--- @param difficulty string "easy", "medium" or "hard".
--- @returns table The offer records for that difficulty.
function M.all_at(difficulty)
    local offers = {}
    for i, offer in ipairs(M.offers) do offers[i] = steps.resolve(offer, difficulty) end
    return offers
end

--- Site key -> site record, the spoils pick included.
M.site_by_key = { [M.spoils.key] = M.spoils }
for _, site in ipairs(M.sites) do
    M.site_by_key[site.key] = site
end

return M
