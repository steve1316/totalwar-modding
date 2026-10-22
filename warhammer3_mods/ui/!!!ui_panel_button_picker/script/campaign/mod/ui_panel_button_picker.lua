--- Panel button picker: an icon button for one kind of character, with a picker of icon options in columns above it. Opt-in: nothing shows until a
--- mod calls `UI_PANEL_BUTTON_PICKER.register()`. Other mods ship this file at the same path inside their own pack, so whichever pack wins load order
--- runs it.
---
--- A registered button shows while the character panel shows a matching character of the local player, and while one is selected on the campaign map
--- with no full-screen panel open. It is a child of a vanilla row: the character panel's bottom-right buttons, or the hover strip over the selected
--- character's unit card. The picker options are direct children of the UI root. A pick goes through a UI trigger, so every client runs the mod's
--- `apply`. The script only ever changes or destroys a component it found by its own unique name.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log and in the listener and callback names.
local NAME = "ui_panel_button_picker"

--- Start of every component name this script makes: each button is the prefix and its id, each option adds its column and place.
local PREFIX = "ui_pbp_"

--- Start of the UI trigger string that carries a pick to every client, followed by the id, cqi, column key and option key.
local TRIGGER_PREFIX = "ui_pbp:"

--- Vanilla square icon button layout (ui3.pack). Its image 0 is the icon.
local BUTTON_TEMPLATE = "ui/templates/square_medium_button"

--- Image index of the icon in `BUTTON_TEMPLATE`.
local BUTTON_ICON_INDEX = 0

--- State of an option already in use. It is one of `BUTTON_TEMPLATE`'s states (active, down, down_off, hover, inactive), the pressed look.
local CURRENT_STATE = "down"

--- Pixels between picker options.
local OPTION_GAP = 4

--- Pixels between picker columns.
local COLUMN_GAP = 8

--- Lowest draw priority of the buttons and picker, so they sit above the campaign HUD.
local UI_PRIORITY = 200

--- Name and delay in milliseconds of the one-shot real-time callback that re-checks which buttons show, so the HUD and the panel list have settled.
local REFRESH_NAME = NAME .. "_refresh"
local REFRESH_MS = 300

--- Name of the one-shot real-time callback that runs a click on this script's components.
local CLICK_NAME = NAME .. "_click"

--- Delay of that callback in milliseconds. Making or destroying root components while the game still handles the click broke every script's UI checks
--- and crashed the game, so clicks only schedule their work.
local CLICK_MS = 50

--- Name of the one-shot real-time callback that selects a character again after a pick, and the delay in milliseconds after clearing the selection.
local RESELECT_NAME = NAME .. "_reselect"
local RESELECT_MS = 100

--- Panels that open under or next to the buttons without hiding them. Vanilla blocking panels and `events` hide them straight away.
local KEEP_BUTTON_PANELS = {
    --- The character panel, which the buttons sit on while it shows a matching character.
    character_details_panel = true,
    --- The selected army's unit cards.
    units_panel = true,
    --- The recruitment options bar of the selected army.
    recruitment_options = true,
    --- The selected settlement's panel.
    settlement_panel = true,
}

--- The character panel.
local PANEL = "character_details_panel"

--- Child of the panel whose context is the character it shows. Read only.
local PANEL_CONTEXT_HOLDER = "character_context_parent"

--- Path from the panel to its bottom-right row of square buttons (replace, event feed, rename). Panel buttons are made in it.
local PANEL_ROW_PATH = { "character_context_parent", "holder_br", "bottom_buttons" }

--- The same row as `PANEL_ROW_PATH`, from the UI root: `PANEL` followed by `PANEL_ROW_PATH`.
local ROW_PATH = { PANEL }
for _, name in ipairs(PANEL_ROW_PATH) do
    table.insert(ROW_PATH, name)
end

--- Path from the UI root to the button strip over the hovered unit card (Disband, Rename). The game shows it and moves it on hover. Map buttons are
--- made in it while a matching character is selected on his own.
local STRIP_PATH = { "units_panel", "main_units_panel", "button_group_unit" }

--- Draw priority added on top of the panel's own, so the buttons and picker draw over it.
local PANEL_PRIORITY_BONUS = 50

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- The registered buttons, in the order they were registered. Each is `{ spec, name, cqi, path, last_decision }`.
local buttons = {}

