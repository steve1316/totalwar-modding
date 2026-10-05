--- Logs where every army starts in an allied-army test battle (configs/debug.lua `ally_test` in the campaign): which armies deploy and which
--- march in from the map edge, whether each is player-controlled, and how strong its units are. Does nothing in any other battle. The relief
--- column modes' enemy charge and our arrival run in land_enc_ally_reinforcements.lua.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the test's mode. Mirrored in script/land_encounters/core/managers.lua.
local ALLY_TEST_SVR_KEY = "land_enc_ally_test"
--- How often the armies are logged after deployment, in ms, and how many times.
local LOG_EVERY_MS = 15000
local LOG_TIMES = 12

local mode = core:svr_load_string(ALLY_TEST_SVR_KEY)
if mode == nil or mode == "" then return end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Logging

--- Writes one line to the battle script log.
--- @param msg string The line to write.
local function log(msg)
    bm:out("[LEAPOI ally test] " .. tostring(msg))
end

--- Logs every army in both alliances: faction, player control, units on the field, men alive against the battle's start, and how many
--- reinforcement sets it has.
--- @param moment string When this is, for the log.
local function log_armies(moment)
    for alliance_id = 1, 2 do
        local ok, problem = pcall(function()
            local armies = bm:alliances():item(alliance_id):armies()
            for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
                local army = armies:item(army_id)
                local sunits = bm:get_scriptunits_for_army(alliance_id, army_id)
                local count, on_field, alive, start = 0, 0, 0, 0
                if sunits then
                    for i = 1, sunits:count() do
                        local unit = sunits:item(i).unit
                        count = count + 1
                        if unit:is_deployed() then on_field = on_field + 1 end
                        alive = alive + unit:number_of_men_alive()
                        start = start + unit:initial_number_of_men()
                    end
                end
                log(moment .. ": alliance " .. alliance_id .. " army " .. army_id .. " " .. army:faction_key() .. (army:is_player_controlled() and " (player)" or " (AI)")
                    .. ", units " .. count .. ", on the field " .. on_field .. ", men " .. alive .. "/" .. start .. ", reinforcement sets "
                    .. tostring(bm:num_reinforcing_armies_for_army_in_alliance(alliance_id, army_id)))
            end
        end)
        if not ok then log(moment .. ": alliance " .. alliance_id .. " could not be read: " .. tostring(problem)) end
    end
end

log("mode " .. mode)
bm:register_phase_change_callback("Deployment", function() log_armies("deployment") end)
bm:register_phase_change_callback("Deployed", function()
    log_armies("battle start")
    local times = 0
    bm:repeat_callback(function()
        times = times + 1
        log_armies("after " .. (times * LOG_EVERY_MS / 1000) .. "s")
        if times >= LOG_TIMES then bm:remove_process("land_enc_ally_test_log") end
    end, LOG_EVERY_MS, "land_enc_ally_test_log")
end)
