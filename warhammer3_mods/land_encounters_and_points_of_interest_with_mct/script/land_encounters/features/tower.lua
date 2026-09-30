--- TowerState + TowerEventDelegate. One tower stands in every zone, on one of that zone's encounter spots, and is held by one enemy
--- faction for the whole campaign. A human lord who enters fights up to five floors in a row, choosing after each win to go deeper or
--- leave. TowerEventDelegate places the towers, runs the delves, keeps the markers in line with MCT, ticks cooldowns and saves it all.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")
require("script/land_encounters/core/managers")

local tower_data = require("script/land_encounters/configs/tower_data")
local item_pool = require("script/land_encounters/core/item_pool")
local TowerSpot = require("script/land_encounters/core/spot").TowerSpot
local Army = require("script/land_encounters/core/army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0

--- Go-deeper choices after Climb (FIRST): tend the wounded, hold war rites, or leave. The older shared go-deeper dilemma only has Climb and
--- Leave, with Leave second.
local CHOICE_TEND_WOUNDED = 1
local CHOICE_WAR_RITES = 2
local CHOICE_LEAVE = 3
local CHOICE_LEAVE_SHARED_DILEMMA = 1

local EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017

--- Dilemma offered when a lord enters an open tower.
local EVENT_ENTER = "land_enc_dilemma_tower_enter"
--- Dilemma offered after winning every floor but the last. The floor number is appended, so each floor's description can show the climb so
--- far. The bare key is still handled, since older saves can hold a dilemma opened with it.
local EVENT_DEEPER = "land_enc_dilemma_tower_deeper"
--- One-choice dilemma that pays the full haul after the last floor.
local EVENT_CLAIM = "land_enc_dilemma_tower_claim"

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
}

--- Builds a tower record.
--- @param zone_name string Zone the tower stands in.
--- @param spot_index number Index of the encounter spot the tower occupies.
--- @param coordinates table The tower's {x, y} position.
--- @param faction string Shorthand of the faction holding the tower.
--- @param cooldown number Turns left before the tower opens.
--- @returns TowerState The new tower.
function TowerState:new(zone_name, spot_index, coordinates, faction, cooldown)
    local t = { zone_name = zone_name, spot_index = spot_index, coordinates = coordinates, faction = faction, cooldown = cooldown or 0 }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- Exports the tower as a plain table for the save file.
--- @returns table The tower's saved fields.
function TowerState:export()
    return { zone_name = self.zone_name, spot_index = self.spot_index, coordinates = self.coordinates, faction = self.faction, cooldown = self.cooldown }
end

