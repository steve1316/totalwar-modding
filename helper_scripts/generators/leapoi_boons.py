"""Text and bundle effects of the LEAPOI boons and curses. The keys and rules live in script/land_encounters/configs/boons.lua. Written into the
mod by update_leapoi_spot_offers.py: one character bundle and one payload line per boon or curse level (per race for a rolled one), the
faction-wide bundles, the incidents and the full-slots dilemma."""

import re
from typing import Dict, List, Optional, Tuple

from generators import leapoi_battle_modifiers as battle_modifiers
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

# Line break inside loc text, stored escaped in the TSV, and the gap between paragraphs.
NL = "\\\\n"
BREAK = NL + NL

# Characters of loc text that fit on one line of the notification panel's description box, and the lines a description should fill. The
# box has a fixed height of about 17 lines, so a short description leaves a dark gap under it and a long one scrolls.
LINE_CHARS = 45
MIN_LINES, MAX_LINES = 10, 18

# Rule section shared by the pick and full-slots dilemmas: (heading, bullet lines). "{wins}" and "{max}" are filled from the config.
BOON_GROWTH_SHORT = ("How boons grow", ["A boon grows one level for every {wins} battles this lord wins, up to level {max}.",
                                        "Lost battles do not count, but they never take a level away."])

# The line `incidents` ends every boon and curse notice with. The rules it points to are on the Boons and Curses help page
# (leapoi_help_pages.py).
POINTER = "How boons and curses work: Land Encounters, Boons and Curses, in the help pages."

# Notice sections shared by several events: a lifted curse, and a faction-wide effect.
CURSE_GONE = ("What changed", ["The curse is gone for good, with every level it had gained."])
FACTION_WIDE = ("Faction-wide", ["It touches the whole faction, not one lord, and takes no lord's slot.",
                                 "It lasts {realm_turns} turns, then passes."])

# Clock name (configs/boons.lua `clock_counts` keys and `fixed_clocks`) -> (text, text when the count is 1). The clock is the countdown a boon's
# or curse's bundle shows in the army's effects, with "%n" its count. A fixed clock has no count.
CLOCKS: Dict[str, Tuple[str, Optional[str]]] = {
    "lasts": ("Lasts %n more battles.", "Lasts 1 more battle."),
    "upgrades": ("Upgrades in %n won battles.", "Upgrades in 1 won battle."),
    "worsens": ("Worsens in %n turns.", "Worsens in 1 turn."),
    "becomes": ("Becomes a boon in %n turns.", "Becomes a boon in 1 turn."),
    "strongest": ("At its strongest, and lasts for good.", None),
    "worst": ("At its worst, and lasts until lifted.", None),
}

# Icon, priority and scope of the clock effects, as vanilla dummy effects on lord bundles have them. Priority 0 hides an effect.
CLOCK_ICON, CLOCK_PRIORITY, CLOCK_SCOPE = "turns.png", 1, "character_to_character_own"

