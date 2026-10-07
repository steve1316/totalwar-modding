--- TowerState + TowerEventDelegate. One tower stands in every zone, on one of that zone's encounter spots, and is held by one enemy
--- faction for the whole campaign. A human lord who enters fights up to five floors in a row. After each win they climb, take one of the
--- drawn offers (features/tower_offers.lua) or leave. TowerEventDelegate places the towers, runs the delves, keeps the markers in line with
--- MCT, ticks cooldowns and saves it all.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")
require("script/land_encounters/core/managers")

local tower_data = require("script/land_encounters/configs/tower_data")
local item_pool = require("script/land_encounters/core/item_pool")
local TowerSpot = require("script/land_encounters/core/spot").TowerSpot
local Army = require("script/land_encounters/core/army")
local tower_army = require("script/land_encounters/features/tower_army")
local tower_offers = require("script/land_encounters/features/tower_offers")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")
local offer_effects = require("script/land_encounters/core/offer_effects")
local army_generator = require("script/land_encounters/core/army_generator")
local launch_dilemma = require("script/land_encounters/core/dilemmas").launch
local debug_config = require("script/land_encounters/configs/debug")
local tower_lords = require("script/land_encounters/features/tower_lords")
local tower_missions = require("script/land_encounters/features/tower_missions")
local tower_battlefields = require("script/land_encounters/features/tower_battlefields")
local offers_data = require("script/land_encounters/configs/tower_offers")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0

--- The highest units-joined payload line. More units than that show this line.
local MOST_JOINED_LINE = 10

--- Dilemma offered when a lord enters an open tower.
local EVENT_ENTER = "land_enc_dilemma_tower_enter"
--- Dilemma offered after winning every floor but the last. "_floor_" and the floor number are appended, so each floor's description can
--- show the climb so far.
local EVENT_DEEPER = "land_enc_dilemma_tower_deeper"
--- One-choice dilemma that pays the full haul after the last floor.
local EVENT_CLAIM = "land_enc_dilemma_tower_claim"

--- Prefix of a floor army's invasion id. The delving faction's key follows, so each human faction has its own floor army.
local FLOOR_INVASION_PREFIX = "tower_invasion_"

--- The next rarity up for a Treasure map. A rare becomes a legendary, picked from the legendary pool.
local RARITY_UP = { common = "uncommon", uncommon = "rare", rare = "legendary" }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerState

local TowerState = {
    --- Zone the tower stands in. Also the tower's id, since every zone has one tower.
    zone_name = "",
    --- Index of the encounter spot the tower occupies in its zone.
    spot_index = 0,
    --- The tower's {x, y} position.
    coordinates = {0, 0},
    --- Shorthand of the faction holding the tower, such as "skv".
    faction = "",
    --- Turns left before the tower can be entered again. 0 means open.
    cooldown = 0,
    --- Faction key -> true for factions whose delves here start on floor 2 (an Echoes of the climb offer).
    echoes = {},
    --- Faction key of the last faction to delve the tower, told when it opens again. Empty when none has.
    last_delver = "",
}

