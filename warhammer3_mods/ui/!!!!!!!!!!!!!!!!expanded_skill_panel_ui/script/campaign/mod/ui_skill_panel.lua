--- Skill panel card boxes: our own box in place of the vanilla tooltip of chosen skill cards in the character panel's skill tree. Opt-in: no card
--- changes until a mod calls `UI_SKILL_PANEL.add_card_boxes()`. Other mods ship this file at the same path inside their own pack, so whichever pack
--- wins load order runs it.
---
--- The box shows a title, a text, the effects of an effect bundle drawn by the game's own effect list, and a foot under them. Like the game's tooltips
--- it locks once a card has been hovered for a moment, so the mouse can move onto it and read its effects' tooltips. The mod's
--- ui/campaign ui/character_details_panel_skills.twui.xml is separate: it is always on once its pack loads.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log, the component names and the callback name.
local NAME = "ui_skill_panel"

--- The character panel, and the child of it whose context is the character it shows. Read only.
local PANEL = "character_details_panel"
local PANEL_CONTEXT_HOLDER = "character_context_parent"

--- The vanilla tooltip the game builds inside a hovered skill card. The card's `layout_path` is ui3.pack ui/campaign ui/edict_tooltip.
local SKILL_TOOLTIP = "edict_tooltip"

--- Our box shown in place of the vanilla tooltip, with the layout it is made from and its title and text children.
local BOX = NAME .. "_box"
local BOX_LAYOUT = "ui/common ui/tooltip_centred_title_and_text"
local BOX_TITLE = "dy_title"
local BOX_TEXT = "dy_text"

--- Copy of the box's text made below its effect list, for the foot.
local BOX_FOOT = NAME .. "_foot"

--- The vanilla effect bundle tooltip, made only to move its effect list into the box. The list draws the effects of the `CcoEffectBundle` it is
--- given with the game's own icons and eye tooltips.
local BUNDLE = NAME .. "_bundle"
local BUNDLE_LAYOUT = "ui/common ui/tooltip_effect_bundle"
local EFFECT_LIST = "effect_list"

--- Top and bottom text padding in pixels of the foot. The text it is copied from has 10 above and below.
local FOOT_PAD = { 10, 0 }

--- The lock bar the game draws in its tooltips, the part of it set to the box's width, and the part that fills while a card is hovered. The bar is
--- its own UI root child laid on the box's bottom edge, as inside the box its layout stacked the bar under the text.
local BAR = NAME .. "_bar"
local BAR_LAYOUT = "ui/templates/stick_progress_bar"
local BAR_FRAME = "bar_extents_and_pos"
local BAR_FILL = "auto_resizing_comp"

--- Children of the fill shown while it fills and once the box is locked, the bar's height in pixels, and pixels from its top up to the box's bottom.
--- The fill's line is drawn 2 pixels below the bar's top.
local BAR_FILLING = "in_progress_comp"
local BAR_DONE = "completed_comp"
local BAR_H = 3
local BAR_LIFT = 5

--- Every part of the lock bar that is looked up and resized.
local BAR_PARTS = { BAR_FRAME, BAR_FILL, BAR_FILLING, BAR_DONE }

--- Gap in pixels kept between a card and its box.
local BOX_GAP = 8

--- Seconds a card is hovered before its box locks, and seconds a locked box stays after the mouse leaves it. These match the game's
--- `ui_tooltip_stick_delay` and `ui_tooltip_removal_delay` in preferences.script.txt.
local STICK_S = 0.35
local REMOVAL_S = 0.15

--- Name of the real-time callback that looks for a hovered card while the character panel is open.
local POLL_NAME = NAME .. "_poll"

--- Delay in milliseconds between looks for a hovered card, and how many looks pass between rebuilds of the cards' texts.
local POLL_MS = 20
local CARD_LOOKS = 15

--- Lowest draw priority of the box, and how far above the panel's own it draws.
local UI_PRIORITY = 200
local PANEL_PRIORITY_BONUS = 50

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- The registered card box sets, in the order they were added. Each is `{ id, show_for, tips }`.
local specs = {}

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- What each card's box shows, by skill key, from the shown set's `tips`. Cleared when the panel opens.
local card_tips = {}

--- Ids of the sets `card_tips` came from, joined with commas, so the log notes when they change. Nil when none.
local tips_from = nil

