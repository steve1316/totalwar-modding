--- Vertical scroll for the skill tree. The game's sideways list keeps the rows, since the skill panel needs it as is. A small vertical list beside
--- it only drives the vertical bar, and this script moves the rows' box up or down to match the bar. Each list then moves only its own box.
--- It also places the rows with regular or compact gaps, picked by the player in MCT or by a mod for its own skill trees with `add_row_gaps`.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log and the callback name.
local NAME = "ui_skill_panel_vscroll"

--- The character panel and the skill tree's holder from character_details_panel_skills.twui.xml.
local PANEL = "character_details_panel"
local HOLDER = "skills_holder"

--- The panel's holder of the shown character's context.
local PANEL_CONTEXT_HOLDER = "character_context_parent"

--- Delay in milliseconds between looks at the bar while the panel is open.
local POLL_MS = 10

--- The MCT mod and checkbox for compact row gaps, from script/mct/settings/ui_skill_panel.lua.
local MCT_MOD_KEY = "ui_skill_panel"
local MCT_OPTION = "compact_rows"

--- The first skill row. Row 0 holds the card templates and is never touched.
local FIRST_ROW = 1

--- Distance in pixels from one row's top to the next with compact gaps. The rows size to their cards, so compact gaps move them instead of resizing.
local COMPACT_ROW_STEP = 70

--- Group box frame height and its offset above the box, keyed by whether compact gaps are on. Regular matches `template_module` in the layout.
local FRAMES = { [false] = { h = 99, y = -22 }, [true] = { h = 79, y = -12 } }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- Height of the used rows at the last look, so the log gets a line only when it changes.
local last_used = nil

--- Whether a look has failed since the panel opened, so the log gets one line per open instead of one every `POLL_MS`.
local failed = false

--- Whether the player turned compact row gaps on in MCT. Off without MCT. Used for trees no row gap set picks gaps for.
local player_compact = false

--- The row gap sets added with `add_row_gaps`, in the order they were added. Each is `{ id, gaps_for }`.
local gap_specs = {}

--- Whether `mod_gaps` is known for `gaps_cqi`. Cleared when the panel opens and when a set is added or removed.
local gaps_known = false

--- The character the row gap sets were last asked about, nil when the panel's character could not be read.
local gaps_cqi = nil

--- What the sets picked for `gaps_cqi`: "compact", "regular" or nil when none picked.
local mod_gaps = nil

--- Whether fitting the rows has failed since the panel opened, kept apart from `failed` so the scroll still works when only this fails.
local fit_failed = false

--- Whether the rows were last placed with compact gaps, so turning them off restacks the rows once.
local rows_compact = false

--- Whether compact gaps have been used this session. Until then the rows and frames are as the layout made them, so fitting is skipped.
local ever_compact = false

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rows

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- How far down the bar's list is scrolled, from 0 at the top to 1 at the bottom.
--- @param drive_clip UIC The bar list's clip.
--- @param drive UIC The bar list's box.
--- @returns number The scrolled share.
local function bar_share(drive_clip, drive)
    local range = drive:Height() - drive_clip:Height()
    if range <= 0 then
        return 0
    end
    local _, clip_y = drive_clip:Position()
    local _, drive_y = drive:Position()
    return math.max(0, math.min(1, (clip_y - drive_y) / range))
end

--- How much height the rows that hold skills need, with the same gap under the last row as above the first. Empty rows are left out, so a
--- short tree does not scroll into blank rows.
--- @param rows UIC The rows' box that the script moves.
--- @param list_box UIC The box holding the row containers.
--- @returns number The height the used rows need, in pixels.
local function used_height(rows, list_box)
    local _, rows_y = rows:Position()
    local top, bottom = nil, rows_y
    for i = 0, list_box:ChildCount() - 1 do
        local row = UIComponent(list_box:Find(i))
        if row:ChildCount() > 0 then
            local _, y = row:Position()
            top = math.min(top or y, y)
            bottom = math.max(bottom, y + row:Height())
        end
    end
    return bottom - rows_y + ((top or rows_y) - rows_y)
end

