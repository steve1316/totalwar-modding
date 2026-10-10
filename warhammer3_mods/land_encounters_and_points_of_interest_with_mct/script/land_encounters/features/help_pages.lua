--- LEAPOI pages in the game's help panel (the "?" button), their help index entries, link tooltips and Home page card, and the intro message
--- that links to them. The pages and their lines come from configs/help_pages.lua, written by helper_scripts/generators/leapoi_help_pages.py
--- with the text. A page is a list of `advice_info_texts` records registered on its script link, so the index, the Home page card and any
--- `[[url:<link>]]` in event text open it. Links inside notification panels never reach the script, so only the intro message links to pages.

require("script/land_encounters/utils/common")

local debug_config = require("script/land_encounters/configs/debug")
local help_config = require("script/land_encounters/configs/help_pages")

local M = {}

--- Prefix of the Home page card's `advice_info_texts` record keys: title, image and text.
local CONTENTS_RECORD = "land_enc_hp_contents_"

--- Picture of the Home page card.
local CONTENTS_IMAGE = "UI/help_images/campaign_map.png"

--- Section name of the Home page card.
local CONTENTS_SECTION = "land_enc"

--- Prefix of the loc keys of `advice_info_texts` records.
local RECORD_LOC = "advice_info_texts_localised_text_"

--- Saved value set once the intro message has been shown.
local INTRO_SHOWN = "land_enc_intro_shown"

--- Seconds the notification panel must stay closed before the intro message shows. A message sent while the game's own Path to Glory
--- or another notification is open is dropped.
local INTRO_DELAY = 2

--- Name of the callback that shows the intro message, so a panel opening can cancel it.
local INTRO_TIMER = "land_enc_intro_timer"

--- Listeners that only live until the intro message has shown: the panel watchers while it waits, and the turn 2 fallback.
local INTRO_LISTENERS = { "land_enc_intro_panel_opened", "land_enc_intro_panel_closed", "land_enc_intro_fallback" }

--- True while the intro message waits for the notification panel to stay closed.
local intro_waiting = false

--- Where the intro message points on the map: the faction leader, else the faction's home settlement, else the map origin. The plain
--- `show_message_event` call never showed the message in game, even with event feed string rows, while the located one does.
--- @param faction faction The faction that sees the message.
--- @returns number, number The logical x and y.
local function intro_position(faction)
    if faction:has_faction_leader() and faction:faction_leader():has_military_force() then
        local leader = faction:faction_leader()
        return leader:logical_position_x(), leader:logical_position_y()
    end
    if faction:has_home_region() then
        local settlement = faction:home_region():settlement()
        return settlement:logical_position_x(), settlement:logical_position_y()
    end
    return 0, 0
end

--- Shows the intro message, which links to the help pages, to every human faction. Once per campaign unless the debug `intro_now` switch is on.
local function show_intro()
    if cm:get_saved_value(INTRO_SHOWN) and not debug_config.intro_now[1] then return end
    cm:set_saved_value(INTRO_SHOWN, true)
    intro_waiting = false
    for _, name in ipairs(INTRO_LISTENERS) do core:remove_listener(name) end
    for _, faction_name in ipairs(cm:get_human_factions()) do
        local x, y = intro_position(cm:get_faction(faction_name))
        show_located_message(faction_name, "intro", { x, y })
        log("help pages: showed the intro message to " .. faction_name .. " at (" .. x .. ", " .. y .. ")")
    end
end

--- Shows the intro message once the notification panel has stayed closed for `INTRO_DELAY` seconds, starting the wait again on each close.
--- The panel watchers are added on the first call and removed once the message shows.
local function queue_intro()
    if not intro_waiting then
        intro_waiting = true
        core:add_listener("land_enc_intro_panel_opened", "PanelOpenedCampaign", function(context) return context.string == "events" end,
            function() cm:remove_callback(INTRO_TIMER) end, true)
        core:add_listener("land_enc_intro_panel_closed", "PanelClosedCampaign", function(context) return context.string == "events" end,
            queue_intro, true)
    end
    cm:remove_callback(INTRO_TIMER)
    cm:callback(show_intro, INTRO_DELAY, INTRO_TIMER)
