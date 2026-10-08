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

--- Turns a faction-wide boon or curse lasts.
M.realm_turns = 10

--- MCT setting keys: the switch, and the slots a lord has for boons and for curses.
M.enable_setting = "enable_boons"
M.slot_settings = { boon = "boon_slots", curse = "curse_slots" }

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

--- Prefix of the incidents that tell the player about a lord's boons and curses. The event follows: boon_gained, boon_grew, boon_lost,
--- curse_gained, curse_worse, curse_lifted, curse_turned, realm_boon, realm_curse.
M.incident_prefix = "land_enc_incident_"

--- Script context the incidents read the lord's name from.
M.lord_context = "land_enc_boon_lord"

--- The dilemma asked when a lord with full boon slots gains another: give up one of the boons, or the new one.
M.full_dilemma = "land_enc_dilemma_boon_full"

--- Choice keys of the full-slots dilemma: one per boon slot, in slot order, then the new boon. Up to 5 slots fit.
M.full_choices = { "LEAPOI_BON_DROP_1", "LEAPOI_BON_DROP_2", "LEAPOI_BON_DROP_3", "LEAPOI_BON_DROP_4", "LEAPOI_BON_DROP_5" }
M.full_new_choice = "LEAPOI_BON_DROP_NEW"

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Catalogue

--- Races a rolled boon or curse can be about (Bane of a Race, Grudge of a Race).
M.races = { "empire", "bretonnia", "kislev", "cathay", "dwarfs", "high_elves", "wood_elves", "dark_elves", "lizardmen", "greenskins", "skaven",
    "ogres", "vampire_counts", "vampire_coast", "tomb_kings", "norsca", "chaos", "khorne", "nurgle", "slaanesh", "tzeentch", "daemons",
    "beastmen", "chaos_dwarfs" }

--- Boons, by key. `charges`: lasts that many of the lord's battles at one level instead of growing. `race`: rolls a race when gained.
M.boons = {
    { key = "bloodsworn" }, { key = "ironhide" }, { key = "old_oath_banner" }, { key = "eagle_eyed" }, { key = "swift_column" },
    { key = "kindled_winds" }, { key = "stormcaller" }, { key = "stone_rampart" }, { key = "storm_forward" }, { key = "plunderer" },
    { key = "quartermaster" }, { key = "drillmaster" }, { key = "blinding_strikes" }, { key = "leeching_strikes" }, { key = "hunters_path" },
    { key = "warded" }, { key = "overflowing_power" }, { key = "dread_host" }, { key = "bane", race = true }, { key = "death_touched" },
    { key = "tireless" },
    { key = "war_chant", charges = 3 }, { key = "fates_favour", charges = 3 }, { key = "kings_ransom", charges = 3 },
    { key = "undying_vigil", charges = 2 },
}

--- Curses, by key. `turns_into`: the boon it becomes after `turns_to_turn` turns at `max_level`. `race`: rolls a race when gained.
M.curses = {
    { key = "haunted", turns_into = "death_touched" }, { key = "creeping_rust" }, { key = "leaden_march" }, { key = "bleeding_coffers" },
    { key = "weary_ranks", turns_into = "tireless" }, { key = "withered_supply" }, { key = "fogbound" }, { key = "magpies_curse" },
    { key = "wild_magic", turns_into = "overflowing_power" }, { key = "shunned_by_the_winds" }, { key = "cowards_mark" }, { key = "marked_prey" },
    { key = "brittle_bones", turns_into = "ironhide" }, { key = "shaky_aim" }, { key = "grudge", race = true, turns_into = "bane" },
    { key = "glass_jaw" }, { key = "stumbling_charge" }, { key = "cursed_coin" },
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

--- Key -> faction-wide record, filled below.
M.realm_by_key = {}
for _, record in ipairs(M.realm) do M.realm_by_key[record.key] = record end

return M
