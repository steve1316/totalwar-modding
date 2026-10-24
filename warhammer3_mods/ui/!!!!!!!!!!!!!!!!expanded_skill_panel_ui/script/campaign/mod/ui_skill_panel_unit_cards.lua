--- Scrolling unit card lists in skill tooltips. The mod's edict_tooltip layout gives the unit card list a fixed box of `SCROLL_ROWS` rows of
--- `CARDS_PER_ROW` at the tooltip's width, so the tooltip has its final size on the first frame the game draws. A longer list is moved into a
--- list of the same size with a vertical bar, so the tooltip does not move or change size.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log, the callback name and the scroll list's name.
local NAME = "ui_skill_panel_unit_cards"

--- The character panel and the skill tree's holder from character_details_panel_skills.twui.xml.
local PANEL = "character_details_panel"
local HOLDER = "skills_holder"

--- Delay in milliseconds between looks for a hovered skill card's or level pip's tooltip while the panel is open. At 1 it looks every frame, so a
--- long list gets its bar on the frame after the game draws it. At 0 `cm:real_callback` calls back at once, so the look calls itself until the
--- stack overflows.
local POLL_MS = 1

--- The vanilla tooltips of a skill card and of its level pips, both made inside the card, their list of parts, and the start of the name of
--- their unit card list's copy.
local SKILL_TOOLTIPS = { "edict_tooltip", "CharacterSkillsTooltip" }
local TOOLTIP_LIST = "list_parent"
local UNIT_CARDS = "unit_card_list"

--- The scroll list the unit cards are moved into, made from `SCROLL_LIST_LAYOUT`, and the box inside its clip that holds the cards.
local SCROLL_LIST_LAYOUT = "ui/common ui/ui_skill_panel_unit_cards"
local LIST_CLIP = "list_clip"
local LIST_BOX = "list_box"

--- The scroll list's vertical bar and how far its arrows reach past its ends. Keep the arrows equal to the bar's top offset in the layout.
local SLIDER = "vslider"
local SLIDER_ARROWS = 24

--- Cards in a row and rows shown before the list scrolls. Keep them equal to the layouts' `itemsperrow` and to the height of edict_tooltip's
--- unit card list, which set the real rows.
local CARDS_PER_ROW = 9
local SCROLL_ROWS = 4

--- The gap between rows. Keep it equal to the layouts' `spacing`.
local ROW_GAP = 3

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

--- The height of one row of cards in the scroll list, with the gap under it.
--- @param box UIC The box holding the cards.
--- @returns number The row's height.
local function row_height(box)
    return UIComponent(box:Find(box:ChildCount() - 1)):Height() + ROW_GAP
end

--- Sizes the scroll list to the vanilla list it replaces and shows `SCROLL_ROWS` rows of its cards with the vertical bar. The vanilla list's
--- blank space under its rows stays blank under the scroll list.
--- @param scroll_list UIC The scroll list.
--- @param box UIC The box holding the cards.
--- @param cards UIC The vanilla unit card list.
--- @param count number The shown cards.
local function size_list(scroll_list, box, cards, count)
    box:Layout()
    local rows = math.ceil(count / CARDS_PER_ROW)
    local height = box:Height() - (rows - SCROLL_ROWS) * row_height(box)
    scroll_list:SetCanResizeWidth(true)
    scroll_list:SetCanResizeHeight(true)
    scroll_list:Resize(cards:Width(), cards:Height())
    local clip = find_uicomponent(scroll_list, LIST_CLIP)
    clip:SetCanResizeWidth(true)
    clip:SetCanResizeHeight(true)
    clip:Resize(box:Width(), height)
    local slider = find_uicomponent(scroll_list, SLIDER)
    slider:SetCanResizeHeight(true)
    slider:Resize(slider:Width(), height - 2 * SLIDER_ARROWS)
end

--- Moves a tooltip's unit cards into a scroll list in the vanilla list's place when they need more than `SCROLL_ROWS` rows, and hides the vanilla
--- list. When the game fills the tooltip again and a scroll list is already there, its old cards are hidden, not destroyed, as the game may still
--- hold them.
--- @param tooltip UIC The skill card's or level pip's tooltip.
local function scroll_cards(tooltip)
    local parts = find_uicomponent(tooltip, TOOLTIP_LIST)
    if not parts then
        return
    end
    local cards, index = shown_card_list(parts)
    -- A short list is skipped before its cards are counted, as this runs every `POLL_MS` for the whole hover.
    local fits = CARDS_PER_ROW * SCROLL_ROWS
    if not cards or cards:ChildCount() <= fits then
        return
    end
    local count = shown_count(cards)
    if count <= fits then
        return
    end
    local scroll_list = find_uicomponent(parts, NAME)
    local box = scroll_list and find_uicomponent(scroll_list, LIST_CLIP, LIST_BOX)
    if box then
        for i = 0, box:ChildCount() - 1 do
            UIComponent(box:Find(i)):SetVisible(false)
        end
    else
        scroll_list = UIComponent(parts:CreateComponent(NAME, SCROLL_LIST_LAYOUT))
        parts:Divorce(scroll_list:Address())
        parts:Adopt(scroll_list:Address(), index)
        box = find_uicomponent(scroll_list, LIST_CLIP, LIST_BOX)
    end
    for i = cards:ChildCount() - 1, 0, -1 do
        local card = UIComponent(cards:Find(i))
        if card:Visible() then
            cards:Divorce(card:Address())
            box:Adopt(card:Address(), 0)
        end
    end
    cards:SetVisible(false)
    size_list(scroll_list, box, cards, count)
    log(count .. " unit cards moved from a " .. cards:Width() .. "x" .. cards:Height() .. " px list into a " .. scroll_list:Width() .. "x" .. scroll_list:Height() .. " px one")
end

--- Scrolls the unit cards of the hovered skill card's or level pip's tooltip.
local function scroll_card_tooltip()
    local holder = find_uicomponent(core:get_ui_root(), PANEL, HOLDER)
    if not holder or not holder:Visible(true) then
        return
    end
    for _, id in ipairs(SKILL_TOOLTIPS) do
        local address = holder:Find(id, false)
        if address then
            scroll_cards(UIComponent(address))
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Polling

--- Scrolls the hovered skill card's or level pip's tooltip every `POLL_MS` while the panel is open, logging the first failure since it opened.
local function poll()
    if not panel_open then
        return
    end
    local ok, err = pcall(scroll_card_tooltip)
    if not ok and not failed then
        failed = true
        log("scroll_card_tooltip failed: " .. tostring(err))
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