--- Sets a group box frame to the regular or compact size in the module's current state. A module that changes state is fixed on the next look.
--- @param module UIC The group box, a `module_<skill>` component in a row.
--- @param from table The frame size to change, from `FRAMES`.
--- @param to table The frame size to set, from `FRAMES`.
--- @returns boolean Whether the frame changed.
local function fit_frame(module, from, to)
    for i = 0, module:NumCurrentStateImages() - 1 do
        if module:GetCurrentStateImageHeight(i) == from.h then
            local x = module:GetCurrentStateImageDockOffset(i)
            module:SetCanResizeCurrentStateImageHeight(i, true)
            module:ResizeCurrentStateImage(i, module:GetCurrentStateImageWidth(i), to.h)
            module:SetCurrentStateImageDockOffset(i, x, to.y)
            return true
        end
    end
    return false
end

--- Sets the frame of every group box in a row.
--- @param row UIC The row.
--- @param from table The frame size to change, from `FRAMES`.
--- @param to table The frame size to set, from `FRAMES`.
--- @returns number How many frames changed.
local function fit_row_frames(row, from, to)
    local count = 0
    for i = 0, row:ChildCount() - 1 do
        local module = UIComponent(row:Find(i))
        if string.find(module:Id(), "^module_") and fit_frame(module, from, to) then
            count = count + 1
        end
    end
    return count
end

--- Places each row `COMPACT_ROW_STEP` below the one before with compact gaps, or lets the game stack them again once compact gaps are turned off. The
--- group box frames are set to match in every row. Does nothing until compact gaps are first used.
--- @param list_box UIC The box holding the row containers.
--- @param compact boolean Whether the shown tree gets compact gaps.
local function fit_rows(list_box, compact)
    ever_compact = ever_compact or compact
    if not ever_compact then
        return
    end
    if rows_compact and not compact then
        list_box:Layout()
        log("regular gaps: rows stacked again")
    end
    rows_compact = compact
    local first = find_uicomponent(list_box, "chain" .. FIRST_ROW)
    if not first then
        return
    end
    local _, first_y = first:Position()
    local from, to = FRAMES[not compact], FRAMES[compact]
    local moved, frames = 0, 0
    for i = 0, list_box:ChildCount() - 1 do
        local row = UIComponent(list_box:Find(i))
        local n = tonumber(string.match(row:Id(), "^chain(%d+)$"))
        if n and n >= FIRST_ROW then
            if compact then
                local x, y = row:Position()
                local target = first_y + (n - FIRST_ROW) * COMPACT_ROW_STEP
                if y ~= target then
                    row:MoveTo(x, target)
                    moved = moved + 1
                end
            end
            frames = frames + fit_row_frames(row, from, to)
        end
    end
    if moved > 0 or frames > 0 then
        log((compact and "compact" or "regular") .. " gaps: moved " .. moved .. " rows and set " .. frames .. " group box frames")
    end
end

--- The cqi of the character the open panel shows.
--- @returns number|nil The cqi, or nil when it cannot be read.
local function panel_cqi()
    local holder = find_uicomponent(core:get_ui_root(), PANEL, PANEL_CONTEXT_HOLDER)
    if not holder then
        return nil
    end
    local ok, id = pcall(function()
        return holder:GetContextObjectId("CcoCampaignCharacter")
    end)
    return ok and tonumber(id) or nil
end

--- Whether the shown tree gets compact gaps. The first row gap set that picks gaps for the panel's character decides, and the player's MCT choice
--- covers the rest. The sets are only asked again when the character changes, the panel opens or a set is added or removed.
--- @returns boolean True for compact gaps.
local function wants_compact()
    if #gap_specs == 0 then
        return player_compact
    end
    local cqi = panel_cqi()
    if not gaps_known or cqi ~= gaps_cqi then
        gaps_known, gaps_cqi, mod_gaps = true, cqi, nil
        local character = cqi and cm:get_character_by_cqi(cqi) or nil
        for _, spec in ipairs(gap_specs) do
            local ok, gaps = pcall(spec.gaps_for, character)
            if not ok then
                log(spec.id .. " gaps_for raised: " .. tostring(gaps))
            elseif gaps == "compact" or gaps == "regular" then
                mod_gaps = gaps
                log("cqi " .. tostring(cqi) .. " gets " .. gaps .. " gaps from " .. spec.id)
                break
            end
        end
    end
    if mod_gaps then
        return mod_gaps == "compact"
    end
    return player_compact
end