--- Names of this script's components registered as top-most, so each is unregistered before it is destroyed.
local topmost = {}

--- Our box: the component, false when it could not be made while this panel is open, or nil when it is not made yet.
local box = nil

--- The skill key and text the box shows, or nil while it is hidden.
local box_skill = nil
local box_text = nil

--- The vanilla effect list moved into the box, or nil when it could not be made.
local box_effects = nil

--- The box's title, text and foot copy. Made with the box.
local box_title = nil
local box_body = nil
local box_foot = nil

--- The box's lock bar parts by name, nil when it could not be made, its full width in pixels, and the width and state it was last given.
local bar = nil
local bar_full = 0
local bar_width = nil
local bar_done = nil

--- When the shown card's hover began, from `os.clock`, whether the box is locked, and when the mouse left a locked box (nil while on it).
local box_since = 0
local box_locked = false
local box_left = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI components

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- Runs a step and logs it when it fails: a failed box only leaves the vanilla tooltip.
--- @param what string The step, for the log.
--- @param step function The step.
local function logged(what, step)
    local ok, err = pcall(step)
    if not ok then
        log(what .. " failed: " .. tostring(err))
    end
end

--- The UI root, or nil when the UI is not there yet.
--- @returns UIC|nil The root.
local function ui_root()
    local ok, root = pcall(function()
        return core:get_ui_root()
    end)
    if ok and root then
        return root
    end
    return nil
end

--- A component's name, or nil when the handle is dead or not a component.
--- @param uic UIC|nil The component.
--- @returns string|nil The name.
local function component_id(uic)
    if not uic then
        return nil
    end
    local ok, id = pcall(function()
        return uic:Id()
    end)
    if ok and type(id) == "string" then
        return id
    end
    return nil
end

--- Wraps a component address only when it is the named component. `UIComponent(nil)` hands back the UI root, so a missing address is never wrapped.
--- @param address any The address from `Find` or `CreateComponent`.
--- @param name string The name the component must have.
--- @returns UIC|nil The component, or nil when the address is missing or names another component.
local function wrap_named(address, name)
    if not address then
        return nil
    end
    local uic = UIComponent(address)
    if component_id(uic) ~= name then
        return nil
    end
    return uic
end

--- Finds a named descendant of a component.
--- @param parent UIC|nil The component to search under.
--- @param name string The descendant's name.
--- @returns UIC|nil The descendant, or nil when not found.
local function find_named(parent, name)
    if not parent then
        return nil
    end
    local ok, address = pcall(function()
        return parent:Find(name, false)
    end)
    if not ok then
        return nil
    end
    return wrap_named(address, name)
end

--- Finds a direct child of a component with exactly this name.
--- @param parent UIC|nil The component to look under.
--- @param name string The child's name.
--- @returns UIC|nil The child, or nil when it does not exist.
local function find_child(parent, name)
    if not parent then
        return nil
    end
    local ok, count = pcall(function()
        return parent:ChildCount()
    end)
    if not ok or type(count) ~= "number" then
        return nil
    end
    for i = 0, count - 1 do
        local found, address = pcall(function()
            return parent:Find(i)
        end)
        local child = found and wrap_named(address, name)
        if child then
            return child
        end
    end
    return nil
end

--- Destroys one of this script's components under a parent if it exists. Nothing but a direct child with exactly this name is touched.
--- @param parent UIC|nil The parent it was made in.
--- @param name string The component's name.
--- @param why string Why, for the log.
local function destroy_child(parent, name, why)
    local uic = find_child(parent, name)
    if not uic then
        return
    end
    if topmost[name] then
        topmost[name] = nil
        logged("RemoveTopMost on " .. name, function()
            uic:RemoveTopMost()
        end)
    end
    local ok, err = pcall(function()
        uic:Destroy()
    end)
    log("destroyed " .. name .. " (" .. why .. ")" .. (ok and "" or (", error: " .. tostring(err))))
end