# Event -> (incident title, description parts, picture). A part is a paragraph or a (heading, lines) section. `incidents` adds `POINTER`. "{lord}" is the lord's name, read from
# the config's `lord_context`.
INCIDENTS: Dict[str, Tuple[str, list, str]] = {
    "boon_gained": ("A Boon Is Won", [
        "Something has changed in {lord}'s army, and for the better. Every warrior can feel it.",
        "Blades strike truer and shields hold firmer, and the soldiers march with their heads high. Whatever touched them on the field has stayed, and "
        "every victory will make it stronger.",
        ("What it means", ["The boon is listed with the lord's traits, and an icon in the army's effects counts the battles to its next level.",
                          "It stays until the lord falls, leaves the faction, or gives it up for another."])],
        "ursun_claimed"),
    "boon_grew": ("The Boon Grows", [
        "Another victory, and {lord}'s army has grown stronger for it.",
        "The veterans tell the story of the battle around the fires, and each telling makes the blessing on them burn brighter. The recruits listen, "
        "and believe.",
        ("What changed", ["The boon rose one level, and its effects grow with it.",
                         "Its count of won battles starts again toward the next level."])],
        "victory"),
    "boon_lost": ("A Boon Fades", [
        "Whatever gave {lord}'s army its edge is gone now.",
        "The soldiers still fight, but something has gone out of them. They remember how it felt, and they want it back.",
        ("Why boons fade", ["A charged boon fades after its last battle.",
                           "A boon given up to make room for a new one is gone for good, with every level it gained."])],
        "attrition_mountain"),
    "curse_gained": ("A Curse Takes Hold", [
        "A shadow has fallen over {lord}'s army, and it will not lift on its own.",
        "The soldiers mutter at night and look over their shoulders on the march. Something followed them from the field, and it is patient.",
        ("What it means", ["The curse is listed with the lord's traits, and an icon in the army's effects counts the turns until it worsens.",
                          "It stays until it is lifted, or until the lord falls or leaves the faction."])],
        "ai_wins_soul"),
    "curse_worse": ("The Curse Deepens", [
        "The curse on {lord}'s army grows heavier with every passing day.",
        "Fewer soldiers laugh at the fires now, and the sick lists grow longer. Whatever festers in the ranks has dug its roots in deeper, and it will "
        "not wait forever.",
        ("What changed", ["The curse sank one level, and its effects grow with it.",
                         "Its clock starts again toward the next level."])],
        "attrition_vampire_territory"),
    "curse_lifted": ("A Curse Is Lifted", [
        "The weight on {lord}'s army is gone at last.",
        "The soldiers sleep through the night for the first time in weeks, and the camp is loud with songs again.",
        CURSE_GONE],
        "rift_entered"),
    "curse_shifted": ("The Gamble Fails", [
        "The hedge-witch's bones fell badly. The curse on {lord}'s army has not lifted. It has become something else.",
        ("What changed", ["The gamble failed. The new curse keeps the old one's level.",
                         "Its clock starts again, so it worsens {turns} turns from now.",
                         "A lord who gambles must wait {cooldown} turns to gamble at that Tavern again."])],
        "chaos_doom_tide"),
    "gamble_won": ("The Gamble Pays Off", [
        "The hedge-witch's bones fell well. The curse on {lord}'s army is gone, for a fraction of the usual price.",
        ("The gamble", ["It paid off. The curse is gone for good, with every level it had gained.",
                       "A lord who gambles must wait {cooldown} turns to gamble at that Tavern again."])],
        "winds_of_magic_change"),
    "curse_cleansed": ("Cleansed by the Hedge-Witch", [
        "Bitter smoke, a muttered word and a pinch of grave dust, and the curse on {lord}'s army is gone.",
        "The witch pockets the coin without a word and turns back to the pot. The soldiers do not look back as they leave.",
        CURSE_GONE],
        "rift_entered"),
    "curse_broken": ("The Curse Is Broken", [
        "Hammer and fire have done what prayer could not. The curse on {lord}'s army is broken.",
        "The smith quenches the last blade and holds it to the light. Whatever clung to the steel is gone, and the ring of the metal is clean again.",
        CURSE_GONE],
        "rift_entered"),
    "boon_tempered": ("Tempered at the Forge", [
        "The master smith has worked the blessing on {lord}'s army into the steel itself. It burns brighter now.",
        "Every blade has been folded again, every rivet set anew. The soldiers test their edges and grin.",
        ("What changed", ["The boon rose one level, and its effects grow with it."])],
        "army_morale_up"),
    "boon_fed": ("Fed by the Hedge-Witch", [
        "The hedge-witch burned a lock of {lord}'s hair with bitter herbs. The blessing on the army drank it in and grew.",
        ("What changed", ["The witch's feeding pushed the boon over the edge. It rose one level.",
                         "Its count of won battles starts again from nothing."])],
        "army_morale_up"),
    "boon_rewoven": ("The Weave Holds", [
        "The hedge-witch pulled the threads of {lord}'s blessing apart and wove them tighter. It held.",
        ("What changed", ["The boon rose one level.",
                         "A lord who reweaves must wait {service_cooldown} turns to use that service at that Tavern again."])],
        "winds_of_magic_change"),
    "boon_shifted": ("The Weave Shifts", [
        "The hedge-witch's threads slipped. The blessing on {lord}'s army is still there, but it is not the one it was.",
        ("What changed", ["The reweave failed. The new boon keeps the old one's level.",
                         "Its count of won battles starts again from nothing.",
                         "A lord who reweaves must wait {service_cooldown} turns to use that service at that Tavern again."])],
        "chaos_doom_tide"),
    "blood_rite": ("A Blood Rite", [
        "The hedge-witch asked for no gold, only blood. {lord}'s soldiers gave it, and the curse washed out with it.",
        ("What it cost", ["The army bled {blood}% of its strength for each level the curse had.",
                         "A lord who works a blood rite must wait {service_cooldown} turns to work another at that Tavern."]),
        CURSE_GONE],
        "rift_entered"),
    "rust_struck": ("Rust for Iron", [
        "The smith's bargain is struck. {lord}'s army is harder to wound now, but rust has crept into its blades.",
        "The armour sits heavy and sure on every shoulder. The edges, though, dull a little more each day.",
        ("The pact", ["The boon and the curse came together.",
                     "The boon grows with victories, and the curse worsens with time, like any other."])],
        "carnage_weapons"),
    "curse_turned": ("The Curse Turns", [
        "{lord}'s army has carried its curse so long that it has become something else.",
        "What once gnawed at the soldiers now hardens them. They have learned to live with the thing, and then to use it.",
        ("What it became", ["The curse is gone, and its boon takes its place at level 1.",
                           "If this lord has no room for it, another boon must be given up to keep it."])],
        "sword_of_khaine"),
    "realm_boon": ("A Blessing on the Realm", [
        "Good fortune has settled over the whole realm, though it will not last forever.",
        "Harvests come in early, roads stay dry and the coffers fill faster than the clerks can count. The priests call it a sign. The generals call it"
        " a chance.",
        FACTION_WIDE],
        "winds_of_magic_change"),
    "realm_curse": ("A Curse on the Realm", [
        "A darkness has fallen over the whole realm. It will pass, in time.",
        "Wells sour, messengers go missing and the omens are poor wherever the priests look. The people wait for it to end.",
        FACTION_WIDE],
        "chaos_doom_tide"),
}

# Display order of the full-slots dilemma's first choice in cdir_events_dilemma_choices. The others follow it, the new boon's last.
FULL_CHOICE_ORDER = 1100

# Display order of the pick dilemma's first choice in cdir_events_dilemma_choices.
PICK_CHOICE_ORDER = 1110

