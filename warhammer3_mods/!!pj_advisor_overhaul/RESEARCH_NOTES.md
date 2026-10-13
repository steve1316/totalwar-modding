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
  at humanoid01c files, they overrode his staff (no spin). `generators/pj_advisor_anims.py` retargets the spliced animations too and writes
  copies of those metas pointing at them. Strings in a meta are u16-length-prefixed, with no per-entry size, so swapping a path is safe. `[game]`
- **Battle model comes from the uniform.** A character's battle variant is `agent_uniforms.battle_filename` of the uniform in use, not
  `unit_variants`. Custom battles pick it from `units_custom_battle_permissions.general_uniform`. In campaign,
  `campaign_character_uniform_ancillary_junctions` (ancillary, art set -> uniform) swaps it while a mount ancillary is equipped. `[game]`
- **The disc metas add Tzeentch VFX:** `wh3_dlc20_lord_tze_tze_staff` (purple swirl at the staff) and `..._fire_eyes`. Kept on purpose. `[game]`
- **Viewer.** `python -m tools.anim_viewer` plays a source and a retargeted set side by side as skeletons in the browser.
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
- **Fix: derived sets.** `generators/pj_advisor_anims.py` `DERIVED_SETS` copies a vanilla set under a new name, takes `RIDER_CAST_SPELL_*`
  from a donor set (the staff-and-sword horse set) and writes copies of every `CAST_SPELL_*` / `RIDER_CAST_SPELL_*` animation where the shield
  keeps its stand frame-0 offset from `hand_left`. Slot blend, weight and weapon states stay the sword-and-shield set's. The shield is pinned for
  the whole clip with no blend, since the vanilla clips have it on his back from the first frame. The left hand still makes the staff gestures,
  so he lifts the shield while casting. `[data]`
- **After the fix:** rider casts keep hips at 1.64-1.65 m and the shield 0.05 m from the hand in every frame. The sword keeps the stand's grip
  in the rider casts (within 1.1 degrees, 4 mm). `[data]`
- **Metas carry dock events.** The vanilla sword-and-shield cast metas (kept on foot) have `DOCK_EQPT_LHAND` / `DOCK_EQPT_LHAND_2`, and the
  donor rider metas have `WEAPON_LHAND` / `DOCK_EQPT_RHAND`. They name no animation path, so they need no copies. Whether a dock event moves the
  shield in game over the pinned bone is unknown. `[untested]`

### Change Loadout button

- **Skills unlock, the button picks.** Weapon and mount skills (rows 6 and 7) only unlock an item. Staff and Sword and On Foot are always unlocked,
  so they have no skill. The base mod's Pegasus skill (`pj_advisor_mount_warhorse`) unlocks the pegasus. It also equips its own ancillary, so the
  skill listener puts the chosen pair back at once. `[untested]`
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
  `pj_advisor_overhaul_loadout_*` names. Nothing is added to a vanilla panel. The script only changes or destroys a root child whose `Id()` is one of
  its own names. It does not use `find_uicomponent` or `is_uicomponent`. `[untested]`
- **Second test: no button, no errors (2026-10-13, run3).** The redesigned button never appeared and there was no SCRIPT ERROR. The vanilla
  campaign UI manager logged `Character selected, cqi: 1486 ... subtype: pj_advisor` three times (68.2s, 69.1s, 75.7s), so `CharacterSelected`
  did fire for the Advisor. The `events` panel (mission review) or `character_details_panel` was open around each of those selections, and that
  version counted both as covering through `get_open_blocking_or_event_panel()`. Its hides logged nothing, so the log shows no trace of them.
  Log: `debugging/2026-10-13-loadout-button-crash/run3/`. `[game]`
- **When it shows.** The button shows in two cases. `[untested]`
  - **Character panel.** While `character_details_panel` is open (from `PanelOpenedCampaign` / `PanelClosedCampaign`) and its
    `character_context_parent:GetContextObjectId("CcoCampaignCharacter")` is the local faction's `pj_advisor`. The panel is only read, inside
    `pcall`, with every component's `Id()` checked. The arrows, character list and tabs give no event, so any `ComponentLClickUp` that is not ours
    while the panel is open schedules a re-check. Another blocking panel over it (from the manager's `campaign_ui_panels_blocking_open`, the
    character panel left out) hides it.
  - **Map selection.** `CharacterSelected` stores the CQI. `CharacterDeselected` and `SettlementSelected` clear it. It shows while no vanilla
    blocking panel is open. `units_panel`, `recruitment_options`, `settlement_panel` and `events` open on selection and do not cover the map, so
    they keep it. A panel in the vanilla blocking list hides it at once.
  - Every check is one 300 ms `cm:real_callback`, replaced by any newer request. There is no polling. A selected general with the Advisor
    embedded is not handled. Clicking the Advisor's own hero card already fires `CharacterSelected` with his CQI (run3 log).
- **Logging.** Every `CharacterSelected` logs CQI, subtype, faction, local Advisor and embedded. Every `PanelOpenedCampaign` / `PanelClosedCampaign`
  logs its name and whether it hides the button. Every check logs one `loadout button shown ... at x,y (rule)` or `loadout button hidden: <reason>`
  line. Checks started by clicks in the panel log only when the decision changes. `[untested]`
- **Where it sits.** On the character panel it sits left of `character_context_parent > holder_br > bottom_buttons`, vertically centred on it, with
  draw priority the panel's plus 50 (at least 200). If that row cannot be read, it goes 420 px left of the panel's right edge and 120 px above its
  bottom. On the map it sits above the right end of `hud_campaign > info_panel_background`, with a screen fallback of 16 px from the left and
  420 px above the bottom. The log names the rule used. `[untested]`
- **Button inside vanilla rows (`INJECT_BUTTON`, on by default, 2026-10-13).** The button is made with `CreateComponent(name, square_medium_button)`
  as a child of a vanilla row, and the row's layout places it. It is never moved, raised or made top-most. Setting `INJECT_BUTTON = false` brings
  back the UI root button above. Both rows line it up in game. `[game]`
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
- **Cause: a `%` in loc text read through `common.get_localised_string` (runs 1 and 4-8, fixed in run9).** Deferring the click (run6) and short option
  names (run8) changed nothing. The log always stops right after the first option's "created ... got Id" line. The next step reads
  `pj_advisor_overhaul_ui_weapon_option`, whose loc text was `Weapon: %s`. After that, `out` stops writing for every script and `is_uicomponent`
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
- **Applying is multiplayer safe.** A pick sends `CampaignUI.TriggerCampaignScriptEvent(faction_cqi, "pj_advisor_overhaul_loadout:<cqi>:<w>:<m>")`
  and the `UITrigger` listener validates and equips on every client. Changing the model straight from a click desyncs (vanilla
  `wh2_dlc17_bloodgrounds.lua` says so). `[data]`
- **Once per turn** is the `ONE_CHANGE_PER_TURN` constant in `pj_advisor_overhaul.lua`, off by default. `[data]`
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
- **Weapon art sets.** `pj_advisor_art_<weapon>` (in `campaign_character_art_sets` and `campaign_character_arts`) carries the weapon's uniform and
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
