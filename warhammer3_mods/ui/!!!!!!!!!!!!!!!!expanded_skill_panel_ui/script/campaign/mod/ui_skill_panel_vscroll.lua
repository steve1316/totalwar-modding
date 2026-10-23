--- Vertical scroll for the skill tree. The game's sideways list keeps the rows, since the skill panel needs it as is. A small vertical list beside
--- it only drives the vertical bar, and this script moves the rows' box up or down to match the bar. Each list then moves only its own box.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log and the callback name.
local NAME = "ui_skill_panel_vscroll"

--- The character panel and the skill tree's holder from character_details_panel_skills.twui.xml.
local PANEL = "character_details_panel"
local HOLDER = "skills_holder"

--- Delay in milliseconds between looks at the bar while the panel is open.
local POLL_MS = 10

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- Height of the used rows at the last look, so the log gets a line only when it changes.
local last_used = nil

--- Whether a look has failed since the panel opened, so the log gets one line per open instead of one every `POLL_MS`.
local failed = false

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
