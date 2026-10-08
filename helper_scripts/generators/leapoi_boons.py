"""Text and bundle effects of the LEAPOI boons and curses. The keys and rules live in script/land_encounters/configs/boons.lua. Written into the
mod by update_leapoi_spot_offers.py: one character bundle and one payload line per boon or curse level (per race for a rolled one), the
faction-wide bundles, the incidents and the full-slots dilemma."""

from typing import Dict, List, Optional, Tuple

from generators import leapoi_effect_library as library

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Scopes and effects

# Scopes of a lord's bundle effects: the lord's army, the lord alone, the lord's faction.
F = "character_to_force_own"
C = "character_to_character_own"
FACTION = "character_to_faction"

# Vanilla effects the catalogue uses.
MA, MD, WS = "wh_main_effect_force_stat_melee_attack", "wh_main_effect_force_stat_melee_defence", "wh_main_effect_force_stat_weapon_strength"
PHYS, LEAD, ARMOUR = "wh_main_effect_force_stat_physical_resistance", "wh_main_effect_force_stat_leadership", "wh_main_effect_force_stat_armour"
RANGE, AMMO, MISSILE = "wh_main_effect_force_stat_range", "wh_main_effect_force_stat_ammunition", "wh_main_effect_force_stat_missile_damage"
WARD, CHARGE, VIGOUR = "wh_main_effect_force_stat_ward_save", "wh_main_effect_force_stat_charge_bonus_pct", "wh_main_effect_force_stat_vigour_loss_reduction"
MOVE, UPKEEP = "wh_main_effect_force_all_campaign_movement_range", "wh_main_effect_force_all_campaign_upkeep"
LOOT, REPLENISH = "wh_main_effect_force_all_campaign_post_battle_loot_mod", "wh_main_effect_force_all_campaign_replenishment_rate"
SIGHT, MISCAST = "wh_main_effect_agent_field_line_of_sight_mod", "wh_main_effect_character_stat_miscast"
WINDS_COST, COOLDOWN = "wh2_dlc14_effect_magic_cost_all_lores_percentage", "wh2_dlc12_effect_magic_cooldown_all_lores"
BARRIER, INTENSITY = "wh3_main_effect_battle_barrier_health_add", "wh3_main_effect_spell_mastery"
AURA, DROP = "wh_main_effect_character_stat_leadership_aura_size", "wh_main_effect_character_mod_ancillary_drop"
AMBUSH, AMBUSH_DEFENCE = "wh_main_effect_force_army_campaign_ambush_attack_success_chance", "wh_main_effect_force_army_campaign_ambush_defence_success_chance"
STRIDER, STALK, VANGUARD = "wh_main_effect_attribute_enable_strider", "wh_main_effect_attribute_enable_stalk", "wh_main_effect_attribute_enable_vanguard_deployment"
UNBREAKABLE, IMMUNE = "wh_main_effect_attribute_enable_unbreakable", "wh_main_effect_attribute_enable_immune_to_psychology"
FEAR, TERROR = "wh_main_effect_attribute_enable_causes_fear", "wh_main_effect_attribute_enable_causes_terror"
RAID, WIN_MOVE = "wh_main_effect_force_all_campaign_raid_income", "wh3_main_effect_force_all_campaign_movement_range_post_battle_win"
UNIT_XP, RECRUIT = "wh_main_effect_agent_action_outcome_parent_army_xp_gain", "wh_main_effect_force_all_campaign_recruitment_cost_all"
ENEMY_HEROES, CAPTIVES = "wh_main_effect_agent_action_success_chance_enemy", "wh_main_effect_force_all_campaign_captives"
WINDED, TIRED = "wh_main_effect_force_campaign_stance_begin_fatigued_3_winded", "wh_main_effect_force_campaign_stance_begin_fatigued_4_tired"
ATTRITION, FRENZY = "wh_main_effect_campaign_enable_attrition", "wh3_dlc27_effect_ability_enable_frenzy_all"
PERFECT_VIGOUR = "wh2_dlc10_effect_attribute_enable_perfect_vigour"
LORD_MA, LORD_ARMOUR, LORD_WARD = "wh_main_effect_character_stat_melee_attack", "wh_main_effect_character_stat_armour", "wh_main_effect_character_stat_ward_save"

