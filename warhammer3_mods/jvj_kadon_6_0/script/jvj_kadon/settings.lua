--- In-memory settings for Kadon's Scrolls. Defaults apply until MCT loads. MCT values replace them on `MctInitialized` and `MctFinalized`,
--- so mid-campaign changes apply to the next drop.

local creatures = require("script/jvj_kadon/creatures")

local M = {}

--- MCT mod key shared by the MCT anchor and this reader.
M.MCT_MOD_KEY = "jvj_kadon"

--- Default value for every non-creature option, keyed by MCT option key.
M.DEFAULTS = {
    battle_drop_chance = 5,
    mission_drop_chance = 10,
    ai_can_find_scrolls = true,
    no_duplicate_scrolls = false,
    starting_scroll = false,
    allow_kin = true,
    allow_bind = true,
    enable_all_creatures = true,
}

--- Current settings: every `DEFAULTS` key plus `enabled_creatures`, a map of creature id to boolean. Replaced by `reset()`.
M.values = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Restores `values` to the defaults with every creature enabled.
function M.reset()
    M.values = {}
    for key, value in pairs(M.DEFAULTS) do
        M.values[key] = value
    end
    M.values.enabled_creatures = {}
    for _, creature in ipairs(creatures.list) do
        M.values.enabled_creatures[creature.id] = true
    end
end

--- Returns the MCT option key of a creature toggle.
--- @param id string Creature id from `creatures.list`.
--- @returns string The option key.
function M.creature_option_key(id)
    return "creature_" .. id
end

--- Copies every finalized MCT option value into `values`. Options MCT does not return keep their current value.
--- @param mct_mod table The `mct_mod` registered under `MCT_MOD_KEY`.
function M.load_from_mct(mct_mod)
    for key in pairs(M.DEFAULTS) do
        local option = mct_mod:get_option_by_key(key)
        if option then
            M.values[key] = option:get_finalized_setting()
        end
    end
    for _, creature in ipairs(creatures.list) do
        local option = mct_mod:get_option_by_key(M.creature_option_key(creature.id))
        if option then
            M.values.enabled_creatures[creature.id] = option:get_finalized_setting()
        end
    end
    out("jvj_kadon: settings loaded from MCT")
end

--- Registers persistent listeners that reload settings when MCT initializes and whenever the player finalizes settings.
function M.register_listeners()
    for _, event in ipairs({ "MctInitialized", "MctFinalized" }) do
        core:add_listener(
            "jvj_kadon_settings_" .. event,
            event,
            true,
            function(context)
                local mct_mod = context:mct():get_mod_by_key(M.MCT_MOD_KEY)
                if mct_mod then
                    M.load_from_mct(mct_mod)
                end
            end,
            true
        )
    end
end

M.reset()

return M