--- Creates one of this script's components under a parent and checks the game gave back exactly that component.
--- @param parent UIC|nil The parent.
--- @param name string The new component's name.
--- @param template string The layout file.
--- @returns UIC|nil The component, or nil when it could not be made.
local function create_child(parent, name, template)
    if not parent then
        log("create " .. name .. ": no parent")
        return nil
    end
    destroy_child(parent, name, "made again")
    local ok, address = pcall(function()
        return parent:CreateComponent(name, template)
    end)
    if not ok or not address then
        log("create " .. name .. " from " .. template .. " failed: " .. tostring(address))
        return nil
    end
    local made = wrap_named(address, name)
    if not made then
        log("create " .. name .. ": the game gave back " .. tostring(component_id(UIComponent(address))) .. ", so it is left alone")
    end
    return made
end

--- A component's position and size, read without changing it.
--- @param uic UIC The component.
--- @returns table|nil `{ x, y, w, h, visible }`, or nil when it cannot be read.
local function read_bounds(uic)
    local ok, x, y, w, h, visible = pcall(function()
        local px, py = uic:Position()
        local pw, ph = uic:Dimensions()
        return px, py, pw, ph, uic:Visible()
    end)
    if not ok or type(x) ~= "number" or type(w) ~= "number" then
        return nil
    end
    return { x = x, y = y, w = w, h = h, visible = visible }
end

--- The character the open panel shows, read from its context holder without changing anything.
--- @param panel UIC The character panel.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The character, or nil when it cannot be read.
local function panel_character(panel)
    local holder = find_named(panel, PANEL_CONTEXT_HOLDER)
    if not holder then
        return nil
    end
    local ok, id = pcall(function()
        return holder:GetContextObjectId("CcoCampaignCharacter")
    end)
    local cqi = ok and tonumber(id)
    return cqi and cm:get_character_by_cqi(cqi) or nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Box

--- Copies the box's text into its foot below the effect list, hidden and left out of mouse hits until the box locks.
--- @param text UIC The box's text.
--- @returns UIC|nil The copy, or nil when it could not be made.
local function make_foot(text)
    local ok, address = pcall(function()
        return text:CopyComponent(BOX_FOOT)
    end)
    if not ok or not address then
        log("box: CopyComponent " .. BOX_FOOT .. " failed: " .. tostring(address))
        return nil
    end
    local copy = UIComponent(address)
    copy:SetInteractive(false)
    logged("box: SetTextYOffset on " .. BOX_FOOT, function()
        copy:SetTextYOffset(FOOT_PAD[1], FOOT_PAD[2])
    end)
    copy:SetVisible(false)
    return copy
end

--- Makes the box's lock bar, hidden and set to the width of the box's text. Leaves `bar` nil when the game refuses any of it.
--- @param width number The width in pixels of the box's text.
--- @param priority number The box's draw priority.
local function make_bar(width, priority)
    local root = create_child(ui_root(), BAR, BAR_LAYOUT)
    if not root then
        return
    end
    local parts = { root = root }
    for _, name in ipairs(BAR_PARTS) do
        parts[name] = find_named(root, name)
        if not parts[name] then
            log("box: no " .. name .. " in " .. BAR_LAYOUT)
            return
        end
    end
    local ok, err = pcall(function()
        root:SetInteractive(false)
        root:SetCanResizeWidth(true)
        root:Resize(width, BAR_H)
        for _, name in ipairs(BAR_PARTS) do
            parts[name]:SetCanResizeWidth(true)
        end
        parts[BAR_FRAME]:Resize(width, BAR_H)
        root:PropagatePriority(priority)
        root:RegisterTopMost()
        topmost[BAR] = true
        root:SetVisible(false)
    end)
    log("box: lock bar " .. (ok and ("made " .. width .. " wide") or ("failed: " .. tostring(err))))
    if ok then
        bar, bar_full = parts, width
    end
end

--- Fills the box's lock bar from its middle out, as the game's tooltips do while they wait to lock.
--- @param progress number How full, from 0 to 1.
--- @param done boolean True once the box is locked.
local function fill_bar(progress, done)
    if not bar then
        return
    end
    local width = math.max(1, math.floor(bar_full * math.min(1, progress) + 0.5))
    if width == bar_width and done == bar_done then
        return
    end
    bar_width, bar_done = width, done
    logged("box: lock bar fill", function()
        for _, name in ipairs({ BAR_FILL, BAR_FILLING, BAR_DONE }) do
            bar[name]:Resize(width, BAR_H)
        end
        bar[BAR_FILLING]:SetVisible(not done)
        bar[BAR_DONE]:SetVisible(done)
    end)
