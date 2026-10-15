# Advisor Overhaul research notes

These notes cover the Advisor Overhaul: a standalone hero, the Advisor, with his own agent subtype, a model built from vanilla meshes, weapon and
mount loadouts, and a script that gives every human faction one at campaign start. It shares nothing with Prop Joe's Addvisor (Workshop
2795714008), which only served as inspiration. The findings come from the 2026-10-13 research passes on the vanilla data. The vanilla TSV dump is at
`helper_scripts/_diag/vanilla_all/db/` and the vanilla campaign scripts are at `helper_scripts/_diag/ca_campaign/script/`.

**Status tags** used on every finding:

| Tag | Meaning |
|---|---|
| `[game]` | Tested in game and confirmed. |
| `[data]` | The game files show it. Not checked in game on its own. |
| `[untested]` | An assumption we have not checked. |

---

## Standalone hero (2026-10-13)

- **Every key starts with `advisor_overhaul_`.** Agent subtype `advisor_overhaul_advisor`, agent type `wizard`, skill node set
  `advisor_overhaul_advisor_skill_node_set`, units `advisor_overhaul_<weapon>_<mount>`, rig ancillaries `advisor_overhaul_rig_<weapon>_<mount>`,
  art sets `advisor_overhaul_art_<weapon>`. `generators/advisor_overhaul.py` writes every table from `advisor_overhaul_registry.json` and the
  vanilla rows kept in `advisor_overhaul.json`.
- **Tables a script-spawned hero needs.** Read from the vanilla Amethyst and Grey Wizard rows. `[data]`
  - Agent: `agent_subtypes`, `faction_agent_permitted_subtypes`, `names`, `character_skill_node_sets`.
  - Look: `campaign_character_art_sets`, `campaign_character_arts`, `agent_uniforms`, `variants`, `unit_variants`, the variant mesh definitions,
    and portrait settings for the art sets and campaign variants (`ui/portraits/{portholes,units}/portrait_settings__advisor_overhaul.bin`).
  - Units: `land_units`, `main_units`, `unit_description_historical_texts`, `unit_description_short_texts`, `unit_attributes_groups`,
    `unit_attributes_to_groups_junctions`, `land_units_to_unit_abilites_junctions`, `ui_unit_bullet_point_unit_overrides`,
    `battle_currency_units_cost_values`, `campaign_map_attrition_unit_immunities`, `cdir_military_generator_unit_qualities`,
    `units_custom_battle_permissions`, `units_custom_battle_mounts`.
  - Animation: `battle_animations_table` (the four custom sets) and `culture_to_battle_animation_tables` (every set he and his mounts play, for
    every culture pack that vanilla does not already cover).
  - Loadout: `ancillaries`, `ancillary_info`, `ancillaries_included_agent_subtypes`, `campaign_character_uniform_ancillary_junctions`,
    `campaign_mount_animation_set_overrides`, `character_skills`, `character_skill_nodes`, `character_skill_node_set_items`,
    `character_skill_level_details`.
- **Stats are placeholders.** His foot unit is the Amethyst Wizard's (`wh2_pro07_emp_cha_wizard_death_0`) land and main unit with his own keys and
  texts. Mounted pairs start from the vanilla hero on that mount plus the vanilla mounted-minus-foot difference. The agent subtype copies the
  Amethyst Wizard's caster and cost settings, with the Grey Wizard's icon and voice. No value has been tuned. `[data]`
- **No spells yet.** The lore system was removed, so he is a caster with no lore page and no spell skills. `[data]`

### Model (2026-10-13)

- **He wears the vanilla campaign Advisor, re-rigged.** `misc_advisor_body_01_ad1` and `misc_advisor_head_01_ad1` (variants.pack, rigged to the
  `advisor01` skeleton) are moved onto `humanoid01` by `generators.advisor_overhaul_model` into
  `variantmeshes/wh_variantmodels/hu1/advisor_overhaul/` (`advisor_overhaul_body_01`, `advisor_overhaul_head_01` and
  `advisor_overhaul_head_01_hoodless`). The `.wsmodel` files point at the vanilla `hu1/misc/misc_advisor/materials` XMLs, so no texture is copied.
  Nothing comes from Prop Joe's Addvisor. `[data]`
- **Registry switches.** `model.body` picks a slot set from `model.bodies` (`advisor` by default, plus the shortlisted vanilla outfits below for
  later per-weapon armour, not wired yet). `model.head` picks from `model.heads` and `model.hood` false swaps in the head's `hoodless` model. `[data]`
- **Props.** He keeps the loadout props (staff, sword, shield, disc). The vanilla Advisor's book (`misc_advisor_book_01`) is a separate prop that his
  variant never names, so it is left out. `[data]`

### Re-rig (2026-10-13)

- **Bone map.** A bone humanoid01 has within 3 cm of the same bind spot keeps its name. Robe and cape chains go to the nearest bone of the matching
  humanoid01 chain: front and side skirts to `skirt_front_*` (which hang from the thighs, so the robe follows his legs), back skirts to
  `skirt_back_0-2`, the back cape to `cape_0/1` and `cape_middle_0/1`, shoulder and side capes to `shoulder_pad_*` and `cape_left/right_0/1`. The
  arm twist bones keep their names. Everything else falls to its closest kept ancestor: face bones to `head` and `jaw`, middle and pinky fingers to
  `hand`, toes to `foot`, sleeves to the arms, buttons and scrolls to `spine_2` and `root`. `[data]`
- **Bind gaps over 1 cm** (advisor01 vs humanoid01): `root` 2.6, `neck_0` 1.7, `jaw` 2.0, `upperarm` 2.1, `lowerarm` 1.7, `hand` 1.8, `thumb_0/1`
  1.9/1.5, `lowerleg` 1.3, `foot` 2.5, `toe_0` 4.1, arm twist bones 5.9-8.3, `skirt_front_*_0/1` 8.7/19.7, `cape_left/right_0/1` 46-64 cm. The
  spine, clavicles, upper legs and `head` match. `[data]`
- **Vertex moves.** Arm, hand, finger and leg vertices move bone by bone from the advisor01 bind pose to humanoid01's (he has 2 cm longer arms).
  Without it the hand mesh sits 1.9 cm off the humanoid01 hand bones that carry the props. With it the gap is 0.3 mm. Every other vertex stays,
  since moving the robe and cape by their 9-64 cm gaps would tear them. No originally welded vertices split (0.00 mm). `[data]`
- **Lost.** His face animation (about 60 face bones fold into `head` and `jaw`, only the jaw and eyes move), the separate robe and cape bone chains
  (fewer humanoid01 bones drive them), and the button and scroll jiggle. One lod only, as in vanilla. `[data]`