# The pick dilemma: (title, description parts, picture, label of each choice).
PICK_DILEMMA = ("Spoils of the Champion", ["The champion has fallen, and something of its power can be claimed. Choose one boon for {lord}.",
                                           ("The boons on offer", ["Each starts at level 1. The ones not chosen are lost.",
                                                                   "If {lord} has no free slot, another boon must be given up to take it."]),
                                           BOON_GROWTH_SHORT], "sword_of_khaine", "Claim This Boon")

# The full-slots dilemma: (title, description parts, picture, label of a slot's choice, label of the new boon's choice).
FULL_DILEMMA = ("Too Many Blessings", ["{lord} can carry no more boons. To take the new one, another must be given up.",
                                       ("What giving one up costs", ["A boon given up is gone for good, with every level it has gained.",
                                                                     "The new boon is on the last choice. Refusing it keeps every boon as it is."]),
                                       BOON_GROWTH_SHORT], "nemesis_crown", "Give This Up", "Refuse the New Boon")

# The Smithy's Temper and Break room: (title, description parts, picture, choice labels by kind).
SMITHY_ROOM = ("Temper and Break", ["The master smith clears the anvil for {lord}. Steel can be tempered here, and old curses beaten out of it.",
                                    ("What the forge offers", ["Temper a boon: it rises one level. The price grows with the level it reaches.",
                                                               "Break a curse: it is gone for good. The price grows with the curse's level.",
                                                               "Rust for Iron: a pact that hardens the army's hide and rusts its blades."]),
                                    ("Prices", ["As the owner, we pay {owner_off}% less than the smith's usual rates. The room never cools down."])],
               "story_panels/chd_drill_blades", {"temper": "Temper This Boon", "break": "Break This Curse", "rust": "Trade Rust for Iron", "back": "Back"})

# The Tavern's hedge-witch: (title, description parts, picture, choice labels by kind).
WITCH_ROOM = ("The Hedge-Witch", ["Behind a curtain of dried herbs, the hedge-witch looks {lord} over and smiles. Each service waits "
                                  "{service_cooldown} turns after use, and the owner pays {owner_off}% less.",
                                  ("Boons", ["Feed: {feed_wins} more won battles toward its next level.",
                                             "Reweave: {rise}% it rises a level, or it becomes another boon."]),
                                  ("Curses", ["Cleanse: it lifts for good.", "Gamble: cheaper, but lifts {lift}% of the time, or becomes another curse.",
                                              "Blood rite: lifts for no gold, but the army bleeds {blood}% per level."])],
              "story_panels/chd_drill_machinations", {"feed": "Feed This Boon", "reweave": "Reweave This Boon", "cleanse": "Cleanse This Curse",
                                                      "gamble": "Gamble on This Curse", "blood": "Work a Blood Rite", "back": "Back"})

# The services' result lines, which a reopened room shows at the top: service -> text. "{old}" and "{new}" are the boon or curse names before
# and after, filled in by features/boon_services.lua.
RESULTS = {
    "temper": "[[col:green]]Tempered:[[/col]] {old} is now {new}.",
    "break": "[[col:green]]Broken:[[/col]] {old} is gone.",
    "cleanse": "[[col:green]]Cleansed:[[/col]] {old} is gone.",
    "gamble_won": "[[col:green]]The gamble paid off:[[/col]] {old} is gone.",
    "gamble_lost": "[[col:red]]The gamble failed:[[/col]] {old} has become {new}.",
    "rust": "[[col:yellow]]The pact is struck:[[/col]] {new}, at the cost of {old}.",
    "feed": "[[col:green]]Fed:[[/col]] {old} draws closer to its next level.",
    "feed_raised": "[[col:green]]Fed:[[/col]] {old} is now {new}.",
    "reweave_won": "[[col:green]]The weave held:[[/col]] {old} is now {new}.",
    "reweave_lost": "[[col:yellow]]The weave shifted:[[/col]] {old} has become {new}.",
    "reweave_held": "[[col:yellow]]The weave slipped, but nothing changed:[[/col]] {old} stays as it was.",
    "blood": "[[col:green]]Lifted in blood:[[/col]] {old} is gone.",
}

# Labels of the choices that open the rooms, on the forge and the hub.
ROOM_LABELS = {"smithy_room": SMITHY_ROOM[0], "witch_room": "Visit the Hedge-Witch"}

# Display orders of the room choices in cdir_events_dilemma_choices: the forge's room choice sits after the donation (6) and before Leave
# (998), the hub's after the donation (5) and before Leave (998). Inside the rooms, temper then break then Rust for Iron then Leave, and
# each curse's cleanse with its gamble.
ROOM_OPEN_ORDER = {"smithy_room": 7, "witch_room": 6}
TEMPER_ORDER, BREAK_ORDER, RUST_ORDER, SMITHY_BACK_ORDER = 1120, 1125, 1130, 1131
FEED_ORDER, CLEANSE_ORDER, WITCH_BACK_ORDER = 1100, 1140, 1160

# Icon of the services' lines, other than the Smithy room's.
SERVICE_ICON = "fractured_mind.png"

