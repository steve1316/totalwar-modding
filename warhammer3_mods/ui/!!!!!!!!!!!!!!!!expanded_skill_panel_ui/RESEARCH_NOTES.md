# Expanded Skill Panel UI research notes

The character panel's skill tree with ten rows instead of six, plus our own box in place of the vanilla tooltip on chosen skill cards. Split out
of the Advisor Overhaul on 2026-10-22. The Advisor ships a copy of both files at the same in-pack paths, so the subscribed standalone pack (`!!!`
sorts first, so it wins) or the Advisor's copy runs, never both.

## Use
- **The layout is always on.** `ui/campaign ui/character_details_panel_skills.twui.xml` replaces the panel for every character once any pack
  carrying it loads. A twui file cannot be opt-in.
- **The vanilla panel draws only rows 0-5.** Nodes on indent 6 and up are cut off with no error, so a tree that uses them needs this layout. `[game]`
- **Card boxes are opt-in.** Call `UI_SKILL_PANEL.add_card_boxes{ id, show_for, tips }` at first tick or later. While the character panel is open,
  every 15 looks (300 ms) each set whose `show_for(character)` is true gives `tips(character)`: skill key -> `{ title, text, foot, bundle }`.
  `bundle` (an effect bundle key) fills the vanilla effect list. `foot` shows under it. The box is filled again only when one of them changes.
  Texts must already be localised. Several mods can add sets for the same character: a skill both fill keeps the box of the set added first.
  `UI_SKILL_PANEL.remove_card_boxes(id)` takes a set out again.
  Keep `%` out of loc text read through `common.get_localised_string`: one broke the Change Loadout UI (button picker notes).
- **Two ways to ship it.** List the standalone mod as a required item, or copy `script/campaign/mod/ui_skill_panel.lua`,
  `script/campaign/mod/ui_skill_panel_vscroll.lua` and `ui/campaign ui/character_details_panel_skills.twui.xml` into your pack at the same paths.
  The layout needs the vscroll script: without it the vertical bar moves but the rows do not. Only one file per path runs: the pack that sorts first
  by name wins, and `!!!!!!!!!!!!!!!!expanded_skill_panel_ui` sorts ahead of most mod packs, so a subscribed standalone copy replaces older bundled ones.
- **Demo (MCT, off by default).** Checking "Demo box on Best of the Empire" on the Expanded Skill Panel UI > Demo page in MCT gives Karl Franz's Best of the
  Empire card (`wh_dlc08_skill_emp_lord_unique_karl_0`) a box with bold, italic, colours, icons, live rank, turn and treasury, the effects
  of `wh2_main_minister_emp_reikland` and a foot. `script/campaign/mod/ui_skill_panel_demo.lua` is the code to copy. The demo and the MCT
  page ship only in the standalone pack: a mod that bundles the skill panel leaves both out, so its players get no extra MCT page.
- **Example.** A box for one skill of one lord, with a vanilla effect bundle's effects in it:

  ```lua
  cm:add_first_tick_callback(function()
      if not UI_SKILL_PANEL then return end
      UI_SKILL_PANEL.add_card_boxes({
          id = "my_mod",
          show_for = function(character)
              return character ~= nil and character:character_subtype("my_lord_subtype")
          end,
          tips = function(character)
              return {
                  my_skill_key = {
                      title = common.get_localised_string("my_mod_box_title"),
                      text = common.get_localised_string("my_mod_box_text"),
                      foot = common.get_localised_string("my_mod_box_foot"),
                      bundle = "my_effect_bundle_key",
                  },
              }
          end,
      })
  end)
  ```

## Skill tree layout

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
  Since the vertical bar (2026-10-22) rows 1-8 are back to the vanilla 90 px (row 9 stays 70), `list_box` is 900 px at offset 0,15 with no
  docking, and the `hslider` sits at the top of the rows. `[game]`