end

--- Makes a vanilla effect bundle tooltip in the box, moves its effect list under the box and removes the rest, so the list sits below the box's
--- text. Read only of the game's data: the list only draws the bundle it is given later.
--- @param parent UIC The box.
--- @param bounds table|nil Bounds of the box's text, whose width the list takes.
--- @returns UIC|nil The effect list, or nil when it could not be made.
local function make_effect_list(parent, bounds)
    local bundle = create_child(parent, BUNDLE, BUNDLE_LAYOUT)
    local list = bundle and find_named(bundle, EFFECT_LIST)
    if not list then
        log("box: no " .. EFFECT_LIST .. " in " .. BUNDLE_LAYOUT)
        destroy_child(parent, BUNDLE, "it has no effect list")
        return nil
    end
    local ok, err = pcall(function()
        parent:Adopt(list:Address())
        if bounds then
            local _, h = list:Dimensions()
            list:SetCanResizeWidth(true)
            list:Resize(bounds.w, h)
        end
    end)
    destroy_child(parent, BUNDLE, "its effect list was moved into the box")
    log("box: vanilla effect list " .. (ok and "moved in" or ("failed: " .. tostring(err))))
    return ok and list or nil
end

--- Makes the box under the UI root, drawn over the character panel and left out of mouse hits so it never takes the hover from the card. Its text
--- is copied once for the foot under the vanilla effect list, then the lock bar goes last.
--- @param panel UIC The character panel, whose priority the box draws above.
--- @returns UIC|nil The box, or nil when it could not be made.
local function make_box(panel)
    local ok, panel_priority = pcall(function()
        return panel:Priority()
    end)
    local priority = (ok and type(panel_priority) == "number") and math.max(UI_PRIORITY, panel_priority + PANEL_PRIORITY_BONUS) or UI_PRIORITY
    local made = create_child(ui_root(), BOX, BOX_LAYOUT)
    if not made then
        return nil
    end
    made:SetInteractive(false)
    local title, text = find_named(made, BOX_TITLE), find_named(made, BOX_TEXT)
    if not title or not text then
        log("box: no " .. (title and BOX_TEXT or BOX_TITLE) .. " in " .. BOX_LAYOUT)
        return nil
    end
    title:SetInteractive(false)
    text:SetInteractive(false)
    -- The layout centres its text, while the skill tooltips read from the left.
    logged("box: left align", function()
        text:SetTextHAlign("left")
    end)
    local bounds = read_bounds(text)
    box_effects = make_effect_list(made, bounds)
    box_foot = make_foot(text)
    if not box_foot then
        return nil
    end
    box_title, box_body = title, text
    made:PropagatePriority(priority)
    made:RegisterTopMost()
    topmost[BOX] = true
    made:SetVisible(false)
    -- Made after the box is drawn on top, so the bar draws over the box's frame.
    make_bar(bounds and bounds.w or 0, priority)
    return made
end

--- Sets the box's texts, and points the vanilla effect list at the tip's bundle.
--- @param tip table What the box shows.
local function fill_box(tip)
    box_title:SetStateText(tip.title, "")
    box_body:SetStateText(tip.text, "")
    if box_effects and tip.bundle then
        logged("box: effect list context " .. tip.bundle, function()
            box_effects:SetContextObject(cco("CcoEffectBundle", tip.bundle))
        end)
    end
    local foot = tip.foot or ""
    if foot ~= "" then
        box_foot:SetStateText(foot, "")
    end
    box_foot:SetVisible(foot ~= "")
end