--- Shows a located event feed message at the tower.
--- @param faction_name string The faction to show the message to.
--- @param message string The message suffix, e.g. "tower_lost" for event_feed_strings_text_title_event_land_enc_tower_lost.
function TowerState:show_message(faction_name, message)
    cm:show_message_event_located(faction_name,
        "event_feed_strings_text_title_event_land_enc_" .. message,
        "event_feed_strings_text_subtitle_event_land_enc_" .. message,
        "event_feed_strings_text_description_event_land_enc_" .. message,
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Returns a picker that hands out the enabled faction shorthands in a shuffled order, skipping ones already taken, and starts over once
--- every faction is used. The shorthands are sorted before the shuffle so every multiplayer client sees the same order.
--- @param taken table Shorthand -> true set of factions restored towers already hold.
--- @returns function A function that returns the next faction shorthand.
local function faction_picker(taken)
    local keys = get_enabled_faction_keys()
    table.sort(keys)
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

--- Launches a custom dilemma. Each choice shows text lines and can pay gold, items and units when chosen.
--- @param key string The dilemma key.
--- @param choices table An array of { key = "FIRST", lines = { `dummy_` keys }, gold = number or nil, items = { ancillary keys } or nil,
--- units = { force = military force, keys = { unit keys } } or nil }. Units show as cards and join that army.
--- @param faction_name string The faction to show the dilemma to.
local function launch_dilemma(key, choices, faction_name)
    local faction = cm:get_faction(faction_name)
    local builder = cm:create_dilemma_builder(key)
    local payload = cm:create_payload()
    for _, choice in ipairs(choices) do
        if choice.gold and choice.gold > 0 then
            payload:treasury_adjustment(choice.gold)
        end
        for _, item in ipairs(choice.items or {}) do
            payload:faction_ancillary_gain(faction, item)
        end
        if choice.units then
            --- One card per unit key, with the number of copies, in the order the units were sworn.
            local counts, order = {}, {}
            for _, unit in ipairs(choice.units.keys) do
                if not counts[unit] then order[#order + 1] = unit end
                counts[unit] = (counts[unit] or 0) + 1
            end
            for _, unit in ipairs(order) do
                payload:add_unit(choice.units.force, unit, counts[unit], 0)
            end
        end
        for _, line in ipairs(choice.lines or {}) do
            payload:text_display(line)
        end
        builder:add_choice_payload(choice.key, payload)
        payload:clear()
    end
    cm:launch_custom_dilemma_from_builder(builder, faction)
end

--- Finds the delving lord's army.
--- @param general_cqi number The delving lord's command queue index.
--- @returns military_force|nil The army, or nil when the lord is gone or no longer leads one.
local function delving_force(general_cqi)
    local general = cm:get_character_by_cqi(general_cqi)
    if not general or general:is_null_interface() or not general:has_military_force() then return nil end
    return general:military_force()
end

--- Reads the delving lord's army strength, or nil when the lord no longer leads an army.
--- @param general_cqi number The delving lord's command queue index.
--- @returns number|nil The army's average unit strength (0-100).
local function army_strength(general_cqi)
    local force = delving_force(general_cqi)
    return force and cm:military_force_average_strength(force)
end

--- Takes a paid option's cost out of the haul's gold, unless the haul holds too little.
--- @param haul table The delve's haul.
--- @param cost number The option's gold cost.
--- @returns boolean True when the haul paid.
local function pay_from_haul(haul, cost)
    if haul.gold < cost then return false end
    haul.gold = haul.gold - cost
    return true
end

--- Heals a share of each unit's missing strength in the delving army.
--- @param general_cqi number The delving lord's command queue index.
--- @param share number Share of the missing strength to restore (0-1).
local function heal_army(general_cqi, share)
    local force = delving_force(general_cqi)
    if not force then return end
    local units = force:unit_list()
    for i = 0, units:num_items() - 1 do
        local unit = units:item_at(i)
        local strength = unit:percentage_proportion_of_full_strength()
        cm:set_unit_hp_to_unary_of_maximum(unit, (strength + share * (100 - strength)) / 100)
    end
end

--- Takes the war rites bundle off the delving army once the floor it was bought for is over.
--- @param delve table The delve record.
local function end_war_rites(delve)
    if not delve.war_rites then return end
    delve.war_rites = nil
    local force = delving_force(delve.general_cqi)
    if force then cm:remove_effect_bundle_from_force(tower_data.war_rites.effect_bundle, force:command_queue_index()) end
end

--- Builds a paid go-deeper choice: its cost line, or a not-enough-gold line when the haul cannot pay, then the next floor's line.
--- @param choice_key string The choice key, e.g. "SECOND".
--- @param option string The option's line suffix and `tower_data` key: "tend_wounded" or "war_rites".
--- @param haul table The delve's haul.
--- @param next_floor number The floor the choice climbs to.
--- @returns table A choice record for `launch_dilemma`.
local function paid_choice(choice_key, option, haul, next_floor)
    local line = "dummy_land_enc_tower_" .. option
    if haul.gold < tower_data[option].cost then line = line .. "_unaffordable" end
    return { key = choice_key, lines = { line, "dummy_land_enc_tower_descend_floor_" .. next_floor } }
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

--- Adds picked items to the haul, skipping any already in it.
--- @param haul table The delve's haul.
--- @param items table Ancillary keys to add.
local function add_items(haul, items)
    local held = {}
    for _, item in ipairs(haul.items) do held[item] = true end
    for _, item in ipairs(items) do
        if not held[item] then
            haul.items[#haul.items + 1] = item
            held[item] = true
        end
    end
end

--- Picks a floor's items: its rarities, or legendary items with a rare standing in for each one the pool cannot supply.
--- @param faction_name string The delving faction.
--- @param floor table The floor record from `tower_data.floors`.
--- @returns table Ancillary keys.
local function pick_floor_items(faction_name, floor)
    if not floor.legendary_count then
        return item_pool.pick_items(faction_name, floor.item_rarities, floor.item_count)
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

--- Counts the free unit slots in an army.
--- @param force military_force The army.
--- @returns number Slots left under its unit limit.
local function free_slots(force)
    return math.max(0, force:unit_count_limit() - force:unit_list():num_items())
end

--- Builds the choice that pays the whole haul: its gold and items as the payload, plus `tower_data.unit_overflow_gold` for each sworn unit
--- still waiting (units only wait when the army has no room), and a line saying how many sworn units already joined the army.
--- @param choice_key string The choice key, e.g. "FOURTH".
--- @param line string The `dummy_` key describing the choice.
--- @param haul table The delve's haul.
--- @returns table A choice record for `launch_dilemma`.
local function payout_choice(choice_key, line, haul)
    local lines = { line }
    if (haul.joined or 0) > 0 then lines[2] = "dummy_land_enc_tower_units_joined_" .. haul.joined end
    return { key = choice_key, gold = haul.gold + #haul.units * tower_data.unit_overflow_gold, items = haul.items, lines = lines }
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerEventDelegate

local TowerEventDelegate = {
    --- Every tower on the map, one per zone, in zone-name order.
    towers = {},
    --- Delve in progress per human faction: { zone_name, general_cqi, floor, haul = { gold, items, units, joined }, strength_before,
    --- floor_units, war_rites }. `haul.units` are sworn units waiting for room and `haul.joined` counts those already in the army. `war_rites`
    --- is true while the delving army carries the war rites bundle. A delve starts and ends within one turn.
    delves = {},
    --- Enter dilemma waiting for an answer per human faction: { zone_name, general_cqi }.
    pending_dilemma_by_faction = {},
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
            self.towers[#self.towers + 1] = TowerState:new(name, record.spot_index, spots[record.spot_index].coordinates, record.faction, record.cooldown)
            taken[record.faction] = true
        elseif #spots > 0 then
            pending[#pending + 1] = name
        end
    end

    local next_faction = faction_picker(taken)
    for _, name in ipairs(pending) do
        local spots = zone_by_name[name].spot_delegate.spots
        local spot_index = random_number(#spots)
        self.towers[#self.towers + 1] = TowerState:new(name, spot_index, spots[spot_index].coordinates, next_faction())
        log("Placed a tower in " .. name .. " at spot " .. spot_index .. " held by " .. tostring(self.towers[#self.towers].faction))
    end
    table.sort(self.towers, function(a, b) return a.zone_name < b.zone_name end)

    for _, tower in ipairs(self.towers) do
        zone_by_name[tower.zone_name].spot_delegate:reserve_spot(tower.zone_name, tower.spot_index)
    end
    self.delves = saved.delves or {}
    self.pending_dilemma_by_faction = saved.pending_dilemma_by_faction or {}
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

--- Ticks every tower's cooldown down by one turn. Runs once per round and does nothing while towers are disabled.
function TowerEventDelegate:update_state_given_turn_passing()
    if not get_mct_settings().enable_towers then return end
    for _, tower in ipairs(self.towers) do
        if tower.cooldown > 0 then
            tower.cooldown = tower.cooldown - 1
        end
    end
end

--- Closes a delve that outlived its turn, for example when a floor battle never started. It counts as leaving the tower.
--- @param faction_name string The human faction whose turn is starting.
function TowerEventDelegate:on_faction_turn_start(faction_name)
    if self.delves[faction_name] then
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
    launch_dilemma(EVENT_ENTER, {
        { key = "FIRST", lines = { "dummy_land_enc_tower_held_by_" .. tower.faction, "dummy_land_enc_tower_descend_floor_1" } },
        { key = "SECOND", lines = { "dummy_land_enc_tower_walk_away" } },
    }, faction_name)
end

--- Applies a tower dilemma choice: enter floor 1 or walk away, after a win go deeper or leave, and after the last floor claim the haul. The
--- Leave and claim payloads pay the whole haul themselves, so choosing them only ends the delve. Tending the wounded and war rites are paid
--- from the haul before climbing, and climb as a plain Climb when the haul cannot pay.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function TowerEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    local key = dilemma_choice_and_faction_info:dilemma()
    local choice = dilemma_choice_and_faction_info:choice()
    local faction_name = dilemma_choice_and_faction_info:faction():name()

    if key == EVENT_ENTER then
        local pending = self.pending_dilemma_by_faction[faction_name]
        self.pending_dilemma_by_faction[faction_name] = nil
        if pending == nil or choice ~= FIRST_OPTION then return end
        self.delves[faction_name] = { zone_name = pending.zone_name, general_cqi = pending.general_cqi, floor = 1, haul = { gold = 0, items = {}, units = {}, joined = 0 } }
        self:launch_floor(faction_name)
    elseif key == EVENT_DEEPER or key:sub(1, #EVENT_DEEPER + 7) == EVENT_DEEPER .. "_floor_" then
        local delve = self.delves[faction_name]
        if delve == nil then return end
        if choice == (key == EVENT_DEEPER and CHOICE_LEAVE_SHARED_DILEMMA or CHOICE_LEAVE) then
            self:end_delve(faction_name, "tower_left")
            return
        end
        if choice == CHOICE_TEND_WOUNDED and pay_from_haul(delve.haul, tower_data.tend_wounded.cost) then
            heal_army(delve.general_cqi, tower_data.tend_wounded.heal_share)
        elseif choice == CHOICE_WAR_RITES and pay_from_haul(delve.haul, tower_data.war_rites.cost) then
            local force = delving_force(delve.general_cqi)
            if force then
                cm:apply_effect_bundle_to_force(tower_data.war_rites.effect_bundle, force:command_queue_index(), 0)
                delve.war_rites = true
            end
        end
        delve.floor = delve.floor + 1
        self:launch_floor(faction_name)
    elseif key == EVENT_CLAIM then
        if self.delves[faction_name] == nil then return end
        self:end_delve(faction_name, "tower_cleared")
    end
end

--- Spawns the current floor's army and starts the battle, with the floor army attacking the delving lord. The lord defends, so declining
--- the battle is an ordinary retreat that keeps the army (a forced attacker who backs out loses the whole army). A lord who is gone ends the
--- delve as lost. A floor army with no spawn point ends it without a cooldown on floor 1, and as leaving on later floors.
--- @param faction_name string The delving faction.
function TowerEventDelegate:launch_floor(faction_name)
    local delve = self.delves[faction_name]
    local tower = self:tower_in_zone(delve.zone_name)
    local general = cm:get_character_by_cqi(delve.general_cqi)
    if not general or general:is_null_interface() or not cm:char_is_general_with_army(general) then
        self:end_delve(faction_name, "tower_lost")
        return
    end

    delve.strength_before = army_strength(delve.general_cqi)
    local floor = tower_data.floors[delve.floor]
    local army = Army:new_from_event({
        dilemma = "tower",
        faction = tower.faction,
        difficulty = floor.difficulty,
        budget_range = tower_data.budget_by_difficulty[floor.difficulty],
        intervention = INTERCEPTION_TYPE,
        force_identifier = "tower_force_" .. faction_name,
        invasion_identifier = "tower_invasion_" .. faction_name,
    }, general:faction():subculture())

    local ibm = self.invasion_battle_manager
    if not ibm:can_generate_battle(army, tower.coordinates) then
        if delve.floor == 1 then
            self.delves[faction_name] = nil
            tower:show_message(faction_name, "tower_blocked")
        else
            self:end_delve(faction_name, "tower_left")
        end
        return
    end
    ibm:generate_battle(army, general, tower.coordinates)
    --- The army's units are only fixed once the battle is generated. Its lord and heroes are kept apart from `units`, so none can be sworn.
    delve.floor_units = {}
    for _, row in ipairs(army.units or {}) do
        for _ = 1, row.count or 1 do delve.floor_units[#delve.floor_units + 1] = row.id end
    end
    ibm:mark_battle_forces_for_removal(army)
    ibm:reset_state_post_battle(self, "TowerSpot", nil, army)
end

--- Adds a won floor's rewards to the haul. Gold scales with how much of the delving army's strength the floor cost.
--- @param faction_name string The delving faction.
--- @param delve table The delve record.
function TowerEventDelegate:add_floor_rewards(faction_name, delve)
    local floor = tower_data.floors[delve.floor]
    local before, after = delve.strength_before, army_strength(delve.general_cqi)
    local loss = (before and after) and math.max(0, before - after) or 0
    local step = tower_data.gold_step
    delve.haul.gold = delve.haul.gold + math.floor(floor.gold * performance_multiplier(loss) / step + 0.5) * step
    add_items(delve.haul, pick_floor_items(faction_name, floor))
    local candidates = delve.floor_units or {}
    for _ = 1, math.min(floor.sworn_units, #candidates) do
        delve.haul.units[#delve.haul.units + 1] = table.remove(candidates, random_number(#candidates))
    end
    self:swear_in_units(delve)
end

--- Moves sworn units waiting in the haul into the delving army while it has free slots, oldest first. Units that joined stay even if the
--- delve is later lost. The rest keep waiting and try again after the next win, once losses may have freed slots.
--- @param delve table The delve record.
function TowerEventDelegate:swear_in_units(delve)
    local force = delving_force(delve.general_cqi)
    if not force then return end
    local lookup = cm:char_lookup_str(cm:get_character_by_cqi(delve.general_cqi))
    for _ = 1, math.min(free_slots(force), #delve.haul.units) do
        cm:grant_unit_to_character(lookup, table.remove(delve.haul.units, 1))
        delve.haul.joined = (delve.haul.joined or 0) + 1
    end
end

--- Resolves a floor battle and ends any war rites bought for it. A loss ends the delve and forfeits the haul. A win adds the floor to the haul,
--- then offers the claim after the last floor, or climb (plain, after tending the wounded, or after war rites) or leave.
--- @param player_won_battle boolean True when the delving faction won.
--- @param faction_name string The delving faction.
function TowerEventDelegate:trigger_event_given_battle_result(player_won_battle, faction_name)
    local delve = self.delves[faction_name]
    if delve == nil then return end
    end_war_rites(delve)
    if not player_won_battle then
        self:end_delve(faction_name, "tower_lost")
        return
    end
    self:add_floor_rewards(faction_name, delve)
    if delve.floor >= #tower_data.floors then
        launch_dilemma(EVENT_CLAIM, { payout_choice("FIRST", "dummy_land_enc_tower_claim", delve.haul) }, faction_name)
        return
    end
    local next_floor = delve.floor + 1
    launch_dilemma(EVENT_DEEPER .. "_floor_" .. delve.floor, {
        { key = "FIRST", lines = { "dummy_land_enc_tower_descend_floor_" .. next_floor } },
        paid_choice("SECOND", "tend_wounded", delve.haul, next_floor),
        paid_choice("THIRD", "war_rites", delve.haul, next_floor),
        payout_choice("FOURTH", "dummy_land_enc_tower_leave", delve.haul),
    }, faction_name)
end

--- Ends a delve, takes off any war rites, puts its tower on cooldown and tells the player how it ended.
--- @param faction_name string The delving faction.
--- @param outcome string The message suffix: "tower_left", "tower_lost" or "tower_cleared".
function TowerEventDelegate:end_delve(faction_name, outcome)
    end_war_rites(self.delves[faction_name])
    local tower = self:tower_in_zone(self.delves[faction_name].zone_name)
    self.delves[faction_name] = nil
    tower.cooldown = get_mct_settings().tower_cooldown
    tower:show_message(faction_name, outcome)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Save and load

--- Exports the towers, delves in progress and open enter dilemmas for the save file.
--- @returns table { towers, delves, pending_dilemma_by_faction }.
function TowerEventDelegate:export_state_as_table()
    local towers = {}
    for i, tower in ipairs(self.towers) do
        towers[i] = tower:export()
    end
    return { towers = towers, delves = self.delves, pending_dilemma_by_faction = self.pending_dilemma_by_faction }
end

--- Builds an empty delegate. `initialize` places or restores the towers once the zones exist.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns TowerEventDelegate The new delegate.
function TowerEventDelegate:new(invasion_battle_manager)
    local t = { towers = {}, delves = {}, pending_dilemma_by_faction = {}, invasion_battle_manager = invasion_battle_manager }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TowerEventDelegate