--- Registered buttons by id.
local by_id = {}

--- CQI of the selected character, or nil when no character is selected.
local selected_cqi = nil

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- The open picker: its button, the character's cqi, and option component name -> `{ column, key, enabled }`. Nil when it is closed.
local picker = nil

--- Names of this script's components registered as top-most, so each is unregistered before it is destroyed. Without top-most the panel's own
--- bottom-right buttons (Salvage) drew over the lowest option.
local topmost = {}

--- Draw priority of the shown buttons. The picker options use the same.
local ui_priority = UI_PRIORITY

--- CQI of a character picked while the character panel was open, so he is selected again once it closes. Nil when none waits.
local pending_reselect = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- Whether a character belongs to the local player's faction.
--- @param character CHARACTER_SCRIPT_INTERFACE|nil|boolean The character, or nil or false when there is none.
--- @returns boolean True for the local player's character.
local function is_local(character)
    if not character then
        return false
    end
    return character:faction():name() == cm:get_local_faction_name(true)
end

--- Runs a mod's callback and logs it when it raises.
--- @param button table The registered button.
--- @param what string The callback's name in the spec.
--- @param ... any What the callback is given.
--- @returns boolean True when it ran.
--- @returns any What it returned.
local function call_spec(button, what, ...)
    local ok, result = pcall(button.spec[what], ...)
    if not ok then
        log(button.spec.id .. " " .. what .. " raised: " .. tostring(result))
    end
    return ok, result
end

--- Whether a registered button is for a character, which must be the local player's.
--- @param button table The registered button.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @returns boolean True when the button shows for him.
local function is_for(button, character)
    local ok, result = call_spec(button, "is_for", character)
    return ok and result == true
end

--- Whether a registered button is locked for a character. A button with no `locked` is never locked.
--- @param button table The registered button.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @returns boolean True when it is greyed out.
local function is_locked(button, character)
    return button.spec.locked ~= nil and select(2, call_spec(button, "locked", character)) == true
end

--- Whether an event's faction is the local player's.
--- @param context table The event context.
--- @returns boolean True when it is.
local function is_local_faction(context)
    return context:faction():name() == cm:get_local_faction_name(true)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI components

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

--- Follows a path of names down from a component.
--- @param parent UIC|nil The component to start from.
--- @param path table The names, each searched under the previous one.
--- @returns UIC|nil The last component, or nil when any step is missing.
local function find_path(parent, path)
    local uic = parent
    for _, name in ipairs(path) do
        uic = find_named(uic, name)
        if not uic then
            return nil
        end
    end
    return uic
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
--- @returns boolean True when a component was destroyed.
local function destroy_child(parent, name, why)
    local uic = find_child(parent, name)
    if not uic then
        return false
    end
    if topmost[name] then
        topmost[name] = nil
        local removed, remove_err = pcall(function()
            uic:RemoveTopMost()
        end)
        if not removed then
            log("RemoveTopMost on " .. name .. " failed: " .. tostring(remove_err))
        end
    end
    local ok, err = pcall(function()
        uic:Destroy()
    end)
    log("destroyed " .. name .. " (" .. why .. ")" .. (ok and "" or (", error: " .. tostring(err))))
    return ok
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
    if not ok then
        log("create " .. name .. " from " .. template .. " raised: " .. tostring(address))
        return nil
    end
    if not address then
        log("create " .. name .. " from " .. template .. " returned nothing")
        return nil
    end
    local id = component_id(UIComponent(address))
    log("created " .. name .. " from " .. template .. ", got Id " .. tostring(id))
    if id ~= name then
        log("create " .. name .. ": the game gave back " .. tostring(id) .. ", so it is left alone")
        return nil
    end
    return UIComponent(address)
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

--- The vanilla row a button was made in, found again by name at its path.
--- @param button table The registered button.
--- @returns UIC|nil The row, or nil when the button is not made or the row is gone.
local function button_parent(button)
    if not button.path then
        return nil
    end
    return find_path(ui_root(), button.path)
end

--- A registered button's component, found again by name under its parent, since the game may rebuild the parent.
--- @param button table The registered button.
--- @returns UIC|nil The component, or nil when it does not exist.
local function find_button(button)
    return find_child(button_parent(button), button.name)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picker

