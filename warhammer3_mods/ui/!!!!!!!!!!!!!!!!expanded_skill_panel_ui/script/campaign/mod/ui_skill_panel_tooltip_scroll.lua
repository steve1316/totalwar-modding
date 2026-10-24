--- Scrolling effect tooltips. The mod's edict_tooltip layout puts the tooltip's parts in a list with a vertical bar that starts `MAX_HEIGHT` tall, so a
--- long tooltip has its final size on the first frame the game draws. This script shrinks the list to a short tooltip's parts and keeps its top on the
--- screen. The layout is used by skill cards, their level pips and the other campaign tooltips built from edict_tooltip.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Name used in the log and the timer's name.
local NAME = "ui_skill_panel_tooltip_scroll"

--- The scroll list in edict_tooltip.twui.xml, its clip and the box holding the tooltip's parts.
local LIST = "tooltip_scroll"
local LIST_CLIP = "list_clip"
local LIST_BOX = "list_box"

--- Height of the list in the layout, the most a tooltip shows before it scrolls. Keep it equal to the layout's `tooltip_scroll` height.
local MAX_HEIGHT = 600

--- Room the list keeps around its box, as the layout's clip is this much shorter than the list.
local LIST_PAD = 10

--- Gap left above the list when its top would sit off the screen.
local SCREEN_GAP = 10

--- Delay in milliseconds between looks. `real_timer` at 0 looks before the game draws each frame, so a short tooltip shrinks without a flash.
local POLL_MS = 0

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- Whether a look has failed, so the log gets one line instead of one every frame.
local failed = false

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Tooltips

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
    out(NAME .. ": " .. text)
end

--- Shrinks the shown tooltip's list to its parts when they need less than `MAX_HEIGHT`, and moves the list down when its top is off the screen.
local function fit_tooltip()
    local list = find_uicomponent(core:get_ui_root(), LIST)
    if not list then
        return
    end
    local box = find_uicomponent(list, LIST_CLIP, LIST_BOX)
    local height = math.min(box:Height() + LIST_PAD, MAX_HEIGHT)
    if list:Height() ~= height then
        list:Resize(list:Width(), height)
    end
    local _, y = list:Position()
    if y < 0 then
        local offset_x, offset_y = list:GetDockOffset()
        list:SetDockOffset(offset_x, offset_y + SCREEN_GAP - y)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
    NAME .. "_timer",
    "RealTimeTrigger",
    function(context)
        return context.string == NAME
    end,
    function()
        local ok, err = pcall(fit_tooltip)
        if not ok and not failed then
            failed = true
            log("fit_tooltip failed: " .. tostring(err))
        end
    end,
    true
)

real_timer.unregister(NAME)
real_timer.register_repeating(NAME, POLL_MS)
