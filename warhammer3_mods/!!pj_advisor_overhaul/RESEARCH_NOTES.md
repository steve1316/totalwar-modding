# Addvisor Overhaul research notes

These notes cover how the overhaul gives Prop Joe's Addvisor (Workshop 2795714008) every lore, weapon loadouts, mounts, stances and quest items. They
come from the 2026-10-13 research pass on the vanilla data. The vanilla TSV dump is at `helper_scripts/_diag/vanilla_all/db/` and the vanilla
campaign scripts are at `helper_scripts/_diag/ca_campaign/script/`.

**Status tags** used on every finding:

| Tag | Meaning |
|---|---|
| `[game]` | Tested in game and confirmed. |
| `[data]` | The game files show it. Not checked in game on its own. |
| `[untested]` | An assumption we have not checked. |

---

## The mods this replaces

- **Path of Doubt No Transformation (3065001847)** gives the advisor 15 lores as passive skills on two rows: a first lore, plus a second unlocked at rank 14.
  This mod replaces it.
- **GLF advisor submod (3003242934)** only sets `primary_missile_weapon` on the two advisor land units. This mod folds it in.
- **Skill compat (3003189437)** rewrites the advisor's campaign skill nodes with the same keys. `!!` sorts before `!p`, so our rows win. `[data]`

### Bugs in Path of Doubt

- **Lore button vanishes.** `special_ability_groups_to_units_junctions` links the advisor only to Fire, Heavens and Light. With two unlinked lores
  (e.g. Tzeentch + Dark), no linked group has spells, so the lore-switch button never shows. `[data]`
- **3-4 lores at once.** Tzeentch, Nurgle, Slaanesh and Metal lock only 11 of the other lores, so the 4 newer lores stack. `[data]`
- **Placeholder text.** Every lore skill is named "Life-Leeching" with a blank description. `[data]`
- **Too strong.** One point gives the whole lore, plus -50% cooldown, cheaper spells and overcast. `[data]`

## Lores

- **31 selectable lores.** These are all `special_ability_groups` rows with `is_composite_group=false` and `show_lore_icon=true`, minus
  `wh_pro03_lore_kemmler` (no spells), `wh2_dlc12_lore_lord_kroak` (Kroak only) and `wh3_main_cataclysm_spells` (not a lore). Every spell in them has an
  `enable` effect in `effect_bonus_value_unit_ability_junctions`. `[data]`
- **Lore pages.** A unit gets one lore page per row in `special_ability_groups_to_units_junctions` (`ability_group, unit, group_page_order`). Mannfred is
  the only vanilla unit linked to two lores (Death at page 0, Vampires at page 1). `[data]`
- **Effect key pattern:**
  - Enable is `<pfx>_effect_ability_enable_<spell>`.
  - Overcast is `wh2_main_effect_ability_overcast_<spell>`, using `wh3_main_` for Tzeentch.
  - Cost is `..._wom_cost_<spell>`.
  - Cooldown is `..._cooldown_<spell>`.

  There are odd keys, such as the Tzeentch `enable_tzeentch_*` ones and `wom_cost_soulstealer`, and some spells have no overcast effect. So always read the
  keys from the junction table, never build them by name. `[data]`
- **Multi-level skills work for mastery.** `character_skill_level_details` has 103 level-2 and 79 level-3 rows. Each level lists its own full effects;
  they do not stack. `[data]`

## Skill tree layout

- **Visible rows** are indents 0-5. Indent 6 shows innate nodes. Row colours come from `character_skill_categories`. `[data]`
- **Tier is an order, not a column.** The panel packs nodes left to right. The Changeling's row 0 uses tiers 22-30 with no gap. `[data]`
- **A row holds 32 nodes fine.** No vanilla row has more than 17 (Blue Scribes row 2), but all 32 lores fit in one row and the horizontal slider
  reaches them. `[game]`
- **Six rows is a layout limit, not an engine one.** `ui/campaign ui/character_details_panel_skills.twui.xml` (ui3.pack) has six row containers,
  `chain0` to `chain5`. Nodes on indent 6+ never show. Adding `chain6`+ containers makes them show, and `character_skill_categories` bands work on
  them too. `[game]`