--- Builds a tower record.
--- @param zone_name string Zone the tower stands in.
--- @param spot_index number Index of the encounter spot the tower occupies.
--- @param coordinates table The tower's {x, y} position.
--- @param faction string Shorthand of the faction holding the tower.
--- @param cooldown number Turns left before the tower opens.
--- @param echoes table|nil Faction key -> true for factions the tower remembers.
--- @param last_delver string|nil Faction key of the last faction to delve the tower.
--- @returns TowerState The new tower.
function TowerState:new(zone_name, spot_index, coordinates, faction, cooldown, echoes, last_delver)
    local t = {
        zone_name = zone_name, spot_index = spot_index, coordinates = coordinates, faction = faction, cooldown = cooldown or 0, echoes = echoes or {},
        last_delver = last_delver or "",
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- Exports the tower as a plain table for the save file.
--- @returns table The tower's saved fields.
function TowerState:export()
    return {
        zone_name = self.zone_name, spot_index = self.spot_index, coordinates = self.coordinates, faction = self.faction, cooldown = self.cooldown,
        echoes = self.echoes, last_delver = self.last_delver,
    }
end

--- Shows a located event feed message at the tower.
--- @param faction_name string The faction to show the message to.
--- @param message string The message suffix, e.g. "tower_lost" for event_feed_strings_text_title_event_land_enc_tower_lost.
function TowerState:show_message(faction_name, message)
    show_located_message(faction_name, message, self.coordinates)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- The enabled faction shorthands, sorted so every multiplayer client walks them in the same order.
--- @returns table An array of faction shorthands.
local function sorted_faction_keys()
    local keys = get_enabled_faction_keys()
    table.sort(keys)
    return keys
end

--- Returns a picker that hands out the enabled faction shorthands in a shuffled order, skipping ones already taken, and starts over once
--- every faction is used. The shorthands are sorted before the shuffle so every multiplayer client sees the same order.
--- @param taken table Shorthand -> true set of factions restored towers already hold.
--- @returns function A function that returns the next faction shorthand.
local function faction_picker(taken)
    local keys = sorted_faction_keys()
    local queue = {}
    for _, key in ipairs(keys) do
        if not taken[key] then queue[#queue + 1] = key end
    end
    randomic_shuffle(queue)
    local next_index = 1
    return function()
        if next_index > #queue then
            queue = randomic_shuffle(keys)
            next_index = 1
        end
        next_index = next_index + 1
        return queue[next_index - 1]
    end
end

--- Picks the gold multiplier for the share of the army lost on a floor.
--- @param loss number Strength points lost (0-100).
--- @returns number The multiplier from `tower_data.performance`.
local function performance_multiplier(loss)
    for _, band in ipairs(tower_data.performance) do
        if loss <= band.max_loss then return band.multiplier end
    end
    return tower_data.performance[#tower_data.performance].multiplier
end

--- Writes a floor army's budget for the log, e.g. "7000-12000 x1.2".
--- @param budget table The difficulty's { min, max } gold.
--- @param multiplier number The offers' budget multiplier.
--- @returns string The range and multiplier.
local function army_budget_text(budget, multiplier)
    return budget[1] .. "-" .. budget[2] .. " x" .. multiplier
end

--- Picks one legendary item, or a rare standing in when the pool cannot supply one.
--- @param faction_name string The delving faction.
--- @returns string|nil An ancillary key, or nil when even the rare pool is dry.
local function pick_legendary_or_fallback(faction_name)
    return item_pool.pick_legendary_item(faction_name) or item_pool.pick_items(faction_name, { tower_data.legendary_fallback_rarity }, 1)[1]
end

--- Picks a floor's items: its rarities, or legendary items with a rare standing in for each one the pool cannot supply. `rarity_shift`
--- raises each rarity by that many steps (a Treasure map), where a rare becomes a legendary.
--- @param faction_name string The delving faction.
--- @param floor table The floor record from `tower_data.floors`.
--- @param rarity_shift number|nil Rarity steps to raise the floor's items by.
--- @returns table Ancillary keys.
local function pick_floor_items(faction_name, floor, rarity_shift)
    if not floor.legendary_count and not rarity_shift then
        return item_pool.pick_items(faction_name, floor.item_rarities, floor.item_count)
    end
    if not floor.legendary_count then
        local rarities = {}
        for i, rarity in ipairs(floor.item_rarities) do
            for _ = 1, rarity_shift do rarity = RARITY_UP[rarity] or rarity end
            rarities[i] = rarity
        end
        local items = {}
        for _ = 1, floor.item_count do
            local rarity = rarities[random_number(#rarities)]
            local item = rarity == "legendary" and pick_legendary_or_fallback(faction_name) or item_pool.pick_items(faction_name, { rarity }, 1)[1]
            if item then items[#items + 1] = item end
        end
        return items
    end
    local items = {}
    for _ = 1, floor.legendary_count do
        local item = item_pool.pick_legendary_item(faction_name)
        if item then items[#items + 1] = item end
    end
    local missing = floor.legendary_count - #items
    if missing > 0 then
        for _, item in ipairs(item_pool.pick_items(faction_name, { tower_data.legendary_fallback_rarity }, missing)) do
            items[#items + 1] = item
        end
    end
    return items
end

--- Builds the choice that pays the whole haul: its gold and items as the payload, plus `tower_data.unit_overflow_gold` for each sworn unit
--- still waiting (units only wait when the army has no room), and a line saying how many sworn units already joined the army.
--- @param choice_key string The choice key, e.g. "LEAPOI_TWR_LEAVE".
--- @param line string The `dummy_` key describing the choice.
--- @param haul table The delve's haul.
--- @returns table A choice record for `launch_dilemma`.
local function payout_choice(choice_key, line, haul)
    local lines = { line }
    if haul.joined > 0 then lines[2] = "dummy_land_enc_tower_units_joined_" .. math.min(haul.joined, MOST_JOINED_LINE) end
    return { key = choice_key, gold = haul.gold + #haul.units * tower_data.unit_overflow_gold, items = haul.items, lines = lines }
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerEventDelegate

--- Picks where a Daemon's deal army lands: a random distance from the settlement of a random region in the capital's province. A region with no
--- room falls back to the capital itself.
--- @param faction_key string The invading faction, whose movement rules decide which spots are valid.
--- @param capital userdata The delving faction's capital region.
--- @param distance table The { min, max } distance from the settlement.
--- @returns number The x coordinate, -1 when there is no room at all.
--- @returns number The y coordinate, -1 when there is no room at all.
--- @returns string The key of the region the army lands in.
local function province_spawn_point(faction_key, capital, distance)
    local regions = capital:province():regions()
    local region = regions:item_at(random_number(regions:num_items()) - 1)
    local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, random_number(distance[2], distance[1]))
    if x == -1 then
        region = capital
        x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, capital:name(), false, true, distance[1])
    end
    return x, y, region:name()
end

--- Logs who the floor battle lists on each side once it is set up, to confirm a floor's allied army joined it.
--- @param ally_faction string The allied army's faction key.
local function log_ally_battle(ally_faction)
    core:add_listener("land_enc_tower_ally_check", "PendingBattle", true, function(context)
        local listed, problem = pcall(function()
            local battle = context:pending_battle()
            local function sides(list)
                local names = {}
                for i = 0, list:num_items() - 1 do names[#names + 1] = list:item_at(i):faction():name() end
                return table.concat(names, " ")
            end
            log("tower: pending battle: attacker " .. battle:attacker():faction():name() .. ", defender " .. battle:defender():faction():name()
                .. ", secondary attackers [" .. sides(battle:secondary_attackers()) .. "], secondary defenders [" .. sides(battle:secondary_defenders())
                .. "], ally " .. ally_faction)
        end)
        if not listed then log("tower: pending battle check failed: " .. tostring(problem)) end
    end, false)
end

local TowerEventDelegate = {
    --- Every tower on the map, one per zone, in zone-name order.
    towers = {},
    --- Delve in progress per human faction: { zone_name, general_cqi, floor, haul = { gold, items, units, joined }, strength_before, floor_units,
    --- offers, taken, results, climb, battle_bundles, battle_tricks, missions, enemy_notices, in_battle, camping }. `haul.units` are sworn units
    --- waiting for room and `haul.joined` counts those already in the army. `offers` are the offer keys on the current go-deeper dilemma, `taken`
    --- marks offers taken this delve, `results` holds this floor's result lines and `climb` the floors so far as { floor, difficulty, state, bonus }.
    --- `battle_bundles` are the one-battle bundles on the delving army, `battle_tricks` the in-battle tricks the battle script does, `missions` the
    --- missions it tracks, `enemy_notices` the sabotage on the floor army being fought, and `in_battle` is true while a floor battle waits for its
    --- result. `last_battlefield` is where the last floor was fought. A delve ends within its turn unless it is `camping` until the next one.
    delves = {},
    --- Enter dilemma waiting for an answer per human faction: { zone_name, general_cqi }.
    pending_dilemma_by_faction = {},
    --- Tower dividends still paying out: { faction, amount, turns } per purchase, paid at each of that faction's turn starts.
    dividends = {},
    --- Lords a Dark bargain wounds at their faction's next turn start: { faction, general_cqi, turns }.
    wounds = {},
    --- Every encounter spot's {x, y} on the map, in zone-name order, where floors can be fought. Rebuilt from the zones on each load.
    battlefield_spots = {},
    --- Shared invasion battle manager that spawns and resolves floor battles.
    invasion_battle_manager = nil,
}

--- Places a tower in every zone that does not have one yet, restores the rest from the save, reserves their spots and shows their markers.
--- Zones are walked in name order so every multiplayer client places the same towers.
--- @param zones table The land manager's zones.
--- @param saved table|nil The table from `export_state_as_table`, or nil for a new campaign or an older save.
function TowerEventDelegate:initialize(zones, saved)
    saved = saved or {}
    local saved_by_zone, taken = {}, {}
    for _, record in ipairs(saved.towers or {}) do
        saved_by_zone[record.zone_name] = record
    end

    local zone_by_name, names = {}, {}
    for _, zone in ipairs(zones) do
        zone_by_name[zone.name] = zone
        names[#names + 1] = zone.name
    end
    table.sort(names)

    self.towers = {}
    local pending = {}
    for _, name in ipairs(names) do
        local spots = zone_by_name[name].spot_delegate.spots
        local record = saved_by_zone[name]
        if record and spots[record.spot_index] then
            --- A saved tower stays where it stands, even on a spot disabled since, so the save keeps its tower.
            self.towers[#self.towers + 1] = TowerState:new(name, record.spot_index, spots[record.spot_index].coordinates, record.faction, record.cooldown, record.echoes,
                record.last_delver)
            taken[record.faction] = true
        elseif #zone_by_name[name].spot_delegate.enabled_indexes > 0 then
            pending[#pending + 1] = name
        end
    end

    local next_faction = faction_picker(taken)
    for _, name in ipairs(pending) do
        local delegate = zone_by_name[name].spot_delegate
        local spots = delegate.spots
        --- A spot planted as a tower site wins over the random pick.
        local candidates = #delegate.tower_sites > 0 and delegate.tower_sites or delegate.enabled_indexes
        local spot_index = candidates[random_number(#candidates)]
        self.towers[#self.towers + 1] = TowerState:new(name, spot_index, spots[spot_index].coordinates, next_faction())
        log("Placed a tower in " .. name .. " at spot " .. spot_index .. " held by " .. tostring(self.towers[#self.towers].faction))
    end
    table.sort(self.towers, function(a, b) return a.zone_name < b.zone_name end)

    for _, tower in ipairs(self.towers) do
        zone_by_name[tower.zone_name].spot_delegate:reserve_spot(tower.zone_name, tower.spot_index)
    end
    self.battlefield_spots = {}
    for _, name in ipairs(names) do
        local delegate = zone_by_name[name].spot_delegate
        for _, i in ipairs(delegate.enabled_indexes) do self.battlefield_spots[#self.battlefield_spots + 1] = delegate.spots[i].coordinates end
    end
    self.delves = saved.delves or {}
    for faction_name, delve in pairs(self.delves) do
        if delve.in_battle then self:rearm_floor_battle(faction_name) end
        --- A frozen lord is not kept in the save, so a camping lord is frozen again.
        if delve.camping then
            local general = tower_army.character(delve.general_cqi)
            if general then cm:disable_movement_for_character(cm:char_lookup_str(general)) end
        end
    end
    self.pending_dilemma_by_faction = saved.pending_dilemma_by_faction or {}
    self.dividends = saved.dividends or {}
    self.wounds = saved.wounds or {}
    self:sync_markers()
end

--- Finds the tower in a zone.
--- @param zone_name string The zone to look in.
--- @returns TowerState|nil The zone's tower, or nil when it has none.
function TowerEventDelegate:tower_in_zone(zone_name)
    for _, tower in ipairs(self.towers) do
        if tower.zone_name == zone_name then return tower end
    end
    return nil
end

--- Shows every tower marker when towers are enabled in MCT, and removes them otherwise.
function TowerEventDelegate:sync_markers()
    local enabled = get_mct_settings().enable_towers
    for _, tower in ipairs(self.towers) do
        if enabled then
            TowerSpot.place_marker(tower.zone_name, tower.spot_index, tower.coordinates)
        else
            TowerSpot.remove_marker(tower.zone_name, tower.spot_index)
        end
    end
end

--- Ticks every tower's cooldown down by one turn and tells the last delver when a tower opens again. Runs once per round and does nothing
--- while towers are disabled.
function TowerEventDelegate:update_state_given_turn_passing()
    if not get_mct_settings().enable_towers then return end
    for _, tower in ipairs(self.towers) do
        if tower.cooldown > 0 then
            tower.cooldown = tower.cooldown - 1
            if tower.cooldown == 0 then show_ready_notice(tower.last_delver, "tower_ready", tower.coordinates) end
        end
    end
end

--- Pays the faction's Tower dividends, wounds lords a Dark bargain claimed, and closes a delve that outlived its turn, for example when a floor
--- battle never started. A closed delve counts as leaving the tower. A camping delve resumes instead: the lord can move again and the same
--- floor's choice reopens.
--- @param faction_name string The human faction whose turn is starting.
function TowerEventDelegate:on_faction_turn_start(faction_name)
    for i = #self.dividends, 1, -1 do
        local dividend = self.dividends[i]
        if dividend.faction == faction_name then
            cm:treasury_mod(faction_name, dividend.amount)
            dividend.turns = dividend.turns - 1
            log("tower: dividend of " .. dividend.amount .. " gold paid to " .. faction_name .. ", " .. dividend.turns .. " turns left")
            if dividend.turns <= 0 then table.remove(self.dividends, i) end
        end
    end
    for i = #self.wounds, 1, -1 do
        local wound = self.wounds[i]
        if wound.faction == faction_name then
            table.remove(self.wounds, i)
            local general = tower_army.character(wound.general_cqi)
            if general then
                tower_army.remove_bundle(wound.general_cqi, offers_data.by_key.dark_bargain.effect_bundle)
                local x, y = general:logical_position_x(), general:logical_position_y()
                cm:wound_character(cm:char_lookup_str(general), wound.turns)
                cm:show_message_event_located(faction_name, "event_feed_strings_text_title_event_land_enc_tower_dark_bargain_paid",
                    "event_feed_strings_text_subtitle_event_land_enc_tower_dark_bargain_paid", "event_feed_strings_text_description_event_land_enc_tower_dark_bargain_paid",
                    x, y, false, EVENT_IMAGE_ID_LOCATION_OF_INTEREST)
                log("tower: the Dark bargain wounds lord " .. wound.general_cqi .. " for " .. wound.turns .. " turns")
            end
        end
    end
    local delve = self.delves[faction_name]
    if delve and delve.camping then
        tower_offers.end_camp(delve)
        log("tower: " .. faction_name .. " breaks camp on floor " .. delve.floor)
        local line = common.get_localised_string("campaign_localised_strings_string_land_enc_tower_result_camp_in_the_tower")
        delve.results = line ~= "" and { line } or {}
        self:launch_deeper(faction_name)
    elseif delve then
        self:pay_haul(faction_name, delve)
        self:end_delve(faction_name, "tower_left")
    end
    self.pending_dilemma_by_faction[faction_name] = nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Delves

--- Handles a lord entering a tower. A human lord at an open tower gets the enter dilemma, and a cooling tower shows the turns left.
--- AI lords, disabled towers and factions already in a delve are ignored.
--- @param area_and_character_info table The AreaEntered context.
--- @param spot_info table The spot_info record for the tower's spot.
function TowerEventDelegate:trigger_event(area_and_character_info, spot_info)
    local character = area_and_character_info:family_member():character()
    local faction = character:faction()
    if not get_mct_settings().enable_towers or not is_human_and_it_is_its_turn(faction) then return end
    local faction_name = faction:name()
    local tower = self:tower_in_zone(spot_info.zone.name)
    if tower == nil or tower.spot_index ~= spot_info.spot_index or self.delves[faction_name] then return end

    if tower.cooldown > 0 then
        tower:show_message(faction_name, "tower_cooling_turns_" .. math.min(tower.cooldown, tower_data.longest_cooldown_message))
        return
    end
    self.pending_dilemma_by_faction[faction_name] = { zone_name = tower.zone_name, general_cqi = character:command_queue_index() }
    local enter_lines = { "dummy_land_enc_tower_held_by_" .. tower.faction, "dummy_land_enc_tower_descend_floor_1" }
    if tower.echoes[faction_name] then
        enter_lines = { "dummy_land_enc_tower_held_by_" .. tower.faction, "dummy_land_enc_tower_echoes", "dummy_land_enc_tower_descend_floor_2" }
    end
    launch_dilemma(EVENT_ENTER, {
        { key = "FIRST", lines = enter_lines },
        { key = "SECOND", lines = { "dummy_land_enc_tower_walk_away" } },
    }, faction_name)
end

--- Applies a tower dilemma choice: enter floor 1 or walk away, after a win climb, take an offer or leave, and after the last floor claim the
--- haul. The Leave and claim payloads pay the whole haul themselves, so choosing them only ends the delve. A stay offer reopens the same
--- floor's dilemma, and any other offer climbs (as a plain Climb when the haul could not pay for it). Per-floor choices route by choice key.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function TowerEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    local key = dilemma_choice_and_faction_info:dilemma()
    local choice = dilemma_choice_and_faction_info:choice()
    local faction_name = dilemma_choice_and_faction_info:faction():name()

    if key == EVENT_ENTER then
        local pending = self.pending_dilemma_by_faction[faction_name]
        self.pending_dilemma_by_faction[faction_name] = nil
        if pending == nil or choice ~= FIRST_OPTION then return end
        --- A tower that remembers this faction starts it on floor 2, with floor 1's base gold already in the haul and floor 1 skipped.
        local echoed = self:tower_in_zone(pending.zone_name).echoes[faction_name]
        log("tower: " .. faction_name .. " enters the tower in " .. pending.zone_name .. " with lord " .. pending.general_cqi .. " (held by "
            .. tostring(self:tower_in_zone(pending.zone_name).faction) .. (echoed and ", echoed: starts on floor 2" or "") .. ")")
        self.delves[faction_name] = {
            zone_name = pending.zone_name, general_cqi = pending.general_cqi, floor = echoed and 2 or 1,
            haul = { gold = echoed and tower_data.floors[1].gold or 0, items = {}, units = {}, joined = 0 }, offers = {}, taken = {}, results = {},
            climb = echoed and { { floor = 1, difficulty = tower_data.floors[1].difficulty, state = "skipped" } } or {},
        }
        self:launch_floor(faction_name)
    elseif key:sub(1, #EVENT_DEEPER + 7) == EVENT_DEEPER .. "_floor_" then
        local delve = self.delves[faction_name]
        if delve == nil then return end
        local choice_key = dilemma_choice_and_faction_info:choice_key()
        log("tower: " .. faction_name .. " chose " .. tostring(choice_key) .. " on " .. key)
        if choice_key == tower_offers.LEAVE then
            self:end_delve(faction_name, "tower_left")
            return
        elseif choice_key ~= "FIRST" then
            --- Scout the floor builds the army of the floor the next climb leads to.
            local scout = function() return (self:floor_army(faction_name, delve.bonus_floor and delve.floor or delve.floor + 1)).units_pool end
            local offer, result = tower_offers.take(choice_key, delve, faction_name, { dividends = self.dividends, tower = self:tower_in_zone(delve.zone_name),
                scout = scout })
            if offer == nil then
                self:launch_deeper(faction_name)
                return
            end
            --- A camping delve waits for the next turn, see `on_faction_turn_start`.
            if delve.camping then return end
            if offer.stay then
                if result then delve.results[#delve.results + 1] = result end
                self:launch_deeper(faction_name)
                return
            end
        end
        --- A bonus floor (Hidden floor) is fought without moving up. Skips have already moved the floor on.
        if delve.bonus_floor then
            delve.bonus_floor = nil
        else
            delve.floor = delve.floor + 1
        end
        self:launch_floor(faction_name)
    elseif key == EVENT_CLAIM then
        if self.delves[faction_name] == nil then return end
        self:end_delve(faction_name, "tower_cleared")
    end
end

--- Spawns the current floor's army and starts the battle, with the floor army attacking the delving lord. The lord defends, so declining
--- the battle is an ordinary retreat that keeps the army. A floor with an allied army is our attack instead, since the game only brings allies
--- in on the attacking side. Declining it keeps the army too, and loses the floor. A lord who is gone ends the delve as lost. A floor army with no
--- spawn point ends it without a cooldown on floor 1, and as leaving on later floors.
--- @param faction_name string The delving faction.
function TowerEventDelegate:launch_floor(faction_name)
    local delve = self.delves[faction_name]
    local tower = self:tower_in_zone(delve.zone_name)
    local general = tower_army.character(delve.general_cqi)
    if not general or not cm:char_is_general_with_army(general) then
        self:end_delve(faction_name, "tower_lost")
        return
    end

    delve.strength_before = tower_army.army_strength(delve.general_cqi)
    local next_floor = delve.next_floor or {}
    local army, difficulty, budget, budget_multiplier = self:floor_army(faction_name, delve.floor)
    --- A scouted floor is fought against the units the scouts saw.
    if next_floor.scouted then
        army.units_pool = next_floor.scouted
        log("tower: floor " .. delve.floor .. " is fought against the scouted army")
    end

    --- Fought far from the last battle, so the game picks a different map. A floor with no battlefield is fought where the lord stands, which the
    --- floor army must reach: the last floor's battlefield, or the tower.
    local battlefield = tower_battlefields.pick(faction_name, self.battlefield_spots, delve.last_battlefield or tower.coordinates)
    local spot = battlefield or { general:logical_position_x(), general:logical_position_y() }
    local ibm = self.invasion_battle_manager
    if not ibm:can_generate_battle(army, spot) then
        if delve.floor == 1 then
            self.delves[faction_name] = nil
            tower:show_message(faction_name, "tower_blocked")
        else
            self:pay_haul(faction_name, delve)
            self:end_delve(faction_name, "tower_left")
        end
        return
    end
    log("tower: launching floor " .. delve.floor .. " (" .. difficulty .. ", budget " .. army_budget_text(budget, budget_multiplier) .. ", faction "
        .. tostring(next_floor.faction or tower.faction) .. (next_floor.bonus and ", hidden floor" or "") .. ") against lord " .. delve.general_cqi
        .. ", next-floor changes " .. tower_offers.describe_next_floor(next_floor))
    if battlefield then tower_battlefields.move_lord(general, battlefield) end
    delve.last_battlefield = spot
    log("tower: floor " .. delve.floor .. " is fought at " .. spot[1] .. ", " .. spot[2] .. (battlefield and "" or ", where the lord stands"))
    ibm:generate_battle(army, general, spot)
    delve.in_battle = true
    local ally = army.reinforcing_ally_armies and army.reinforcing_ally_armies[1]
    --- Kept so a floor re-armed after a reload still removes the allied army.
    delve.ally_invasion = ally and ally.invasion_identifier or nil
    if ally then log_ally_battle(ally.faction) end
    delve.enemy_notices = next_floor.sabotage
    --- The army's units are only fixed once the battle is generated. Its lord and heroes are kept apart from `units`, so none can be sworn.
    delve.floor_units = {}
    for _, row in ipairs(army.units or {}) do
        for _ = 1, row.count or 1 do delve.floor_units[#delve.floor_units + 1] = row.id end
    end
    delve.floor_army_size = #delve.floor_units
    log("tower: floor " .. delve.floor .. " army has " .. delve.floor_army_size .. " units: " .. table.concat(delve.floor_units, ", "))
    --- Handed over once the units are known, since Night terrors picks its targets from them.
    tower_missions.clear_reports()
    delve.modifier_bundles = battle_modifiers.bundles(delve.modifiers, "ours")
    for _, bundle in ipairs(delve.modifier_bundles) do tower_army.apply_bundle(delve.general_cqi, bundle) end
    tower_offers.hand_buffs_to_battle(delve)
    ibm:mark_battle_forces_for_removal(army)
    ibm:reset_state_post_battle(self, "TowerSpot", nil, army)
end

--- Builds a floor's army from its record and the offers taken for it, without spawning it. Offers can replace the floor's record (Blood moon,
--- Soft landing, Tempt fate, Hidden floor) and its army's faction for one floor. A Mirror curse army copies the delving army's regular units.
--- @param faction_name string The delving faction.
--- @param floor_number number The floor the army is for.
--- @returns Army The floor army.
--- @returns string Its difficulty.
--- @returns table The difficulty's { min, max } budget.
--- @returns number The offers' budget multiplier.
function TowerEventDelegate:floor_army(faction_name, floor_number)
    local delve = self.delves[faction_name]
    local tower = self:tower_in_zone(delve.zone_name)
    local general = cm:get_character_by_cqi(delve.general_cqi)
    local next_floor = delve.next_floor or {}
    --- The debug overrides (configs/debug.lua) replace the difficulty and budget for in-game testing.
    local floor, difficulty = tower_data.floor_difficulty(next_floor, floor_number, debug_config)
    local budget = #debug_config.floor_budget == 2 and debug_config.floor_budget or tower_data.budget_by_difficulty[difficulty]
    local budget_multiplier = (next_floor.budget or 1) * get_mct_settings().tower_enemy_percent / 100
    local sabotage = tower_offers.sabotage_options(next_floor)
    --- A sized allied army (Allies in the dark): its lord and a set number of regular units, with gold to buy them all.
    local ally_options = nil
    if type(next_floor.ally) == "table" then
        local units = random_number(next_floor.ally[2], next_floor.ally[1]) - 1
        ally_options = battle_modifiers.ally_options(units, next_floor.ally_theme)
        log("tower: the floor " .. floor_number .. " allied army fields its lord and " .. units .. " units" .. battle_modifiers.ally_theme_log(next_floor.ally_theme))
    end
    local army = Army:new_from_event({
        dilemma = "tower",
        faction = next_floor.faction or tower.faction,
        difficulty = difficulty,
        budget_range = { math.floor(budget[1] * budget_multiplier + 0.5), math.floor(budget[2] * budget_multiplier + 0.5) },
        intervention = next_floor.ally and ALLIED_REINFORCEMENTS_PERMITTED_TYPE or INTERCEPTION_TYPE,
        force_identifier = "tower_force_" .. faction_name,
        invasion_identifier = FLOOR_INVASION_PREFIX .. faction_name,
        no_heroes = sabotage.no_heroes,
        fewer_units = sabotage.fewer_units,
        max_tier = sabotage.max_tier,
        min_tier = sabotage.min_tier,
        strip_types = sabotage.strip_types,
        lord_subtype = sabotage.lord_subtype,
        ally_options = ally_options,
        ally_bundles = battle_modifiers.bundles(delve.modifiers, "allies"),
        composition = battle_modifiers.composition(delve.modifiers),
    }, general:faction():subculture())
    --- The battle manager puts these on the floor army once it spawns, with the battle modifiers' enemy bundles.
    for _, bundle in ipairs(battle_modifiers.bundles(delve.modifiers, "enemy")) do offer_effects.merge_sabotage(sabotage, { enemy_bundle = bundle }) end
    army.sabotage = sabotage
    if next_floor.mirror then
        army.units_pool, delve.mirror_copied = tower_offers.mirror_units(delve)
        log("tower: the floor " .. floor_number .. " army mirrors " .. delve.mirror_copied .. " of our units")
    end
    return army, difficulty, budget, budget_multiplier
end

--- Re-arms a floor battle that was pending when the game was saved. The battle result and floor army cleanup are game listeners, which are
--- not saved, so without this the floor never resolves after a load and the tower stays stuck in the delve until the next turn. The army's buffs
--- are handed to the battle again too.
--- @param faction_name string The delving faction.
function TowerEventDelegate:rearm_floor_battle(faction_name)
    --- Only the invasion ids are needed to route the result and remove the floor army, and its allied army if it had one.
    local ally_invasion = self.delves[faction_name].ally_invasion
    local army = setmetatable({ invasion_identifier = FLOOR_INVASION_PREFIX .. faction_name, reinforcing_enemy_armies = {},
        reinforcing_ally_armies = ally_invasion and { { invasion_identifier = ally_invasion } } or {} }, { __index = Army })
    local ibm = self.invasion_battle_manager
    ibm:mark_battle_forces_for_removal(army)
    ibm:reset_state_post_battle(self, "TowerSpot", nil, army)
    tower_offers.hand_buffs_to_battle(self.delves[faction_name])
end

--- Adds a won floor's rewards to the haul. Gold scales with how much of the delving army's strength the floor cost.
--- @param faction_name string The delving faction.
--- @param delve table The delve record.
--- @returns table { gold = the floor's gold, items = the floor's items, record = the floor record }, for the missions to pay from.
function TowerEventDelegate:add_floor_rewards(faction_name, delve)
    local next_floor = delve.next_floor or {}
    delve.next_floor = nil
    local floor = next_floor.record or tower_data.floors[delve.floor]
    local before, after = delve.strength_before, tower_army.army_strength(delve.general_cqi)
    local loss = (before and after) and math.max(0, before - after) or 0
    local gold_multiplier = performance_multiplier(loss) * (next_floor.gold or 1) * battle_modifiers.gold_multiplier(delve.modifiers)
        * get_mct_settings().tower_gold_percent / 100
    if next_floor.double_or_nothing then
        gold_multiplier = gold_multiplier * (loss < next_floor.double_or_nothing and 2 or 0)
    end
    local gold = tower_data.round_gold(floor.gold * gold_multiplier)
    if next_floor.mirror then
        local bonus = tower_offers.mirror_bonus(delve.mirror_copied or 0)
        log("tower: the mirror floor adds " .. bonus .. " gold for " .. tostring(delve.mirror_copied) .. " copied units")
        gold = gold + bonus
        delve.mirror_copied = nil
    end
    delve.haul.gold = delve.haul.gold + gold
    log("tower: floor " .. delve.floor .. " won: strength " .. tostring(before) .. " -> " .. tostring(after) .. " (loss " .. loss .. "), gold x"
        .. gold_multiplier .. " = +" .. gold .. ", haul now " .. delve.haul.gold .. " gold")
    delve.climb[#delve.climb + 1] = { floor = delve.floor, difficulty = floor.difficulty, state = "cleared", bonus = next_floor.bonus }
    local items = pick_floor_items(faction_name, floor, next_floor.rarity_shift)
    tower_data.add_items(delve.haul, items)
    log("tower: floor " .. delve.floor .. " items: " .. (#items > 0 and table.concat(items, ", ") or "none"))
    --- A Hellforge pact costs haul items for every floor won after it.
    for _ = 1, delve.hellforge and offers_data.by_key.hellforge_pact.items_lost or 0 do
        if #delve.haul.items == 0 then break end
        log("tower: the Hellforge pact takes " .. table.remove(delve.haul.items, random_number(#delve.haul.items)) .. " from the haul")
    end
    local candidates = delve.floor_units or {}
    for _ = 1, math.min(debug_config.floor_sworn_units[delve.floor] or floor.sworn_units, #candidates) do
        delve.haul.units[#delve.haul.units + 1] = table.remove(candidates, random_number(#candidates))
        log("tower: floor " .. delve.floor .. " swears " .. delve.haul.units[#delve.haul.units])
    end
    return { gold = gold, items = items, record = floor }
end

--- Removes the delving army's weakest regular units after a won floor, as many as the debug `floor_kill_units` override says for it, so
--- offers that need room can be tested with a full army. Does nothing while the override is empty.
--- @param delve table The delve record.
function TowerEventDelegate:debug_kill_units(delve)
    local general = cm:get_character_by_cqi(delve.general_cqi)
    for _ = 1, debug_config.floor_kill_units[delve.floor] or 0 do
        local weakest = tower_army.weakest_regular_unit(delve.general_cqi)
        if not weakest or not general or general:is_null_interface() then return end
        cm:remove_unit_from_character(cm:char_lookup_str(general), weakest.unit:unit_key())
        log("tower: debug override removes " .. weakest.unit:unit_key() .. " after floor " .. delve.floor .. " to free a slot")
    end
end

--- Moves sworn units waiting in the haul into the delving army while it has free slots, oldest first. Units that joined stay even if the
--- delve is later lost. The rest keep waiting and try again after the next win, once losses may have freed slots.
--- @param delve table The delve record.
function TowerEventDelegate:swear_in_units(delve)
    local force = tower_army.delving_force(delve.general_cqi)
    if not force then return end
    local lookup = cm:char_lookup_str(cm:get_character_by_cqi(delve.general_cqi))
    for _ = 1, math.min(tower_army.free_slots(force), #delve.haul.units) do
        local unit = table.remove(delve.haul.units, 1)
        cm:grant_unit_to_character(lookup, unit)
        delve.haul.joined = delve.haul.joined + 1
        log("tower: sworn unit " .. unit .. " joins the army")
    end
end

--- Resolves a floor battle and ends any one-battle effects bought for it. A loss ends the delve and forfeits the haul. A win adds the floor to
--- the haul, then offers the claim after the last floor, or draws this floor's offers and opens its go-deeper dilemma.
--- @param player_won_battle boolean True when the delving faction won.
--- @param faction_name string The delving faction.
function TowerEventDelegate:trigger_event_given_battle_result(player_won_battle, faction_name)
    local delve = self.delves[faction_name]
    if delve == nil then return end
    delve.in_battle = nil
    log("tower: floor " .. delve.floor .. " battle result for " .. faction_name .. ": " .. (player_won_battle and "victory" or "defeat"))
    --- The battle's reports are read before the one-battle effects clear them.
    local outcomes = tower_missions.read_outcomes(delve)
    tower_offers.end_battle_effects(delve)
    delve.ally_invasion = nil
    tower_offers.settle_last_stand(delve, player_won_battle)
    if not player_won_battle then
        self:end_delve(faction_name, "tower_lost", true)
        return
    end
    local floor = self:add_floor_rewards(faction_name, delve)
    local results = tower_missions.settle(delve, faction_name, outcomes, floor)
    self:swear_in_units(delve)
    self:debug_kill_units(delve)
    tower_lords.add_trait(delve.general_cqi, tower_data.climber_trait, 1, false)
    if delve.floor >= #tower_data.floors then
        --- The claim shows the last floor's results and the whole climb.
        delve.results = results
        tower_offers.show_results(delve)
        tower_offers.show_climb(delve)
        local claim = payout_choice("FIRST", "dummy_land_enc_tower_claim", delve.haul)
        if tower_data.floors[delve.floor].freed_hero_rank then claim.lines[#claim.lines + 1] = "dummy_land_enc_tower_freed_hero" end
        launch_dilemma(EVENT_CLAIM, { claim }, faction_name)
        return
    end
    --- The next floor's battle modifiers, rolled before its offers so they can keep some out.
    delve.modifiers = battle_modifiers.roll({ faction = self:tower_in_zone(delve.zone_name).faction, difficulty = tower_offers.next_floor_difficulty(delve) })
    delve.offers = tower_offers.draw(delve, faction_name, self:tower_in_zone(delve.zone_name))
    delve.results = results
    self:launch_deeper(faction_name)
end

--- Opens the current floor's go-deeper dilemma: Climb, the drawn offers, then Leave with the haul. Its description shows this floor's
--- stay-offer results and the climb so far.
--- @param faction_name string The delving faction.
function TowerEventDelegate:launch_deeper(faction_name)
    local delve = self.delves[faction_name]
    tower_offers.show_results(delve)
    tower_offers.show_climb(delve)
    local next_floor = delve.floor + 1
    local choices = { { key = "FIRST", lines = { "dummy_land_enc_tower_descend_floor_" .. next_floor } } }
    for _, offer_key in ipairs(delve.offers) do
        choices[#choices + 1] = tower_offers.choice(offer_key, delve, next_floor)
    end
    choices[#choices + 1] = payout_choice(tower_offers.LEAVE, "dummy_land_enc_tower_leave", delve.haul)
    launch_dilemma(EVENT_DEEPER .. "_floor_" .. delve.floor, choices, faction_name)
end

--- Sends a Daemon's deal army at the delving faction's capital: an army of a random Chaos faction from the `daemons_deal` offer, spawned
--- somewhere in the capital's province as a lasting invasion that stays until beaten. A faction with no capital is spared.
--- @param faction_name string The delving faction.
--- @param count number|nil How many armies to send, each under its own invasion name. nil sends one.
function TowerEventDelegate:send_daemon_army(faction_name, count)
    for index = 1, count or 1 do self:send_one_daemon_army(faction_name, index) end
end

--- Sends one Daemon's deal army, see `send_daemon_army`.
--- @param faction_name string The delving faction.
--- @param index number Which of this turn's armies it is. The second and later add it to their invasion names.
function TowerEventDelegate:send_one_daemon_army(faction_name, index)
    local faction = cm:get_faction(faction_name)
    local region = faction and faction:home_region()
    if not region or region:is_null_interface() then
        log("tower: Daemon's deal has no capital to march on for " .. faction_name)
        return
    end
    local deal = offers_data.by_key.daemons_deal
    local suffix = index > 1 and "_" .. index or ""
    local shorthand = deal.factions[random_number(#deal.factions)]
    local army = Army:new_from_event({
        dilemma = "tower",
        faction = shorthand,
        difficulty = deal.difficulty,
        budget_range = tower_data.budget_by_difficulty[deal.difficulty],
        intervention = INTERCEPTION_TYPE,
        force_identifier = "tower_daemon_force_" .. faction_name .. suffix,
        invasion_identifier = "tower_daemon_" .. faction_name .. "_" .. cm:turn_number() .. suffix,
    }, faction:subculture())
    local x, y, landing = province_spawn_point(army.faction, region, deal.spawn_distance)
    if x == -1 then
        x, y, landing = region:settlement():logical_position_x(), region:settlement():logical_position_y(), region:name()
    end
    local sent = self.invasion_battle_manager:spawn_raid(army, region:name(), faction_name, x, y)
    log("tower: Daemon's deal sends a " .. deal.difficulty .. " " .. shorthand .. " army at " .. region:name() .. " for " .. faction_name .. ", landing in "
        .. landing .. " at " .. x .. ", " .. y .. ": " .. (sent and "spawned" or "no room to spawn"))
end

--- Hands a tower to a new enabled faction, preferring one no other tower holds. A tower whose faction is the only one enabled keeps it.
--- Picks with `random_number`, so every multiplayer client agrees.
--- @param tower table The TowerState to change.
function TowerEventDelegate:reroll_faction(tower)
    local held = {}
    for _, other in ipairs(self.towers) do held[other.faction] = true end
    local free, others = {}, {}
    for _, key in ipairs(sorted_faction_keys()) do
        if key ~= tower.faction then
            others[#others + 1] = key
            if not held[key] then free[#free + 1] = key end
        end
    end
    local pool = #free > 0 and free or others
    if #pool == 0 then return end
    local was = tower.faction
    tower.faction = pool[random_number(#pool)]
    log("tower: " .. tower.zone_name .. " is now held by " .. tower.faction .. " (was " .. tostring(was) .. ")")
end

--- Pays a delve's haul from script, for a delve that ends without its Leave or claim dilemma: its gold, its items, and the overflow gold of each
--- sworn unit still waiting for room.
--- @param faction_name string The delving faction.
--- @param delve table The delve record.
function TowerEventDelegate:pay_haul(faction_name, delve)
    local haul = delve.haul
    local gold = haul.gold + #haul.units * tower_data.unit_overflow_gold
    if gold > 0 then cm:treasury_mod(faction_name, gold) end
    local faction = cm:get_faction(faction_name)
    for _, item in ipairs(haul.items) do cm:add_ancillary_to_faction(faction, item, false) end
    log("tower: paid the haul of a delve closed without a choice: " .. gold .. " gold, " .. #haul.items .. " items")
end

--- Ends a delve, takes off any one-battle effects, puts its tower on cooldown, hands it to a new faction and tells the player how it ended.
--- @param faction_name string The delving faction.
--- @param outcome string The message suffix: "tower_left", "tower_lost" or "tower_cleared".
--- @param in_battle_sequence boolean|nil True when called from a battle's result, so the lord is only moved once the battle sequence is over.
function TowerEventDelegate:end_delve(faction_name, outcome, in_battle_sequence)
    local delve = self.delves[faction_name]
    log("tower: delve for " .. faction_name .. " ends: " .. outcome .. " on floor " .. delve.floor .. ", haul " .. delve.haul.gold .. " gold, "
        .. #delve.haul.items .. " items (" .. table.concat(delve.haul.items, ", ") .. "), " .. #delve.haul.units .. " sworn units waiting, "
        .. delve.haul.joined .. " joined")
    tower_offers.end_delve_effects(delve)
    local tower = self:tower_in_zone(delve.zone_name)
    self.delves[faction_name] = nil
    if in_battle_sequence then
        --- Touching the lord during the battle sequence leaves the game on a stale pre-battle screen.
        core:add_listener("land_enc_tower_return_lord_" .. delve.general_cqi, "ScriptEventPlayerBattleSequenceCompleted", true, function()
            tower_battlefields.return_lord(delve.general_cqi, faction_name, tower.coordinates)
        end, false)
    else
        --- Before the freed hero, who is placed beside the lord.
        tower_battlefields.return_lord(delve.general_cqi, faction_name, tower.coordinates)
    end
    tower.cooldown = get_mct_settings().tower_cooldown
    tower.last_delver = faction_name
    log("tower: " .. tower.zone_name .. " closed for " .. tower.cooldown .. " turns, last delver " .. faction_name)
    tower:show_message(faction_name, outcome)
    if outcome == "tower_cleared" then
        local rank = tower_data.floors[#tower_data.floors].freed_hero_rank
        if rank then tower_lords.free_hero(delve.general_cqi, faction_name, { tower.faction, offer_effects.culture_shorthand(faction_name) }, rank) end
        if delve.epithet then
            local epithet = offers_data.by_key.epithet
            tower_lords.add_trait(delve.general_cqi, epithet.trait, 1, true)
            tower_lords.add_title(delve.general_cqi, common.get_localised_string(epithet.title_loc))
        end
    end
    if delve.dark_bargain then self.wounds[#self.wounds + 1] = { faction = faction_name, general_cqi = delve.general_cqi, turns = delve.dark_bargain } end
    --- After the freed hero, who comes from the faction just beaten.
    self:reroll_faction(tower)
    --- Sent last, so a failed spawn cannot leave the delve half-ended.
    --- An older save holds true for one army.
    if delve.daemons_deal then self:send_daemon_army(faction_name, delve.daemons_deal == true and 1 or delve.daemons_deal) end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Save and load

--- Exports the towers, delves in progress, open enter dilemmas, dividends still paying and pending wounds for the save file.
--- @returns table { towers, delves, pending_dilemma_by_faction, dividends, wounds }.
function TowerEventDelegate:export_state_as_table()
    local towers = {}
    for i, tower in ipairs(self.towers) do
        towers[i] = tower:export()
    end
    return { towers = towers, delves = self.delves, pending_dilemma_by_faction = self.pending_dilemma_by_faction, dividends = self.dividends,
        wounds = self.wounds }
end

--- Builds an empty delegate. `initialize` places or restores the towers once the zones exist.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns TowerEventDelegate The new delegate.
function TowerEventDelegate:new(invasion_battle_manager)
    local t = { towers = {}, delves = {}, pending_dilemma_by_faction = {}, dividends = {}, wounds = {}, battlefield_spots = {},
        invasion_battle_manager = invasion_battle_manager }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TowerEventDelegate