# The services' payload lines: name -> (icon, text). "{lift}" is the gamble's lift chance.
SERVICE_LINES = {
    "smithy_room": ("icon_effects_army.png", "Visit the master smith to [[col:green]]temper a boon[[/col]] or [[col:green]]break a curse[[/col]], each "
                    "paid from our treasury."),
    "witch_room": (SERVICE_ICON, "Seek out the hedge-witch in the back room, who can [[col:green]]feed or reweave a boon[[/col]], and "
                   "[[col:green]]lift a curse[[/col]] for gold, a gamble or blood."),
    "witch_nothing": (SERVICE_ICON, "[[col:red]]This lord carries no boon or curse for the hedge-witch to work on.[[/col]]"),
    "top": (SERVICE_ICON, "[[col:red]]Already at its highest level.[[/col]]"),
    "charged": (SERVICE_ICON, "[[col:red]]A charged boon cannot be tempered.[[/col]]"),
    "gamble": (SERVICE_ICON, "[[col:yellow]]{lift}% of the time the curse lifts. Otherwise it becomes another curse of the same level, which "
               "starts worsening again.[[/col]]"),
    "feed": (SERVICE_ICON, "[[col:green]]+{feed_wins} won battles[[/col]] toward this boon's next level."),
    "reweave": (SERVICE_ICON, "[[col:yellow]]{rise}% of the time the boon rises a level. Otherwise it becomes another boon of the same "
                "level.[[/col]]"),
}

