"""The LEAPOI effect library: custom effects bound through tables LEAPOI did not use before, and the trial bundles that put them and some
unused vanilla effects on an army. The debug `test_bundles` switches in script/land_encounters/configs/debug.lua apply the bundles by key.
Written into the mod by update_leapoi_spot_offers.py."""

from typing import Dict, List, Tuple

from generators.leapoi_battle_modifiers import BUNDLE_ICON, SCOPE

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Naming

# Prefix of every library bundle. The library name follows, e.g. land_enc_effect_lib_onhit_blinded.
BUNDLE_PREFIX = "land_enc_effect_lib_"

# Prefix of every custom effect and junction row key, then of each kind.
CUSTOM_PREFIX = "land_enc_lib_"
EFFECT_PREFIX = CUSTOM_PREFIX + "fx_"
JUNCTION_PREFIX = CUSTOM_PREFIX + "jn_"

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Custom effects

# Custom effect name -> (icon, category, tooltip text, [(table, row fields)]). The effect key is EFFECT_PREFIX + name and its junction key
# is JUNCTION_PREFIX + name. Each row is written as given, with "{fx}" and "{jn}" standing for those keys. A table ending in ".loc" is a
# loc file, whose fields are (key, text).
CUSTOM_EFFECTS: Dict[str, Tuple[str, str, str, List[Tuple[str, Tuple]]]] = {
    "blinded_hits": ("wh_dlc06_unit_contact_blinded.png", "battle", 'Attacks cause "Blinded" for all units', [
        ("unit_set_special_ability_phase_junctions_tables", ("{jn}", "wh_dlc06_unit_contact_blinded", "all_units")),
        ("effect_bonus_value_unit_set_special_ability_phase_junctions_tables", ("active", "{fx}", "{jn}")),
    ]),
    # A light copy of Spirit Leech for every unit's hits. Every hit restarts it, so the spell's per-model effect would replay on each one:
    # this display keeps only the banner marker, the phase has no looping sound, and it drains for less. Its icon is a copy of Spirit Leech's
    # at ui/battle ui/ability_icons/<phase key>.png. A save made before this phase existed crashes on load once an army carries it, so an
    # offer that hands it out needs a new campaign, said in the change notes.
    "leech_hits": ("magic_character.png", "battle", 'Attacks cause "Leeched" for all units, draining hit points', [
        ("special_ability_phase_displays_tables", ("{jn}", "", "wh3_dlc20_lore_of_death_banner_debuff", "", "top", "true")),
        ("special_ability_phases_tables", ("{jn}", "5.0000", "negative", "", "false", "false", "0.0000", "0.0000", "0.0000", "1.0000", "20", "1",
                                           "false", "0.0000", "0.0000", "false", "0", "", "{jn}", "", "false", "false", "true", "0.0000", "", "",
                                           "false", "0.0000", "0.0000", "false", "0.0000")),
        ("special_ability_phases.loc", ("special_ability_phases_onscreen_name_{jn}", "Leeched!")),
        ("effect_bonus_value_special_ability_phase_record_junctions_tables", ("active", "{fx}", "{jn}")),
    ]),
    "melee_attack_defending": ("melee.png", "battle", "Melee attack: %+n when defending", [
        ("effect_bonus_value_battle_context_junctions_tables", ("melee_attack_mod", "{fx}", "fighting_force_status_yours_defending")),
    ]),
    "regeneration_defending": ("general_ability.png", "battle", 'Passive ability: "Regeneration" when defending', [
        ("battle_context_unit_ability_junctions_tables", ("{jn}", "fighting_force_status_yours_defending", "wh_main_unit_passive_regeneration")),
        ("effect_bonus_value_battle_context_unit_ability_junctions_tables", ("enable", "{fx}", "{jn}")),
    ]),
    "speed_attacking": ("battle_movement.png", "battle", "Speed: %+n% when attacking", [
        ("effect_bonus_value_battle_context_junctions_tables", ("mod_land_movement_battle", "{fx}", "fighting_force_status_yours_attacking")),
    ]),
    "unbreakable_attacking": ("attribute_unbreakable.png", "battle", "Attribute: Unbreakable when attacking", [
        ("battle_context_unit_attribute_junctions_tables", ("{jn}", "fighting_force_status_yours_attacking", "unbreakable")),
        ("effect_bonus_value_battle_context_unit_attribute_junctions_tables", ("enable", "{fx}", "{jn}")),
    ]),
    "lore_fire_cost": ("magic.png", "battle", "Winds of Magic cost: %+n% for Lore of Fire spells", [
        ("effect_bonus_value_special_ability_group_junctions_tables", ("cost_percentage_mod", "{fx}", "wh_main_lore_fire")),
        ("effect_bonus_value_special_ability_group_junctions_tables", ("cost_percentage_mod", "{fx}", "wh_main_lore_fire_upgraded")),
    ]),
    # The bound item version of the comet: 1 use and no Winds of Magic cost. An army ability keeps the cost of the spell it points at.
    "comet_army_ability": ("magic.png", "battle", 'Army ability: "Comet of Casandora"', [
        ("army_special_abilities_tables", ("{jn}", "wh3_main_spell_bound_comet_of_casandora", "1700181001", "false")),
        ("effect_bonus_value_military_force_ability_junctions_tables", ("enable", "{fx}", "{jn}")),
    ]),
    "comet_army_ability_uses": ("magic.png", "battle", 'Uses: %+n for the "Comet of Casandora" army ability', [
        ("effect_bonus_value_military_force_ability_junctions_tables", ("uses_mod", "{fx}", JUNCTION_PREFIX + "comet_army_ability")),
    ]),
    "march_blocked": ("teleport.png", "campaign", "Cannot use the March stance", [
        ("effect_bonus_value_stance_junctions_tables", ("disabled", "{fx}", "MILITARY_FORCE_ACTIVE_STANCE_TYPE_MARCH")),
    ]),
    "ambush_stance_cost": ("teleport.png", "campaign", "Campaign movement cost of the Ambush stance: %+n%", [
        ("effect_bonus_value_stance_junctions_tables", ("cost_percentage_mod", "{fx}", "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")),
    ]),
}

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Trial bundles