--- Moves the rows' box to match the vertical bar. The rows' clip sits inside the sideways list and ends above its bar, so the bar stays put.
local function follow_bar()
    local holder = find_uicomponent(core:get_ui_root(), PANEL, HOLDER)
    if not holder or not holder:Visible(true) then
        return
    end
    local clip = find_uicomponent(holder, "rows_clip")
    local rows = clip and find_uicomponent(clip, "vscroll_box")
    local list_box = rows and find_uicomponent(rows, "list_clip", "list_box")
    local vlist = find_uicomponent(holder, "skills_vlistview")
    local drive_clip = vlist and find_uicomponent(vlist, "list_clip")
    local drive = drive_clip and find_uicomponent(drive_clip, "vscroll_drive")
    if not list_box or not drive then
        return
    end
    local ok, err = pcall(function()
        fit_rows(list_box, wants_compact())
    end)
    if not ok and not fit_failed then
        fit_failed = true
        log("fit_rows failed: " .. tostring(err))
    end
    local used = used_height(rows, list_box)
    local overflow = math.max(0, used - clip:Height())
    if used ~= last_used then
        last_used = used
        log("used rows reach " .. used .. " px, the view shows " .. clip:Height())
    end

    -- The bar's box gets the same share of its clip as the view has of the used rows, so the bar stops at the last row and hides when all fit.
    local drive_h = math.floor(drive_clip:Height() * math.max(used, clip:Height()) / clip:Height() + 0.5)
    if drive:Height() ~= drive_h then
        drive:SetCanResizeHeight(true)
        drive:Resize(drive:Width(), drive_h)
    end
    if vlist:Visible() ~= (overflow > 0) then
        vlist:SetVisible(overflow > 0)
    end

    local _, clip_y = clip:Position()
    local rows_x, rows_y = rows:Position()
    local target = clip_y - math.floor(bar_share(drive_clip, drive) * overflow + 0.5)
    if rows_y ~= target then
        rows:MoveTo(rows_x, target)
    end
end

--- Follows the bar every `POLL_MS` while the character panel is open.
local function poll()
    if not panel_open then
        return
    end
    local ok, err = pcall(follow_bar)
    if not ok and not failed then
        failed = true
        log("follow_bar failed: " .. tostring(err))
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
        fit_failed = false
        gaps_known = false
        last_used = nil
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

-- MCT sends its settings once it has loaded and again each time the player applies them. Without MCT the player's gaps stay regular.
for _, event in ipairs({ "MctInitialized", "MctFinalized" }) do
    core:add_listener(
        NAME .. "_" .. event,
        event,
        true,
        function(context)
            local mct_mod = context:mct():get_mod_by_key(MCT_MOD_KEY)
            local option = mct_mod and mct_mod:get_option_by_key(MCT_OPTION)
            if option then
                player_compact = option:get_finalized_setting() == true
                log("compact row gaps " .. (player_compact and "on" or "off"))
            end
        end,
        true
    )
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- API

-- ui_skill_panel.lua fills the same table, and either file may load first.
UI_SKILL_PANEL = UI_SKILL_PANEL or {}

--- Adds a set that picks the row gaps for some skill trees, over the player's MCT choice. Call it once, at first tick or later. `spec` fields:
--- `id` (string) and `gaps_for(character)` returning "compact", "regular" or nil to leave the character to later sets and the player. The
--- character may be nil. When two sets pick gaps for one character, the one added first wins.
--- @param spec table The set.
--- @returns boolean True when it was added.
UI_SKILL_PANEL.add_row_gaps = function(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.gaps_for) ~= "function" then
        log("add_row_gaps refused: the spec needs an id and gaps_for")
        return false
    end
    for _, known in ipairs(gap_specs) do
        if known.id == spec.id then
            log("add_row_gaps " .. spec.id .. " refused: already added")
            return false
        end
    end
    table.insert(gap_specs, spec)
    gaps_known = false
    log("added row gaps " .. spec.id)
    return true
end

--- Removes a set added with `add_row_gaps`. The shown tree follows the next set or the player from the next look.
--- @param id string The set's id.
--- @returns boolean True when a set was removed.
UI_SKILL_PANEL.remove_row_gaps = function(id)
    for i, known in ipairs(gap_specs) do
        if known.id == id then
            table.remove(gap_specs, i)
            gaps_known = false
            log("removed row gaps " .. id)
            return true
        end
    end
    return false
end