# The effect library's custom effects the catalogue uses.
REGEN_DEFENDING, MD_DEFENDING = library.effect_key("regeneration_defending"), library.effect_key("melee_defence_defending")
UNBREAKABLE_DEFENDING, LEAD_DEFENDING = library.effect_key("unbreakable_defending"), library.effect_key("leadership_defending")
SPEED_ATTACKING, UNBREAKABLE_ATTACKING = library.effect_key("speed_attacking"), library.effect_key("unbreakable_attacking")
BLINDED, LEECHED = library.effect_key("blinded_hits"), library.effect_key("leech_hits")
COMET, COMET_USES = library.effect_key("comet_army_ability"), library.effect_key("comet_army_ability_uses")
MARCH_BLOCKED = library.effect_key("march_blocked")

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text and pictures

# Level numbers in bundle titles, e.g. "Bloodsworn III".
ROMAN = ["", "I", "II", "III", "IV", "V"]

# Line break inside loc text, stored escaped in the TSV.
BREAK = "\\\\n\\\\n"

# Event -> (incident title, description, picture). "{lord}" in a description is the lord's name, read from the config's `lord_context`.
INCIDENTS: Dict[str, Tuple[str, str, str]] = {
    "boon_gained": ("A Boon Is Won", "Something has changed in {lord}'s army, and for the better. Every warrior can feel it.", "ursun_claimed"),
    "boon_grew": ("The Boon Grows", "Another victory, and {lord}'s army has grown stronger for it.", "victory"),
    "boon_lost": ("A Boon Fades", "Whatever gave {lord}'s army its edge is gone now.", "attrition_mountain"),
    "curse_gained": ("A Curse Takes Hold", "A shadow has fallen over {lord}'s army, and it will not lift on its own.", "ai_wins_soul"),
    "curse_worse": ("The Curse Deepens", "The curse on {lord}'s army grows heavier with every passing day.", "attrition_vampire_territory"),
    "curse_lifted": ("A Curse Is Lifted", "The weight on {lord}'s army is gone at last.", "rift_entered"),
    "curse_turned": ("The Curse Turns", "{lord}'s army has carried its curse so long that it has become something else.", "sword_of_khaine"),
    "realm_boon": ("A Blessing on the Realm", "Good fortune has settled over the whole realm, though it will not last forever.", "winds_of_magic_change"),
    "realm_curse": ("A Curse on the Realm", "A darkness has fallen over the whole realm. It will pass, in time.", "chaos_doom_tide"),
}

# Display order of the full-slots dilemma's first choice in cdir_events_dilemma_choices. The others follow it, the new boon's last.
FULL_CHOICE_ORDER = 1100

# The full-slots dilemma: (title, description, picture, label of a slot's choice, label of the new boon's choice).
FULL_DILEMMA = ("Too Many Blessings", "This lord can carry no more boons. To take the new one, another must be given up.", "nemesis_crown", "Give This Up",
                "Refuse the New Boon")

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Catalogue

# One level: its text and its effects as (effect, scope, value).
Level = Tuple[str, List[Tuple[str, str, float]]]


def ramp(texts: List[str], *parts: Tuple[str, str, List[Optional[float]]]) -> List[Level]:
    """Builds the levels of a boon or curse from its texts and its effect ramps.

    Args:
        texts (List[str]): One text per level.
        parts (Tuple): (effect, scope, values) where values has one entry per level, None where the effect is absent.

    Returns:
        List[Level]: One (text, effects) per level.
    """
    return [(text, [(effect, scope, values[i]) for effect, scope, values in parts if values[i] is not None]) for i, text in enumerate(texts)]


N = None

