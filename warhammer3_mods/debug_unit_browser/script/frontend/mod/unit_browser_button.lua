--- Standalone debug mod that adds a round button next to Credits on the main menu. Clicking it opens the vanilla Unit & Spell Browser on its
--- Units tab, the same panel the custom battle screen opens, so units and spells can be checked without starting a battle or campaign.
---
--- Every step logs to script_log.txt with the [UNIT BROWSER] prefix. Disable this mod for any shipped build. It is a developer tool only.

if _G._unit_browser_button_loaded then
    out("[UNIT BROWSER] Already loaded - skipping duplicate init.")
    return
end
_G._unit_browser_button_loaded = true

--- Name of the button this mod creates.
local BUTTON_ID = "button_debug_unit_browser"
--- Main menu row that holds the Options, Narrative Viewer and Credits buttons.
local HOLDER_ID = "buttons_holder"
--- Vanilla button the new one is placed after.
local CREDITS_ID = "button_credits"
--- Template for a small round button, the same look as the Narrative Viewer button.
local BUTTON_TEMPLATE = "ui/templates/round_small_button"
--- Vanilla spell browser icon.
local BUTTON_ICON = "ui/skins/default/icon_spell_browser.png"
--- Tooltip shown on hover.
local BUTTON_TOOLTIP = "Unit & Spell Browser"
--- Context command the custom battle spell browser button runs (custom_battle.twui.xml). It opens the browser on the first active ability.
local OPEN_COMMAND = "DatabaseRecords(\"CcoSpecialAbilityGroupRecord\").MaxContext(SortOrder).AbilityList"
    .. ".FirstContext(UnitAbilityContext && UnitAbilityContext.IsPassive == false).UnitAbilityContext.OpenSpellBrowser"
--- Units tab button inside the browser (spell_browser.twui.xml).
local UNITS_TAB_ID = "tab_units"

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Helpers

--- Writes a line to script_log.txt with this mod's prefix.
--- @param msg string The message to log.
local function log(msg)
    out("[UNIT BROWSER] " .. msg)
end

--- Finds the main menu row of small buttons, the one Credits sits in.
--- @returns UIComponent|nil The row, or nil when the main menu is not on screen.
local function find_holder()
    local credits = find_uicomponent(core:get_ui_root(), CREDITS_ID)
    if not credits then
        return nil
    end
    local holder = UIComponent(credits:Parent())
    if holder:Id() ~= HOLDER_ID then
        log("Credits button parent is [" .. holder:Id() .. "], expected [" .. HOLDER_ID .. "]. Using it anyway.")
    end
    return holder
end

--- Adds the browser button to the main menu row if the row is on screen and the button is not there yet.
--- @param reason string What triggered the check, for the log.
local function ensure_button(reason)
    local holder = find_holder()
    if not holder then
        log("(" .. reason .. ") Credits button not found - main menu not on screen, skipping.")
        return
    end
    if find_child_uicomponent(holder, BUTTON_ID) then
        return
    end

    local button = UIComponent(holder:CreateComponent(BUTTON_ID, BUTTON_TEMPLATE))
    if not button then
        log("(" .. reason .. ") CreateComponent from [" .. BUTTON_TEMPLATE .. "] failed.")
        return
    end
    button:SetImagePath(BUTTON_ICON)
    button:SetTooltipText(BUTTON_TOOLTIP, true)
    button:SetVisible(true)
    holder:Layout()

    local x, y = button:Position()
    local w, h = button:Bounds()
    log("(" .. reason .. ") Added button to [" .. holder:Id() .. "] at " .. x .. ", " .. y .. " size " .. w .. "x" .. h
        .. ". Row now has " .. holder:ChildCount() .. " children.")
end

--- Sends the vanilla open command, then switches the browser to its Units tab. The command opens it on the Spells tab by default.
local function open_browser()
    log("Button clicked - sending OpenSpellBrowser command.")
    local ok, err = pcall(common.call_context_command, OPEN_COMMAND)
    if not ok then
        log("Open command raised: " .. tostring(err))
        return
    end

    local panel = find_uicomponent(core:get_ui_root(), "spell_browser")
    if not panel then
        log("spell_browser panel not found right after the command.")
        return
    end
    local tab = find_uicomponent(panel, UNITS_TAB_ID)
    if not tab then
        log("Browser opened but [" .. UNITS_TAB_ID .. "] was not found. Staying on the default tab.")
        return
    end
    local before = tab:CurrentState()
    tab:SimulateLClick()
    log("Browser opened. Clicked [" .. UNITS_TAB_ID .. "], state " .. before .. " -> " .. tab:CurrentState())
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Listeners

core:add_ui_created_callback(function()
    log("UI created.")
    ensure_button("ui created")
end)

core:add_listener(
    "unit_browser_button_screen",
    "FrontendScreenTransition",
    true,
    function(context)
        ensure_button("screen " .. tostring(context.string))
    end,
    true
)

core:add_listener(
    "unit_browser_button_click",
    "ComponentLClickUp",
    function(context) return context.string == BUTTON_ID end,
    open_browser,
    true
)

log("Loaded.")
