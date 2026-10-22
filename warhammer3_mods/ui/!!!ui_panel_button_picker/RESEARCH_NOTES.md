# UI Panel Button Picker research notes

A square icon button in the character panel's bottom-right row, or in the hover strip over the selected character's unit card, with a picker of
icon options stacked above it. Split out of the Advisor Overhaul's Change Loadout button on 2026-10-22. The Advisor ships a copy of the script
at the same in-pack path, so the subscribed standalone pack (`!!!` sorts first, so it wins) or the Advisor's copy runs, never both.

## Use
- Call `UI_PANEL_BUTTON_PICKER.register{ id, icon, is_for, tooltip, locked, columns, apply, reselect }` at first tick or later. Nothing shows
  until a mod registers. Several buttons may be registered, each gets its own button in the row.
- `is_for(character)` picks the characters it is for, of any faction. The library adds the local faction check for showing it.
- `columns(character)` gives `{ { key, options = { { key, icon, tooltip, state } } } }`, state `current` (pressed look), `pick` or `blocked`
  (inactive). Columns stack upward from the button, left to right. Keys must not hold `:`.
- A pick sends `ui_pbp:<id>:<cqi>:<column>:<option>` through `CampaignUI.TriggerCampaignScriptEvent`, and `apply(character, column, option)`
  runs on every client. With `reselect` the character is selected again so his map unit card refreshes.
- Also `refresh(why)`, `shown_in_panel(id)`, `panel_character()`, and `changed(id, cqi, why)` to close, reselect and refresh after an outside change.

## Engine lessons
The notes below come from building the Advisor's Change Loadout button. Older names in them (`advisor_overhaul_loadout_*`, `aolo_`) are now
`ui_pbp_<id>` and `ui_pbp_<id>_<column>_<option>`.


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
- **Untested in game:** the button's spot and draw order over the HUD, whether `MoveTo` holds after a resolution change (the template docks to
  the centre), and whether the character panel redraws the new mount and unit card at once. `[untested]`
- **Vanilla unit comparison from the picker failed (2026-10-13).** Options built from a copy of `square_medium_button`, with the hover-only
  `ContextPinChild` block from `chaos_gifts.twui.xml` and `SetContextObject(cco("CcoMainUnitRecord", unit))`, did show the unit in the HUD panel.
  But it showed no comparison highlighting, and it listed every ability and spell the Advisor could ever have (the record, not his unit). With
  the unit panel pinned, the map Change Loadout button could not be clicked either. `USE_UNIT_CONTEXT` is now false. The main button is
  registered top-most so the unit panel can't cover it. `[game]`
- **No hover events for script components (2026-10-13).** A live preview test listened for `ComponentMouseOn` to equip the hovered pair. The
  whole run logged zero `ComponentMouseOn` events, even with the picker open over the character panel. Scripts can't see hovers on our picker
  options, so live preview is dropped and the test code removed. `[game]`