# Boon key -> (name, flavour, icon, levels). A rolled boon's name and texts carry "{race}".
BOONS: Dict[str, Tuple[str, str, str, List[Level]]] = {
    "bloodsworn": ("Bloodsworn", "The lord swore an oath in blood, and the army fights to keep it.", "blood_kiss.png", ramp(
        ["+3 melee attack", "+6 melee attack", "+9 melee attack", "+12 melee attack", "+15 melee attack, and every unit gains Frenzy"],
        (MA, F, [3, 6, 9, 12, 15]), (FRENZY, F, [N, N, N, N, 1]))),
    "ironhide": ("Ironhide", "Every scar has hardened this army's skin.", "resistance_physical.png", ramp(
        ["+3% physical resistance", "+6% physical resistance", "+9% physical resistance", "+12% physical resistance", "+15% physical resistance"],
        (PHYS, F, [3, 6, 9, 12, 15]))),
    "old_oath_banner": ("Banner of the Old Oath", "An old banner, carried by an older promise. No one breaks while it stands.", "morale.png", ramp(
        ["+4 leadership", "+8 leadership", "+12 leadership", "+16 leadership", "+20 leadership, and the lord's leadership aura is 50% wider"],
        (LEAD, F, [4, 8, 12, 16, 20]), (AURA, C, [N, N, N, N, 50]))),
    "eagle_eyed": ("Eagle-Eyed", "The army's archers and gunners see further than they should.", "ammo.png", ramp(
        ["+5% range", "+10% range", "+15% range, +20% ammunition", "+20% range, +20% ammunition", "+25% range, +20% ammunition, +10% missile strength"],
        (RANGE, F, [5, 10, 15, 20, 25]), (AMMO, F, [N, N, 20, 20, 20]), (MISSILE, F, [N, N, N, N, 10]))),
    "swift_column": ("Swift Column", "This army marches as if the road shortens for it.", "vigour.png", ramp(
        ["+5% campaign movement", "+10% campaign movement", "+15% campaign movement", "+20% campaign movement",
         "+25% campaign movement, and 25% of it comes back after a win"],
        (MOVE, F, [5, 10, 15, 20, 25]), (WIN_MOVE, C, [N, N, N, N, 25]))),
    "kindled_winds": ("Kindled Winds", "The winds come easily to this army's casters.", "wh3_dlc24_wind_blast.png", ramp(
        ["-5% Winds of Magic cost", "-10% Winds of Magic cost", "-15% Winds of Magic cost", "-20% Winds of Magic cost",
         "-25% Winds of Magic cost, -20% spell cooldowns"],
        (WINDS_COST, F, [-5, -10, -15, -20, -25]), (COOLDOWN, F, [N, N, N, N, -20]))),
    "stormcaller": ("Stormcaller", "The lord can call a star down from the sky.", "attribute_mastery_of_elemental_winds.png", ramp(
        ["Army ability: Comet of Casandora, 1 use", "Comet of Casandora, 2 uses", "Comet of Casandora, 3 uses", "Comet of Casandora, 3 uses, +10% spell intensity",
         "Comet of Casandora, 4 uses, +20% spell intensity"],
        (COMET, F, [1, 1, 1, 1, 1]), (COMET_USES, F, [N, 1, 2, 2, 3]), (INTENSITY, F, [N, N, N, 10, 20]))),
    "stone_rampart": ("Stone Rampart", "Attackers break on this army like waves on rock.", "icon_effects_fortify.png", ramp(
        ["+3 melee defence when defending", "+6 melee defence when defending", "+9 melee defence and Regeneration when defending",
         "+12 melee defence and Regeneration when defending", "+15 melee defence, Regeneration and Unbreakable when defending"],
        (MD_DEFENDING, F, [3, 6, 9, 12, 15]), (REGEN_DEFENDING, F, [N, N, 1, 1, 1]), (UNBREAKABLE_DEFENDING, F, [N, N, N, N, 1]))),
    "storm_forward": ("Storm Forward", "When this army attacks, nothing stands in its way for long.", "charge.png", ramp(
        ["+5% battle speed when attacking", "+10% battle speed when attacking", "+15% battle speed when attacking", "+20% battle speed when attacking",
         "+25% battle speed and Unbreakable when attacking"],
        (SPEED_ATTACKING, F, [5, 10, 15, 20, 25]), (UNBREAKABLE_ATTACKING, F, [N, N, N, N, 1]))),
    "plunderer": ("Plunderer", "This army leaves nothing of value behind.", "assassin.png", ramp(
        ["+10% post-battle loot", "+20% post-battle loot", "+30% post-battle loot, +25% raiding income", "+40% post-battle loot, +25% raiding income",
         "+50% post-battle loot, +25% raiding income, +15% magic item drop chance"],
        (LOOT, F, [10, 20, 30, 40, 50]), (RAID, F, [N, N, 25, 25, 25]), (DROP, C, [N, N, N, N, 15]))),
    "quartermaster": ("Quartermaster's Ledger", "A careful hand keeps the army fed for less.", "icon_effects_fortify.png", ramp(
        ["-5% upkeep", "-10% upkeep", "-15% upkeep", "-20% upkeep", "-25% upkeep"], (UPKEEP, F, [-5, -10, -15, -20, -25]))),
    "drillmaster": ("Iron Drillmaster", "Drill at dawn, drill at dusk. The ranks get sharper every day.", "morale.png", ramp(
        ["+50 unit experience per turn", "+100 unit experience per turn", "+150 unit experience per turn", "+200 unit experience per turn",
         "+250 unit experience per turn"], (UNIT_XP, F, [50, 100, 150, 200, 250]))),
    "blinding_strikes": ("Blinding Strikes", "Every blow this army lands leaves its foe reeling and half-blind.", "wh_dlc06_unit_contact_blinded.png", ramp(
        ["Hits cause Blinded", "Blinded, +5% charge bonus", "Blinded, +10% charge bonus", "Blinded, +15% charge bonus", "Blinded, +20% charge bonus"],
        (BLINDED, F, [1, 1, 1, 1, 1]), (CHARGE, F, [N, 5, 10, 15, 20]))),
    "leeching_strikes": ("Leeching Strikes", "The army's weapons drink the life of whatever they cut.", "magic_character.png", ramp(
        ["Hits cause Leeched (10 damage a second for 5 seconds)", "Leeched, +3% ward save", "Leeched, +6% ward save", "Leeched, +9% ward save",
         "Leeched, +12% ward save"], (LEECHED, F, [1, 1, 1, 1, 1]), (WARD, F, [N, 3, 6, 9, 12]))),
    "hunters_path": ("Hunter's Path", "The army moves through rough country like a hunting pack.", "attribute_stalk.png", ramp(
        ["Strider", "Strider and Stalk", "Strider, Stalk, +10% ambush success", "Strider, Stalk, +20% ambush success",
         "Strider, Stalk, +20% ambush success, Vanguard Deployment"],
        (STRIDER, F, [1, 1, 1, 1, 1]), (STALK, F, [N, 1, 1, 1, 1]), (AMBUSH, F, [N, N, 10, 20, 20]), (VANGUARD, F, [N, N, N, N, 1]))),
    "warded": ("Warded", "Old sigils glow on the lord's armour when danger comes.", "resistance_ward_save.png", ramp(
        ["Lord: +3% ward save, +300 barrier", "Lord: +6% ward save, +600 barrier", "Lord: +9% ward save, +900 barrier", "Lord: +12% ward save, +1200 barrier",
         "Lord: +15% ward save, +1500 barrier"], (LORD_WARD, C, [3, 6, 9, 12, 15]), (BARRIER, C, [300, 600, 900, 1200, 1500]))),
    "overflowing_power": ("Overflowing Power", "The lord's magic burns hotter, and harder to hold.", "emp_winds_of_shyish.png", ramp(
        ["+5% spell intensity, +10% miscast chance", "+10% spell intensity, +10% miscast chance", "+15% spell intensity, +10% miscast chance",
         "+20% spell intensity, +10% miscast chance", "+25% spell intensity, +10% miscast chance"],
        (INTENSITY, F, [5, 10, 15, 20, 25]), (MISCAST, F, [10, 10, 10, 10, 10]))),
    "dread_host": ("Dread Host", "Stories of this army walk ahead of it.", "attribute_causes_terror.png", ramp(
        ["Every unit causes fear", "Fear, +5 leadership", "Fear, +10 leadership", "Every unit causes terror, +10 leadership", "Terror, +15 leadership"],
        (FEAR, F, [1, 1, 1, N, N]), (TERROR, F, [N, N, N, 1, 1]), (LEAD, F, [N, 5, 10, 10, 15]))),
    "bane": ("Bane of {race}", "The lord has learned exactly where this enemy breaks.", "weapon_damage.png", []),
    "death_touched": ("Death-Touched", "The dead that haunted this army now march with it.", "icon_necromantic_power.png", ramp(
        ["Immune to psychology", "Immune to psychology, causes fear", "+5 leadership, causes fear", "+10 leadership, causes fear",
         "+10 leadership, causes terror"],
        (IMMUNE, F, [1, 1, N, N, N]), (FEAR, F, [N, 1, 1, 1, N]), (TERROR, F, [N, N, N, N, 1]), (LEAD, F, [N, N, 5, 10, 10]))),
    "tireless": ("Tireless", "Weeks without rest, and now the army has simply stopped getting tired.", "attribute_fatigue_immune.png", ramp(
        ["Tires 10% slower", "Tires 20% slower", "Tires 30% slower", "Tires 40% slower", "Never tires (Perfect Vigour)"],
        (VIGOUR, F, [10, 20, 30, 40, N]), (PERFECT_VIGOUR, F, [N, N, N, N, 1]))),
    "war_chant": ("War Chant", "A song the army learned somewhere strange. It only works for a while.", "morale.png",
                  [("+10 melee attack, +10 leadership, for 3 battles", [(MA, F, 10), (LEAD, F, 10)])]),
    "fates_favour": ("Fate's Favour", "For a short time, every blade seems to miss this army.", "resistance_ward_save.png",
                     [("+10% ward save, for 3 battles", [(WARD, F, 10)])]),
    "kings_ransom": ("King's Ransom", "Every fallen enemy turns out to carry a fat purse.", "assassin.png",
                     [("+100% post-battle loot, +25% captives, for 3 battles", [(LOOT, F, 100), (CAPTIVES, F, 25)])]),
    "undying_vigil": ("Undying Vigil", "For two fights, no one in this army will run.", "attribute_unbreakable.png",
                      [("Every unit is Unbreakable, for 2 battles", [(UNBREAKABLE, F, 1)])]),
}

