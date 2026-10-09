--- Boons and curses: lasting effects a lord carries, plus rare faction-wide ones. Pure data. Their names, text and the effects of each level are
--- written by the generator (helper_scripts/generators/leapoi_boons.py), keyed the same. features/boons.lua runs them.

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rules

--- Highest level of a boon or curse.
M.max_level = 5

--- Battles won by the lord that raise a boon one level.
M.wins_per_level = 5

--- Turns that make a curse one level worse.
M.turns_per_level = 5

--- Turns a curse spends at `max_level` before one with a `turns_into` boon becomes it.
M.turns_to_turn = 10

--- Turns a faction-wide boon or curse lasts. The script counts them and takes the bundle off, so its clock and the bundle agree.
M.realm_turns = 10

--- MCT setting keys: the switch, and the slots a lord has for boons and for curses.
M.enable_setting = "enable_boons"
M.slot_settings = { boon = "boon_slots", curse = "curse_slots" }

--- MCT setting keys of the percent chances: a boon after a hard or modified LEAPOI win, a curse after a lost one or a failed Tavern
--- contract, and each battle modifier leaving its mark.
M.chance_settings = { win = "boon_win_chance", loss = "curse_loss_chance", linger = "linger_chance" }

--- Percent chance a won tower champion floor gives a faction-wide blessing instead of a choice of boons, and a lost one a faction-wide curse.
M.champion_realm_chance = 3

--- How many tower boons a won champion floor lets the lord choose from.
M.champion_choices = 2

--- Level of the boon a finished Tavern quest chain gives.
M.chain_boon_level = 2

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Naming

--- Prefix of a lord's boon and curse bundles. The key, the race for a rolled one, and the level follow, e.g. land_enc_effect_boon_bane_dwarfs_3.
M.bundle_prefix = { boon = "land_enc_effect_boon_", curse = "land_enc_effect_curse_" }

--- Prefix of each faction-wide bundle. The key follows.
M.realm_prefix = "land_enc_effect_realm_"

--- Prefix of a boon's or curse's payload line on a dilemma choice. The kind, then the bundle name without its prefix follow, e.g.
--- dummy_land_enc_boon_bloodsworn_3.
M.line_prefix = "dummy_land_enc_"

--- Prefix of the clock effects: the line at the top of a boon's or curse's bundle saying how long it lasts or when it changes, e.g. "Worsens in
--- 3 turns.". The clock's name follows, then "_one" when a counted clock reads 1, e.g. land_enc_clock_worsens_one.
M.clock_prefix = "land_enc_clock_"

--- Clocks that show a count: battles a charged boon lasts, won battles until a boon upgrades, turns until a curse worsens or becomes its
--- boon, and turns a faction-wide one lasts.
M.counted_clocks = { "lasts", "upgrades", "worsens", "becomes", "realm" }

--- Clocks with a fixed text: a boon at its top level, and a curse at its worst that never turns.
M.fixed_clocks = { "strongest", "worst" }

--- Scope of a clock effect on a lord's bundle and on a faction-wide one.
M.clock_scope = { character = "character_to_character_own", faction = "faction_to_faction_own_unseen" }

--- Prefix of the incidents that tell the player about a lord's boons and curses. The event follows: boon_gained, boon_grew, boon_lost,
--- curse_gained, curse_worse, curse_lifted, curse_turned, curse_shifted (a failed gamble), realm_boon, realm_curse, and the services' own:
--- boon_tempered, curse_broken, curse_cleansed, gamble_won, rust_struck.
M.incident_prefix = "land_enc_incident_"

--- Script context the incidents read the lord's name from.
M.lord_context = "land_enc_boon_lord"

--- The dilemma asked when a lord with full boon slots gains another: give up one of the boons, or the new one.
M.full_dilemma = "land_enc_dilemma_boon_full"

--- Choice keys of the full-slots dilemma: one per boon slot, in slot order, then the new boon. Up to 5 slots fit.
M.full_choices = { "LEAPOI_BON_DROP_1", "LEAPOI_BON_DROP_2", "LEAPOI_BON_DROP_3", "LEAPOI_BON_DROP_4", "LEAPOI_BON_DROP_5" }
M.full_new_choice = "LEAPOI_BON_DROP_NEW"