--- Shows the box with a card's text, just below the card or just above it when it would leave the screen.
--- @param panel UIC The character panel.
--- @param card UIC The hovered card.
--- @param skill string The card's skill key.
local function show_box(panel, card, skill)
    if box == nil then
        box = make_box(panel) or false
    end
    if not box then
        return
    end
    local tip = card_tips[skill]
    local text = tip.title .. "||" .. tip.text .. "\n" .. (tip.bundle or "") .. "\n" .. (tip.foot or "")
    if box_text ~= text then
        box_text = text
        fill_box(tip)
    end
    if box_skill ~= skill then
        box_skill = skill
        box:SetVisible(true)
        if bar then
            bar.root:SetVisible(true)
        end
    end
    -- Placed on every look, as the box may only take its full height a frame after its text is set.
    local bounds, card_bounds = read_bounds(box), read_bounds(card)
    if not bounds or not card_bounds then
        return
    end
    local screen_w, screen_h = core:get_screen_resolution()
    local x = math.max(0, math.min(card_bounds.x, screen_w - bounds.w))
    local y = card_bounds.y + card_bounds.h + BOX_GAP
    if y + bounds.h > screen_h then
        y = math.max(0, card_bounds.y - bounds.h - BOX_GAP)
    end
    if x ~= bounds.x or y ~= bounds.y then
        log("box: " .. skill .. " placed at " .. x .. "," .. y .. ", size " .. bounds.w .. "x" .. bounds.h)
        box:MoveTo(x, y)
    end
    local bar_bounds = bar and read_bounds(bar.root)
    if bar_bounds then
        local bar_x, bar_y = x + math.floor((bounds.w - bar_full) / 2), y + bounds.h - BAR_LIFT
        if bar_x ~= bar_bounds.x or bar_y ~= bar_bounds.y then
            bar.root:MoveTo(bar_x, bar_y)
        end
    end
end

--- Sets whether the box and its texts take the mouse, which they do only while the box is locked, so its effects' tooltips show then.
--- @param on boolean True to take the mouse.
local function set_box_interactive(on)
    box:SetInteractive(on)
    box_title:SetInteractive(on)
    box_body:SetInteractive(on)
    box_foot:SetInteractive(on)
end

--- Hides the box if it is shown, and unlocks it.
--- @param why string Why, for the log.
local function hide_box(why)
    if box_skill then
        log("box: hid " .. box_skill .. " (" .. why .. ")")
        box:SetVisible(false)
        if bar then
            bar.root:SetVisible(false)
        end
        if box_locked then
            set_box_interactive(false)
        end
    end
    box_skill, box_locked, box_left = nil, false, nil
    bar_width, bar_done = nil, nil
end

--- Removes the box and its lock bar if made, and forgets them, so the next hover makes them again.
--- @param why string Why, for the log.
local function remove_box(why)
    hide_box(why)
    destroy_child(ui_root(), BOX, why)
    destroy_child(ui_root(), BAR, why)
    box, box_text, box_title, box_body, box_foot, bar, box_effects = nil, nil, nil, nil, nil, nil, nil
end

--- Whether the mouse is over the box or anything in it.
--- @returns boolean True when it is.
local function mouse_over_box()
    local ok, over = pcall(function()
        return box:IsMouseOverChildren()
    end)
    if not ok then
        log("box: IsMouseOverChildren failed: " .. tostring(over))
        return false
    end
    return over == true
end

--- Shows the box in place of the vanilla tooltip while a card with a tip is hovered. Like the game's tooltips, the box locks once the card has been
--- hovered for `STICK_S`, and a locked box stays while the mouse is over it, closing `REMOVAL_S` after the mouse leaves both. The vanilla tooltip
--- is hidden, as the game keeps undoing a see-through one while it fades it in. The game removes it when the card hover ends.
--- @param panel UIC The character panel.
local function update_box(panel)
    local tooltip = find_named(panel, SKILL_TOOLTIP)
    local card, skill = nil, nil
    if tooltip then
        -- The game builds the tooltip inside the hovered card, and the card's parent entry is named after the skill key.
        card = UIComponent(tooltip:Parent())
        skill = component_id(UIComponent(card:Parent()))
    end
    if skill and card_tips[skill] then
        if tooltip:Visible() then
            tooltip:SetVisible(false)
        end
        if box_skill ~= skill then
            hide_box("another card hovered")
            box_since = os.clock()
        end
        box_left = nil
        show_box(panel, card, skill)
        if box and not box_locked then
            local held = os.clock() - box_since
            fill_bar(held / STICK_S, held >= STICK_S)
            if held >= STICK_S then
                box_locked = true
                set_box_interactive(true)
                log("box: locked " .. skill)
            end
        end
        return
    end
    if tooltip then
        hide_box("another skill hovered")
        return
    end
    if not box_skill then
        return
    end
    if box_locked and mouse_over_box() then
        if box_left then
            log("box: mouse on the locked box of " .. box_skill)
        end
        box_left = nil
        return
    end
    box_left = box_left or os.clock()
    if not box_locked or os.clock() - box_left >= REMOVAL_S then
        hide_box(box_locked and "mouse left the locked box" or "vanilla tooltip gone")
    end