- **Hood.** The hood is its own piece of the head's main mesh: 579 vertices sharing none with the face, its own texture islands in the top half of
  the head texture, weighted to `head`, `neck_0` and the clavicles. A full scalp, ears and hair cards sit under it, so dropping it (919
  triangles) leaves no hole. The hair is a little flat on top. `[data]`

### Other humanoid01 bodies (2026-10-13)

Vanilla outfits checked with the Advisor head in the 3D viewer (stand pose), for later per-weapon armour. Cathay casters (hu1e) and Kislev
boyars (hu1c) use other skeletons. `[data]`

| Group | Registry key | Vanilla slots | Fit with the hooded head |
|---|---|---|---|
| Robes | `jade_wizard` | body, cape, legs | Clean mantle collar |
| Robes | `gold_wizard` | collar | Cowl hugs the hood |
| Robes | `amethyst_wizard` | body | High collar, no clash |
| Robes | `grey_wizard` | body, cape | Fits; the body has a lowered hood built in, seen with the hoodless head |
| Light | `captain` | torso | Fits (helmet and eyepatch slots dropped) |
| Light | `witch_hunter` | body | Fits |
| Light | `huntsmarshal` | body | Fur collar, best of the light group |
| Heavy | `general` | body, legs, cape | Fits; small dark gap under the back of the hood |
| Heavy | `bretonnian_lord` | body | Fits; small gap at the back |
| Heavy | `todbringer` | body, legs, cape | Fits; small gap at the back |

Rejected: Amber and Celestial bodies have a head built in, Bright and Light collars spike or wrap through the hood, Volkmar has a sunburst halo.
Also fine but not kept: Kislev Patriarch, Engineer, Paladin, Warrior Priest. `[data]`

- **Portrait.** Superseded by "Portraits and unit card" below: the 2D images are now his own. `[data]`

### Portraits and unit card (2026-10-13)

- **Format.** `ui/portraits/{portholes,units}/portrait_settings__*.bin`, version 4. `rpfm_cli portrait-settings to-json` / `from-json` reads and
  writes it, and the vanilla file round-trips byte for byte, so no new tool is needed. Each entry has an `id` (art set or campaign variant),
  `camera_settings_head`, an optional `camera_settings_body` and `variants` (`filename`, `file_diffuse`, `file_mask_1-3`, season, level, age).
  Camera fields: `z`, `y`, `yaw`, `pitch`, `fov`, `skeleton_node` and three more (`distance`, `theta`, `phi`). `[data]`
- **Vanilla camera values.** Across all 1402 vanilla entries `yaw`, `pitch`, `distance`, `theta` and `phi` are always 0 and `skeleton_node` is
  nearly always empty. Only `z` (distance, 1.0 on 764 entries) and `y` (height, 0.0 or 0.03) are tuned. Every Empire wizard, captain and witch hunter
  uses `z` 1.0 and `y` 0.03 with `fov` 30. The Kislev Patriarch uses `z` 1.2 and `y` 0, and the Gold Wizard uses `z` 0.7 and `y` 0. `[data]`
