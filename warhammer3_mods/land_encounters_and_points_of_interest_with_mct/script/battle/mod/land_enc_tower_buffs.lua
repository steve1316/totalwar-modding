--- Announces the tower buffs on the delving army when a tower floor battle starts: one banner per buff above the army panel, and one entry per
--- buff in the objectives panel for the rest of the battle. The campaign saves the buff list under `land_enc_tower_battle_buffs` just before a
--- floor battle and clears it once the floor resolves, so other battles see an empty list.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the comma-separated buff names. Mirrored in script/land_encounters/features/tower_offers.lua.
local BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"
--- Prefix of each buff's scripted objective key. The buff name follows, e.g. "land_enc_tower_buff_iron_resolve".
local OBJECTIVE_PREFIX = "land_enc_tower_buff_"
--- Suffix of each buff's banner line, a plain version of its panel entry that reads well on the red banner.
local MESSAGE_SUFFIX = "_message"
--- How long each banner stays on screen, in ms.
local MESSAGE_MS = 6000
--- How long each banner takes to fade in and out, in ms.
local FADE_MS = 1000

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entry

local buffs = {}
for name in (core:svr_load_string(BUFFS_SVR_KEY) or ""):gmatch("[^,]+") do
    buffs[#buffs + 1] = name
end
if #buffs > 0 then
    bm:out("[LEAPOI] tower floor battle with buffs: " .. table.concat(buffs, ", "))
    --- Banners queued during deployment would play before the fight, so the announcement waits for the battle to start.
    bm:register_phase_change_callback("Deployed", function()
        for _, name in ipairs(buffs) do
            bm:set_objective(OBJECTIVE_PREFIX .. name)
            bm:queue_help_message(OBJECTIVE_PREFIX .. name .. MESSAGE_SUFFIX, MESSAGE_MS, FADE_MS)
        end
    end)
end