end

--- Rebuilds the cards' tips from every set that shows for the panel's character. A skill two sets both fill keeps the box of the one added first.
--- @param panel UIC The character panel.
local function update_tips(panel)
    local character = panel_character(panel)
    local tips, from = {}, {}
    for _, spec in ipairs(specs) do
        local ok, wanted = pcall(spec.show_for, character)
        if not ok then
            log(spec.id .. " show_for raised: " .. tostring(wanted))
        elseif wanted == true then
            local built, set = pcall(spec.tips, character)
            if not built then
                log(spec.id .. " tips raised: " .. tostring(set))
            elseif type(set) == "table" then
                for skill, tip in pairs(set) do
                    if tips[skill] == nil then
                        tips[skill] = tip
                    end
                end
            end
            table.insert(from, spec.id)
        end
    end
    local ids = #from > 0 and table.concat(from, ", ") or nil
    if ids and ids ~= tips_from then
        log("cards of cqi " .. (character and character:command_queue_index() or "none") .. " use the boxes of " .. ids)
    end
    card_tips, tips_from = tips, ids
end

--- While the character panel is open, looks for a hovered card every `POLL_MS` and rebuilds the cards' tips every `CARD_LOOKS` of those looks.
--- Removes the box once the panel closes.
--- @param looks number Looks made since the panel opened.
local function poll(looks)
    if not panel_open then
        remove_box("the character panel closed")
        return
    end
    logged("card box", function()
        local panel = find_named(ui_root(), PANEL)
        if panel then
            if looks % CARD_LOOKS == 0 then
                update_tips(panel)
            end
            if next(card_tips) or box_skill then
                update_box(panel)
            end
        end
    end)
    cm:real_callback(function()
        poll(looks + 1)
    end, POLL_MS, POLL_NAME)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
    NAME .. "_panel_opened",
    "PanelOpenedCampaign",
    function(context)
        return #specs > 0 and tostring(context.string) == PANEL
    end,
    function()
        panel_open = true
        -- The panel opens twice in a row, so any running look is stopped first to keep a single one.
        cm:remove_real_callback(POLL_NAME)
        card_tips, tips_from = {}, nil
        remove_box("the character panel opened")
        poll(0)
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

core:add_listener(
    NAME .. "_turn_end",
    "FactionTurnEnd",
    function(context)
        return context:faction():name() == cm:get_local_faction_name(true)
    end,
    function()
        panel_open = false
    end,
    true
)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- API

-- ui_skill_panel_vscroll.lua fills the same table, and either file may load first.
UI_SKILL_PANEL = UI_SKILL_PANEL or {}

--- Adds a set of card boxes. Call it once, at first tick or later. Every set whose `show_for` is true for the panel's character is used, and
--- a skill two sets both fill keeps the box of the one added first. `spec` fields: `id` (string), `show_for(character)` (true when its boxes
--- show for the character, which may be nil), and `tips(character)` returning skill key -> `{ title, text, foot, bundle }`. Texts are
--- already localised and use the game's markup. `foot` and `bundle` may be nil. The box is only filled again when one of them changes.
--- @param spec table The set.
--- @returns boolean True when it was added.
UI_SKILL_PANEL.add_card_boxes = function(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.show_for) ~= "function" or type(spec.tips) ~= "function" then
        log("add_card_boxes refused: the spec needs an id, show_for and tips")
        return false
    end
    for _, known in ipairs(specs) do
        if known.id == spec.id then
            log("add_card_boxes " .. spec.id .. " refused: already added")
            return false
        end
    end
    table.insert(specs, spec)
    log("added card boxes " .. spec.id)
    return true
end

--- Removes a set of card boxes added with `add_card_boxes`. Its boxes go once the cards' tips are next rebuilt.
--- @param id string The set's id.
--- @returns boolean True when a set was removed.
UI_SKILL_PANEL.remove_card_boxes = function(id)
    for i, known in ipairs(specs) do
        if known.id == id then
            table.remove(specs, i)
            log("removed card boxes " .. id)
            return true
        end
    end
    return false
end