- **The vanilla portholes and units files are byte-identical.** Both `file_diffuse` paths point at `UI/Portraits/Portholes/...`. The 60x130 unit
  card the army panel shows is the file of the same name under `ui/portraits/units/` (the Grey Wizard's has the hat and scarf). Our images use
  the same layout: `ui/portraits/{portholes,units}/no_culture/advisor_overhaul_campaign_01_0.png`. `[data]`
- **A hero's unit card comes from the portrait, not `unit_card`.** 571 vanilla character `unit_variants` rows use `placeholder`, and named
  ones such as `wh_main_emp_karl_franz` have no `ui/units/icons` file. Hero units have no `ui/units/infopics` file either. `[data]`
- **His head matches the Grey Wizard's head around the head bone.** In the humanoid01 bind pose his eyes sit 5.5 cm above and 8.9 cm in front of
  the head bone (Grey Wizard 5.8 and 9.2). The jaw-to-eye line leans 6.3 degrees (Grey Wizard 6.4). Both use the same porthole animation
  (`hu1_un_porthole_idle_01`, from both `hu1_pr8_amethyst_staff_and_sword` and `hu1_empire_staff_and_sword`), which tips the head 3-7 degrees
  down. So the Grey Wizard's camera frames his face the same way, as far as the files show. `[data]`
- **Head camera tuned in game.** Raising `y` alone (0.03 -> 0.05) barely changed the upward look. The deep hood and forward-tilted face need
  the camera tilted down. A positive `pitch` tilts it down: 8 fixed the angle. A higher camera pushes the face down the frame, a lower one up.
  Rounds tried (z, y, pitch): (1.0, 0.05, 0), (1.0, 0.12, 8), (0.8, 0.06, 8), (0.8, 0.03, 8) centred but too close, (1.2, 0.03, 8),
  (1.0, 0.03, 8), (1.16, -0.01, 8). Final, tuned in the portrait preview page and accepted in game ("not exactly 1-1 but it will do"):
  `z` 1.0, `y` 0.0, `pitch` 8, `yaw` 0, `fov` 30. The body camera stays the Grey Wizard's. `[game]`
- **Head camera model, fitted to the round 1, 2, 3 and 5 screenshots.** The camera looks at a target 3.7 cm below the point `y` metres above
  the head bone (porthole idle, frame 0). It sits `z` + 0.10 m from that target along its own view axis. `pitch` swings it up around the target
  (an orbit). Pitching around the camera itself fits far worse. `fov` is vertical, and the visible circle (inner edge of the gold ring, about
  88 px radius in a 1080p crop) spans the whole fov. The first fit (without the 0.10 m) made `z` 1.16 look ~15% too big. At pitch 8 the eye
  line now lands within ~0.065 of the radius and the hood width within ~10%. Round 1 (pitch 0) is off by ~0.11. The shots show the head
  turned ~10 degrees, as in frames 75-93 of the idle. The pose barely moves the eye line. `yaw` direction is untested. The anim viewer's
  `portrait.html` previews this camera. `[data]`
- **His own 2D art, cut from the vanilla Advisor bust.** `ui/skins/default/preview_advisor.png` (ui2.pack, 161x161, clear background) is the
  campaign Advisor's hooded head and shoulders. The generator cuts the 300x164 porthole image, the 60x130 unit card and a 120x260 info picture from
  it. The card and info picture put the bust at the bottom over a grey gradient, like the vanilla Amethyst Wizard card. The masks are left empty,
  as on 666 vanilla entries. `unit_card` is now `advisor_overhaul_advisor`, with the card in `ui/units/icons/` and the info picture in
  `ui/units/infopics/`, and the custom battle `general_portrait` points at his porthole image. `[untested]`
- **Other vanilla Advisor art checked.** `ui/skins/default/porthole_advisor.png` is only the frame ring, `icon_advisor.png` (38x38) is too small,
  `ui/help_images/advisor.png` and `ui/loading_ui/diagrams/campaign_advisor.png` are scenes and a framed portrait, and
  `ui/eventpics/tze/advisor_manipulated.png` is an event picture. The anim viewer render route was not needed. `[data]`

### Spawn and availability (2026-10-13)

- **How vanilla makes a hero recruitable.** `faction_agent_permitted_subtypes` (agent, faction, subtype) puts the subtype in that faction's pool,
  and `agent_subtypes.recruitable` shows it in the recruit panel. Even script-only heroes have a row: the Changeling's
  `wh3_dlc24_tze_the_changeling_cultist_special` is `recruitable=false` with one permitted row for its faction. `[data]`
- **What this mod does.** `recruitable=false`, `cap=1`, `contributes_to_agent_cap=false`, and a permitted row for every faction that has any
  permitted row in vanilla (666). Art sets leave culture, subculture and faction empty, so every culture can use them. `[data]`
- **Spawn.** `script/campaign/mod/advisor_overhaul_spawn.lua`, on the first tick of a new game (`cm:is_new_game()`), for each of
  `cm:get_human_factions()`: `cm:find_valid_spawn_location_for_character_from_character(faction, cm:char_lookup_str(leader), true, 2)` (vanilla
  `wh2_pro08_gotrek_felix.lua`), falling back to `cm:find_valid_spawn_location_for_character_from_settlement(faction, home_region, false, true, 10)`
  (vanilla `wh3_dlc24_the_changeling.lua`), then `cm:create_agent(faction, "wizard", subtype, x, y, true)` (`lib_campaign_manager.lua`). A saved
  value per faction stops a second spawn. `[untested]`
- **Kept alive.** `cm:set_character_immortality(lookup, true)` (as vanilla Gotrek), so a defeat wounds him and he returns. He is named with
  `cm:change_character_localised_name(char, "names_name_<id>", "", "", "")` from his own `names` row (frequency 0, so it is never rolled at
  random). `[untested]`
- **Two art sets, one default.** The game picks one of his art sets at random when he spawns. The loadout script sets his weapon's art set with
  `cm:add_character_model_override` two seconds into the first tick, so a sword-and-shield art set is corrected at once. `[untested]`

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
- **The 10-row layout** (`ui/campaign ui/character_details_panel_skills.twui.xml`). `chain0` vanilla, rows 1-9 at 70 px, `list_box` 740 px with
  12 items per row and dock offset 0,20 showed ten rows. It replaces the panel for every character. Removed with the old lore system, restored
  2026-10-15 for the skills plan. The file is the vanilla ui3.pack file plus only those changes, checked against the patched game that day. `[game]`
- **No vertical scrolling.** The `listview` runs the `HorizontalListView` code callback, which drives only the horizontal slider and drag. `[data]`

### Script-added skills and hero actions (2026-10-15)

Answered by the test build `generators/advisor_overhaul_spike.py` plus `script/campaign/mod/advisor_overhaul_spike.lua`.

- **Hero actions come from a hidden pre-learned skill.** A wizard tree without `wh2_main_skill_all_dummy_agent_actions_emp_battle_wizard`
  (indent 8, points on creation 1) shows only Embed Hero and Constant Local Effect on the unit card. `[game]`
- **One node per slot.** Two nodes on the same indent and tier drop one of them. `cm:add_skill` on the dropped node's skill runs with no error
  and `has_skill` stays false. `[game]`
- **`cm:add_skill(char, key, true, true)` spends no skill point.** The node can be hidden. `[game]`
- **A character effect bundle works for weapon gating.** One applied and removed by script gave a spell (`ability_enable`), a personal stat and
  an army stat (`character_to_force_own`), and came off cleanly. `advancement_stage` must be `start_turn_completed`, or the game crashes on load
  with "invalid database record". `[game]`
- **A wizard can use any hero action through a copy.** Copy the `agent_actions` row with `agent` set to `wizard` (zeal becomes authority), give
  it a new enable effect with an `active` bonus value junction, copy the action's other bonus value junctions, and enable it from a skill. The
  copy needs its own `agent_actions_localised_action_name_<key>` and description text, or it shows with a blank name. `[game]`
- **A REQUIRED link from a hidden node does not lock its child.** The visible child stayed learnable before the script added the hidden parent.
  Pact rows need another lock. `[game]`
- **A skill lock does fire from a script-added skill.** A `character_skill_nodes_skill_locks` row (learning skill A locks node B, as Tretch's
  Corruptive locks his Dictatorial node) locked a visible node once the script added the hidden skill A. Pact rows use a rank 30 gate plus
  locks from the skill the dilemma choice adds. `[game]`
- **Adding the Disc's unlock skill by script makes the Disc pickable,** and a `character_to_province_any` Tzeentch corruption effect in a bundle
  on him spreads corruption. `[game]`

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
- **Vanilla bug.** The Amethyst Wizard's campaign rider overrides are crossed: the pegasus gets the warhorse rider set and the barded horse gets
  the pegasus set. `[data]`
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
| Bow | `hu1_huntsmarshal_sword_bow` 6/0, bow shots | `hu1_empire_hr1_warhorse_sword_and_bow` 6/6 (rider casts are foot casts) | - | - | - | - | - |
| Sword + shield | `hu1_empire_sword_and_shield` 6/6 | `hu1_empire_hr1_warhorse_sword_and_shield` 6/6 | `hu1_empire_hr1_pegasus_sword_and_shield` 0/6 | `hu1_empire_bc2_griffon_wb_sword_shield` 6/6 | `hu1_empire_bc2_demigryph_lance_sword_shield` 6/6 | `hu1_leoncoeur_bc2b_hippogryph_wb_sword_shield` 6/6 | - |
| Staff + hammer | `hu1_volkmar_staff_and_hammer` 6/6 F | `hu1_volkmar_hr1_warhorse_staff_and_hammer` 6/6 F | - | - | - | - | - |
| Hammer | `hu1_empire_hammer` 6/6 | `hu1_empire_hr1_warhorse_hammer` 0/0 | `hu1_empire_hr1_pegasus_hammer` 0/0 | `hu1_empire_bc2_griffon_wb_hammer` 6/6 | - | - | - |
| 2h hammer | `hu1_dlc29_emp_priest_ulric_2h_hammer` 6/0 | `hu1_dlc29_emp_hr1_warhorse_priest_ulric_2h_hammer` 6/6 | - | - | - | - | - |
| Dual swords | `hu1_dlc29_emp_dual_sword` 6/6 | chaos steed rig only | - | - | - | - | - |
| Halberd | `hu1_cst_admiral_halberd` 6/6 | tomb steed rig only | - | - | `hu1_empire_bc2_demigryph_halberd` 0/0 | - | - |
| Sword + magic hand | `hu1_wh3_ice_witch_sword_and_magic` 6/0 | `hu1_wh3_ice_witch_hr1_warhorse_sword_and_magic` 0/6 | - | - | - | - | `hu1_wh3_ice_witch_be1_warbear_sword_and_magic` 0/6 |

- **No `humanoid01` rider set exists for a Disc of Tzeentch, Great Eagle, Celestial Lion, Luminark or Hurricanum.** `[data]`

### Disc of Tzeentch by retargeting

- **The disc is a prop, not a mount.** Vanilla disc riders have no `mounts` row. The disc mesh sits in the variant's `weapon_4` slot on `be_prop_4`,
  and the entity (`wh3_dlc20_chs_cha_chaos_sorcerer_tzeentch_mtze_disc`) plus `flying`/`strider` attributes make the unit fly. `[game]`
- **His own foot animations cannot carry it.** They never move `be_prop_4`, so the disc stands upright through him at his origin, and it vanished
  when he cast. Take-off, flight and landing did work. `[game]`
- **Retargeting the Chaos Sorcerer Lord's humanoid01c disc set works.** `tools/anim_retarget.py` copies each shared bone's rotation, keeps his
  bone lengths, carries over the root's offset (the hover), and copies the disc bone. Both skeletons share 63 bones with the same parents and axes.
  The disc lies flat, he sways and casts like vanilla, and the cast where he floats off the disc is vanilla. `[game]`
- **Held props must follow the hand, then let go.** Prop bones hang off `animroot`, so copying a staff's position leaves it floating away from
  his shorter arm. Each prop follows the hand it is nearest to across the animation, and blends to `root` once it is 0.15-0.45 m further from
  that hand than its closest point, so the staff he throws up while casting still spins above him. `[game]`
- **Metas splice other animations by path.** The casts splice themselves and the persistent stand splices a Disc Knight stand. Left pointing
  at humanoid01c files, they overrode his staff (no spin). `generators/advisor_overhaul_anims.py` retargets the spliced animations too and writes
  copies of those metas pointing at them. Strings in a meta are u16-length-prefixed, with no per-entry size, so swapping a path is safe. `[game]`
- **Battle model comes from the uniform.** A character's battle variant is `agent_uniforms.battle_filename` of the uniform in use, not
  `unit_variants`. Custom battles pick it from `units_custom_battle_permissions.general_uniform`. In campaign,
  `campaign_character_uniform_ancillary_junctions` (ancillary, art set -> uniform) swaps it while a mount ancillary is equipped. `[game]`
- **The disc metas add Tzeentch VFX:** `wh3_dlc20_lord_tze_tze_staff` (purple swirl at the staff) and `..._fire_eyes`. Kept on purpose. `[game]`
- **Viewer.** The modding workbench's Viewer tab (`modding-workbench/`, Advisor Overhaul project) plays a source and a retargeted set side by side in the browser.
- **Staff-only (ranged)** uses the staff + sword set with a sword-less variant. On foot `FIRE_LEVEL` is already filled. Riders need `RIDER_FIRE_*` slots added
  through a GLF-style animpack edit (see `1a_glf_battle_mage_Dante/RESEARCH_NOTES.md`). `[data]`
- **Monster mounts** (griffon, war bear, demigryph) swap his melee weapon for the mount's attack. `[data]`

### Sword and shield casts (derived sets)

- **Vanilla bug: mounted sword-and-shield riders cast with foot animations.** `hu1_empire_hr1_warhorse_sword_and_shield` and
  `hu1_empire_hr1_pegasus_sword_and_shield` fill all six `RIDER_CAST_SPELL_*` slots with the foot `hu1_sfsw_cast_*_01`. The rider's hips drop
  from 1.64 m to 0.89 m (he sinks into the mount) and sit 0.61 m further back. The staff-and-sword horse sets have proper rider casts
  (`hu1_hr1_sfsw_rider1_cast_*`). `[data]`
- **Every sword-and-shield cast is a staff-and-sword animation.** Those never hold a shield, so `be_prop_2` (the shield) sits 0.37-0.92 m from
  his left hand for the whole clip, on his back. In shield animations it moves with `hand_left` to within 2 mm. `[data]`
- **Fix: derived sets.** `generators/advisor_overhaul_anims.py` `DERIVED_SETS` copies a vanilla set under a new name, takes `RIDER_CAST_SPELL_*`
  from a donor set (the staff-and-sword horse set) and writes copies of every `CAST_SPELL_*` / `RIDER_CAST_SPELL_*` animation where the shield
  keeps its stand frame-0 offset from `hand_left`. Slot blend, weight and weapon states stay the sword-and-shield set's. The shield is pinned for
  the whole clip with no blend, since the vanilla clips have it on his back from the first frame. The left hand still makes the staff gestures,
  so he lifts the shield while casting. `[data]`
- **After the fix:** rider casts keep hips at 1.64-1.65 m and the shield 0.05 m from the hand in every frame. The sword keeps the stand's grip
  in the rider casts (within 1.1 degrees, 4 mm). `[data]`
- **Metas carry dock events.** The vanilla sword-and-shield cast metas (kept on foot) have `DOCK_EQPT_LHAND` / `DOCK_EQPT_LHAND_2`, and the
  donor rider metas have `WEAPON_LHAND` / `DOCK_EQPT_RHAND`. They name no animation path, so they need no copies. Whether a dock event moves the
  shield in game over the pinned bone is unknown. `[untested]`

### Greatsword and Sword and Bow (2026-10-13)

- **Pairs made.** Greatsword and Sword and Bow each have On Foot and Barded Warhorse only. No vanilla `humanoid01` set holds a greatsword or a
  bow on a Pegasus, and none exists for the disc, so those pairs are left out. `[data]`

  | Pair | Animation set | Built from | Casts |
  |---|---|---|---|
  | Greatsword, foot | `hu1_dlc29_walach_harkon_2handed_sword` (vanilla) | Walach Harkon | Native: Noctilus's `hu1_fleet_admiral_cast_*`, sword kept in his right hand |
  | Greatsword, warhorse | `hu1_advisor_overhaul_hr1_warhorse_greatsword` | Walach Harkon on his Nightmare | Donor: all six `RIDER_CAST_SPELL_*` from the staff-and-sword horse set |
  | Sword and Bow, foot | `hu1_advisor_overhaul_sword_and_bow` | The Huntsmarshal | Donor: all six `CAST_SPELL_*` from the Amethyst Wizard |
  | Sword and Bow, warhorse | `hu1_advisor_overhaul_hr1_warhorse_sword_and_bow` | The Mounted Yeomen | Donor: all six `RIDER_CAST_SPELL_*` from the staff-and-sword horse set |

- **Vanilla gaps the derived sets fix.** Walach's horse set plays the foot cast `hu1_fleet_admiral_cast_short_01` in `RIDER_CAST_SPELL_UP_SHORT`
  (hips at 0.89 m instead of 1.64 m), and the Mounted Yeomen's set plays foot `hu1_sw_cast_*` in all six rider cast slots. The Huntsmarshal's
  short and medium casts are bow tricks (`hu1_bow_oil_flask_01`, `hu1_bow_amber_bow_01`), not spells. `[data]`
- **Other candidates.** `hu1_empire_2handed_sword` (Greatswords), `hu1_pr7_felix_2h_sword` and Repanse's sets have no casts. Ulrika's
  `hu1_dlc23_*_dual_swords_bow` sets have casts and fire slots but dual swords. `[data]`
- **Props.** Greatsword: `emp_greatswords_sword_2h_01` on `be_prop_0`, Walach's slot (his chalice on `be_prop_1` is left out). Sword and Bow:
  the Huntsmarshal's own kit, `emp_huntsmarshal_sword_1h_01` on `be_prop_1`, `emp_huntsmarshal_bow_rigid_01` on `be_prop_3` and
  `emp_huntsmarshal_arrow_01` on `be_prop_4`. `[data]`
- **Where the props go.** In these sets `be_prop_0` and `be_prop_3` sit at a fixed back spot (to within 2 mm of `spine_2`) whenever the weapon
  is not in use. So the greatsword goes onto his back in the horse casts, and the bow onto his back in melee, stand and casts. The sword is
  sheathed at the left hip (a fixed offset from `root`) while he shoots. `[data]`
- **A staff in the sword slot was tried and dropped.** Held in `be_prop_1`, the bow animations sheathed it at the hip, where it ran from the
  ground to above his head beside the bow and through the horse. Moving it to the bow's back spot worked in the viewer, but the weapon became
  Sword and Bow instead (2026-10-13). `[data]`
- **Bow fire slots.** The foot set has `FIRE_LEVEL` and the four `MOVING_FIRE_*_LEVEL` slots, and the horse set the four `RIDER_FIRE_*_LEVEL`
  slots, all with vanilla metas that have `FIRE_POS` (foot fire at 0.06 s of 1.5 s, horse fire at 1.4-2.3 s of 2.4-3.8 s). The foot set has
  `COMBAT_READY` and the horse set `RIDER_COMBAT_READY`. `[data]`
- **The bow metas carry `DOCK_EQPT_LWAIST` and `DOCK_EQPT_BACK` events.** Whether the game moves props by them over the animated bones is
  unknown. `[untested]`
- **His bow.** `advisor_overhaul_sword_and_bow_missile` (missile weapon and projectile) copies the Huntsmarshal's arrow with damage 120, AP 60
  (Huntsmarshal 240 + 160), range 160 (180), reload 8, marksmanship 50 (100) and no bonus vs large (100). Ammo 30, as vanilla Ulrika. The bow
  units also get `mounted_fire_move` (the Huntsmarshal and the Yeomen have it). `[data]`
- **Campaign pose.** Greatsword: `cam_hero_hu1_dlc29_walach_harkon_2handed_sword`, and on the horse `cam_hu1_dlc14_hr1_warhorse_repanse_2handed_sword`
  (as vanilla Walach). Sword and Bow: `cam_lord_hu1_dlc13_huntsmarshal_sword_bow`, and on the horse Ulrika's
  `cam_hero_hu1_dlc23_hr1_ulrika_dual_swords_bow` (the only `humanoid01` horse bow campaign set). `[untested]`
- **Placeholders.** Both keep his foot melee weapon (`wh_main_emp_sword_caster`) and wear the Advisor robes with the hood up. Each weapon has a
  `body` key in the registry for later armour. `[data]`
- **In game.** Firing on foot and from the horse, and firing while moving, are unchecked in game. `[untested]`

### Staff bolt (2026-10-13)

- **Every Staff and Sword pair shoots a staff bolt**, GLF Battle Mage style. `advisor_overhaul_staff_bolt` (missile weapon and projectile, a
  generic key so the element can follow his first lore later) copies the vanilla Hag Witch's bolt (`wh3_dlc24_ksl_hag_witch_hags_bolt`, a
  magical caster bolt with its own trail and impact VFX) with 1 bolt per shot (2), damage 60 + AP 120 (40 + 90 per bolt), range 150 (100),
  reload 10 (8), marksmanship 50 (10), spread 2 (6) and `homing_strong_magical_fast` (none, GLF's homing). Ammo 20 (Hag Witch 28). `[data]`
- **AI group.** A pair that shoots gets the hybrid of its caster group: `mage_highvalue` -> `hybrid_mage_highvalue`, `flying_mage_highvalue` ->
  `flying_hybrid_highvalue`, `flying_melee_mage_highvalue` -> `flying_melee_mage_hybrid_highvalue` (`RANGED_AI_GROUPS`). `[data]`
- **Fire animation per set.** `[data]`

  | Pair | Set | Fire slots | Animation | `FIRE_POS` |
  |---|---|---|---|---|
  | Foot | `hu1_pr8_amethyst_staff_and_sword` (vanilla, unchanged) | `FIRE_LEVEL` (vanilla) | `hu1_sfsw_aim_fire_stand_01`, a forward staff thrust | 0.91 s of 2.2 s |
  | Warhorse, Pegasus | `hu1_advisor_overhaul_hr1_{warhorse,pegasus}_staff_and_sword` (vanilla copies) | `RIDER_FIRE_FORWARD/LEFT/RIGHT/BACK_LEVEL`, `RIDER_SHOOT_TURN_LEFT/RIGHT_90` | seated `hu1_hr1_sfsw_rider1_cast_up_short`, its vanilla meta | 1.0 s of 4.0 s |
  | Disc | `hu1_advisor_overhaul_disc01_staff_and_sword` | `FIRE_LEVEL` | his retargeted forward short cast with the staff pinned | 1.0 s of 4.0 s |

- **Why these.** The foot set already fires a staff shot. The horse sets' rider casts are proper seated ones (hips at 1.64 m), and GLF fires
  from the same sets with the same cast. All three face forward (static animroot identity) or are the vanilla disc casts GLF uses, and none is
  turned around. The 4 s casts leave about 3 s after the shot, the same ratio GLF ships for these sets. Shorter seated staff animations are
  melee swings. `[data]`
- **Combat-ready stances.** The foot set has `COMBAT_READY`. The horse sets get `RIDER_COMBAT_READY` copied from `RIDER_STAND`, and the disc set,
  which had none, gets `COMBAT_READY` from `STAND` and `FLY_COMBAT_READY` from `FLY_STAND`, so he does not T-pose after a shot. `[data]`
- **The staff stays in his left hand.** `be_prop_5` stays 9-11 cm from `hand_left` through the foot fire and the rider fire, as in the stand.
  Every disc cast throws the staff up to spin above him, so the disc `FIRE_LEVEL` plays a copy (`disc_staff_and_sword/fire/`) with the staff
  pinned at its stand offset from `hand_left` (0.56 m from the hand bone in every frame, as in the disc stand), and a copy of the cast meta whose
  self-splice points at it. He still rises off the disc in that cast, as in vanilla. `[data]`
- **In game.** Whether he fires on each mount, whether the bolt shows its Hag Witch trail, and whether 20 bolts at 60 + 120 is balanced are all
  unchecked. `[untested]`

### Change Loadout button

- **Skills unlock, the button picks.** Weapon and mount skills (rows 0 and 1) only unlock an item. Staff and Sword and On Foot are always unlocked,
  so they have no skill. Every pair, the Pegasus ones included, has its own unit, skill and rig. `[data]`
- **First try crashed the game (2026-10-13 test).** The first version put the button inside the character panel (`character_context_parent >
  holder_br > bottom_buttons`) and the picker in a `script_dummy` on the panel. The button was made there, and a picker option appeared with the
  template's placeholder text `dy_text` near the middle of the screen. On that click, the library's `is_uicomponent` check began failing for every
  component, the UI root included (`find_single_uicomponent() ... supplied parent [UIComponent (...)] is not a ui component` from our script and
  from vanilla `wh_campaign_setup.lua`). Reopening the Skills tab then crashed the game. Log: `debugging/2026-10-13-loadout-button-crash/run2/`.
  `[game]`
- **Why the UI broke is not fully proven.** `is_uicomponent` (`lib_types.lua`) only checks that `tostring(value)` starts with `UIComponent `, and
  the failing values printed exactly that, so something below the script broke. The likely causes are adding components to a panel the game
  rebuilds, and using a wrapped handle that was never checked. `[untested]`
- **`UIComponent(nil)` pitfall.** Wrapping a missing address (a failed `CreateComponent` or `Find`) is reported to hand back the UI root, so later
  `SetState`, `MoveTo` or `Destroy` calls hit the root. The script never wraps a missing address, and it only uses a wrapped handle after `Id()`
  (under `pcall`) returns the exact name it asked for. `[untested]`
- **How the button works now.** The button and the picker options are the script's own components, direct children of the UI root, with unique
  `advisor_overhaul_loadout_*` names. Nothing is added to a vanilla panel. The script only changes or destroys a root child whose `Id()` is one of
  its own names. It does not use `find_uicomponent` or `is_uicomponent`. `[untested]`
- **Second test: no button, no errors (2026-10-13, run3).** The redesigned button never appeared and there was no SCRIPT ERROR. The vanilla
  campaign UI manager logged `Character selected, cqi: 1486 ... subtype: <the Advisor>` three times (68.2s, 69.1s, 75.7s), so `CharacterSelected`
  did fire for the Advisor. The `events` panel (mission review) or `character_details_panel` was open around each of those selections, and that
  version counted both as covering through `get_open_blocking_or_event_panel()`. Its hides logged nothing, so the log shows no trace of them.
  Log: `debugging/2026-10-13-loadout-button-crash/run3/`. `[game]`
- **When it shows.** The button shows in two cases. `[untested]`
  - **Character panel.** While `character_details_panel` is open (from `PanelOpenedCampaign` / `PanelClosedCampaign`) and its
    `character_context_parent:GetContextObjectId("CcoCampaignCharacter")` is the local faction's `advisor_overhaul_advisor`. The panel is only read, inside
    `pcall`, with every component's `Id()` checked. The arrows, character list and tabs give no event, so any `ComponentLClickUp` that is not ours
    while the panel is open schedules a re-check. Another blocking panel over it (from the manager's `campaign_ui_panels_blocking_open`, the
    character panel left out) hides it.
  - **Map selection.** `CharacterSelected` stores the CQI. `CharacterDeselected` and `SettlementSelected` clear it. It shows while no vanilla
    blocking panel is open. `units_panel`, `recruitment_options`, `settlement_panel` and `events` open on selection and do not cover the map, so
    they keep it. A panel in the vanilla blocking list hides it at once.
  - Every check is one 300 ms `cm:real_callback`, replaced by any newer request. There is no polling. A selected general with the Advisor
    embedded is not handled. Clicking the Advisor's own hero card already fires `CharacterSelected` with his CQI (run3 log).
- **Logging.** Every `CharacterSelected` logs CQI, subtype, faction, local Advisor and embedded. A `PanelOpenedCampaign` / `PanelClosedCampaign`
  logs its name and whether it hides the button, but only for the character panel, `units_panel`, a panel that hides the button, or any panel
  while the button is shown (trimmed 2026-10-13). Every check logs one `loadout button shown ... at x,y (rule)` or `loadout button hidden: <reason>`
  line. Checks started by clicks in the panel log only when the decision changes. `[untested]`
- **Where it sits.** On the character panel it sits left of `character_context_parent > holder_br > bottom_buttons`, vertically centred on it, with
  draw priority the panel's plus 50 (at least 200). If that row cannot be read, it goes 420 px left of the panel's right edge and 120 px above its
  bottom. On the map it sits above the right end of `hud_campaign > info_panel_background`, with a screen fallback of 16 px from the left and
  420 px above the bottom. The log names the rule used. Removed 2026-10-13: only the button inside vanilla rows below is left. `[untested]`
- **Button inside vanilla rows (2026-10-13).** The button is made with `CreateComponent(name, square_medium_button)`
  as a child of a vanilla row, and the row's layout places it. It is never moved, raised or made top-most. Both rows line it up in
  game, so the UI root button above (`INJECT_BUTTON = false`) was removed. `[game]`
  - **Character panel:** `character_details_panel > character_context_parent > holder_br > bottom_buttons`. The row is a `HorizontalList`
    (`sizetocontent`, no gap, anchored right) of 55x55 `square_medium_button`s: `button_replace_general`, `button_event_feed`, `button_view_tree`,
    `button_rename`, `button_save_character`. Our button goes at the right end. Run2 already made a button here and clicked it with no error. `[data]`
  - **Map:** `units_panel > main_units_panel > button_group_unit`, the strip over the hovered unit card. It is one shared component, hidden by
    default, shown and moved by the game's `UpgradePopupCallback`. Its `List` layout is one 77 px column, so our button stacks with Disband. It is
    only made while the local Advisor is selected on his own. An embedded Advisor gets none, since the strip serves every card. `[data]`
  - **Get or create:** the script keeps only the parent's path. Each check finds the parent again by name, then looks for our button by exact `Id()`
    among its direct children, and creates it only when missing. It never keeps a handle, so a rebuilt row is simply re-added on the next check
    (`CharacterSelected`, `PanelOpenedCampaign`, panel clicks). Hiding destroys only a direct child with our exact name under that path. The
    `units_panel` closing only closes the picker: the strip is rebuilt with the panel anyway. `[game]`
  - **Strip placement:** the game places the strip over the card from its size when it appears, and only corrects it when the mouse moves. A
    button added by script to a rebuilt strip left it one button (55 px) low until then. Moving it with `MoveTo` (the game put it back) and
    `Layout()` did not help. The fix is to never rebuild it: after a switch from the strip, the script sends `Select` for the still-selected
    Advisor without `ClearSelection`. That refreshes the map card and leaves the strip alone. `ClearSelection` closes the units panel and
    rebuilds the strip. It is still used after a switch in the character panel, once the panel closes, when the mouse is not over the card. `[game]`
  - **Picker:** the options stay UI root children, placed from the button's screen position. On the map they stay open after the mouse leaves
    the strip and the strip hides. If our button lands on a shown sibling, the row's `Layout()` is called and logged. `[game]`
  - **Embedded Advisor (`STRIP_FOR_EMBEDDED`, on by default, 2026-10-13).** The strip button is made from `ui/advisor_overhaul/
    loadout_strip_button.twui.xml`, a byte copy of vanilla `square_medium_button` plus one `ContextVisibilitySetter` on `CcoCampaignCharacter`
    (as Disband): `FactionContext.IsPlayersFaction && AgentSubtypeRecordContext.Key == "advisor_overhaul_advisor"`. The first try used `CcoCampaignUnit` with
    `IsContextValid(CharacterContext) && CharacterContext...`. With either, the button was made but never shown, even with the Advisor himself
    selected. So a child added to the strip by script gets no card context, and its setter hides it. The attempt was removed (2026-10-13): an
    embedded Advisor uses the button in his character panel. `[game]` What the attempt did: it was made whenever the selected local character is the Advisor or leads (or sits in) an army with him embedded. The game
    shows it only on his card, and the script never calls `SetVisible` on it. With the switch off, an embedded Advisor gets no strip button. `[untested]`
    - **Vanilla sources.** The strip's own `dev_button_kill_character` uses `CcoCampaignUnit` with `IsContextValid(CharacterContext)`
      (units_panel.twui.xml), so strip children get the hovered card's unit. Disband uses `CcoCampaignCharacter` with `IsGovernor() == false &&
      HasChaoticPlanSchemerForce == false`. `FactionContext.IsPlayersFaction && AgentSubtypeRecordContext.Key == "wh3_main_sla_nkari"` is the
      N'Kari button in character_information.twui.xml. `CharacterContext.FactionContext` chains appear in cathay_caravans.twui.xml. `[data]`
    - **Click.** The click takes the selected character when he is the Advisor, else the first local Advisor in his army (more than one is
      logged). A switch then sends `Select` without clearing for the selected character, the general when the Advisor is embedded. `[untested]`
- **Cause: a `%` in loc text read through `common.get_localised_string` (runs 1 and 4-8, fixed in run9).** Deferring the click (run6) and short option
  names (run8) changed nothing. The log always stops right after the first option's "created ... got Id" line. The next step reads
  `advisor_overhaul_ui_weapon_option`, whose loc text was `Weapon: %s`. After that, `out` stops writing for every script and `is_uicomponent`
  fails on real components. The Change Loadout tooltip has no `%`, and it never broke. This fits a C format-string bug in the game's loc lookup.
  The UI loc now holds no `%`, labels are joined in Lua, and the harness fails on any `%` in the UI loc file. Run9 opened the picker with no error or crash. `[game]`
- **Disproven: making components inside a click handler (run5, run6).** Run5 used `square_medium_button`, the template that
  works for the main button, and broke the same way, right after the first option's "created ... got Id" line. Every broken run made root
  components from inside the `ComponentLClickUp` handler of our own button. The main button itself is only ever made from a delayed real-time
  callback, and it never broke. Deferring clicks (`after_click`, a 50 ms one-shot `real_callback`) did not fix run6, but it is kept because it is harmless. `[game]`
- **`square_large_text_button` breaks the game UI (run2 and run4).** Both runs created one `ui/templates/square_large_text_button` (as a panel
  child in run2, as a UI root child in run4). The script then read its `button_txt` child and wrote the label into each of its states
  (`CurrentState`, `NumStates`, `GetStateByIndex`, `SetState`, `SetStateText`). In run4 the log shows the option's "created ... got Id" line and
  then nothing more from our script, not even a Lua error. From then on, `is_uicomponent` failed on real components for every script (884
  `find_single_uicomponent`, 70 `uicomponent_descended_from` and 70 `output_uicomponent` errors), and the next Advisor click crashed the game. The
  native call that does it is not pinned down. The text button layout and the state-text loop are no longer used. Logs:
  `debugging/2026-10-13-loadout-button-crash/run2/` and `run4/`. `[game]`
- **`square_medium_button` under the UI root works (run4).** The Change Loadout button was created under the root and then shown, moved and
  clicked with no error: `SetImagePath(icon, 0)`, `SetTooltipText`, `SetState` (`active` / `inactive`), `MoveTo`, `PropagatePriority`,
  `SetVisible`. `[game]`
- **Layouts and icons.** The button and every picker option are `ui/templates/square_medium_button` (ui3.pack, 55x55). Its image 0 is the icon,
  and its states are `active`, `down`, `down_off`, `hover`, `inactive` and `NewState`. The button icon is `ui/skins/default/icon_swap.png`
  (ui2.pack). The option icons (all in ui.pack) are under `ui/campaign ui/skills/`: `item_weapon.png` (Staff and Sword),
  `wh_dlc07_lord_abilities_lions_shield.png` (Sword and Shield), `character_bonus_vs_infantry.png` (On Foot), `mount_barded_warhorse.png`,
  `mount_imperial_pegasus.png` and `mount_disc_of_tzeentch.png`. Any other item gets the swap icon. `[data]`
- **The picker.** Weapons sit in the button's column and mounts in the next column to the right, stacked upward from just above the button. Each
  option's label and reason go in its tooltip (`Weapon: Staff and Sword (current)||The Advisor already uses this.`). The current item is set
  `down`, the pressed look. Items with no unit for the other half of the pair are `inactive`. Every native UI call in the option and picker path is
  logged as `ui call <component>: <call>` just before it runs, so if one breaks the game it is the last line. If any option cannot be made, every
  option made so far is destroyed and the picker stays closed. `[untested]`
- **Applying is multiplayer safe.** A pick sends `CampaignUI.TriggerCampaignScriptEvent(faction_cqi, "advisor_overhaul_loadout:<cqi>:<w>:<m>")`
  and the `UITrigger` listener validates and equips on every client. Changing the model straight from a click desyncs (vanilla
  `wh2_dlc17_bloodgrounds.lua` says so). `[data]`
- **Once per turn** is the `ONE_CHANGE_PER_TURN` constant in `advisor_overhaul.lua`, off by default. `[data]`
- **Untested in game:** the button's spot and draw order over the HUD, whether `MoveTo` holds after a resolution change (the template docks to
  the centre), and whether the character panel redraws the new mount and unit card at once. `[untested]`

### Models in campaign (2026-10-13)

- **A skill needs a `character_skill_level_details` row.** Without one it has 0 levels. The tree then draws it as learned, but `has_skill` stays
  false, so the Change Loadout picker never offered it. The units generator now writes level 1 for each weapon and mount skill. `[game]`
- **Three models, three sources.**
  - `agent_uniforms.filename` is the campaign map model. It follows the rig ancillary through `campaign_character_uniform_ancillary_junctions`.
  - `battle_filename` is the battle model.
  - The character panel's Details model is the full-body porthole (`ClanLeaderModelView` in `character_details_panel_details.twui.xml`). It
    ignores the ancillary junction and follows only the art set.
  - The uniforms now point `filename` and `campaign_porthole_filename` at the weapon's foot variant. `[game]`
- **Weapon art sets.** `advisor_overhaul_art_<weapon>` (in `campaign_character_art_sets` and `campaign_character_arts`) carries the weapon's uniform and
  campaign animation set. On every apply, including on load, the script calls `cm:add_character_model_override(character, art_set)`. Junction rows
  repeat for every art set, so the map still follows the rig. Portrait settings are copied from the base entry for both art set ids and variant
  ids. The Details model then switched. `[game]`
- **Campaign pose comes from the art row's `land_animation`.** With the staff set (`cam_hu1_pr8_amethyst_staff_and_sword`), the shield sat on his
  back. Sword and shield now uses `cam_hu1_empire_sword_and_shield`. When mounted, it uses `cam_hu1_empire_hr1_warhorse_lance_sword_shield`, through
  `campaign_mount_animation_set_overrides` rows for both character sets. Panel, map and mounted map pose all confirmed. `[game]`

- **Vanilla unit comparison from the picker failed (2026-10-13).** Options built from a copy of `square_medium_button`, with the hover-only
  `ContextPinChild` block from `chaos_gifts.twui.xml` and `SetContextObject(cco("CcoMainUnitRecord", unit))`, did show the unit in the HUD panel.
  But it showed no comparison highlighting, and it listed every ability and spell the Advisor could ever have (the record, not his unit). With
  the unit panel pinned, the map Change Loadout button could not be clicked either. `USE_UNIT_CONTEXT` is now false. The main button is
  registered top-most so the unit panel can't cover it. `[game]`

- **No hover events for script components (2026-10-13).** A live preview test listened for `ComponentMouseOn` to equip the hovered pair. The
  whole run logged zero `ComponentMouseOn` events, even with the picker open over the character panel. Scripts can't see hovers on our picker
  options, so live preview is dropped and the test code removed. `[game]`

### Character panel Mount box (2026-10-13)

- **The Mount box lists the faction pool, not the character.** In ui3.pack `character_details_panel_details.twui.xml`:
  - The list `list_box` under `ancillary_selector_mount` (line 11229) is `FactionContext.AncillaryList.Filter(CharacterEquippedToContext !=
    SelectedOrContainedCharacter && CanCharacterEquip(...) && Category == "mount").Distinct(AncillaryRecordContext.Key)`. `[data]`
  - Picking an entry runs `EquipToCharacter(char, <worn mount>)` (line 13387), a native swap. "None" (`entry_none`) shows whenever he wears a
    mount ancillary and runs `RemoveAncillary` on it (line 6476 on). Both are native commands, so every client sees the same result. `[data]`
  - Line 10530 leaves mounts out of the "new item" alert, so the game expects mount items to sit in the pool. `[data]`
- **Vanilla mounts.** A skill grants the mount through `character_skill_level_to_ancillaries_junctions` (763 of 774 mount ancillaries), with
  `ancillaries_required_skills` and `ancillaries_included_agent_subtypes` rows. Every vanilla mount has `turns_before_swap_allowed` 0. The base
  mod's Pegasus uses the same pattern. `wh_main_effect_enable_mount_warhorse` is only the skill's display effect. `[data]`
- **Why it showed only "None".** The script destroyed every rig it took off (`force_remove_ancillary(..., false, true)`), so the pool never held
  one. `[data]`
- **Script API.** `cm:add_ancillary_to_faction(faction, key, suppress_event)` and `cm:force_remove_ancillary_from_faction(faction, key)`.
  `faction:ancillary_exists(key)` only says yes or no. Removing from the faction also strips a worn copy: vanilla `wh2_dlc16_wef_sisters_forge.lua`
  ("remove item from faction/character") and `wh2_dlc10_sword_of_khaine.lua` use it that way. The Sword of Khaine script re-equips with "remove
  from faction, then `force_add_ancillary`". `CharacterAncillaryGained` gives `character()` and the key string `ancillary()`. There is no
  ancillary lost event. `[data]`
- **What the script now does.** The box lists his unlocked pairs, a pick sticks across turns, "None" puts the saved pair back, and the picker
  and the box stay in step. Confirmed in game on 2026-10-13. `[game]`
  - The rigs use `turns_before_swap_allowed` 0.
  - A swap returns the old rig to the pool (`force_remove_ancillary(char, rig, true, true)`).
  - Pool sync, run after every apply: the pool holds one copy of each unlocked pair's rig that no Advisor wears, and no locked rig. A worn rig is
    never removed from the faction. Each sync logs one line naming the rigs it added or removed, or "no change". When several Advisors of a
    faction are reconciled together, the pool is synced once afterwards.
  - Reconcile, run at first tick (every human faction), at turn start (that faction's Advisors), on a weapon or mount skill, on `CharacterAncillaryGained` for a rig, and from a
    `advisor_overhaul_reconcile:<cqi>` UI trigger. Exactly one worn rig of an unlocked pair becomes his saved choice ("loadout taken from the
    worn rig"). No rig ("None"), a locked rig or several put back the saved pair, taking the pool copy first.
  - A click inside `ancillary_selector_mount` checks the worn rig 500 ms later, read only. If it no longer matches the saved pair, it sends the UI
    trigger, so the saved values are written on every client by the trigger.
  - A change from the box selects him again once the character panel closes, like the picker does.
  - `add_ancillary_to_faction` does pool a `transferrable=false` rig. `[game]`
  - Hovering a box entry shows the game's own stat comparison against his current unit, with no work on our side. It shows once per entry, then
    only again after the mouse leaves the list. That is the vanilla dropdown's own behaviour, and fixing it would mean overriding the large
    `character_details_panel_details.twui.xml`, so it is left as is. `[game]`

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
  is_quest_battle). Gelt's rows sit at ranks 7, 12 and 17. Rows for `advisor_overhaul_advisor` should show the same way. `[untested]`
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
