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

--- Moves the rows' box to match the vertical bar. The rows' clip sits inside the sideways list and ends above its bar, so the bar stays put.
local function follow_bar()
    local holder = find_uicomponent(core:get_ui_root(), PANEL, HOLDER)
    if not holder or not holder:Visible(true) then
        return
    end
    local clip = find_uicomponent(holder, "rows_clip")
    local rows = clip and find_uicomponent(clip, "vscroll_box")
    local list_box = rows and find_uicomponent(rows, "list_clip", "list_box")
    local drive_clip = find_uicomponent(holder, "skills_vlistview", "list_clip")
    local drive = drive_clip and find_uicomponent(drive_clip, "vscroll_drive")
    if not list_box or not drive then
        return
    end
    local _, clip_y = clip:Position()
    local rows_x, rows_y = rows:Position()
    local _, box_y = list_box:Position()
    local overflow = math.max(0, box_y + list_box:Height() - rows_y - clip:Height())
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
