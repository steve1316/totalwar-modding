--- MCT page for the Expanded Skill Panel UI. MCT finds this file and builds the page from it. script/campaign/mod/ui_skill_panel_demo.lua reads the option.

--- The registered MCT mod. Its key must match `MCT_MOD_KEY` in the demo script.
local mct_mod = get_mct():register_mod("ui_skill_panel")

mct_mod:set_title("Expanded Skill Panel UI", true)
mct_mod:set_description("A ten-row skill tree and custom boxes on skill cards, for other mods to use. The demo shows what a box can do.", true)

-- MCT names a page after its key and starts every mod with a "Settings" page. The only option here is the demo, so the page is "Demo" instead.
local settings_page = mct_mod:get_default_settings_page()
local demo_page = mct_mod:create_settings_page("Demo", 2)
mct_mod:set_default_settings_page(demo_page)
mct_mod:remove_settings_page(settings_page)

--- The section holding the demo checkbox, shown in place of MCT's "Default Category".
local demo_section = mct_mod:add_new_section("demo", "Demo")
demo_section:set_description("Not a setting. Turn this on to see an example box on a skill card, then turn it off again.")

--- The demo checkbox. Its key must match `MCT_OPTION` in the demo script.
local demo = mct_mod:add_new_option("demo", "checkbox")
demo:set_text("Demo box on Best of the Empire", true)
demo:set_tooltip_text("Shows a demo box on Karl Franz's Best of the Empire skill card: text formatting, colours, icons, live text and effects.", true)
demo:set_is_global(true)
demo:set_default_value(false)