--- Closes the picker if it is open.
--- @param why string Why, for the log.
local function close_picker(why)
    if not picker then
        return
    end
    local id = picker.button.spec.id
    for name in pairs(picker.options) do
        destroy_child(ui_root(), name, why)
    end
    picker = nil
    log(id .. " picker closed: " .. why)
end

--- Adds one picker option: an icon button made from the same layout as the buttons, with its label in the tooltip.
--- @param name string The option's component name.
--- @param option table The option from the mod's `columns`: `key`, `icon`, `tooltip` and `state`.
--- @returns UIC|nil The option, or nil when it could not be made.
local function add_option(name, option)
    local uic = create_child(ui_root(), name, BUTTON_TEMPLATE)
    if not uic then
        return nil
    end
    local ui_state = option.state == "current" and CURRENT_STATE or option.state == "blocked" and "inactive" or "active"
    local ok, err = pcall(function()
        uic:SetImagePath(option.icon, BUTTON_ICON_INDEX)
        uic:SetTooltipText(option.tooltip, true)
        uic:SetState(ui_state)
        uic:PropagatePriority(ui_priority)
        uic:RegisterTopMost()
        topmost[name] = true
    end)
    if not ok then
        log("option " .. name .. " set up failed: " .. tostring(err))
        return nil
    end
    return uic
end