--- The dilemma that lets a lord choose one of a few boons, and its choice keys in order.
M.pick_dilemma = "land_enc_dilemma_boon_pick"
M.pick_choices = { "LEAPOI_BON_PICK_1", "LEAPOI_BON_PICK_2", "LEAPOI_BON_PICK_3" }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Services

--- Share of a service's price the owner of the Smithy or Tavern pays. Only an owner uses a Smithy's forge, so its room always charges this.
M.owner_price_share = 0.75

--- Prefix of the services' payload lines. The line's name follows: smithy_room and witch_room on the forge and hub choices, witch_nothing
--- when the lord has no curse, top and charged under a boon that cannot be tempered, gamble under a gamble, and gamble_cooling_<turns>.
M.service_line_prefix = "dummy_land_enc_boon_service_"

--- Prefix of the services' result lines (text/db/land_enc_and_poi_spot_strings.loc.tsv), which the reopened room shows at the top of its
--- description through `result_context`. The service follows: temper, break, cleanse, gamble_won, gamble_lost, rust.
M.result_prefix = "land_enc_boon_result_"

--- Prefix of each boon's, curse's and faction-wide effect's MCT guide line (text/db/land_enc_and_poi_spot_strings.loc.tsv): its effects and
--- where it comes from. The kind (boon, curse or realm), then the key follow.
M.guide_prefix = "land_enc_boon_guide_"
M.result_context = "land_enc_boon_service_result"

--- The Smithy's Temper and Break room, opened by `open_choice` on the forge. Tempering raises a boon one level for `temper_price` gold per
--- level it reaches, breaking lifts a curse for `break_price` gold per level it has, and `rust_offer` (a tower pact in configs/tower_offers.lua)
--- can be taken once per visit. One temper and one break choice per slot, in slot order.
M.smithy_room = {
    dilemma = "land_enc_dilemma_smithy_temper",
    open_choice = "LEAPOI_BON_SMITHY_ROOM",
    --- The forge dilemmas that show `open_choice`.
    opened_from = { "land_enc_dilemma_smithy_forge_level_1", "land_enc_dilemma_smithy_forge_level_2", "land_enc_dilemma_smithy_forge_level_3" },
    temper_choices = { "LEAPOI_BON_TEMPER_1", "LEAPOI_BON_TEMPER_2", "LEAPOI_BON_TEMPER_3", "LEAPOI_BON_TEMPER_4", "LEAPOI_BON_TEMPER_5" },
    break_choices = { "LEAPOI_BON_BREAK_1", "LEAPOI_BON_BREAK_2", "LEAPOI_BON_BREAK_3", "LEAPOI_BON_BREAK_4", "LEAPOI_BON_BREAK_5" },
    rust_choice = "LEAPOI_BON_RUST",
    --- Goes back to the forge.
    back_choice = "LEAPOI_BON_SMITHY_BACK",
    temper_price = 5000,
    break_price = 5000,
    rust_offer = "rust_for_iron",
}

