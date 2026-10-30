--- MCT page for the Expanded Skill Panel UI. MCT finds this file and builds the page from it.
--- script/campaign/mod/ui_skill_panel_vscroll.lua reads the compact rows option, script/campaign/mod/ui_skill_panel_demo.lua the demo option.

--- The registered MCT mod. Its key must match `MCT_MOD_KEY` in the vscroll and demo scripts.
local mct_mod = get_mct():register_mod("ui_skill_panel")

mct_mod:set_title("Expanded Skill Panel UI", true)
mct_mod:set_description("A ten-row skill tree and custom boxes on skill cards, for other mods to use. The demo shows what a box can do.", true)

--- The section holding the layout options, shown in place of MCT's "Default Category".
local layout_section = mct_mod:add_new_section("layout", "Layout")

--- The compact rows checkbox. Its key must match `MCT_OPTION` in the vscroll script.
local compact_rows = mct_mod:add_new_option("compact_rows", "checkbox")
compact_rows:set_text("Compact row gaps", true)
compact_rows:set_tooltip_text("Packs the skill rows closer together, so more of a tall skill tree fits without scrolling. A mod developer can choose their own gaps for their own skill trees and theirs take priority over this toggle.", true)
compact_rows:set_is_global(true)
compact_rows:set_default_value(false)

--- The section holding the demo checkbox.
local demo_section = mct_mod:add_new_section("demo", "Demo")
demo_section:set_description("Not a setting. Turn this on to see an example box on a skill card, then turn it off again.")

--- The demo checkbox. Its key must match `MCT_OPTION` in the demo script.
local demo = mct_mod:add_new_option("demo", "checkbox")
demo:set_text("Demo box on Best of the Empire", true)
demo:set_tooltip_text("Shows a demo box on Karl Franz's Best of the Empire skill card: text formatting, colours, icons, live text and effects.", true)
demo:set_is_global(true)
demo:set_default_value(false)