# What each hedge-witch service's cooldown line says the witch will not do again: service -> words.
COOLING_WORDS = {"cleanse": "cleanse a curse for", "gamble": "gamble with", "feed": "feed a boon for", "reweave": "reweave a boon for", "blood": "work a blood rite for"}

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
    "stone_rampart": ("Stone Rampart", "Attackers break on this army like waves upon the rocks.", "armour_character.png", ramp(
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
    "quartermaster": ("Quartermaster's Ledger", "A careful hand keeps the army fed for less.", "variable_upkeep.png", ramp(
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
    "bane": ("Bane of {race}", "The lord has learned exactly how to make this enemy hurt the most.", "weapon_damage.png", []),
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
    "haunted": ("Haunted", "The dead follow this army at night. The soldiers are unsettled by them.", "dlc10_death_night.png", ramp(
        ["-3 leadership", "-6 leadership", "-9 leadership", "-12 leadership", "-15 leadership"], (LEAD, F, [-3, -6, -9, -12, -15]))),
    "creeping_rust": ("Creeping Rust", "No amount of oil is enough to keep the rust off this army's blades.", "weapon_damage.png", ramp(
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
    "withered_supply": ("Withered Supply", "The food in the supply has spoiled, and wounds seem to fester and are slower to heal.", "phase_posion.png", ramp(
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
    "brittle_bones": ("Brittle Bones", "The men are physically weakened. They have lost muscle, and their bones have grown creaky.", "resistance_physical.png", ramp(
        ["-3 armour", "-6 armour", "-9 armour", "-12 armour", "-15 armour"], (ARMOUR, F, [-3, -6, -9, -12, -15]))),
    "shaky_aim": ("Shaky Aim", "With shaky hands, ranged attacks drift wide.", "ammo.png", ramp(
        ["-5% missile strength", "-10% missile strength", "-15% missile strength", "-20% missile strength", "-25% missile strength"],
        (MISSILE, F, [-5, -10, -15, -20, -25]))),
    "grudge": ("Grudge of {race}", "This enemy has sworn to remember the lord's name.", "discouraged.png", []),
    "glass_jaw": ("Glass Jaw", "The lord took a blow to the head that never quite healed right.", "casualties.png", ramp(
        ["Lord: -5 armour", "Lord: -10 armour", "Lord: -15 armour, -5 melee attack", "Lord: -20 armour, -5 melee attack", "Lord: -25 armour, -10 melee attack"],
        (LORD_ARMOUR, C, [-5, -10, -15, -20, -25]), (LORD_MA, C, [N, N, -5, -5, -10]))),
    "stumbling_charge": ("Stumbling Charge", "Charges lose their nerve a few paces from the enemy.", "charge.png", ramp(
        ["-5% charge bonus", "-10% charge bonus", "-15% charge bonus", "-20% charge bonus", "-25% charge bonus"], (CHARGE, F, [-5, -10, -15, -20, -25]))),
    "cursed_coin": ("Cursed Coin", "Recruits want extra pay before they will march under this lord.", "casualties.png", ramp(
        ["+5% recruitment cost", "+10% recruitment cost", "+15% recruitment cost", "+20% recruitment cost", "+25% recruitment cost"],
        (RECRUIT, F, [5, 10, 15, 20, 25]))),
}

# Faction-wide key -> (name, flavour, icon, text, [(effect, scope, value)]).
REALM: Dict[str, Tuple[str, str, str, str, List[Tuple[str, str, float]]]] = {
    "comet_sign": ("Sign of the Twin-Tailed Comet", "A comet hangs over the realm, and the Winds swell under it.", "attribute_mastery_of_elemental_winds.png",
                   "Every army: +5 Winds of Magic reserve per turn", [("wh3_main_effect_winds_of_magic_events", "faction_to_force_own", 5)]),
    "old_ones_favour": ("Favour of the Old Ones", "Scholars across the realm wake with ideas they did not have before.", "lileaths_blessing.png",
                        "+15% research rate", [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", 15)]),
    "golden_age": ("Golden Age", "Trade flows and the harvests are rich.", "trade_agreement.png", "+10% income from all buildings, +10 public order",
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
        grant: The offer's `boon` or `curse` field as dumped: [key, level], or { "from": source } for a random one. A race boon (Bane) is named
            for the enemy race.

    Returns:
        str: The text.
    """
    colour = "green" if kind == "boon" else "red"
    if isinstance(grant, dict):
        level = grant.get("level", 1)
        return f"[[col:{colour}]]a random {f'level {level} ' if level > 1 else ''}{kind}[[/col]]"
    key, level = grant[0], grant[1] if len(grant) > 1 else 1
    name, _, _, levels = (BOONS if kind == "boon" else CURSES)[key]
    if not levels:
        return f"[[col:{colour}]]{name.format(race='the enemy race')} {ROMAN[level]}[[/col]]"
    return f"[[col:{colour}]]{level_title(name, levels, level)} ({levels[level - 1][0]})[[/col]]"


def offer_texts(offers: List[Dict], pay: str) -> Tuple[Dict[str, Tuple[str, str]], Dict[str, str]]:
    """The name, line and icon of every offer that grants a boon or curse, other than a composed tower offer, whose text says more.

    Args:
        offers (List[Dict]): Offer records from the Lua dump.
        pay (str): The paid line's opening, with a {cost} placeholder, ending where the action follows.

    Returns:
        Tuple: (offer key -> (name, line), offer key -> icon).
    """
    texts, icons = {}, {}
    for offer in offers:
        if not grants(offer) or offer.get("compose") or offer["key"] not in OFFERS:
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


def variants(kind: str, config: Dict) -> List[Tuple[str, str, str, str, List[Level], Dict]]:
    """Every boon or curse as it is bundled: one variant per race for a rolled one.

    Args:
        kind (str): "boon" or "curse".
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple]: (bundle stem without level, name, flavour, icon, levels, config record) per variant.
    """
    catalogue = BOONS if kind == "boon" else CURSES
    out = []
    for record in config["boons" if kind == "boon" else "curses"]:
        key = record["key"]
        name, flavour, icon, levels = catalogue[key]
        if record.get("race"):
            for race in config["races"]:
                out.append((f"{key}_{race}", name.format(race=library.RACES[race][0]), flavour, icon, race_levels(key, race), record))
        else:
            out.append((key, name, flavour, icon, levels, record))
    return out


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rows


def clock_states(kind: str, record: Dict, config: Dict, level: int) -> List[Tuple[str, Optional[int]]]:
    """Every clock a boon or curse can show at a level, with each count it can reach.

    Args:
        kind (str): "boon" or "curse".
        record (Dict): The boon or curse record from the config.
        config (Dict): The boons config from the Lua dump.
        level (int): The level.

    Returns:
        List[Tuple[str, Optional[int]]]: (clock name, count, or None for a fixed clock).
    """
    counts = config["clock_counts"]
    if record.get("charges"):
        name = "lasts"
    elif level < config["max_level"]:
        name = "upgrades" if kind == "boon" else "worsens"
    elif kind == "boon":
        return [("strongest", None)]
    elif record.get("turns_into"):
        name = "becomes"
    else:
        return [("worst", None)]
    return [(name, n) for n in range(1, counts[name] + 1)]


def clocks(config: Dict) -> List[Tuple[str, str]]:
    """The clock effects, one per fixed clock and two per counted clock (its count, and 1).

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple[str, str]]: (effect key, text) per clock effect.
    """
    out = []
    for name, (text, one) in CLOCKS.items():
        out.append((config["clock_prefix"] + name, f"[[col:yellow]]{text}[[/col]]"))
        if one:
            out.append((config["clock_prefix"] + name + "_one", f"[[col:yellow]]{one}[[/col]]"))
    return out


def bundles(config: Dict) -> Dict[str, Tuple]:
    """Every boon and curse countdown bundle per level, naming the level's effects with its clock as its only effect, and every faction-wide bundle,
    which the game counts down.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple]: Bundle key -> (target, icon, title, description, [(effect, scope, value)]).
    """
    shaped = {}
    for kind in ("boon", "curse"):
        colour = "green" if kind == "boon" else "red"
        for stem, name, flavour, icon, levels, record in variants(kind, config):
            for number, (text, _) in enumerate(levels, 1):
                shown = f"{flavour}{BREAK}[[col:{colour}]]{text}[[/col]]"
                for clock, count in clock_states(kind, record, config, number):
                    effect = config["clock_prefix"] + clock + ("_one" if count == 1 else "")
                    key = f"{config['bundle_prefix'][kind]}{stem}_{number}_{clock}" + (f"_{count}" if count else "")
                    shaped[key] = ("character", icon, level_title(name, levels, number), shown, [(effect, CLOCK_SCOPE, count or 1)])
    for key, (name, flavour, icon, _, effects) in REALM.items():
        shaped[config["realm_prefix"] + key] = ("faction", icon, name, flavour, effects)
    return shaped


def traits(config: Dict) -> Dict[str, Tuple]:
    """Every boon and curse as a trait whose levels carry its effects, in the generator's trait shape.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple]: Trait key -> (icon, [(points, name, flavour, rule, [(effect, scope, value)])]). A level's points are its number, so the
        script sets a level by adding that many points.
    """
    shaped = {}
    for kind in ("boon", "curse"):
        for stem, name, flavour, _, levels, record in variants(kind, config):
            if record.get("charges"):
                rule = f"Lasts {record['charges']} battles, then fades."
            elif kind == "boon":
                rule = f"Grows a level for every {config['wins_per_level']} won battles, up to level {config['max_level']}."
            else:
                rule = f"Worsens a level every {config['turns_per_level']} turns, up to level {config['max_level']}."
                if record.get("turns_into"):
                    rule += f" After {config['turns_to_turn']} turns at its worst, it becomes {BOONS[record['turns_into']][0].replace('{race}', 'the same race')}."
            shaped[config["trait_prefix"][kind] + stem] = ("trait_good" if kind == "boon" else "trait_bad",
                                                           [(number, level_title(name, levels, number), flavour, rule, effects)
                                                            for number, (_, effects) in enumerate(levels, 1)])
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
        for stem, name, _, icon, levels, _ in variants(kind, config):
            for number, (text, _) in enumerate(levels, 1):
                level = "" if len(levels) == 1 else f" (level {number} of {len(levels)})"
                out.append((f"{config['line_prefix']}{kind}_{stem}_{number}", icon, f"[[col:{colour}]]{name}{level}: {text}[[/col]]"))
    good = {r["key"]: r.get("good") for r in config["realm"]}
    for key, (name, _, icon, text, _) in REALM.items():
        out.append((f"{config['line_prefix']}realm_{key}", icon, f"[[col:{'green' if good[key] else 'red'}]]{name}: {text}, for {config['realm_turns']} turns[[/col]]"))
    return out


def describe(parts: list, config: Dict, event: str) -> str:
    """Writes a description from its parts, with the rules and the lord's name filled in.

    Args:
        parts (list): Paragraphs and (heading, bullet lines) rule sections.
        config (Dict): The boons config from the Lua dump.
        event (str): The event type whose context holds the lord's name, "Incident" or "Dilemma".

    Returns:
        str: The description as loc text.
    """
    lord = f'[[col:yellow]]{{{{CcoCampaignEvent{event}:ScriptObjectContext("{config["lord_context"]}").StringValue}}}}[[/col]]'
    witch = config["witch_room"]
    values = {"lord": lord, "wins": config["wins_per_level"], "max": config["max_level"], "turns": config["turns_per_level"],
              "realm_turns": config["realm_turns"], "lift": witch["gamble_lift_chance"],
              "cooldown": witch["cooldowns"]["gamble"], "owner_off": round((1 - config["owner_price_share"]) * 100), "feed_wins": witch["feed_wins"],
              "rise": witch["reweave_rise_chance"], "blood": witch["blood_bleed"], "service_cooldown": max(witch["cooldowns"].values())}
    shown = [part if isinstance(part, str) else f"[[col:yellow]]{part[0]}[[/col]]" + "".join(NL + "- " + line for line in part[1]) for part in parts]
    return BREAK.join(shown).format_map(values)


def shown_lines(description: str) -> int:
    """Roughly how many lines a description fills in the notification panel.

    Args:
        description (str): The loc text.

    Returns:
        int: The line count.
    """
    plain = re.sub(r"\[\[/?(?:url|tooltip|img)[^\]]*\]\]", "", description)
    plain = re.sub(r"\[\[/?col[^\]]*\]\]|\{\{[^}]*\}\}", "Lordname", plain)
    return sum(max(1, -(-len(line) // LINE_CHARS)) for line in plain.split(NL))


def incidents(config: Dict) -> Dict[str, Tuple[str, str, str]]:
    """The incidents with their rules and the lord's name filled into their descriptions.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple[str, str, str]]: Event -> (title, description, picture).
    """
    return {event: (title, describe(parts + [POINTER], config, "Incident"), image) for event, (title, parts, image) in INCIDENTS.items()}


def dilemmas(config: Dict) -> Dict[str, Tuple[str, str, str]]:
    """The full-slots, pick and service room dilemmas with their rules and the lord's name filled into their descriptions.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        Dict[str, Tuple[str, str, str]]: "full", "pick", "smithy" and "witch" -> (title, description, picture).
    """
    named = (("full", FULL_DILEMMA), ("pick", PICK_DILEMMA), ("smithy", SMITHY_ROOM), ("witch", WITCH_ROOM))
    result = f'{{{{CcoCampaignEventDilemma:ScriptObjectContext("{config["result_context"]}").StringValue}}}}'
    return {name: ((dilemma[0], (result if name in ("smithy", "witch") else "") + describe(dilemma[1], config, "Dilemma"), dilemma[2]))
            for name, dilemma in named}


def results(config: Dict) -> List[Tuple[str, str]]:
    """The services' result lines.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple[str, str]]: (loc key, text).
    """
    return [("campaign_localised_strings_string_" + config["result_prefix"] + name, text) for name, text in RESULTS.items()]


def service_choices(config: Dict) -> List[Tuple[str, int, List[Tuple[str, str]]]]:
    """Every choice of the service rooms and the choices that open them.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple[str, int, List[Tuple[str, str]]]]: (choice key, display order, [(dilemma, label)]).
    """
    smithy, witch = config["smithy_room"], config["witch_room"]
    labels, witch_labels = SMITHY_ROOM[3], WITCH_ROOM[3]
    out = [(room["open_choice"], ROOM_OPEN_ORDER[name], [(dilemma, ROOM_LABELS[name]) for dilemma in room["opened_from"]])
           for name, room in (("smithy_room", smithy), ("witch_room", witch))]
    out += [(choice, TEMPER_ORDER + i, [(smithy["dilemma"], labels["temper"])]) for i, choice in enumerate(smithy["temper_choices"])]
    out += [(choice, BREAK_ORDER + i, [(smithy["dilemma"], labels["break"])]) for i, choice in enumerate(smithy["break_choices"])]
    out += [(smithy["rust_choice"], RUST_ORDER, [(smithy["dilemma"], labels["rust"])]),
            (smithy["back_choice"], SMITHY_BACK_ORDER, [(smithy["dilemma"], labels["back"])])]
    for i, (feed, reweave) in enumerate(zip(witch["feed_choices"], witch["reweave_choices"])):
        out += [(feed, FEED_ORDER + 2 * i, [(witch["dilemma"], witch_labels["feed"])]),
                (reweave, FEED_ORDER + 2 * i + 1, [(witch["dilemma"], witch_labels["reweave"])])]
    for i, (cleanse, gamble, blood) in enumerate(zip(witch["cleanse_choices"], witch["gamble_choices"], witch["blood_choices"])):
        out += [(cleanse, CLEANSE_ORDER + 3 * i, [(witch["dilemma"], witch_labels["cleanse"])]),
                (gamble, CLEANSE_ORDER + 3 * i + 1, [(witch["dilemma"], witch_labels["gamble"])]),
                (blood, CLEANSE_ORDER + 3 * i + 2, [(witch["dilemma"], witch_labels["blood"])])]
    out.append((witch["back_choice"], WITCH_BACK_ORDER, [(witch["dilemma"], witch_labels["back"])]))
    return out


def room_choices(config: Dict, room: str) -> List[str]:
    """The choices of one service room, in display order (`service_choices` lists each room's choices in that order).

    Args:
        config (Dict): The boons config from the Lua dump.
        room (str): "smithy_room" or "witch_room".

    Returns:
        List[str]: The choice keys.
    """
    dilemma = config[room]["dilemma"]
    return [choice for choice, _, shown in service_choices(config) if shown[0][0] == dilemma]


def service_lines(config: Dict) -> List[Tuple[str, str, str]]:
    """The payload lines of the services: the room choices, the reasons a service is closed, the gamble's odds and its cooldown.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[Tuple[str, str, str]]: (payload key, icon, text).
    """
    witch, prefix = config["witch_room"], config["service_line_prefix"]
    values = {"lift": witch["gamble_lift_chance"], "feed_wins": witch["feed_wins"], "rise": witch["reweave_rise_chance"]}
    out = [(prefix + name, icon, text.format(**values)) for name, (icon, text) in SERVICE_LINES.items()]
    for level in range(1, config["max_level"] + 1):
        out.append((f"{prefix}blood_{level}", SERVICE_ICON, f"[[col:red]]The army bleeds {witch['blood_bleed'] * level}% of its strength[[/col]] to lift "
                    "this curse, but pays no gold."))
    for kind, words in COOLING_WORDS.items():
        for turns in range(1, witch["cooldowns"][kind] + 1):
            out.append((f"{prefix}{kind}_cooling_{turns}", SERVICE_ICON,
                        f"[[col:red]]The hedge-witch will not {words} this lord again for {turns} turn{'s' if turns > 1 else ''}.[[/col]]"))
    return out


def guide(config: Dict, offers: List[Dict], tower_offers: List[Dict], names: Optional[Dict[str, str]] = None) -> List[Tuple[str, str, str, str]]:
    """The MCT guide line of every boon, curse and faction-wide effect: what its first and last levels do and where a lord gets it.

    Args:
        config (Dict): The boons config from the Lua dump.
        offers (List[Dict]): The spot offers from the Lua dump.
        tower_offers (List[Dict]): The tower offers from the Lua dump.
        names (Optional[Dict[str, str]]): Names of offers granting a boon or curse that `OFFERS` does not name, e.g. the composed tower offers
            and the spot offers with their own text.

    Returns:
        List[Tuple[str, str, str, str]]: (kind, key, loc key, text), boons then curses then faction-wide effects, in config order.
    """
    found: Dict[Tuple[str, str], List[str]] = {}

    def source(kind: str, key: str, text: str) -> None:
        found.setdefault((kind, key), []).append(text)

    drop_text = {("boon", "battle"): "a hard or modified LEAPOI win", ("curse", "battle"): "a lost LEAPOI battle",
                 ("boon", "treasure"): "Claim the Cursed Relic at treasure sites", ("curse", "treasure"): "Claim the Cursed Relic at treasure sites",
                 ("boon", "tower"): "the spoils of a fallen Tower champion",
                 ("boon", "tavern"): f"a finished Tavern quest chain (level {config['chain_boon_level']})",
                 ("curse", "tavern"): "a failed or dropped Tavern contract",
                 ("boon", "smithy"): "the Smith's Blessing at a Smithy's Work Orders",
                 ("curse", "smithy"): "a Cursed Masterwork from a Smithy's Work Orders (two at level 3)"}
    for kind, records in (("boon", config["boons"]), ("curse", config["curses"])):
        for record in records:
            for drop in record.get("drops", []):
                source(kind, record["key"], drop_text[(kind, drop)])
    named = {**OFFERS, **(names or {})}
    places: Dict[str, List[str]] = {}
    for offer in offers:
        if grants(offer) and not isinstance(offer.get("boon"), dict):
            places.setdefault(offer["key"], []).append({"tavern": "the Tavern bar", "pre_battle": "battle spots", "spoils": "battle spoils",
                                                        "mission": "battle spot missions"}.get(offer.get("pool"), "treasure sites"))
    for offer in tower_offers:
        if grants(offer):
            places.setdefault(offer["key"], []).append("the Tower")
    places.setdefault(config["smithy_room"]["rust_offer"], []).append("the Smithy")
    for offer in offers + tower_offers:
        if offer["key"] not in places:
            continue
        for kind in ("boon", "curse"):
            grant = offer.get(kind)
            if isinstance(grant, list):
                level = f", level {grant[1]}" if grant[1] > 1 else ""
                text = f"{named[offer['key']]} ({' and '.join(dict.fromkeys(places[offer['key']]))}{level})"
                if text not in found.get((kind, grant[0]), []):
                    source(kind, grant[0], text)
    lingering: Dict[Tuple[str, str], List[str]] = {}
    for modifier, (kind, key) in config["lingers"].items():
        lingering.setdefault((kind, key), []).append(battle_modifiers.MODIFIERS[modifier][0])
    for (kind, key), names in lingering.items():
        source(kind, key, " or ".join(sorted(names)) + " lingering after a fight")
    for record in config["curses"]:
        if record.get("turns_into"):
            name = CURSES[record["key"]][0].replace("{race}", "the same race")
            source("boon", record["turns_into"], f"{name} after {config['turns_to_turn']} turns at level {config['max_level']}")
    source("boon", "bane", "a finished Tavern bounty, against the hunted race")
    chance = config["champion_realm_chance"]
    for key in config["blessings"]:
        source("realm", key, f"a fallen Tower champion ({chance}% chance, in place of its boons)")
    for key in config["realm_curses"]:
        source("realm", key, f"losing to a Tower champion ({chance}% chance)")

    def effects(levels: List[Level]) -> str:
        if len(levels) == 1:
            return levels[0][0] + "."
        return f"Level 1: {levels[0][0]}. Level {len(levels)}: {levels[-1][0]}."

    out = []
    for kind, catalogue, records in (("boon", BOONS, config["boons"]), ("curse", CURSES, config["curses"])):
        for record in records:
            name, _, _, levels = catalogue[record["key"]]
            if record.get("race"):
                name = name.replace("{race}", "a Race")
                levels = [(text.replace(library.RACES[config["races"][0]][0], "that race"), fx)
                          for text, fx in race_levels(record["key"], config["races"][0])]
            text = f"[[col:yellow]]{name}[[/col]]: {effects(levels)}"
            if record.get("race"):
                text += " The race is rolled when it is gained."
            if record.get("turns_into"):
                text += f" Turns into {BOONS[record['turns_into']][0].replace('{race}', 'the same race')} after {config['turns_to_turn']} turns at level {config['max_level']}."
            sources = found.get((kind, record["key"]), [])
            text += " [[col:yellow]]From:[[/col]] " + ("; ".join(sources) if sources else "nothing yet") + "."
            out.append((kind, record["key"], "campaign_localised_strings_string_" + config["guide_prefix"] + kind + "_" + record["key"], text))
    good = {r["key"]: r.get("good") for r in config["realm"]}
    for record in config["realm"]:
        name, _, _, text, _ = REALM[record["key"]]
        sources = found.get(("realm", record["key"]), [])
        line = (f"[[col:yellow]]{name}[[/col]] ({'blessing' if good[record['key']] else 'curse'}, {config['realm_turns']} turns): {text}. "
                f"[[col:yellow]]From:[[/col]] {'; '.join(sources) if sources else 'nothing yet'}.")
        out.append(("realm", record["key"], "campaign_localised_strings_string_" + config["guide_prefix"] + "realm_" + record["key"], line))
    return out


def owned_prefixes(config: Dict) -> List[str]:
    """Every key prefix of the rows this catalogue writes, so the generator replaces them on each run.

    Args:
        config (Dict): The boons config from the Lua dump.

    Returns:
        List[str]: The prefixes.
    """
    return (list(config["bundle_prefix"].values()) + list(config["trait_prefix"].values())
            + [config["realm_prefix"], config["full_dilemma"], config["full_new_choice"], config["pick_dilemma"], config["smithy_room"]["dilemma"],
               config["witch_room"]["dilemma"], config["result_prefix"], config["guide_prefix"], config["clock_prefix"]]
            + config["pick_choices"]
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
    counted = config["clock_counts"]
    found += [f"clock {name} differs" for name in sorted((set(counted) | set(config["fixed_clocks"])) ^ set(CLOCKS))]
    found += [f"clock {name} should {'' if name in counted else 'not '}have a count" for name, (text, one) in CLOCKS.items()
              if (one is not None) != (name in counted) or ("%n" in text) != (one is not None)]
    found += [f"faction-wide {key} differs" for key in sorted({r["key"] for r in config["realm"]} ^ set(REALM))]
    texts = {**incidents(config), **{"dilemma " + name: text for name, text in dilemmas(config).items()}}
    found += [f"{name} description fills {shown_lines(text[1])} lines, not {MIN_LINES}-{MAX_LINES}" for name, text in texts.items()
              if not MIN_LINES <= shown_lines(text[1]) <= MAX_LINES]
    return found