--- Opens a button's picker above it: one column per column the mod gives, left to right from the button. Empty columns are left out.
--- @param button table The registered button.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
local function open_picker(button, character)
    close_picker("reopened")
    local id = button.spec.id
    local uic = find_button(button)
    if not uic then
        log(id .. " picker: the button is gone, not opening")
        return
    end
    local listed, columns = call_spec(button, "columns", character)
    if not listed or type(columns) ~= "table" then
        return
    end
    local cqi = character:command_queue_index()
    -- Registered before the options are made, so `close_picker` removes them if a later step fails.
    picker = { button = button, cqi = cqi, options = {} }
    local made = {}
    for column_index, column in ipairs(columns) do
        local stack, shown = {}, {}
        for option_index, option in ipairs(column.options) do
            local name = button.name .. "_" .. column_index .. "_" .. option_index
            picker.options[name] = { column = column.key, key = option.key, enabled = option.state == "pick" }
            local option_uic = add_option(name, option)
            if not option_uic then
                close_picker("option " .. column.key .. " " .. option.key .. " could not be made")
                return
            end
            table.insert(stack, option_uic)
            table.insert(shown, option.key .. "=" .. option.state)
        end
        table.insert(made, stack)
        log(id .. " picker cqi " .. cqi .. " " .. column.key .. ": " .. table.concat(shown, ", "))
    end
    -- Each column stacks upward from just above the button.
    local ok, err = pcall(function()
        local button_x, button_y = uic:Position()
        local size, height = uic:Dimensions()
        local x = button_x
        for _, stack in ipairs(made) do
            if #stack > 0 then
                for i, option_uic in ipairs(stack) do
                    option_uic:MoveTo(x, math.max(0, button_y - (#stack - i + 1) * (height + OPTION_GAP)))
                end
                x = x + size + COLUMN_GAP
            end
        end
        log(id .. " picker opened for cqi " .. cqi .. ", button at " .. button_x .. "," .. button_y)
    end)
    if not ok then
        close_picker("layout failed: " .. tostring(err))
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Buttons

--- Logs a show or hide decision. A check started by a click inside the character panel logs only when the decision differs from the last one.
--- @param button table The registered button.
--- @param why string What asked for the check.
--- @param outcome string What was decided and why.
local function note_decision(button, why, outcome)
    local from_click = string.sub(why, 1, 9) == "click on "
    if from_click and outcome == button.last_decision then
        return
    end
    button.last_decision = outcome
    log(button.spec.id .. " button " .. outcome .. " (check: " .. why .. ")")
end

--- Removes a button and its picker. A button is looked up by name under its row, so a row the game rebuilt is left alone.
--- @param button table The registered button.
--- @param why string Why, for the log.
local function hide_button(button, why)
    if picker and picker.button == button then
        close_picker(why)
    end
    destroy_child(button_parent(button), button.name, why)
    button.cqi = nil
    button.path = nil
end

--- Removes a button and its picker and logs the decision.
--- @param button table The registered button.
--- @param why string What asked for it.
--- @param reason string Why it is hidden.
local function set_hidden(button, why, reason)
    hide_button(button, reason)
    note_decision(button, why, "hidden: " .. reason)
end

--- Removes every button and the picker and logs each decision.
--- @param why string What asked for it.
--- @param reason string Why they are hidden.
local function hide_all(why, reason)
    for _, button in ipairs(buttons) do
        set_hidden(button, why, reason)
    end
end

--- The open character panel, found read only by its name.
--- @returns UIC|nil The panel, or nil when it is not there or hidden.
local function find_panel()
    local panel = find_named(ui_root(), PANEL)
    local bounds = panel and read_bounds(panel)
    if not bounds or not bounds.visible then
        return nil
    end
    return panel
end

--- The character the open panel shows, read from its context holder without changing anything.
--- @param panel UIC The character panel.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The character, or nil when it cannot be read.
--- @returns string What was seen, for the log.
local function panel_character(panel)
    local holder = find_named(panel, PANEL_CONTEXT_HOLDER)
    if not holder then
        return nil, "the panel has no " .. PANEL_CONTEXT_HOLDER
    end
    local ok, id = pcall(function()
        return holder:GetContextObjectId("CcoCampaignCharacter")
    end)
    local cqi = ok and tonumber(id)
    if not cqi then
        return nil, "the panel shows no readable character (" .. tostring(id) .. ")"
    end
    local character = cm:get_character_by_cqi(cqi)
    if not character then
        return nil, "the panel shows cqi " .. cqi .. ", which is not found"
    end
    return character, "the panel shows " .. character:character_subtype_key() .. " cqi " .. cqi
end

--- Lays the row out again when a button sits on a shown sibling.
--- @param parent UIC The row the button is in.
--- @param uic UIC The button.
--- @returns string The button's spot, for the log.
local function check_row_layout(parent, uic)
    local own = read_bounds(uic)
    if not own then
        return "unreadable spot"
    end
    local own_id = component_id(uic)
    local overlap = nil
    local ok, count = pcall(function()
        return parent:ChildCount()
    end)
    for i = 0, (ok and type(count) == "number") and count - 1 or -1 do
        local found, address = pcall(function()
            return parent:Find(i)
        end)
        local child = found and address and UIComponent(address)
        local id = component_id(child)
        if id and id ~= own_id then
            local bounds = read_bounds(child)
            if bounds and bounds.visible and bounds.x == own.x and bounds.y == own.y then
                overlap = id
            end
        end
    end
    if overlap then
        local laid, err = pcall(function()
            parent:Layout()
        end)
        if not laid then
            log("Layout failed: " .. tostring(err))
        end
        own = read_bounds(uic) or own
    end
    return own.x .. "," .. own.y
end

--- The selected army's button strip over the hovered unit card, read only. The strip itself is hidden until a card is hovered, so only the
--- units panel has to be shown.
--- @returns UIC|nil The strip, or nil when the units panel is missing or hidden.
local function find_strip()
    local units = find_named(ui_root(), STRIP_PATH[1])
    local bounds = units and read_bounds(units)
    if not bounds or not bounds.visible then
        return nil
    end
    return find_path(ui_root(), STRIP_PATH)
end

--- Makes or updates a button for a character inside a vanilla row: the character panel's bottom-right row, or the unit card hover strip on the map.
--- The row's layout places it, so it is never moved, raised or made top-most. It is found by name first, so there is never a second copy.
--- @param button table The registered button.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @param panel UIC|nil The character panel when the button goes on it, or nil for the map strip.
--- @param why string What asked for the check, for the log.
local function show_button(button, character, panel, why)
    local cqi = character:command_queue_index()
    if picker and picker.button == button and picker.cqi ~= cqi then
        close_picker("another character shown")
    end
    local path = panel and ROW_PATH or STRIP_PATH
    local where = path[#path]
    if button.path ~= path then
        hide_button(button, "moved to " .. where)
    end
    local parent = panel and find_path(panel, PANEL_ROW_PATH) or find_strip()
    if not parent then
        set_hidden(button, why, where .. " is missing or hidden")
        return
    end
    local priority = UI_PRIORITY
    if panel then
        local ok, panel_priority = pcall(function()
            return panel:Priority()
        end)
        if ok and type(panel_priority) == "number" then
            priority = math.max(priority, panel_priority + PANEL_PRIORITY_BONUS)
        end
    end
    local uic = find_child(parent, button.name) or create_child(parent, button.name, BUTTON_TEMPLATE)
    if not uic then
        set_hidden(button, why, "the button could not be made in " .. where)
        return
    end
    button.path = path
    local spec = button.spec
    local locked = is_locked(button, character)
    local _, tooltip = call_spec(button, "tooltip", character)
    local ok, result = pcall(function()
        uic:SetImagePath(spec.icon, BUTTON_ICON_INDEX)
        uic:SetState(locked and "inactive" or "active")
        uic:SetTooltipText(tostring(tooltip or ""), true)
        uic:SetVisible(true)
        return check_row_layout(parent, uic)
    end)
    if not ok then
        set_hidden(button, why, "button set up failed: " .. tostring(result))
        return
    end
    button.cqi = cqi
    ui_priority = priority
    note_decision(button, why, "shown for cqi " .. cqi .. " in " .. where .. " at " .. result .. ", picker priority " .. priority
        .. (locked and ", locked" or ""))
end

--- Names of the open blocking panels and the event panel, read from the vanilla campaign UI manager.
--- @param ignore string|nil A panel to leave out.
--- @returns string|nil The names joined by commas, or nil when none is open.
local function covering_panels(ignore)
    local ok, names = pcall(function()
        local manager = cm:get_campaign_ui_manager()
        local found = {}
        if type(manager.campaign_ui_panels_blocking_open) == "table" then
            for name, is_open in pairs(manager.campaign_ui_panels_blocking_open) do
                if is_open and name ~= ignore then
                    table.insert(found, name)
                end
            end
        else
            local name = manager:get_open_blocking_panel()
            if name and name ~= ignore then
                table.insert(found, name)
            end
        end
        table.sort(found)
        return found
    end)
    if not ok or #names == 0 then
        return nil
    end
    return table.concat(names, ", ")
end

--- Whether a panel hides the buttons the moment it opens: a vanilla blocking panel other than the keep panels.
--- @param panel string The panel name.
--- @returns boolean True when it hides the buttons.
local function hides_on_open(panel)
    if KEEP_BUTTON_PANELS[panel] then
        return false
    end
    local ok, blocking = pcall(function()
        return cm:get_campaign_ui_manager().campaign_ui_panels_blocking_lookup[panel]
    end)
    return ok and blocking == true
end

--- The local character the buttons may show for: the one the open character panel shows, or the one selected on the map with no panel over it.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The character, or nil when no button may show.
--- @returns UIC|nil The character panel when the buttons go on it, or nil for the map strip.
--- @returns string What was seen, or why no button may show, for the log.
local function find_target()
    if panel_open then
        local panel = find_panel()
        if not panel then
            return nil, nil, "the character panel is open but could not be read"
        end
        local character, seen = panel_character(panel)
        if not is_local(character) then
            return nil, nil, seen .. (character and ", not of the local faction" or "")
        end
        local over = covering_panels(PANEL)
        if over then
            return nil, nil, seen .. ", but " .. over .. " is open over it"
        end
        return character, panel, seen
    end
    local character = selected_cqi and cm:get_character_by_cqi(selected_cqi)
    if not character then
        return nil, nil, selected_cqi and ("selected cqi " .. selected_cqi .. " is not found") or "nothing selected"
    end
    local seen = "selected " .. character:character_subtype_key() .. " cqi " .. selected_cqi
    if not is_local(character) then
        return nil, nil, seen .. ", not of the local faction"
    end
    local over = covering_panels(nil)
    if over then
        return nil, nil, seen .. ", but " .. over .. " is open"
    end
    if character:is_embedded_in_military_force() then
        -- The hover strip is shared by every card of the army, so an embedded character gets no strip button.
        return nil, nil, seen .. " is embedded, and the unit card strip is shared by the whole army"
    end
    return character, nil, seen
end

--- Shows each button whose mod wants it for the local character the panel shows or the map has selected, and hides the rest.
--- @param why string What asked for the check, for the log.
local function refresh(why)
    local character, panel, seen = find_target()
    for _, button in ipairs(buttons) do
        if not character then
            set_hidden(button, why, seen)
        elseif not is_for(button, character) then
            set_hidden(button, why, seen .. ", not for this button")
        else
            show_button(button, character, panel, why)
        end
    end
end

--- Runs a UI step and, if it raises, logs it and removes this script's components.
--- @param what string The step, for the log.
--- @param step function The step.
local function guarded(what, step)
    local ok, err = pcall(step)
    if not ok then
        log(what .. " failed: " .. tostring(err))
        pcall(hide_all, what, what .. " failed")
    end
end

--- Checks the buttons once after a short delay, so the HUD and the open panel list have settled. A newer request replaces an older one.
--- @param why string What asked for the check, for the log.
local function schedule_refresh(why)
    if #buttons == 0 then
        return
    end
    cm:remove_real_callback(REFRESH_NAME)
    cm:real_callback(function()
        guarded("refresh", function()
            refresh(why)
        end)
    end, REFRESH_MS, REFRESH_NAME)
end

--- Runs a click's UI work once the game has finished handling the click. A newer click replaces an older one that has not run yet.
--- @param what string The step, for the log.
--- @param step function The step.
local function after_click(what, step)
    cm:remove_real_callback(CLICK_NAME)
    cm:real_callback(function()
        guarded(what, step)
    end, CLICK_MS, CLICK_NAME)
end

--- Sends `Select` for a character without clearing the selection first. After a pick from the unit card strip it refreshes the map card while he is
--- still selected: clearing closed the units panel and rebuilt the strip, which then sat one button low until the mouse moved. `reselect` calls it
--- once the selection is cleared.
--- @param cqi number The character's command queue index.
local function select_again(cqi)
    local ok, err = pcall(function()
        common.call_context_command("CcoCampaignCharacter", tostring(cqi), "Select")
    end)
    log("reselect cqi " .. cqi .. ": Select " .. (ok and "sent" or ("failed: " .. tostring(err))))
end

--- Selects a character again after a change on the map, so the HUD unit card shows his new unit. Without it the card stayed stale until he was
--- deselected and selected by hand. While the character panel is open it waits until the panel closes. Skipped when he is not selected.
--- @param cqi number The character's command queue index.
local function reselect(cqi)
    if panel_open then
        pending_reselect = cqi
        log("reselect cqi " .. cqi .. " waits for the character panel to close")
        return
    end
    if selected_cqi ~= cqi then
        log("reselect cqi " .. cqi .. " skipped: he is not selected")
        return
    end
    local cleared, clear_err = pcall(function()
        CampaignUI.ClearSelection()
    end)
    log("reselect cqi " .. cqi .. ": ClearSelection " .. (cleared and "ok" or ("failed: " .. tostring(clear_err))))
    cm:remove_real_callback(RESELECT_NAME)
    cm:real_callback(function()
        select_again(cqi)
    end, RESELECT_MS, RESELECT_NAME)
end

--- The registered button whose component has this name.
--- @param name string The clicked component's name.
--- @returns table|nil The registered button, or nil when the name is not one of them.
local function button_named(name)
    if string.sub(name, 1, #PREFIX) ~= PREFIX then
        return nil
    end
    return by_id[string.sub(name, #PREFIX + 1)]
end

--- Whether a panel opening or closing is worth a log line: the character panel, the units panel, a panel that hides the buttons, or any panel
--- while a button is shown.
--- @param panel string The panel name.
--- @param hides boolean Whether it hides the buttons.
--- @returns boolean True when it is logged.
local function worth_logging(panel, hides)
    if #buttons == 0 then
        return false
    end
    if panel == PANEL or panel == STRIP_PATH[1] or hides then
        return true
    end
    for _, button in ipairs(buttons) do
        if button.cqi then
            return true
        end
    end
    return false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
    NAME .. "_character_selected",
    "CharacterSelected",
    function()
        return #buttons > 0
    end,
    function(context)
        selected_cqi = context:character():command_queue_index()
        schedule_refresh("character " .. selected_cqi .. " selected")
    end,
    true
)

core:add_listener(
    NAME .. "_character_deselected",
    "CharacterDeselected",
    function()
        return #buttons > 0
    end,
    function()
        selected_cqi = nil
        schedule_refresh("character deselected")
    end,
    true
)

core:add_listener(
    NAME .. "_settlement_selected",
    "SettlementSelected",
    function()
        return #buttons > 0
    end,
    function()
        selected_cqi = nil
        schedule_refresh("settlement selected")
    end,
    true
)

core:add_listener(
    NAME .. "_panel_opened",
    "PanelOpenedCampaign",
    function()
        return #buttons > 0
    end,
    function(context)
        local panel = tostring(context.string)
        if panel == PANEL then
            panel_open = true
        end
        local hides = hides_on_open(panel)
        if worth_logging(panel, hides) then
            log("PanelOpenedCampaign " .. panel .. (hides and ", hides the buttons" or ", keeps the buttons"))
        end
        if hides then
            guarded("panel open", function()
                hide_all("panel " .. panel .. " opened", "panel " .. panel .. " opened")
            end)
        end
        schedule_refresh("panel " .. panel .. " opened")
    end,
    true
)

core:add_listener(
    NAME .. "_panel_closed",
    "PanelClosedCampaign",
    function()
        return #buttons > 0
    end,
    function(context)
        local panel = tostring(context.string)
        if worth_logging(panel, false) then
            log("PanelClosedCampaign " .. panel)
        end
        if panel == STRIP_PATH[1] and picker and picker.button.path == STRIP_PATH then
            -- The button stays in the strip: the reselect after a pick closes and reopens the units panel, and adding the button back while the
            -- strip is shown made the strip grow down over the card. The next refresh removes it if the character is no longer selected.
            guarded("units panel close", function()
                close_picker("the units panel closed")
            end)
        end
        if panel == PANEL then
            panel_open = false
            guarded("panel close", function()
                for _, button in ipairs(buttons) do
                    if button.path == ROW_PATH then
                        set_hidden(button, "panel " .. panel .. " closed", "the character panel closed")
                    end
                end
            end)
            if pending_reselect then
                local cqi = pending_reselect
                pending_reselect = nil
                guarded("reselect", function()
                    reselect(cqi)
                end)
            end
        end
        schedule_refresh("panel " .. panel .. " closed")
    end,
    true
)

core:add_listener(
    NAME .. "_panel_click",
    "ComponentLClickUp",
    function(context)
        return panel_open and #buttons > 0 and string.sub(tostring(context.string), 1, #PREFIX) ~= PREFIX
    end,
    function(context)
        -- The panel's arrows, character list and tabs give no event of their own, so any click re-checks which character it shows.
        schedule_refresh("click on " .. tostring(context.string))
    end,
    true
)

core:add_listener(
    NAME .. "_button_click",
    "ComponentLClickUp",
    function(context)
        return button_named(tostring(context.string)) ~= nil
    end,
    function(context)
        local button = button_named(tostring(context.string))
        after_click("button click", function()
            local id = button.spec.id
            if picker then
                local same = picker.button == button
                close_picker("a button was clicked with the picker open")
                if same then
                    return
                end
            end
            local character = button.cqi and cm:get_character_by_cqi(button.cqi)
            if not is_local(character) or not is_for(button, character) then
                log(id .. " button clicked but it belongs to no local character it is for")
                set_hidden(button, "button click", "the button had no character")
                return
            end
            local cqi = character:command_queue_index()
            if is_locked(button, character) then
                log(id .. " button clicked for cqi " .. cqi .. " but it is locked")
                return
            end
            log(id .. " button clicked for cqi " .. cqi)
            open_picker(button, character)
        end)
    end,
    true
)

core:add_listener(
    NAME .. "_option_click",
    "ComponentLClickUp",
    function(context)
        return picker ~= nil and picker.options[context.string] ~= nil
    end,
    function(context)
        local clicked = context.string
        after_click("option click", function()
            local option = picker and picker.options[clicked]
            if not option then
                log("option " .. tostring(clicked) .. " clicked but the picker closed first")
                return
            end
            local id, cqi = picker.button.spec.id, picker.cqi
            local character = cm:get_character_by_cqi(cqi)
            if not character then
                log(id .. " option " .. tostring(clicked) .. " clicked but its character is gone")
                close_picker("its character is gone")
                return
            end
            if not option.enabled then
                log(id .. " option " .. option.column .. " " .. option.key .. " clicked but it is not pickable")
                return
            end
            local trigger = TRIGGER_PREFIX .. id .. ":" .. cqi .. ":" .. option.column .. ":" .. option.key
            log(id .. " option " .. option.column .. " " .. option.key .. " clicked, sending " .. trigger)
            close_picker("option picked")
            CampaignUI.TriggerCampaignScriptEvent(character:faction():command_queue_index(), trigger)
        end)
    end,
    true
)

core:add_listener(
    NAME .. "_trigger",
    "UITrigger",
    function(context)
        return string.sub(context:trigger(), 1, #TRIGGER_PREFIX) == TRIGGER_PREFIX
    end,
    function(context)
        local trigger = context:trigger()
        local id, cqi, column, key = string.match(string.sub(trigger, #TRIGGER_PREFIX + 1), "^([^:]+):(%d+):([^:]+):([^:]+)$")
        local button = id and by_id[id]
        local character = cqi and cm:get_character_by_cqi(tonumber(cqi))
        if not button or not character or not is_for(button, character) then
            log("trigger " .. trigger .. " names no registered button or no character it is for")
            return
        end
        if character:faction():command_queue_index() ~= context:faction_cqi() then
            log("trigger " .. trigger .. " came from another faction (cqi " .. tostring(context:faction_cqi()) .. ")")
            return
        end
        call_spec(button, "apply", character, column, key)
        if is_local(character) then
            if button.spec.reselect then
                if button.path == STRIP_PATH then
                    select_again(character:command_queue_index())
                else
                    reselect(character:command_queue_index())
                end
            end
            schedule_refresh(id .. " picked " .. column .. " " .. key)
        end
    end,
    true
)

core:add_listener(
    NAME .. "_turn_start",
    "FactionTurnStart",
    is_local_faction,
    function()
        schedule_refresh("turn start")
    end,
    true
)

core:add_listener(
    NAME .. "_turn_end",
    "FactionTurnEnd",
    is_local_faction,
    function()
        selected_cqi = nil
        panel_open = false
        cm:remove_real_callback(REFRESH_NAME)
        guarded("turn end", function()
            hide_all("turn end", "turn ended")
        end)
    end,
    true
)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- API

UI_PANEL_BUTTON_PICKER = {
    --- Adds a button. Call it once, at first tick or later. `spec` fields:
    --- `id` (string, no `:`), `icon` (image path), `is_for(character)` (true when it shows for this character, of any faction),
    --- `tooltip(character)` (text, already localised), `locked(character)` (optional, true greys the button out),
    --- `columns(character)` (list of `{ key, options = { { key, icon, tooltip, state } } }`, state `current`, `pick` or `blocked`),
    --- `apply(character, column_key, option_key)` (runs on every client), and `reselect` (true selects him again after a pick).
    --- @param spec table The button.
    --- @returns boolean True when it was added.
    register = function(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id:find(":", 1, true) then
            log("register refused: the spec needs an id with no colon")
            return false
        end
        if by_id[spec.id] then
            log("register " .. spec.id .. " refused: already registered")
            return false
        end
        local button = { spec = spec, name = PREFIX .. spec.id }
        table.insert(buttons, button)
        by_id[spec.id] = button
        log("registered " .. spec.id)
        schedule_refresh(spec.id .. " registered")
        return true
    end,

    --- Re-checks which buttons show, after a short delay.
    --- @param why string What asked for it, for the log.
    refresh = schedule_refresh,

    --- Tells the picker a character changed outside it: closes the button's picker for him, selects him again when the button has `reselect`
    --- (once the character panel is closed) and re-checks which buttons show.
    --- @param id string The button's id.
    --- @param cqi number The character's command queue index.
    --- @param why string What changed, for the log.
    changed = function(id, cqi, why)
        local button = by_id[id]
        if not button then
            log("changed " .. tostring(id) .. " ignored: not registered")
            return
        end
        guarded("change", function()
            if picker and picker.button == button and picker.cqi == cqi then
                close_picker(why)
            end
            if button.spec.reselect then
                reselect(cqi)
            end
        end)
        schedule_refresh(why)
    end,

    --- Whether a button is shown in the open character panel's row.
    --- @param id string The button's id.
    --- @returns boolean True when it is.
    shown_in_panel = function(id)
        local button = by_id[id]
        return panel_open and button ~= nil and button.cqi ~= nil and button.path == ROW_PATH
    end,

    --- The character the open character panel shows, read only.
    --- @returns CHARACTER_SCRIPT_INTERFACE|nil The character, or nil when the panel is closed or shows none.
    --- @returns string What was seen, for the log.
    panel_character = function()
        local panel = find_panel()
        if not panel then
            return nil, "the character panel is closed"
        end
        return panel_character(panel)
    end,
}