- **Rows stack by container height. Their offsets are ignored.** Vanilla rows 0-4 are 90 px and row 5 is 70 px. The `list_box` (`HorizontalList`)
  wraps after `itemsperrow` items. The top spacer counts as one, so 10 rows need at least 11, or the last row lands in a second column off screen.
  `[game]`
- **Never change `chain0`.** It holds the skill card templates. Shrinking it to 70 px (with offset 0) froze the game when the skill panel opened,
  twice. Crash artifacts are in `debugging/2026-10-13-skill-panel-freeze/`. `[game]`
- **The 10-row layout.** `chain0` is vanilla. Rows 1-9 are 70 px. `list_box` is 740 px with 12 items per row and dock offset 0,20, so row 0 is not
  clipped. `generators/pj_advisor_skill_panel.py` builds it from the vanilla file. It replaces the panel for every character and clashes with any other
  mod that ships this layout. `[game]`
- **No vertical scrolling.** The `listview` runs the `HorizontalListView` code callback, which drives only the horizontal slider and drag. `[data]`

## Weapons and mounts

- **The advisor fits only the `humanoid01` skeleton.** A weapon is part of the land unit's `man_animation`, so each (weapon, mount) pair is its own
  land unit, with its own variant holding the right props. `[data]`
- **How a mount ancillary picks the unit:**
  1. A skill grants the ancillary through `character_skill_level_to_ancillaries_junctions`.
  2. `ancillaries_tables.provided_bodyguard_unit` names a main_units key.
  3. `main_units.land_unit` names the battle unit.
  4. `main_units.mount` names the campaign_mounts model.

  The campaign rider animation comes from `campaign_mount_animation_set_overrides`. Equipping is gated by `ancillaries_required_skills` and
  `ancillaries_included_agent_subtypes`. `[data]`
- **Vanilla bug copied into the base mod.** The Amethyst Wizard's campaign rider overrides are crossed: the pegasus gets the warhorse rider set and the
  barded horse gets the pegasus set. Also, the base mod's `pj_advisor_mount_warhorse` is really a pegasus. `[data]`
- **Swapping by script.** `cm:force_add_ancillary(char, anc, true, true)` changes a lord's mount. Vanilla `wh_start.lua:146` does this for Louen. These
  are unknown: whether `force_remove_ancillary` drops him back on foot, whether the skill gate blocks a forced equip, and whether HP and XP carry over.
  `[untested]`

### Weapon x mount matrix

Each cell is the vanilla `man_animation`, followed by spell-cast slots filled (foot / rider; 6 is a full set). `F` means `FIRE_LEVEL` already holds a
staff shot.

| Weapon | Foot | Warhorse | Pegasus | Griffon | Demigryph | Hippogryph | War bear |
|---|---|---|---|---|---|---|---|
| Staff + sword | `hu1_pr8_amethyst_staff_and_sword` 6/6 F | `hu1_empire_hr1_warhorse_staff_and_sword` 6/6 F | `hu1_empire_hr1_pegasus_staff_and_sword` 6/6 F | `hu1_empire_bc2_griffon_wb_staff_and_sword` 0/6 | - | - | `hu1_wh3_katarin_be1_warbear_staff_and_sword` 6/6 |
| Greatsword | `hu1_dlc29_walach_harkon_2handed_sword` 6/0 | `hu1_dlc29_hr1_warhorse_walach_2handed_sword` 0/6 | - | - | - | - | - |
| Sword + shield | `hu1_empire_sword_and_shield` 6/6 | `hu1_empire_hr1_warhorse_sword_and_shield` 6/6 | `hu1_empire_hr1_pegasus_sword_and_shield` 0/6 | `hu1_empire_bc2_griffon_wb_sword_shield` 6/6 | `hu1_empire_bc2_demigryph_lance_sword_shield` 6/6 | `hu1_leoncoeur_bc2b_hippogryph_wb_sword_shield` 6/6 | - |
| Staff + hammer | `hu1_volkmar_staff_and_hammer` 6/6 F | `hu1_volkmar_hr1_warhorse_staff_and_hammer` 6/6 F | - | - | - | - | - |
| Hammer | `hu1_empire_hammer` 6/6 | `hu1_empire_hr1_warhorse_hammer` 0/0 | `hu1_empire_hr1_pegasus_hammer` 0/0 | `hu1_empire_bc2_griffon_wb_hammer` 6/6 | - | - | - |
| 2h hammer | `hu1_dlc29_emp_priest_ulric_2h_hammer` 6/0 | `hu1_dlc29_emp_hr1_warhorse_priest_ulric_2h_hammer` 6/6 | - | - | - | - | - |
| Dual swords | `hu1_dlc29_emp_dual_sword` 6/6 | chaos steed rig only | - | - | - | - | - |
| Halberd | `hu1_cst_admiral_halberd` 6/6 | tomb steed rig only | - | - | `hu1_empire_bc2_demigryph_halberd` 0/0 | - | - |
| Sword + magic hand | `hu1_wh3_ice_witch_sword_and_magic` 6/0 | `hu1_wh3_ice_witch_hr1_warhorse_sword_and_magic` 0/6 | - | - | - | - | `hu1_wh3_ice_witch_be1_warbear_sword_and_magic` 0/6 |