end

--- Registers every page on its link, with its index entry's link and its tooltip, and adds the LEAPOI card to the game's Home page.
--- @param env table The entry point's environment, which holds CA's help page helpers.
local function add_pages(env)
    local parser = env.get_link_parser()
    for _, page in ipairs(help_config) do
        local index_key = "land_enc_" .. page.key
        local link, tooltip = "script_link_" .. index_key, "tooltip_" .. index_key
        local records = {}
        for i, builder in ipairs(page.records) do records[i] = env[builder](string.format("land_enc_hp_%s_%03d", page.key, i)) end
        --- The game runs Lua 5.1, which has the global `unpack`. `table.unpack` is for tooling on newer Lua.
        env.help_page:new(link, (unpack or table.unpack)(records))
        parser:add_record(index_key, link, tooltip)
        env.tooltip_patcher:new(tooltip):set_layout_data("tooltip_title_and_text", RECORD_LOC .. "land_enc_hp_" .. page.key .. "_001",
            RECORD_LOC .. "land_enc_hp_" .. page.key .. "_tip")
        log("help pages: added the " .. page.key .. " page (" .. #records .. " lines) on " .. link)
    end
    --- The game's Home page is a page like any other, so the LEAPOI card is appended to its records. Its list starts at the second page,
    --- since the first is the header the card stands for.
    if not env.hp_contents then
        log("help pages: the game's Home page was not found, so it has no LEAPOI card")
        return
    end
    for _, record in ipairs({ env.hpr_section(CONTENTS_SECTION), env.hpr_title(CONTENTS_RECORD .. "001", CONTENTS_SECTION),
        env.hpr_image(CONTENTS_RECORD .. "002", CONTENTS_IMAGE, CONTENTS_SECTION), env.hpr_normal(CONTENTS_RECORD .. "003", CONTENTS_SECTION),
        env.hpr_section_index(CONTENTS_SECTION, "land_enc_" .. help_config[2].key) }) do
        table.insert(env.hp_contents.content, record)
    end
    log("help pages: added the LEAPOI card to the Home page")
end

--- Registers the pages at first tick, after the game's own help pages, and the listeners that show the intro message once per campaign. CA's
--- help page helpers are globals of the entry point's environment, which required modules do not see, so the entry point hands it in.
--- @param env table|nil The entry point's environment, or nil to read `_G`.
function M.register(env)
    env = env or _G
    cm:add_first_tick_callback(function()
        if not (env.help_page and env.get_link_parser and env.tooltip_patcher) then
            log("help pages: the game's help page helpers are missing, so the LEAPOI pages are not added")
            return
        end
        add_pages(env)
        --- The debug switch shows the intro on a loaded save. A new campaign shows it after the opening cutscene anyway.
        if debug_config.intro_now[1] and not cm:is_new_game() then
            queue_intro()
        elseif not cm:get_saved_value(INTRO_SHOWN) then
            --- Multiplayer, and a campaign without an opening cutscene, show the intro at the start of turn 2.
            core:add_listener("land_enc_intro_fallback", "FactionTurnStart", function(context)
                return context:faction():is_human() and cm:turn_number() >= 2
            end, function()
                log("help pages: turn 2 started without the intro message, so it shows now")
                show_intro()
            end, true)
        end
    end)
    --- The intro follows the game's opening cutscene and its own messages. Not in multiplayer, where each player's panels open and close at
    --- their own pace.
    core:add_listener("land_enc_intro_after_cutscene", "ScriptEventIntroCutsceneFinished", function() return not cm:is_multiplayer() end, function()
        log("help pages: the opening cutscene finished, the intro message follows once the notifications are closed")
        queue_intro()
    end, true)
    core:add_listener("land_enc_help_link_clicked", "ComponentLinkClicked", true, function(context)
        log("help pages: link clicked: " .. tostring(context.string))
    end, true)
end

return M
