--- Wider unit card lists in skill tooltips. A tooltip with more than `CARDS_MAX` unit cards gets them moved into a list of `CARDS_PER_ROW` to
--- a row, so it stays short enough for the screen. Shorter lists keep the vanilla layout.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log, the callback name and the wide list's name.
local NAME = "ui_skill_panel_unit_cards"

--- The character panel and the skill tree's holder from character_details_panel_skills.twui.xml.
local PANEL = "character_details_panel"
local HOLDER = "skills_holder"

--- Delay in milliseconds between looks for a hovered skill card's or level pip's tooltip while the panel is open.
local POLL_MS = 10

--- The vanilla tooltips of a skill card and of its level pips, both made inside the card, their list of parts, and the start of the name of
--- their unit card list's copy.
local SKILL_TOOLTIPS = { "edict_tooltip", "CharacterSkillsTooltip" }
local TOOLTIP_LIST = "list_parent"
local UNIT_CARDS = "unit_card_list"

--- The wide list the unit cards are moved into, made from `WIDE_LIST_LAYOUT`.
local WIDE_LIST_LAYOUT = "ui/common ui/ui_skill_panel_unit_cards"

--- Unit cards a tooltip keeps in the vanilla list (3 rows of 10), and the cards in a row of the wide list for the log. Keep it equal to the
--- layout's `itemsperrow`, which sets the real row.
local CARDS_MAX = 30
local CARDS_PER_ROW = 15

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- Whether a look has failed since the panel opened, so the log gets one line per open instead of one every `POLL_MS`.
local failed = false

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Unit cards

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- The tooltip's shown vanilla unit card list, as the game names its tooltip parts `<name>_copy_<n>`.
--- @param parts UIC The tooltip's list of parts.
--- @returns UIC|nil The list, or nil when there is none.
--- @returns number|nil The list's index among the parts.
local function shown_card_list(parts)
    for i = 0, parts:ChildCount() - 1 do
        local child = UIComponent(parts:Find(i))
        if string.sub(child:Id(), 1, string.len(UNIT_CARDS)) == UNIT_CARDS and child:Visible() then
            return child, i
        end
    end
    return nil
end

--- How many of a unit card list's cards are shown.
--- @param cards UIC The unit card list.
--- @returns number The shown cards.
local function shown_count(cards)
    local count = 0
    for i = 0, cards:ChildCount() - 1 do
        if UIComponent(cards:Find(i)):Visible() then
            count = count + 1
        end
    end
    return count
end

--- Moves a tooltip's unit cards into a wide list in the vanilla list's place when there are more than `CARDS_MAX`, and hides the vanilla list.
--- When the game fills the tooltip again and a wide list is already there, its old cards are hidden, not destroyed, as the game may still hold
--- them.
--- @param tooltip UIC The skill card's or level pip's tooltip.
local function widen_cards(tooltip)
    local parts = find_uicomponent(tooltip, TOOLTIP_LIST)
    if not parts then
        return
    end
    local cards, index = shown_card_list(parts)
    -- A short list is skipped before its cards are counted, as this runs every `POLL_MS` for the whole hover.
    if not cards or cards:ChildCount() <= CARDS_MAX then
        return
    end
    local count = shown_count(cards)
    if count <= CARDS_MAX then
        return
    end
    local wide = find_uicomponent(parts, NAME)
    if wide then
        for i = 0, wide:ChildCount() - 1 do
            UIComponent(wide:Find(i)):SetVisible(false)
        end
    else
        wide = UIComponent(parts:CreateComponent(NAME, WIDE_LIST_LAYOUT))
        parts:Divorce(wide:Address())
        parts:Adopt(wide:Address(), index)
    end
    for i = cards:ChildCount() - 1, 0, -1 do
        local card = UIComponent(cards:Find(i))
        if card:Visible() then
            cards:Divorce(card:Address())
            wide:Adopt(card:Address(), 0)
        end
    end
    cards:SetVisible(false)
    log(count .. " unit cards moved into a list of " .. CARDS_PER_ROW .. " to a row")
end

--- Widens the unit cards of the hovered skill card's or level pip's tooltip.
local function widen_card_tooltip()
    local holder = find_uicomponent(core:get_ui_root(), PANEL, HOLDER)
    if not holder or not holder:Visible(true) then
        return
    end
    for _, id in ipairs(SKILL_TOOLTIPS) do
        local address = holder:Find(id, false)
        if address then
            widen_cards(UIComponent(address))
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Polling

--- Widens the hovered skill card's or level pip's tooltip every `POLL_MS` while the panel is open, logging the first failure since it opened.
local function poll()
    if not panel_open then
        return
    end
    local ok, err = pcall(widen_card_tooltip)
    if not ok and not failed then
        failed = true
        log("widen_card_tooltip failed: " .. tostring(err))
    end
    cm:real_callback(poll, POLL_MS, NAME)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
    NAME .. "_panel_opened",
    "PanelOpenedCampaign",
    function(context)
        return tostring(context.string) == PANEL
    end,
    function()
        panel_open = true
        failed = false
        -- The panel opens twice in a row, so any running look is stopped first to keep a single one.
        cm:remove_real_callback(NAME)
        poll()
    end,
    true
)

core:add_listener(
    NAME .. "_panel_closed",
    "PanelClosedCampaign",
    function(context)
        return tostring(context.string) == PANEL
    end,
    function()
        panel_open = false
    end,
    true
)