- **No `humanoid01` rider set exists for a Disc of Tzeentch, Great Eagle, Celestial Lion, Luminark or Hurricanum.** `[data]`
- **Staff-only (ranged)** uses the staff + sword set with a sword-less variant. On foot `FIRE_LEVEL` is already filled. Riders need `RIDER_FIRE_*` slots added
  through a GLF-style animpack edit (see `1a_glf_battle_mage_Dante/RESEARCH_NOTES.md`). `[data]`
- **Monster mounts** (griffon, war bear, demigryph) swap his melee weapon for the mount's attack. `[data]`

### Mount rows

| Mount | `mounts` key | campaign_mounts | icon |
|---|---|---|---|
| Warhorse | `wh_main_emp_mnt_warhorse_360` | `wh_main_cam_mnt_emp_warhorse` | mount_warhorse.png |
| Barded warhorse | `wh_main_emp_mnt_warhorse_barded_hero` | `wh_main_cam_mnt_emp_barded_warhorse` | mount_barded_warhorse.png |
| Pegasus | `wh_main_emp_mnt_pegasus` | `wh_main_cam_mnt_emp_imperial_pegasus` | mount_imperial_pegasus.png |
| Griffon | `wh_dlc03_emp_mnt_amber_wizard_griffon` | `wh_dlc03_cam_mnt_emp_amber_wizard_griffon` | mount_imperial_griffon.png |
| Demigryph | `wh3_dlc25_emp_mnt_demigryph_reaper` | `wh3_dlc25_cam_mnt_reaper` | mount_hippogryph.png (no demigryph icon) |
| Hippogryph | `wh_main_brt_mnt_hippogryph_lords` | `wh_main_cam_mnt_brt_hippogryph` | mount_hippogryph.png |
| War bear | `wh3_main_ksl_mnt_war_bear_heavy_katarin` | `wh3_main_cam_mnt_ksl_war_bear_*` | mount_war_bear.png |

Stat deltas from foot (Amethyst Wizard, vanilla):

| Mount | HP | Charge | Other |
|---|---|---|---|
| Warhorse | +420 | 15 -> 35 | none |
| Barded | +420 | 15 -> 35 | plate_50 armour |
| Pegasus | +588 | 15 -> 35 | plate_50 armour |
| Griffon | +2308 | 15 -> 60 | war_beast, +10 MA |
| War bear | +1000 | 15 -> 50 | none |

## Stances, auras and bolts

- **Toggle stance:**
  - The `unit_special_abilities` row has `active_time=-1`, `passive=false` and `recharge_time=30`. The phase has `duration=-1`.
  - To make stances exclusive, add a key to `special_ability_exclusive_toggle_groups_tables` and a row per ability in
    `unit_special_ability_to_special_ability_toggle_groups_junctions_tables`.
  - Example: Dechala's dances in `wh3_dlc27_dechala_dances`. `[data]`