# Curse key -> (name, flavour, icon, levels). A rolled curse's name and texts carry "{race}".
CURSES: Dict[str, Tuple[str, str, str, List[Level]]] = {
    "haunted": ("Haunted", "The dead follow this army at night. The soldiers can hear them.", "dlc10_death_night.png", ramp(
        ["-3 leadership", "-6 leadership", "-9 leadership", "-12 leadership", "-15 leadership"], (LEAD, F, [-3, -6, -9, -12, -15]))),
    "creeping_rust": ("Creeping Rust", "No amount of oil keeps the rust off this army's blades.", "weapon_damage.png", ramp(
        ["-3% weapon strength", "-6% weapon strength", "-9% weapon strength", "-12% weapon strength", "-15% weapon strength"],
        (WS, F, [-3, -6, -9, -12, -15]))),
    "leaden_march": ("Leaden March", "Every step feels like wading through mud.", "attrition.png", ramp(
        ["-5% campaign movement", "-10% campaign movement", "-15% campaign movement", "-20% campaign movement", "-25% campaign movement, and no March stance"],
        (MOVE, F, [-5, -10, -15, -20, -25]), (MARCH_BLOCKED, F, [N, N, N, N, 1]))),
    "bleeding_coffers": ("Bleeding Coffers", "Gold leaks out of this army's chests faster than it comes in.", "casualties.png", ramp(
        ["+5% upkeep", "+10% upkeep", "+15% upkeep", "+20% upkeep", "+25% upkeep"], (UPKEEP, F, [5, 10, 15, 20, 25]))),
    "weary_ranks": ("Weary Ranks", "Nobody in this army has slept well in weeks.", "attrition.png", ramp(
        ["Tires 5% faster", "Tires 10% faster", "Starts every battle Winded, tires 10% faster", "Starts every battle Tired, tires 10% faster",
         "Starts every battle Tired, tires 15% faster"],
        (VIGOUR, F, [-5, -10, -10, -10, -15]), (WINDED, F, [N, N, 3, N, N]), (TIRED, F, [N, N, N, 4, 4]))),
    "withered_supply": ("Withered Supply", "Food spoils, wounds fester, and new recruits never seem to arrive.", "phase_posion.png", ramp(
        ["-20% replenishment", "-40% replenishment", "-60% replenishment", "-80% replenishment", "No replenishment, and attrition even at home"],
        (REPLENISH, F, [-20, -40, -60, -80, -100]), (ATTRITION, F, [N, N, N, N, 1]))),
    "fogbound": ("Fogbound", "A grey fog follows this army wherever it goes.", "attribute_revealed.png", ramp(
        ["-10% line of sight", "-20% line of sight", "-30% line of sight", "-40% line of sight", "-50% line of sight"], (SIGHT, C, [-10, -20, -30, -40, -50]))),
    "magpies_curse": ("Magpie's Curse", "Loot slips out of the soldiers' hands as soon as they pick it up.", "casualties.png", ramp(
        ["-10% post-battle loot", "-20% post-battle loot", "-30% post-battle loot", "-40% post-battle loot", "-50% post-battle loot"],
        (LOOT, F, [-10, -20, -30, -40, -50]))),
    "wild_magic": ("Wild Magic", "Spells cast near this army go wrong more often than they should.", "wh3_dlc24_wind_blast.png", ramp(
        ["+5% miscast chance", "+10% miscast chance", "+15% miscast chance", "+20% miscast chance", "+25% miscast chance"], (MISCAST, F, [5, 10, 15, 20, 25]))),
    "shunned_by_the_winds": ("Shunned by the Winds", "The Winds of Magic thin out around this lord.", "emp_winds_of_shyish.png", ramp(
        ["+10% Winds of Magic cost", "+20% Winds of Magic cost", "+30% Winds of Magic cost", "+40% Winds of Magic cost", "+50% Winds of Magic cost"],
        (WINDS_COST, F, [10, 20, 30, 40, 50]))),
    "cowards_mark": ("Coward's Mark", "Someone in this army ran once, and everyone remembers.", "discouraged.png", ramp(
        ["-4 leadership when defending", "-8 leadership when defending", "-12 leadership when defending", "-16 leadership when defending",
         "-20 leadership when defending"], (LEAD_DEFENDING, F, [-4, -8, -12, -16, -20]))),
    "marked_prey": ("Marked Prey", "Someone is always watching this army from the treeline.", "attribute_stalk.png", ramp(
        ["-10% ambush defence", "-15% ambush defence", "-20% ambush defence", "-25% ambush defence, +10% enemy hero action success",
         "-30% ambush defence, +15% enemy hero action success"],
        (AMBUSH_DEFENCE, F, [-10, -15, -20, -25, -30]), (ENEMY_HEROES, C, [N, N, N, 10, 15]))),
    "brittle_bones": ("Brittle Bones", "Wounds that should heal in days take weeks.", "resistance_physical.png", ramp(
        ["-3 armour", "-6 armour", "-9 armour", "-12 armour", "-15 armour"], (ARMOUR, F, [-3, -6, -9, -12, -15]))),
    "shaky_aim": ("Shaky Aim", "Hands shake, and arrows drift wide.", "ammo.png", ramp(
        ["-5% missile strength", "-10% missile strength", "-15% missile strength", "-20% missile strength", "-25% missile strength"],
        (MISSILE, F, [-5, -10, -15, -20, -25]))),
    "grudge": ("Grudge of {race}", "This enemy has sworn to remember the lord's name.", "discouraged.png", []),
    "glass_jaw": ("Glass Jaw", "The lord took a blow that never quite healed.", "casualties.png", ramp(
        ["Lord: -5 armour", "Lord: -10 armour", "Lord: -15 armour, -5 melee attack", "Lord: -20 armour, -5 melee attack", "Lord: -25 armour, -10 melee attack"],
        (LORD_ARMOUR, C, [-5, -10, -15, -20, -25]), (LORD_MA, C, [N, N, -5, -5, -10]))),
    "stumbling_charge": ("Stumbling Charge", "Charges lose their nerve a few paces from the enemy.", "charge.png", ramp(
        ["-5% charge bonus", "-10% charge bonus", "-15% charge bonus", "-20% charge bonus", "-25% charge bonus"], (CHARGE, F, [-5, -10, -15, -20, -25]))),
    "cursed_coin": ("Cursed Coin", "Recruits want double pay before they will march under this lord.", "casualties.png", ramp(
        ["+5% recruitment cost", "+10% recruitment cost", "+15% recruitment cost", "+20% recruitment cost", "+25% recruitment cost"],
        (RECRUIT, F, [5, 10, 15, 20, 25]))),
}

