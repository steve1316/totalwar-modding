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
  `script/campaign/mod/ui_skill_panel_vscroll.lua`, `script/campaign/mod/ui_skill_panel_tooltip_scroll.lua`,
  `ui/campaign ui/character_details_panel_skills.twui.xml` and `ui/campaign ui/edict_tooltip.twui.xml` into your pack at the same paths. The
  skill panel layout needs the vscroll script: without it the vertical bar moves but the rows do not. The tooltip layout needs the tooltip
  scroll script: without it every short tooltip stays 600 px tall.
  Only one file per path runs: the pack that sorts first by name wins, and `!!!!!!!!!!!!!!!!expanded_skill_panel_ui` sorts ahead of most mod
  packs, so a subscribed standalone copy replaces older bundled ones.
- **`edict_tooltip` is replaced for the whole campaign.** 36 campaign layouts use it (banners, the city bar, events, dilemmas, post-battle and
  more) and no battle or frontend one does, so all their tooltips scroll past 600 px. Another mod that replaces `edict_tooltip.twui.xml` clashes
  with this one, so this mod takes on such fixes itself (UI Slider's, 2026-10-23).
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
- **Ten rows is the engine limit (2026-10-22).** A 100-row layout with a test tree on indents 0-99 filled only `chain0` to `chain9`: nodes on
  indent 10+ were dropped with no error. The game sorts nodes into a fixed list of 10 rows and skips any indent of 10 or more before it looks up
  `chain%d` (`cmp [node+0x6c], 0xa` in `Warhammer3.exe`). Extra row containers do nothing. `[game]`
- **Skill tooltips scroll past 600 px (2026-10-23).** A skill's units are listed in `edict_tooltip`'s `unit_card_list` (10 to a row), so a skill
  with 92 units ran off the screen bottom. The mod's `edict_tooltip.twui.xml` moves the tooltip root's parts (`list_parent`, `stick_progress_bar`,
  `tokens_list`) into `tooltip_scroll`, a Listview 402x600 px docked bottom left, whose `list_box` takes the root's `HorizontalList`. The root
  loses its layout engine and is 392x100 px. `ui_skill_panel_tooltip_scroll.lua` shrinks the list to a short tooltip's parts and moves it down
  when its top is off the screen. The same build in the "UI Slider" mod (Workshop 3244295546), there only for skill cards through a
  `layout_path`, showed no flash on short or long tooltips, and this build none on cards or pips. The bar and the wheel scroll it. `[game]`
- **A level pip's tooltip is `CharacterSkillsTooltip`, also inside the card (2026-10-23).** It appears as `... > <skill key> > card >
  CharacterSkillsTooltip` with the same `list_parent > unit_card_list_copy_N`, so searches for `edict_tooltip` never saw it. The game builds it in
  code (`SkillLevelPip`, no layout path), but from `ui/campaign ui/edict_tooltip`, so replacing that file reaches it. A new tooltip is made for each
  hover and each pip. `[game]`
- **A script change in a tooltip shows a frame late through `cm:real_callback` (2026-10-23).** Looking every frame at 1 ms, widening its text,
  moving its cards or cutting its rows made it flash and jump on every pip. At 0 ms it calls back at once, so a look that registers itself again
  recurses until "stack overflow". `real_timer.register_repeating(name, 0)` with a `RealTimeTrigger` listener lands before the frame is drawn,
  so the tooltip scroll script shrinks tooltips with no flash. `sizetocontent="false"` alone did not hold a list's height: the game grew it to
  1374-1586 px for 92 cards. `allowverticalresize="false"` did. `[game]`
- **The game places a tooltip, not the script.** It goes under the mouse when it fits, else it is pushed up until its bottom is 28 px past the
  screen bottom (y 1468 on a 1440 px screen), so the bottom of a tall tooltip is what goes off screen. Levels with more effects are taller,
  so they sit higher than shorter ones. The card's `ContextLayoutTooltip` takes `alternate_parent_dock_point` and `invert_y`, but the pip
  tooltip takes no settings, and a script `MoveTo` on the tooltip is undone every frame. The vanilla placement was kept (2026-10-23). `[game]`
  The tooltip scroll script moves the scroll list's dock offset inside the tooltip to keep its top on the screen (not yet tested at the screen top).
- **A tooltip has no height limit that grows to its content.** A layout is either sized to its content or fixed, so the scroll list starts at
  its 600 px limit and a script shrinks short tooltips. `[game]`
- **Rows stack by container height. Their offsets are ignored.** Vanilla rows 0-4 are 90 px and row 5 is 70 px. The `list_box` (`HorizontalList`)
  wraps after `itemsperrow` items. The top spacer counts as one, so 10 rows need at least 11, or the last row lands in a second column off screen.
  `[game]`
- **Never change `chain0`.** It holds the skill card templates. Shrinking it to 70 px (with offset 0) froze the game when the skill panel opened,
  twice. Crash artifacts are in `debugging/2026-10-13-skill-panel-freeze/`. `[game]`
- **The 10-row layout** (`ui/campaign ui/character_details_panel_skills.twui.xml`). `chain0` vanilla, rows 1-9 at 70 px, `list_box` 740 px with
  12 items per row and dock offset 0,20 showed ten rows. It replaces the panel for every character. Removed with the old lore system, restored
  2026-10-15 for the skills plan. The file is the vanilla ui3.pack file plus only those changes, checked against the patched game that day. `[game]`
  Since the vertical bar (2026-10-22) rows 1-8 are back to the vanilla 90 px (row 9 stays 70), `list_box` is 900 px at offset 0,15 with no
  docking, and the `hslider` keeps the vanilla spot at the bottom. `[game]`
- **Group boxes are modules.** A vanilla boxed group (Karl Franz's army buffs) is a `module_<skill>` component inside one row: a run of
  cards in a line, framed by `template_module` (in `chain0`) with the `parchment_divider` image. The frame is drawn 99 px tall from 22 px above the
  module, so modules in neighbouring 90 px rows overlap about 9 px and read as one box. With 70 px rows they clipped into each other, so the 10-row
  panel drew the frame 79 px tall from 12 px above (all four module states). With 90 px rows again it is back to the vanilla 99 px from 22 px
  above. Changing only that image size inside `chain0` did not freeze the game. `[game]`
- **Zones: labels and blanks in a row crash the game.** A script can put its own components between a row's cards (`CreateComponent` on the
  row's `chain` list, then `Divorce` and `Adopt(address, index)`), and they lay out and look right. But learning any skill then froze and crashed
  the game, even when only the script's own parts were moved and the cards were left alone. Without the script it works. Do not add components to
  the skill rows. `[game]`
- **Vertical scrolling (2026-10-22).** The rows stay in the vanilla `listview` (`HorizontalListView`): wheel and drag scroll sideways. The
  `listview` (700 px, inside a plain `skills_holder`) holds `rows_clip`, which clips 669 px of the 960 px `vscroll_box` around `list_clip`, and the
  `hslider` under the clip. Beside it, `skills_vlistview` is a `Listview` that only drives the vertical bar by scrolling its empty `vscroll_drive`
  box. `ui_skill_panel_vscroll.lua` moves `vscroll_box` to the same share every 10 ms. The wheel scrolls up and down only over the bar. `[game]`
- **The scroll reaches only the rows that hold skills.** The script measures the rows with children (plus the top gap again under the last
  one), resizes `vscroll_drive` to that share of its clip, and hides `skills_vlistview` when they all fit. Karl Franz's vanilla tree needs 560
  of the 849 px view, so it gets no vertical bar. Resizing the driver box and hiding the list while the panel is open worked fine. `[game]`
- **Keep the `hslider` outside the clip.** Inside the moving box it had to be pinned by script, and rows showed under and below it. With the
  clip between the `listview` and `list_clip`, the bar stays put and the rows end above it. The `listview` still finds `list_clip` and its bar.
  `[game]`
- **The game widened the 20 px bar list to 340 px.** It covered the right end of the rows, where the wheel then scrolled up and down. Its frame
  and clip are not interactive now, so the wheel and clicks there reach the rows, and the wheel over the bar itself still scrolls up and down.
  The `vslider` is 638 px from 24 px below the top: its top arrow is drawn above its box. `[game]`
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