- **A phase can change damage type.** Use `imbue_magical`, `imbue_ignition` (10 = flaming) or `imbue_contact` (a contact phase key). `[data]`
- **Aura:**
  - `passive=true`, `effect_range` 35 (55 when upgraded), `num_effected_friendly_units=-1`. The targets are set on the phase junction.
  - Example: `wh_main_lord_passive_hold_the_line`, granted by `wh_main_effect_ability_enable_hold_the_line`. `[data]`
- **Per-lore bolts:**
  - Vanilla swaps a hero's missile with `unit_missile_weapon_junctions_tables` (id, missile_weapon, unit) plus
    `effect_bonus_value_missile_weapon_junctions_tables` (`enable`, effect, id).
  - Examples: Ku'gath (`wh3_main_effect_character_ammunition_type_necrotic_missiles`) and the Blue Scribes skill `wh3_dlc24_skill_tze_blue_scribes_top_2`.
  - So each lore skill can switch the staff to its own bolt. Putting `ignition_amount` or `contact_stat_effect` on that bolt's projectile flavours only the bolt. `[data]`
- **GLF hero bolt baseline:** damage 200, AP 60, range 160, reload 12, magical, homing `homing_strong_magical_fast`, ammo 20. `[data]`
- **Stat effects** for loadouts, all `character_to_character_own`: `wh_main_effect_character_stat_` + `melee_attack`, `melee_defence`,
  `weapon_strength`, `ap_damage`, `armour`, `unit_health`, `charge_bonus_add`, `speed`, `leadership`, `ward_save`, `physical_resistance`,
  `magic_resistance`, `missile_resistance`, `bonus_vs_infantry`, `bonus_vs_large`, `missile_block`. `[data]`

## Quests and dilemmas

- **The quest list in the character panel** comes from `character_ancillary_quest_ui_details` (agent_subtype, ancillary, rank, instant,
  is_quest_battle). Gelt's rows sit at ranks 7, 12 and 17. Rows for `pj_advisor` should show the same way. `[untested]`
- **Vanilla quests use a local table.** Vanilla issues quests from a local table in `wh_quests.lua` `q_setup()` with a rank listener in
  `wh_campaign_setup.lua:2078`. A mod cannot add to that table, so we run our own `CharacterRankUp` listener, guarded by a saved value per step. `[data]`
- **DB quest missions bind a startpos character id.** That cannot work for a script-spawned hero, so we use script missions:
  - Build them with `mission_manager:new` + `add_new_objective`, as in LEAPOI `features/tavern_contracts.lua`.
  - Objectives: `DEFEAT_N_ARMIES_OF_FACTION`, `ACHIEVE_CHARACTER_RANK`, `KILL_X_ENTITIES`, `PERFORM_ANY_AGENT_ACTION`, `SEARCH_RUINS`, `CAPTURE_REGIONS` or
    `SCRIPTED`.
  - There is no win-N-battles objective, so use `SCRIPTED` with a counter. `[data]`
- **Item payloads.** Script missions only have a faction-pool item payload. To put the item on the advisor, listen for `MissionSucceeded` and call
  `cm:force_add_ancillary`. Two `money` payloads on one mission silently drop the mission (a LEAPOI lesson). `[data]`
- **Two-choice dilemma:**
  - Tables: `dilemmas_tables`, `cdir_events_dilemma_option_junctions`, `cdir_events_dilemma_choice_details`, `cdir_events_dilemma_payloads`. Every
    choice needs at least a TEXT_DISPLAY payload.
  - Fire it with `cm:trigger_dilemma_with_targets(...)` and read the answer with `DilemmaChoiceMadeEvent` + `context:choice_key()`.
  - Example: LEAPOI `land_enc_dilemma_skirmish_cth`. `[data]`

## Base mod script (`pj_advisor.lua`)

- **What it does:** spawns the advisor for a random human faction after 6 seconds, makes him immortal, gives +1000 XP and gives the Tome of Fates when
  the `pj_advisor_tome` skill is taken (saved value `pj_advisor_tome`).
- **Error wrapper:** `pj_error_wrapping.lua` wraps `core:add_listener` and the callbacks in pcall, so our listeners get wrapped too.
- **No overlap:** it has no rank, mission or dilemma listeners, so ours do not clash as long as we do not reuse its listener names or saved keys.
  `[data]`