- **Group boxes are modules.** A vanilla boxed group (Karl Franz's army buffs) is a `module_<skill>` component inside one row: a run of
  cards in a line, framed by `template_module` (in `chain0`) with the `parchment_divider` image. The frame is drawn 99 px tall from 22 px above the
  module, so modules in neighbouring 90 px rows overlap about 9 px and read as one box. With 70 px rows they clipped into each other, so the 10-row
  panel drew the frame 79 px tall from 12 px above (all four module states). With 90 px rows again it is back to the vanilla 99 px from 22 px
  above. Changing only that image size inside `chain0` did not freeze the game. `[game]`
- **Zones: labels and blanks in a row crash the game.** A script can put its own components between a row's cards (`CreateComponent` on the
  row's `chain` list, then `Divorce` and `Adopt(address, index)`), and they lay out and look right. But learning any skill then froze and crashed
  the game, even when only the script's own parts were moved and the cards were left alone. Without the script it works. Do not add components to
  the skill rows. `[game]`
- **Vertical scrolling (2026-10-22).** The rows stay in the vanilla `listview` (`HorizontalListView`): wheel and drag scroll sideways. A plain
  `skills_holder` holds `rows_clip` (clips 700 px of the 960 px `vscroll_box` around the `listview`) and `skills_vlistview`, a 20 px `Listview` that
  only drives the vertical bar by scrolling its empty `vscroll_drive` box. `ui_skill_panel_vscroll.lua` moves `vscroll_box` to the same share every
  10 ms and keeps the `hslider` at the top of the clip. The wheel scrolls up and down only over the bar. `[game]`
- **Two lists must never move the same box.** Both list callbacks set the whole position of their box: `HorizontalListView` puts it back at the
  clip's top and `Listview` back at its left. A `Listview` wrapped around the `listview` found the inner `list_box` and moved it, so each scroll
  undid the other. Moving it back by script fought the game every frame and flickered. A single component with both callbacks ran only `Listview`.
  `[game]`
- **Lists find their box by the name `list_box` first, anywhere below them.** With no `list_box`, the first box with a `List` callback is used.
  A box with no list callback crashed the game when the panel opened. `[game]`
- **The rows' box must be `list_box`.** Renamed, the game crashed when the character panel opened. A wrapper also named `list_box` around the
  `listview` made the game delete the inner `list_clip`, so no skills showed. `[game]`
- **Vanilla `Listview` drag is vertical only and `HorizontalListView` drag sideways only.** Over the rows, the wheel and drag go to the list
  that owns them, so the wheel cannot scroll up and down there while drag scrolls sideways. `[game]`

## Card boxes

- **`ComponentMouseOn` never reached a mod listener in the campaign (2026-10-18).** Not one hover was logged over the character panel, with
  no condition on the listener. Poll with `cm:real_callback` to react to a hover. `[game]`
- **A skill tree card's tooltip is `edict_tooltip`, built inside the hovered card (2026-10-18).** The card's `layout_path` is
  `ui/campaign ui/edict_tooltip`, not `character_background_skill_tooltip`. It appears as `... > <skill key> > card > edict_tooltip`, so the
  card's parent names the skill. Its children are copied with a `_copy_N` suffix: `list_parent > dy_heading_textbox_copy_0` holds the skill
  name and `dy_description_textbox_copy_2` the description, so match them by their start. `[game]`
- **`SetStateText` on that tooltip's description stops every script (2026-10-18, two runs).** `GetStateText` read 153 characters fine. The
  next call, `SetStateText` with plain ASCII and no `%`, left the tooltip empty, and `out` wrote nothing more from any script, the same as the
  `square_large_text_button` runs that also called `SetStateText`. Do not write text into vanilla tooltips. `[game]`
- **Our own tooltip box over the skill card works (2026-10-18).** Hide `edict_tooltip` with `SetVisible(false)` (the game re-fades an
  opacity change, so that flashes), then show a box made from `ui/common ui/tooltip_centred_title_and_text` under the UI root. Poll every
  20ms, as the game destroys `edict_tooltip` when the hover ends. `SetStateText` on our own box is safe. `[game]`
- **The vanilla effect list can be moved into our box (2026-10-18).** Make `ui/common ui/tooltip_effect_bundle` as a child of the box,
  `box:Adopt(effect_list:Address())`, destroy the rest, then `effect_list:SetContextObject(cco("CcoEffectBundle", bundle_key))`. The game
  builds the rows itself with the right icons, colours and the eye tooltips on attributes, abilities and contact effects. Text lines with
  `SetTooltipText` had the same words but not the vanilla layout or icons. `[game]`
- **`CopyComponent` and `SetTextYOffset` work on our own text components (2026-10-18).** A copy lands in the same List layout, below the
  original. `[game]`
- **The lock bar must sit outside the box's List layout (2026-10-18).** `ui/templates/stick_progress_bar` made inside the box was stacked
  under the text, too far up. Made under the UI root and moved to the box's bottom edge each look, it matches vanilla. Vanilla's lock times
  are `ui_tooltip_stick_delay` 0.35s and `ui_tooltip_removal_delay` 0.15s (`preferences.script.txt`). `[game]`