# Library name -> (title, description, [(effect, value)]). A custom effect is named by its CUSTOM_EFFECTS name, a vanilla one by its key.
LIBRARY: Dict[str, Tuple[str, str, List[Tuple[str, float]]]] = {
    "onhit_blinded": ("Blinding Strikes", "Test: every unit's attacks blind what they hit.", [("blinded_hits", 1)]),
    "onhit_leech": ("Leeching Strikes", "Test: every unit's attacks drain the life of what they hit.", [("leech_hits", 1)]),
    "ctx_defending": ("Hold the Ground", "Test: stronger and self-healing when defending.", [("melee_attack_defending", 10), ("regeneration_defending", 1)]),
    "ctx_attacking": ("Storm Forward", "Test: faster and unbreakable when attacking, and unbreakable against the Undead.",
                      [("speed_attacking", 20), ("unbreakable_attacking", 1), ("wh3_dlc25_effect_force_stat_unbreakable_vs_undead", 1)]),
    "lore": ("Kindled Winds", "Test: cheaper Lore of Fire and faster spell cooldowns.",
             [("lore_fire_cost", -50), ("wh2_dlc12_effect_magic_cooldown_all_lores", -25)]),
    "army_spell": ("Falling Star", "Test: the army can call down the Comet of Casandora twice per battle, at no Winds of Magic cost.",
                   [("comet_army_ability", 1), ("comet_army_ability_uses", 1)]),
    "stances": ("Hobbled March", "Test: no March stance, and the Ambush stance costs more.", [("march_blocked", 1), ("ambush_stance_cost", 100)]),
    "tired": ("Weary Ranks", "Test: the army starts every battle tired.", [("wh_main_effect_force_campaign_stance_begin_fatigued_4_tired", 4)]),
    "magic": ("Unstable Power", "Test: stronger barriers and spells, and more miscasts.",
              [("wh3_main_effect_battle_barrier_health_add", 500), ("wh_main_effect_character_stat_miscast", 25), ("wh3_main_effect_spell_mastery", 20)]),
    "campaign_curse": ("Cursed Column", "Test: dearer upkeep, poor loot, short sight and no replenishment.",
                       [("wh_main_effect_force_all_campaign_upkeep", 50), ("wh_main_effect_force_all_campaign_post_battle_loot_mod", -50),
                        ("wh_main_effect_agent_field_line_of_sight_mod", -50), ("wh_main_effect_force_all_campaign_replenishment_rate", -100)]),
}

# Scope of a vanilla effect that does not read from the army itself, by effect key. Every other effect uses SCOPE.
SCOPES: Dict[str, str] = {
    "wh_main_effect_agent_field_line_of_sight_mod": "force_to_general_own",
}


def effect_key(name: str) -> str:
    """The key of a library bundle effect.

    Args:
        name (str): A CUSTOM_EFFECTS name or a vanilla effect key.

    Returns:
        str: The effect key.
    """
    return EFFECT_PREFIX + name if name in CUSTOM_EFFECTS else name


def custom_rows() -> List[Tuple[str, Tuple]]:
    """The DB rows of every custom effect: its effects_tables row and its binding rows.

    Returns:
        List[Tuple[str, Tuple]]: (table, fields) per row.
    """
    rows = []
    for name, (icon, category, _, bindings) in CUSTOM_EFFECTS.items():
        fx, jn = EFFECT_PREFIX + name, JUNCTION_PREFIX + name
        rows.append(("effects_tables", (fx, icon, 310, icon, category, "true")))
        for table, fields in bindings:
            if table.endswith(".loc"):
                continue
            rows.append((table, tuple(str(f).replace("{fx}", fx).replace("{jn}", jn) for f in fields)))
    return rows


def custom_texts() -> List[Tuple[str, str, str]]:
    """The loc rows of every custom effect: its tooltip text, and the rows of its ".loc" bindings.

    Returns:
        List[Tuple[str, str, str]]: (loc file name without ".loc", key, text) per row.
    """
    texts = []
    for name, (_, _, text, bindings) in CUSTOM_EFFECTS.items():
        fx, jn = EFFECT_PREFIX + name, JUNCTION_PREFIX + name
        texts.append(("effects", "effects_description_" + fx, text))
        for table, (key, line) in [(t, f) for t, f in bindings if t.endswith(".loc")]:
            texts.append((table[:-4], key.replace("{jn}", jn), line))
    return texts


def bundles() -> Dict[str, Tuple]:
    """The library bundles, in the generator's bundle shape.

    Returns:
        Dict[str, Tuple]: Bundle key -> (target, icon, title, description, [(effect, scope, value)]).
    """
    shaped = {}
    for name, (title, description, effects) in LIBRARY.items():
        rows = [(effect_key(e), SCOPES.get(e, SCOPE), v) for e, v in effects]
        shaped[BUNDLE_PREFIX + name] = ("force", BUNDLE_ICON, title, description, rows)
    return shaped