--- The Tavern's hedge-witch, opened by `open_choice` on the hub. Cleansing lifts a curse for `cleanse_price` gold per level it has. A gamble
--- costs `gamble_price` gold per level: `gamble_lift_chance` percent of the time the curse lifts, otherwise it becomes another curse of the
--- same level whose clock starts again. A blood rite lifts a curse for no gold, bleeding the army `blood_bleed` percent per level. For a boon,
--- feeding it adds `feed_wins` won battles toward its next level for `feed_price` gold per level, and reweaving it costs `reweave_price` gold
--- per level: `reweave_rise_chance` percent of the time it rises a level, otherwise it becomes another boon of the same level. A lord who
--- uses a service in `cooldowns` cannot use it at that Tavern again for its turns. One feed and one reweave choice per boon slot, then one cleanse, gamble and blood rite choice per curse slot, in slot order.
M.witch_room = {
    dilemma = "land_enc_dilemma_tavern_witch",
    open_choice = "LEAPOI_BON_TAVERN_ROOM",
    --- The hub dilemmas that show `open_choice`.
    opened_from = { "land_enc_dilemma_tavern_hub_level_1", "land_enc_dilemma_tavern_hub_level_2", "land_enc_dilemma_tavern_hub_level_3" },
    cleanse_choices = { "LEAPOI_BON_CLEANSE_1", "LEAPOI_BON_CLEANSE_2", "LEAPOI_BON_CLEANSE_3", "LEAPOI_BON_CLEANSE_4", "LEAPOI_BON_CLEANSE_5" },
    gamble_choices = { "LEAPOI_BON_GAMBLE_1", "LEAPOI_BON_GAMBLE_2", "LEAPOI_BON_GAMBLE_3", "LEAPOI_BON_GAMBLE_4", "LEAPOI_BON_GAMBLE_5" },
    blood_choices = { "LEAPOI_BON_BLOOD_1", "LEAPOI_BON_BLOOD_2", "LEAPOI_BON_BLOOD_3", "LEAPOI_BON_BLOOD_4", "LEAPOI_BON_BLOOD_5" },
    feed_choices = { "LEAPOI_BON_FEED_1", "LEAPOI_BON_FEED_2", "LEAPOI_BON_FEED_3", "LEAPOI_BON_FEED_4", "LEAPOI_BON_FEED_5" },
    reweave_choices = { "LEAPOI_BON_REWEAVE_1", "LEAPOI_BON_REWEAVE_2", "LEAPOI_BON_REWEAVE_3", "LEAPOI_BON_REWEAVE_4", "LEAPOI_BON_REWEAVE_5" },
    back_choice = "LEAPOI_BON_WITCH_BACK",
    cleanse_price = 2500,
    gamble_price = 1000,
    gamble_lift_chance = 50,
    blood_bleed = 5,
    feed_price = 1500,
    feed_wins = 2,
    reweave_price = 1000,
    reweave_rise_chance = 50,
    cooldowns = { feed = 5, reweave = 5, gamble = 5, blood = 5 },
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Catalogue

--- Faction shorthand (as in configs/factions_data.lua) -> the race a boon or curse about it rolls, e.g. a Tavern bounty's Bane.
M.race_of_shorthand = { emp = "empire", brt = "bretonnia", ksl = "kislev", cth = "cathay", dwf = "dwarfs", hef = "high_elves",
    wef = "wood_elves", def = "dark_elves", lzd = "lizardmen", grn = "greenskins", skv = "skaven", ogr = "ogres", vmp = "vampire_counts",
    cst = "vampire_coast", tmb = "tomb_kings", nor = "norsca", chs = "chaos", kho = "khorne", nur = "nurgle", sla = "slaanesh",
    tze = "tzeentch", dae = "daemons", bst = "beastmen", chd = "chaos_dwarfs" }

--- Races a rolled boon or curse can be about (Bane of a Race, Grudge of a Race), in a fixed order.
M.races = {}
for _, race in pairs(M.race_of_shorthand) do M.races[#M.races + 1] = race end
table.sort(M.races)

--- Boons, by key. `charges`: lasts that many of the lord's battles at one level instead of growing. `race`: rolls a race when gained.
--- `drops`: the sources it can come from at random, e.g. "treasure"; none when left out.
M.boons = {
    { key = "bloodsworn", drops = { "battle" } }, { key = "ironhide", drops = { "battle", "smithy" } }, { key = "old_oath_banner", drops = { "tower" } },
    { key = "eagle_eyed", drops = { "treasure" } }, { key = "swift_column", drops = { "battle" } }, { key = "kindled_winds" },
    { key = "stormcaller", drops = { "tower", "tavern" } }, { key = "stone_rampart", drops = { "battle", "smithy" } }, { key = "storm_forward", drops = { "battle" } },
    { key = "plunderer", drops = { "treasure" } }, { key = "quartermaster", drops = { "treasure", "tavern" } }, { key = "drillmaster", drops = { "tower" } },
    { key = "blinding_strikes", drops = { "treasure", "battle" } }, { key = "leeching_strikes", drops = { "tower" } }, { key = "hunters_path" },
    { key = "warded", drops = { "tavern" } }, { key = "overflowing_power", drops = { "treasure" } }, { key = "dread_host" },
    { key = "bane", race = true, drops = { "battle" } }, { key = "death_touched" }, { key = "tireless" },
    { key = "war_chant", charges = 3, drops = { "treasure" } }, { key = "fates_favour", charges = 3, drops = { "treasure", "tower" } },
    { key = "kings_ransom", charges = 3 }, { key = "undying_vigil", charges = 2, drops = { "treasure", "tower" } },
}

--- Curses, by key. `turns_into`: the boon it becomes after `turns_to_turn` turns at `max_level`. `race`: rolls a race when gained. `drops`: the
--- sources it can come from at random; none when left out.
M.curses = {
    { key = "haunted", turns_into = "death_touched", drops = { "battle" } }, { key = "creeping_rust", drops = { "smithy" } }, { key = "leaden_march" },
    { key = "bleeding_coffers", drops = { "battle" } }, { key = "weary_ranks", turns_into = "tireless", drops = { "battle" } },
    { key = "withered_supply", drops = { "battle" } }, { key = "fogbound", drops = { "battle", "treasure" } }, { key = "magpies_curse" },
    { key = "wild_magic", turns_into = "overflowing_power" }, { key = "shunned_by_the_winds" },
    { key = "cowards_mark", drops = { "battle" } }, { key = "marked_prey", drops = { "battle", "tavern" } },
    { key = "brittle_bones", turns_into = "ironhide", drops = { "battle", "smithy" } }, { key = "shaky_aim" },
    { key = "grudge", race = true, turns_into = "bane", drops = { "treasure", "tavern" } }, { key = "glass_jaw", drops = { "battle" } },
    { key = "stumbling_charge", drops = { "battle" } }, { key = "cursed_coin", drops = { "treasure", "tavern", "smithy" } },
}

--- Battle modifier key (configs/battle_modifiers.lua) -> the boon or curse it can leave on the lord after the fight, as { kind, key }.
M.lingers = {
    blood_moon = { "boon", "bloodsworn" }, iron_hides = { "boon", "ironhide" }, hallowed = { "boon", "old_oath_banner" },
    plenty_shot = { "boon", "eagle_eyed" }, swift_winds = { "boon", "swift_column" }, winds_surge = { "boon", "kindled_winds" },
    hold_fast = { "boon", "stone_rampart" }, strider = { "boon", "hunters_path" }, ambush_country = { "boon", "hunters_path" },
    wards = { "boon", "warded" }, storm_magic = { "boon", "overflowing_power" }, terror_field = { "boon", "dread_host" },
    cursed_earth = { "curse", "haunted" }, brittle = { "curse", "creeping_rust" }, heavy_ground = { "curse", "leaden_march" },
    mud = { "curse", "stumbling_charge" }, exhausting = { "curse", "weary_ranks" }, miasma = { "curse", "withered_supply" },
    rot = { "curse", "withered_supply" }, wild_winds = { "curse", "wild_magic" }, winds_drained = { "curse", "shunned_by_the_winds" },
    cowards = { "curse", "cowards_mark" }, gale = { "curse", "shaky_aim" }, disarmed = { "curse", "shaky_aim" },
    gift_of_the_winds = { "boon", "kindled_winds" }, blinding_dust = { "boon", "blinding_strikes" }, bloodlust = { "boon", "bloodsworn" },
    weary_march = { "curse", "weary_ranks" },
}

--- Faction-wide boons and curses, by key. `good` is true for a blessing.
M.realm = {
    { key = "comet_sign", good = true }, { key = "old_ones_favour", good = true }, { key = "golden_age", good = true },
    { key = "dark_gods_wrath" }, { key = "black_plague" }, { key = "pariah" },
}

--- Kind -> key -> record, filled below.
M.by_key = { boon = {}, curse = {} }
for _, record in ipairs(M.boons) do M.by_key.boon[record.key] = record end
for _, record in ipairs(M.curses) do M.by_key.curse[record.key] = record end

--- Key -> faction-wide record, and the keys of the faction-wide blessings and curses, filled below.
M.realm_by_key = {}
M.blessings = {}
M.realm_curses = {}
for _, record in ipairs(M.realm) do
    M.realm_by_key[record.key] = record
    local list = record.good and M.blessings or M.realm_curses
    list[#list + 1] = record.key
end

return M