# Faction-wide key -> (name, flavour, icon, text, [(effect, scope, value)]).
REALM: Dict[str, Tuple[str, str, str, str, List[Tuple[str, str, float]]]] = {
    "comet_sign": ("Sign of the Twin-Tailed Comet", "A comet hangs over the realm, and the Winds swell under it.", "attribute_mastery_of_elemental_winds.png",
                   "Every army: +5 Winds of Magic reserve per turn", [("wh3_main_effect_winds_of_magic_events", "faction_to_force_own", 5)]),
    "old_ones_favour": ("Favour of the Old Ones", "Scholars across the realm wake with ideas they did not have before.", "lileaths_blessing.png",
                        "+15% research rate", [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", 15)]),
    "golden_age": ("Golden Age", "Trade flows and the harvests are rich.", "icon_effects_fortify.png", "+10% income from all buildings, +10 public order",
                   [("wh_main_effect_economy_gdp_mod_all", "faction_to_province_own", 10), ("wh_main_effect_public_order_faction", "faction_to_province_own", 10)]),
    "dark_gods_wrath": ("Wrath of the Dark Gods", "The realm has caught the attention of something hungry.", "corruption_tzeentch.png",
                        "+10 Chaos corruption and -10 public order in every province",
                        [("wh3_main_effect_corruption_chaos_events_bad", "faction_to_province_own", 10),
                         ("wh_main_effect_public_order_faction", "faction_to_province_own", -10)]),
    "black_plague": ("Black Plague", "Sickness spreads from town to town.", "phase_posion.png", "-10 growth in every province",
                     [("wh3_main_effect_province_growth_faction", "faction_to_province_own", -10)]),
    "pariah": ("Pariah", "Envoys stop answering this realm's letters.", "discouraged.png", "-20 relations with every faction",
               [("wh_main_faction_political_diplomacy_mod", "faction_to_faction_own_unseen", -20)]),
}


# Offer key -> name, for the offers that grant boons and curses at sites, the bar and tower floors. Its line opens with the name in lower case.
OFFERS: Dict[str, str] = {
    "blood_pact": "Swear the Blood Pact",
    "hunters_bargain": "Strike the Hunter's Bargain",
    "price_of_the_winds": "Pay the Price of the Winds",
    "dread_oath": "Take the Dread Oath",
    "star_pact": "Seal the Star Pact",
    "claim_the_cursed_relic": "Claim the Cursed Relic",
    "read_the_omens": "Read the Omens",
    "sing_the_war_chant": "Learn the War Chant",
    "thiefs_mark": "Take the Thief's Mark",
    "gold_for_blood": "Trade Gold for Blood",
    "rust_for_iron": "Trade Rust for Iron",
}

# Icon of an offer whose boon is random.
RANDOM_ICON = "fractured_mind.png"


def grants(offer: Dict) -> bool:
    """True when an offer grants a boon or a curse, as features/boons.lua `grants` decides.

    Args:
        offer (Dict): An offer record from the Lua dump.

    Returns:
        bool: True for such an offer.
    """
    return "boon" in offer or "curse" in offer


def level_title(name: str, levels: List[Level], number: int) -> str:
    """A boon's or curse's title at a level, e.g. "Bloodsworn II". One with a single level keeps its name.

    Args:
        name (str): Its name.
        levels (List[Level]): Its levels.
        number (int): The level.

    Returns:
        str: The title.
    """
    return name if len(levels) == 1 else f"{name} {ROMAN[number]}"


def grant_text(kind: str, grant) -> str:
    """How an offer's line names what it grants in its colour, e.g. "[[col:green]]Bloodsworn II (+6 melee attack)[[/col]]".

    Args:
        kind (str): "boon" or "curse".
        grant: The offer's `boon` or `curse` field as dumped: [key, level], or { "from": source } for a random one.

    Returns:
        str: The text.
    """
    colour = "green" if kind == "boon" else "red"
    if isinstance(grant, dict):
        return f"[[col:{colour}]]a random {kind}[[/col]]"
    key, level = grant[0], grant[1] if len(grant) > 1 else 1
    name, _, _, levels = (BOONS if kind == "boon" else CURSES)[key]
    return f"[[col:{colour}]]{level_title(name, levels, level)} ({levels[level - 1][0]})[[/col]]"


def offer_texts(offers: List[Dict], pay: str) -> Tuple[Dict[str, Tuple[str, str]], Dict[str, str]]:
    """The name, line and icon of every offer that grants a boon or curse.

    Args:
        offers (List[Dict]): Offer records from the Lua dump.
        pay (str): The paid line's opening, with a {cost} placeholder, ending where the action follows.

    Returns:
        Tuple: (offer key -> (name, line), offer key -> icon).
    """
    texts, icons = {}, {}
    for offer in offers:
        if not grants(offer):
            continue
        name = OFFERS[offer["key"]]
        action = name.lower()
        opening = pay + action if "cost" in offer else action[0].upper() + action[1:]
        parts = [f"our lord gains {grant_text('boon', offer['boon'])}"] if "boon" in offer else []
        if "curse" in offer:
            parts.append(f"{'and is struck by' if parts else 'our lord is struck by'} {grant_text('curse', offer['curse'])}")
        texts[offer["key"]] = (name, opening + ": " + ", ".join(parts) + ".")
        boon = offer.get("boon")
        icons[offer["key"]] = BOONS[boon[0]][2] if isinstance(boon, list) else RANDOM_ICON
    return texts, icons


def race_levels(key: str, race: str) -> List[Level]:
    """The levels of a rolled boon or curse for one race.

    Args:
        key (str): "bane" or "grudge".
        race (str): The race key.

    Returns:
        List[Level]: One (text, effects) per level.
    """
    name, _, diplomacy = library.RACES[race]
    weapon, attack = library.effect_key("weapon_strength_vs_" + race), library.effect_key("melee_attack_vs_" + race)
    if key == "bane":
        return ramp([f"+5% weapon strength against {name}", f"+10% weapon strength against {name}", f"+15% weapon strength against {name}",
                     f"+20% weapon strength against {name}", f"+25% weapon strength and +5 melee attack against {name}"],
                    (weapon, F, [5, 10, 15, 20, 25]), (attack, F, [N, N, N, N, 5]))
    return ramp([f"-10 relations with {name}", f"-20 relations with {name}", f"-30 relations with {name}", f"-40 relations with {name}",
                 f"-50 relations with {name}"], (diplomacy, FACTION, [-10, -20, -30, -40, -50]))


def variants(kind: str, config: Dict) -> List[Tuple[str, str, str, str, List[Level]]]:
    """Every boon or curse as it is bundled: one variant per race for a rolled one.

    Args:
        kind (str): "boon" or "curse".
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple]: (bundle stem without level, name, flavour, icon, levels) per variant.
    """
    catalogue = BOONS if kind == "boon" else CURSES
    out = []
    for record in config["boons" if kind == "boon" else "curses"]:
        key = record["key"]
        name, flavour, icon, levels = catalogue[key]
        if record.get("race"):
            for race in config["races"]:
                out.append((f"{key}_{race}", name.format(race=library.RACES[race][0]), flavour, icon, race_levels(key, race)))
        else:
            out.append((key, name, flavour, icon, levels))
    return out


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rows


def bundles(config: Dict) -> Dict[str, Tuple]:
    """Every boon, curse and faction-wide bundle, in the generator's bundle shape.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple]: Bundle key -> (target, icon, title, description, [(effect, scope, value)]).
    """
    shaped = {}
    for kind in ("boon", "curse"):
        for stem, name, flavour, icon, levels in variants(kind, config):
            for number, (text, effects) in enumerate(levels, 1):
                title = level_title(name, levels, number)
                shown = flavour if len(levels) == 1 else f"{flavour}{BREAK}Level {number} of {len(levels)}."
                shaped[f"{config['bundle_prefix'][kind]}{stem}_{number}"] = ("character", icon, title, shown, effects)
    for key, (name, flavour, icon, _, effects) in REALM.items():
        shaped[config["realm_prefix"] + key] = ("faction", icon, name, flavour, effects)
    return shaped


def lines(config: Dict) -> List[Tuple[str, str, str]]:
    """The payload line of every boon and curse level and every faction-wide effect, which dilemmas and incidents show.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple[str, str, str]]: (payload key, icon, text).
    """
    out = []
    for kind, colour in (("boon", "green"), ("curse", "red")):
        for stem, name, _, icon, levels in variants(kind, config):
            for number, (text, _) in enumerate(levels, 1):
                level = "" if len(levels) == 1 else f" (level {number} of {len(levels)})"
                out.append((f"{config['line_prefix']}{kind}_{stem}_{number}", icon, f"[[col:{colour}]]{name}{level}: {text}[[/col]]"))
    good = {r["key"]: r.get("good") for r in config["realm"]}
    for key, (name, _, icon, text, _) in REALM.items():
        out.append((f"{config['line_prefix']}realm_{key}", icon, f"[[col:{'green' if good[key] else 'red'}]]{name}: {text}, for {config['realm_turns']} turns[[/col]]"))
    return out


def incidents(config: Dict) -> Dict[str, Tuple[str, str, str]]:
    """The incidents with the lord's name filled into their descriptions.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple[str, str, str]]: Event -> (title, description, picture).
    """
    lord = f'[[col:yellow]]{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["lord_context"]}").StringValue}}}}[[/col]]'
    return {event: (title, description.replace("{lord}", lord), image) for event, (title, description, image) in INCIDENTS.items()}


def owned_prefixes(config: Dict) -> List[str]:
    """Every key prefix of the rows this catalogue writes, so the generator replaces them on each run.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[str]: The prefixes.
    """
    return (list(config["bundle_prefix"].values()) + [config["realm_prefix"], config["full_dilemma"], config["full_new_choice"]]
            + [config["line_prefix"] + kind + "_" for kind in ("boon", "curse", "realm")] + config["full_choices"]
            + [config["incident_prefix"] + event for event in INCIDENTS])


def problems(config: Dict) -> List[str]:
    """Names every mismatch between the config and this catalogue: boons, curses, races or faction-wide effects that differ, a level
    count that is off, or a charged boon whose text names the wrong number of battles.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[str]: The problems, empty when none.
    """
    found = []
    for kind, catalogue in (("boons", BOONS), ("curses", CURSES)):
        keys = {r["key"] for r in config[kind]}
        found += [f"{kind}: no text for {key}" for key in sorted(keys - set(catalogue))]
        found += [f"{kind}: text for unknown {key}" for key in sorted(set(catalogue) - keys)]
        for record in config[kind]:
            levels = catalogue.get(record["key"], (None, None, None, []))[3]
            charges = record.get("charges")
            if not record.get("race") and len(levels) != (1 if charges else config["max_level"]):
                found.append(f"{record['key']} has {len(levels)} levels")
            if charges and not levels[0][0].endswith(f"for {charges} battles"):
                found.append(f"{record['key']} text does not say {charges} battles")
    found += [f"race {race} differs" for race in sorted(set(config["races"]) ^ set(library.RACES))]
    found += [f"faction-wide {key} differs" for key in sorted({r["key"] for r in config["realm"]} ^ set(REALM))]
    return found
