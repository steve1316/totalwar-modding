--- Demo of the skill panel's card boxes, off unless the MCT option is checked. With it on, Karl Franz's Best of the Empire card shows a box that
--- tries each thing a box can do: the game's text markup and icons, text built from the character on every rebuild, a vanilla effect bundle's
--- effects and a foot. Everything here goes through `UI_SKILL_PANEL` like another mod's code would, so it doubles as the example to copy.
--- Only the standalone pack ships this file. Mods that bundle the skill panel take `ui_skill_panel.lua` and the layout file, not this.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log and as the id of the demo's card box set.
local NAME = "ui_skill_panel_demo"

--- The MCT mod and checkbox that turn the demo on, from script/mct/settings/ui_skill_panel.lua.
local MCT_MOD_KEY = "ui_skill_panel"
local MCT_OPTION = "demo"

--- Karl Franz's agent subtype and his Best of the Empire skill, the card the demo box replaces.
local SUBTYPE = "wh_main_emp_karl_franz"
local SKILL = "wh_dlc08_skill_emp_lord_unique_karl_0"

--- A vanilla effect bundle whose effects fill the box's effect list. Karl is the Elector Count of Reikland.
local BUNDLE = "wh2_main_minister_emp_reikland"

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- Whether the demo's card box set is added.
local active = false

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Demo box

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- Whether the demo box shows for a character.
--- @param character CHARACTER_SCRIPT_INTERFACE|nil The character the panel shows, nil when it could not be read.
--- @returns boolean True for Karl Franz.
local function is_karl(character)
    return character ~= nil and character:character_subtype_key() == SUBTYPE
end

--- Builds the demo box. It runs every 300 ms while the panel is open, so the numbers in it follow the campaign.
--- @param character CHARACTER_SCRIPT_INTERFACE The character the panel shows.
--- @returns table Skill key -> what its box shows.
local function demo_tips(character)
    local text = table.concat({
        "[[i]]A demo of what a skill card box can show. Turn it off in MCT under Expanded Skill Panel UI.[[/i]]",
        "",
        "[[b]]Text markup[[/b]]",
        "[[img:bullet_point_white]][[/img]] [[b]]Bold[[/b]] and [[i]]italic[[/i]] text.",
        "[[img:bullet_point_white]][[/img]] [[col:yellow]]Yellow[[/col]], [[col:green]]green[[/col]], [[col:red]]red[[/col]] and [[col:white]]white[[/col]] text.",
        "[[img:bullet_point_white]][[/img]] Icons in a line: [[img:icon_general]][[/img]] lord, [[img:icon_hero]][[/img]] hero, [[img:icon_treasury]][[/img]] gold, [[img:icon_public_order]][[/img]] public order.",
        "",
        "[[b]]Live text[[/b]]",
        "Built again while the panel is open, from the character and the campaign:",
        "[[img:bullet_point_white]][[/img]] Rank [[col:yellow]]" .. character:rank() .. "[[/col]], turn [[col:yellow]]" .. cm:model():turn_number() .. "[[/col]].",
        "[[img:bullet_point_white]][[/img]] Treasury [[col:yellow]]" .. character:faction():treasury() .. " gold[[/col]].",
        "",
        "[[b]]Effects[[/b]]",
        "The list below is the game's own effect list, pointed at a vanilla effect bundle (" .. BUNDLE .. ").",
    }, "\n")
    return {
        [SKILL] = {
            title = "Expanded Skill Panel UI demo",
            text = text,
            bundle = BUNDLE,
            foot = "[[col:green]]Keep the mouse on the card until the bar fills to lock the box, then move onto it to read each effect's tooltip.[[/col]]",
        },
    }
end

--- Adds or removes the demo's card box set to match the MCT option.
--- @param on boolean True to show the demo.
local function set_demo(on)
    if on == active or not UI_SKILL_PANEL then
        return
    end
    if on then
        active = UI_SKILL_PANEL.add_card_boxes({ id = NAME, show_for = is_karl, tips = demo_tips })
    else
        UI_SKILL_PANEL.remove_card_boxes(NAME)
        active = false
    end
    log("demo " .. (active and "on" or "off"))
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

-- MCT sends its settings once it has loaded and again each time the player applies them. Without MCT the demo stays off.
for _, event in ipairs({ "MctInitialized", "MctFinalized" }) do
    core:add_listener(
        NAME .. "_" .. event,
        event,
        true,
        function(context)
            local mct_mod = context:mct():get_mod_by_key(MCT_MOD_KEY)
            local option = mct_mod and mct_mod:get_option_by_key(MCT_OPTION)
            if option then
                set_demo(option:get_finalized_setting() == true)
            end
        end,
        true
    )
end
