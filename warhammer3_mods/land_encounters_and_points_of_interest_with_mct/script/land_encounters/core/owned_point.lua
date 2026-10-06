--- OwnedPoint: what a point of interest owned by a faction shares, Smithies and Taverns alike. It holds the owner fields' helpers, the war and
--- stance checks, the rules for AI takeovers and the owner a config entry starts with. SmithyState and TavernState inherit from it and keep
--- their own fields, battles and dilemmas.

require("script/land_encounters/utils/common")

local OwnedPoint = {
    --- Owning faction key, or "" when unowned.
    controlling_faction_name = "",
    --- Owning faction subculture, used to build its armies.
    controlling_faction_subculture = "",
    --- {x, y} map position.
    coordinates = {},
}

--- Percent chance that an AI army at war with an AI owner takes the point by walking onto it.
OwnedPoint.AI_TAKEOVER_CHANCE = 26

--- Script context value a point's dilemma text reads its owner's name from.
OwnedPoint.OWNER_CONTEXT = "land_enc_point_owner"

--- Subcultures that never take a point: rogue armies, savage orcs and the Border Princes.
OwnedPoint.PROHIBITED_SUBCULTURES = {
    ["wh2_main_rogue"] = true,
    ["wh_main_sc_grn_savage_orcs"] = true,
    ["wh_main_sc_teb_teb"] = true,
}

--- The owner a config entry starts with: `initial_owner`, or `owner_if_player` when a player leads the initial owner.
--- @param entry table A config entry with initial_owner and owner_if_player.
--- @returns string|nil The starting owner's faction key, or nil when the entry names none.
function OwnedPoint.initial_owner(entry)
    if entry.initial_owner and is_human_faction_name(entry.initial_owner) then return entry.owner_if_player end
    return entry.initial_owner
end

--- Returns true when any faction currently controls the point.
--- @returns boolean True when controlling_faction_name is non-empty.
function OwnedPoint:is_occupied()
    return self.controlling_faction_name ~= ""
end

--- Returns true when a human faction currently controls the point.
--- @returns boolean True when controlling_faction_name belongs to a human player.
function OwnedPoint:is_occupied_by_player()
    return is_human_faction_name(self.controlling_faction_name)
end

--- Returns true when the point is controlled by the given faction.
--- @param faction_name string The faction key to compare against.
--- @returns boolean True when controlling_faction_name equals faction_name.
function OwnedPoint:is_occupied_by_same_faction(faction_name)
    return self.controlling_faction_name == faction_name
end

--- Returns true when the visiting faction's subculture never takes points (see `PROHIBITED_SUBCULTURES`).
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the subculture is prohibited.
function OwnedPoint:is_prohibited_subculture(visiting_faction)
    return OwnedPoint.PROHIBITED_SUBCULTURES[visiting_faction:subculture()] == true
end

--- Returns true when the visiting faction is at war with the point's owner.
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the two factions are at war, false when the point is unowned.
function OwnedPoint:is_faction_at_war_with_owner(visiting_faction)
    local owner = cm:get_faction(self.controlling_faction_name)
    if not owner then return false end
    return owner:at_war_with(visiting_faction)
end

--- Resolves the owner, or clears ownership when the owner is dead or missing.
--- @returns faction The living owner, or nil when ownership was cleared.
function OwnedPoint:check_if_owner_is_alive_and_return_faction()
    local owner = cm:get_faction(self.controlling_faction_name)
    if not owner or not cm:faction_is_alive(owner) then
        self.controlling_faction_name = ""
        return nil
    end
    return owner
end

--- Sets the owner. Accepts a faction object or faction key.
--- @param faction faction|string|nil The new owner. Nil, "" or a faction this campaign does not have clears ownership.
function OwnedPoint:set_controlling_faction(faction)
    if type(faction) == "string" and faction ~= "" then
        faction = cm:get_faction(faction)
    end
    if not faction or faction == "" then
        self.controlling_faction_name = ""
        self.controlling_faction_subculture = ""
    else
        self.controlling_faction_name = faction:name()
        self.controlling_faction_subculture = faction:subculture()
    end
end

--- True if the character is a general in a stance that permits the point's dilemma to trigger.
--- @param character character The character to check.
--- @returns boolean True when the character is a general in an eligible stance.
function OwnedPoint:character_can_trigger_dilemma(character)
    if not cm:char_is_general_with_army(character) then return false end
    local active_stance = character:military_force():active_stance()
    return active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH"
end

--- Sets the owner's name for the point's next dilemma to show: its faction's screen name, or its key when it has none.
function OwnedPoint:show_owner_in_dilemmas()
    local key = self.controlling_faction_name
    local name = key ~= "" and common.get_localised_string("factions_screen_name_" .. key) or ""
    common.set_context_value(OwnedPoint.OWNER_CONTEXT, name ~= "" and name or key)
end

--- Shows one of the point's event-feed messages at its position.
--- @param faction_name string The faction that sees the message.
--- @param message string The message suffix, e.g. "smithy_lost" for event_feed_strings_text_title_event_land_enc_smithy_lost.
function OwnedPoint:show_message(faction_name, message)
    show_located_message(faction_name, message, self.coordinates)
end

--- Makes `class` inherit OwnedPoint, so its instances fall back to it for anything the class does not define.
--- @param class table A state class whose instances use `class` as their metatable.
--- @returns table The class.
function OwnedPoint.extend(class)
    return setmetatable(class, { __index = OwnedPoint })
end

return OwnedPoint
