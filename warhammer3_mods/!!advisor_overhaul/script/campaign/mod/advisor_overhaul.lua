--- Advisor Overhaul loadout script: lets the player switch the Advisor between the weapons and mounts he has unlocked.
---
--- Weapon and mount skills unlock an item. The default weapon and mount are always unlocked. A Change Loadout button shows while the character panel
--- shows the local player's Advisor, and while he is selected on the campaign map with no full-screen panel open. It opens a picker of his unlocked
--- weapons and mounts. A pick goes through a UI trigger, so every client applies it, and this script equips the hidden mount ancillary of the
--- chosen pair (its bodyguard unit and uniform are the pair's). The pairs come from `ADVISOR_OVERHAUL_RIGS`, which
--- generators/advisor_overhaul.py writes into advisor_overhaul_rigs.lua. advisor_overhaul_spawn.lua spawns the Advisors.
---
--- The rigs he does not wear sit in the faction pool, so the character panel's Mount box lists them. A pick there is read back from the worn rig.
---
--- With `INJECT_BUTTON` on, the button is a child of a vanilla row: the character panel's bottom-right buttons, or the hover strip over the
--- selected Advisor's unit card on the map. With it off, the button is a direct child of the UI root, placed over those spots. The picker options
--- are always direct children of the UI root. The script only ever changes or destroys a component it found by its own unique name.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- The Advisor's agent subtype.
local SUBTYPE = "advisor_overhaul_advisor"

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul"

--- When true the Advisor may change his loadout only once per turn.
local ONE_CHANGE_PER_TURN = false

--- When true the button is made inside the vanilla button rows (`PANEL_ROW_PATH`, `STRIP_PATH`). When false it is a UI root child placed over them.
local INJECT_BUTTON = true

--- Name of the Change Loadout button.
local BUTTON_NAME = TAG .. "_loadout_button"

--- Start of every picker option's name, followed by `w` or `m` and the item's place in its list.
local OPTION_PREFIX = "aolo_"

--- Vanilla square icon button layout (ui3.pack). Its image 0 is the icon.
local BUTTON_TEMPLATE = "ui/templates/square_medium_button"

--- Image index of the icon in `BUTTON_TEMPLATE`.
local BUTTON_ICON_INDEX = 0

--- Icon of the Change Loadout button (ui2.pack).
local BUTTON_ICON = "ui/skins/default/icon_swap.png"

--- Icon of each picker option, by kind and item key (all in ui.pack). An item missing here uses `BUTTON_ICON`.
local OPTION_ICONS = {
	--- Weapon icons.
	weapon = {
		--- Staff and Sword: the vanilla weapon item icon.
		staff_and_sword = "ui/campaign ui/skills/item_weapon.png",
		--- Sword and Shield: a shield ability icon.
		sword_and_shield = "ui/campaign ui/skills/wh_dlc07_lord_abilities_lions_shield.png",
	},
	--- Mount icons.
	mount = {
		--- On Foot: the bonus vs infantry icon.
		foot = "ui/campaign ui/skills/character_bonus_vs_infantry.png",
		--- Barded Warhorse.
		warhorse = "ui/campaign ui/skills/mount_barded_warhorse.png",
		--- Imperial Pegasus.
		pegasus = "ui/campaign ui/skills/mount_imperial_pegasus.png",
		--- Disc of Tzeentch.
		disc = "ui/campaign ui/skills/mount_disc_of_tzeentch.png",
	},
}

--- State of the option he already uses. It is one of `BUTTON_TEMPLATE`'s states (active, down, down_off, hover, inactive), the pressed look.
local CURRENT_STATE = "down"

--- Path from the UI root to the character info panel at the bottom left, which the button sits on top of.
local ANCHOR_PATH = { "hud_campaign", "info_panel_background" }

--- Pixels between the button and the info panel.
local BUTTON_GAP = 6

--- Fallback spot when the info panel cannot be read: pixels from the screen's left edge.
local FALLBACK_LEFT = 16

--- Fallback spot when the info panel cannot be read: pixels from the screen's bottom edge to the button's bottom.
local FALLBACK_BOTTOM = 420

--- Pixels between picker options.
local OPTION_GAP = 4

--- Pixels between the two picker columns.
local COLUMN_GAP = 8

--- Lowest draw priority of the button and picker, so they sit above the campaign HUD.
local UI_PRIORITY = 200

--- Name of the one-shot real-time callback that re-checks whether the button should show.
local REFRESH_NAME = TAG .. "_loadout_refresh"

--- Delay of that callback in milliseconds, so the HUD and the panel list have settled.
local REFRESH_MS = 300

--- Name of the one-shot real-time callback that runs a click on this script's components.
local CLICK_NAME = TAG .. "_loadout_click"

--- Delay of that callback in milliseconds. Making or destroying root components while the game still handles the click broke every script's UI checks
--- and crashed the game (runs 1, 4 and 5), so clicks only schedule their work.
local CLICK_MS = 50

--- Name of the one-shot real-time callback that selects the Advisor again after a loadout change.
local RESELECT_NAME = TAG .. "_loadout_reselect"

--- Delay in milliseconds between clearing the selection and selecting the Advisor again.
local RESELECT_MS = 100

--- Panels that open under or next to the button without hiding it. Vanilla blocking panels and `events` hide it straight away.
local KEEP_BUTTON_PANELS = {
	--- The character panel, which the button sits on while it shows the Advisor.
	character_details_panel = true,
	--- The selected army's unit cards.
	units_panel = true,
	--- The recruitment options bar of the selected army.
	recruitment_options = true,
	--- The selected settlement's panel.
	settlement_panel = true,
}

--- The character panel. While it shows the local Advisor the button sits on it.
local PANEL = "character_details_panel"

--- Child of the panel whose context is the character it shows. Read only.
local PANEL_CONTEXT_HOLDER = "character_context_parent"

--- Path from the panel to its bottom-right row of square buttons (replace, event feed, rename). With `INJECT_BUTTON` on the button is made in it,
--- else it is only read for the button's spot.
local PANEL_ROW_PATH = { "character_context_parent", "holder_br", "bottom_buttons" }

--- The same row as `PANEL_ROW_PATH`, from the UI root. With `INJECT_BUTTON` on the button is made in it.
local ROW_PATH = { "character_details_panel", "character_context_parent", "holder_br", "bottom_buttons" }

--- Path from the UI root to the button strip over the hovered unit card (Disband, Rename). The game shows it and moves it on hover. With
--- `INJECT_BUTTON` on, the button is made in it while the local Advisor is selected on his own.
local STRIP_PATH = { "units_panel", "main_units_panel", "button_group_unit" }

--- Fallback spot on the panel when its button row cannot be read: pixels from the panel's right edge to the button's left edge.
local PANEL_FALLBACK_RIGHT = 420

--- Fallback spot on the panel when its button row cannot be read: pixels from the panel's bottom edge to the button's top edge.
local PANEL_FALLBACK_BOTTOM = 120

--- Draw priority added on top of the panel's own, so the button and picker draw over it.
local PANEL_PRIORITY_BONUS = 50

--- Start of the UI trigger string that carries a pick to every client.
local TRIGGER_PREFIX = TAG .. "_loadout:"

--- Start of the UI trigger string that asks every client to read the Advisor's worn rig again, after a pick in the panel's Mount box.
local RECONCILE_PREFIX = TAG .. "_reconcile:"

--- Start of every pair's mount ancillary key.
local RIG_PREFIX = "advisor_overhaul_rig_"

--- The character panel's Mount box list (ui3.pack character_details_panel_details.twui.xml). A click inside it may pick a rig or "None".
local MOUNT_BOX = "ancillary_selector_mount"

--- How many parents a clicked component is followed up to find `MOUNT_BOX`.
local MOUNT_BOX_DEPTH = 12

--- Name of the one-shot real-time callback that checks the worn rig after a click in the Mount box.
local MOUNT_PICK_NAME = TAG .. "_mount_pick"

--- Delay of that callback in milliseconds, so the game has run the native equip command first.
local MOUNT_PICK_MS = 500

--- UI text: loc key in text/db/advisor_overhaul_ui.loc and the English fallback used if the key does not resolve.
local TEXT = {
	--- Tooltip of the Change Loadout button.
	button = { "advisor_overhaul_ui_button_tooltip", "Change Loadout||Choose which of the Advisor's unlocked weapons and mounts he takes to war." },
	--- Tooltip of the button once he has changed his loadout this turn.
	button_used = { "advisor_overhaul_ui_button_used_tooltip", "Change Loadout||The Advisor has already changed his loadout this turn." },
	--- Start of a weapon option's label, followed by the weapon. No UI text holds `%`: reading one through the game broke every script and crashed it.
	weapon = { "advisor_overhaul_ui_weapon_option", "Weapon:" },
	--- Start of a mount option's label, followed by the mount.
	mount = { "advisor_overhaul_ui_mount_option", "Mount:" },
	--- End of the label of the option he already uses.
	current = { "advisor_overhaul_ui_option_current", "(current)" },
	--- Tooltip of an option he can switch to.
	pick = { "advisor_overhaul_ui_option_pick_tooltip", "Switch the Advisor to this. The change applies at once." },
	--- Tooltip of the option he already uses.
	in_use = { "advisor_overhaul_ui_option_current_tooltip", "The Advisor already uses this." },
	--- Tooltip of a weapon with no unit on his current mount.
	weapon_blocked = { "advisor_overhaul_ui_weapon_blocked_tooltip", "The Advisor cannot use this weapon on his current mount. Pick another mount first." },
	--- Tooltip of a mount with no unit for his current weapon.
	mount_blocked = { "advisor_overhaul_ui_mount_blocked_tooltip", "The Advisor cannot ride this mount with his current weapon. Pick another weapon first." },
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- CQI of the selected character, or nil when no character is selected.
local selected_cqi = nil

--- CQI of the Advisor the shown button belongs to, or nil when the button is hidden.
local button_cqi = nil

--- Path from the UI root to the parent the button was made in (`ROW_PATH` or `STRIP_PATH`), or nil when it is a UI root child or not made.
--- Only the path is kept. The button is found again by name under it each time, since the game may rebuild the parent.
local button_path = nil

--- Option component name -> { kind, key, enabled } for the open picker. Empty when the picker is closed.
local picker_options = {}

--- CQI of the Advisor the open picker belongs to, or nil when it is closed.
local picker_cqi = nil

--- Names of this script's components registered as top-most, so each is unregistered before it is destroyed. Without top-most the panel's own
--- bottom-right buttons (Salvage) drew over the lowest option.
local topmost = {}

--- Whether the character panel is open, from `PanelOpenedCampaign` and `PanelClosedCampaign`.
local panel_open = false

--- CQI of an Advisor whose loadout changed while the character panel was open, so he is selected again once it closes. Nil when none waits.
local pending_reselect = nil

--- Draw priority of the shown button. The picker options use the same.
local ui_priority = UI_PRIORITY

--- The last show or hide decision, so the log gets one line each time it changes.
local last_decision = nil


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Data

--- The generated pair data. Read when used, since script load order does not promise the data file loads first.
--- @returns table The `ADVISOR_OVERHAUL_RIGS` table.
local function rig_data()
	return ADVISOR_OVERHAUL_RIGS
end

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end

--- Logs the native UI call about to run, so a call that breaks the game is the last line in the log.
--- @param name string The component.
--- @param call string The call and its arguments.
local function log_call(name, call)
	log("ui call " .. name .. ": " .. call)
end


--- The saved value key holding one of an Advisor's choices.
--- @param cqi number The Advisor's command queue index.
--- @param kind string `weapon` or `mount`.
--- @returns string The key.
local function choice_key(cqi, kind)
	return TAG .. "_" .. kind .. "_" .. cqi
end

--- The saved value key holding the turn an Advisor last changed his loadout.
--- @param cqi number The Advisor's command queue index.
--- @returns string The key.
local function changed_turn_key(cqi)
	return TAG .. "_loadout_turn_" .. cqi
end

--- The item list of a kind.
--- @param kind string `weapon` or `mount`.
--- @returns table The `weapons` or `mounts` list of `ADVISOR_OVERHAUL_RIGS`.
local function items_of(kind)
	return kind == "weapon" and rig_data().weapons or rig_data().mounts
end

--- A picker option's component name: the prefix, `w` or `m`, and the item's place in its list, e.g. `aolo_w1`.
--- @param kind string `weapon` or `mount`.
--- @param item table The item row.
--- @returns string The name.
local function option_name(kind, item)
	for i, row in ipairs(items_of(kind)) do
		if row.key == item.key then
			return OPTION_PREFIX .. string.sub(kind, 1, 1) .. i
		end
	end
	return OPTION_PREFIX .. string.sub(kind, 1, 1) .. "0"
end

--- Finds a weapon or mount by key.
--- @param kind string `weapon` or `mount`.
--- @param key string The item key.
--- @returns table|nil The item row, or nil when the key is unknown.
local function find_item(kind, key)
	for _, item in ipairs(items_of(kind)) do
		if item.key == key then
			return item
		end
	end
	return nil
end

--- Whether the Advisor has unlocked a weapon or mount. Defaults have no skill and are always unlocked.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param item table The item row.
--- @returns boolean True when unlocked.
local function is_unlocked(character, item)
	return item.skill == "" or character:has_skill(item.skill)
end

--- The keys of every unlocked item of a kind, for the log.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param kind string `weapon` or `mount`.
--- @returns string The keys joined by commas.
local function unlocked_list(character, kind)
	local keys = {}
	for _, item in ipairs(items_of(kind)) do
		if is_unlocked(character, item) then
			table.insert(keys, item.key)
		end
	end
	return table.concat(keys, ", ")
end

--- Whether a weapon and mount pair has a unit.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when the pair has a mount ancillary.
local function has_unit(weapon, mount)
	return rig_data().ancillaries[weapon .. "|" .. mount] ~= nil
end

--- The weapon and mount to use: the saved choices while still unlocked (a respec can take them away), else the defaults. A pair with no unit falls
--- back first to the default weapon and then to the default mount.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns string The weapon key.
--- @returns string The mount key.
local function current_pair(character)
	local rigs = rig_data()
	local cqi = character:command_queue_index()
	local weapon = cm:get_saved_value(choice_key(cqi, "weapon")) or rigs.default_weapon
	local mount = cm:get_saved_value(choice_key(cqi, "mount")) or rigs.default_mount
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	if not weapon_item or not is_unlocked(character, weapon_item) then
		log("cqi " .. cqi .. " saved weapon " .. weapon .. " is unknown or locked, using " .. rigs.default_weapon)
		weapon = rigs.default_weapon
	end
	if not mount_item or not is_unlocked(character, mount_item) then
		log("cqi " .. cqi .. " saved mount " .. mount .. " is unknown or locked, using " .. rigs.default_mount)
		mount = rigs.default_mount
	end
	if has_unit(weapon, mount) then
		return weapon, mount
	end
	log("no unit for " .. weapon .. " on " .. mount .. ", trying " .. rigs.default_weapon)
	if has_unit(rigs.default_weapon, mount) then
		return rigs.default_weapon, mount
	end
	return weapon, rigs.default_mount
end

--- Switches the Advisor's art set to his weapon's, so the character panel model shows it. The panel follows only the art set. The override is
--- set again every time his loadout is applied, which includes each load.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon key.
local function apply_art_set(character, weapon)
	local item = find_item("weapon", weapon)
	local art_set = item and item.art_set
	if not art_set then
		log("cqi " .. character:command_queue_index() .. " has no art set for " .. weapon .. ", character panel model left as is")
		return
	end
	local ok, err = pcall(function()
		cm:add_character_model_override(character, art_set)
	end)
	log("cqi " .. character:command_queue_index() .. " character panel model set to " .. art_set .. (ok and "" or (", error: " .. tostring(err))))
end

--- Whether the once-per-turn rule blocks a change for this Advisor.
--- @param cqi number The Advisor's command queue index.
--- @returns boolean True when he already changed this turn and the rule is on.
local function used_this_turn(cqi)
	return ONE_CHANGE_PER_TURN and cm:get_saved_value(changed_turn_key(cqi)) == cm:model():turn_number()
end

--- The weapon and mount of a rig ancillary.
--- @param ancillary string The ancillary key.
--- @returns string|nil The weapon key, or nil when it is not a rig.
--- @returns string|nil The mount key.
local function rig_pair(ancillary)
	for pair, key in pairs(rig_data().ancillaries) do
		if key == ancillary then
			return string.match(pair, "^([^|]+)|([^|]+)$")
		end
	end
	return nil, nil
end

--- Whether the Advisor has unlocked both items of a pair.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when both are unlocked.
local function pair_unlocked(character, weapon, mount)
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	return weapon_item ~= nil and mount_item ~= nil and is_unlocked(character, weapon_item) and is_unlocked(character, mount_item)
end

--- The rig ancillaries the Advisor wears, sorted. Normally one. None after the Mount box's "None" entry.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table The ancillary keys.
local function worn_rigs(character)
	local worn = {}
	for _, ancillary in pairs(rig_data().ancillaries) do
		if character:has_ancillary(ancillary) then
			table.insert(worn, ancillary)
		end
	end
	table.sort(worn)
	return worn
end

--- The Advisors of a faction.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @returns table The Advisors.
local function faction_advisors(faction)
	local found = {}
	local characters = faction:character_list()
	for i = 0, characters:num_items() - 1 do
		local character = characters:item_at(i)
		if character:character_subtype_key() == SUBTYPE then
			table.insert(found, character)
		end
	end
	return found
end

--- Whether any of the Advisors wears an ancillary.
--- @param advisors table The faction's Advisors.
--- @param ancillary string The ancillary key.
--- @returns boolean True when one wears it.
local function worn_by_any(advisors, ancillary)
	for _, advisor in ipairs(advisors) do
		if advisor:has_ancillary(ancillary) then
			return true
		end
	end
	return false
end

--- Whether an unworn copy of an ancillary sits in the faction's pool: the faction owns it and no Advisor wears it. False whenever an Advisor wears
--- it, since `ancillary_exists` cannot tell a pool copy from the worn one.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param advisors table The faction's Advisors.
--- @param ancillary string The ancillary key.
--- @returns boolean True when a copy is in the pool.
local function in_pool(faction, advisors, ancillary)
	if worn_by_any(advisors, ancillary) then
		return false
	end
	local ok, exists = pcall(function()
		return faction:ancillary_exists(ancillary)
	end)
	return ok and exists == true
end

--- How many copies of an ancillary the faction's item list holds, read from the UI context for the log only. Nothing is decided on it.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param ancillary string The ancillary key.
--- @returns string The count, or `unreadable`.
local function list_count(faction, ancillary)
	local ok, count = pcall(function()
		return common.get_context_value("CcoCampaignFaction", tostring(faction:command_queue_index()),
			"AncillaryList.Filter(AncillaryRecordContext.Key == \"" .. ancillary .. "\").Size")
	end)
	if ok and count ~= nil then
		return tostring(count)
	end
	return "unreadable"
end

--- Makes the faction's pool hold one copy of every unlocked pair's rig that no Advisor wears, and no locked pair's rig. The
--- character panel's Mount box lists exactly those pool copies. A worn rig is never removed from the faction, since that strips the worn copy too.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param why string What asked for it, for the log.
local function sync_pool(faction, why)
	local advisors = faction_advisors(faction)
	if #advisors == 0 then
		return
	end
	local keys = {}
	for _, ancillary in pairs(rig_data().ancillaries) do
		table.insert(keys, ancillary)
	end
	table.sort(keys)
	log_call("CcoCampaignFaction " .. faction:command_queue_index(), "get_context_value item list counts, for the log")
	for _, ancillary in ipairs(keys) do
		local weapon, mount = rig_pair(ancillary)
		local unlocked = false
		for _, advisor in ipairs(advisors) do
			unlocked = unlocked or (weapon ~= nil and pair_unlocked(advisor, weapon, mount))
		end
		local before = list_count(faction, ancillary)
		local pooled = in_pool(faction, advisors, ancillary)
		local action
		if worn_by_any(advisors, ancillary) then
			action = "worn, left alone"
		elseif unlocked and not pooled then
			cm:add_ancillary_to_faction(faction, ancillary, true)
			action = "added to the pool"
		elseif not unlocked and pooled then
			cm:force_remove_ancillary_from_faction(faction, ancillary)
			action = "removed from the pool"
		else
			action = pooled and "in the pool, kept" or "not in the pool, kept"
		end
		log("pool " .. faction:name() .. " (" .. why .. ") " .. ancillary .. ": unlocked " .. tostring(unlocked) .. ", in pool " .. tostring(pooled)
			.. ", " .. action .. ", list count " .. before .. " -> " .. list_count(faction, ancillary))
	end
end

--- Equips the mount ancillary of the Advisor's current pair. Every other pair's rig goes back to the faction pool, so the Mount box lists it. The
--- pair is saved back, so a choice a respec took away does not return when he learns the skill again. Also sets his weapon's art set and syncs the
--- pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when an ancillary was equipped or removed.
local function apply_pair(character)
	local rigs = rig_data()
	local weapon, mount = current_pair(character)
	local cqi = character:command_queue_index()
	local faction = character:faction()
	cm:set_saved_value(choice_key(cqi, "weapon"), weapon)
	cm:set_saved_value(choice_key(cqi, "mount"), mount)
	local wanted = rigs.ancillaries[weapon .. "|" .. mount]
	apply_art_set(character, weapon)
	if not wanted then
		log("cqi " .. cqi .. " has no unit for " .. weapon .. " on " .. mount .. ", nothing equipped")
		sync_pool(faction, "cqi " .. cqi .. " applied")
		return false
	end
	local stale = {}
	for _, ancillary in pairs(rigs.ancillaries) do
		if ancillary ~= wanted and character:has_ancillary(ancillary) then
			table.insert(stale, ancillary)
		end
	end
	if character:has_ancillary(wanted) and #stale == 0 then
		sync_pool(faction, "cqi " .. cqi .. " applied")
		return false
	end
	table.sort(stale)
	for _, ancillary in ipairs(stale) do
		-- A rig goes back to the pool, so the Mount box lists it.
		cm:force_remove_ancillary(character, ancillary, true, true)
	end
	local from_pool = false
	if not character:has_ancillary(wanted) then
		-- The pool copy is removed first, so equipping does not leave a second one. The vanilla Sword of Khaine script does the same.
		from_pool = in_pool(faction, faction_advisors(faction), wanted)
		if from_pool then
			cm:force_remove_ancillary_from_faction(faction, wanted)
		end
		cm:force_add_ancillary(character, wanted, true, true)
	end
	log("cqi " .. cqi .. " now " .. weapon .. " on " .. mount .. " (" .. wanted .. "), returned or removed: " .. table.concat(stale, ", ")
		.. ", pool copy taken: " .. tostring(from_pool) .. ", has it now: " .. tostring(character:has_ancillary(wanted)))
	sync_pool(faction, "cqi " .. cqi .. " applied")
	return true
end

--- Reads which rig the Advisor wears and makes it his loadout, so a pick in the character panel's Mount box sticks. With exactly one worn rig of an
--- unlocked pair, that pair is saved as his choice. With none (the Mount box's "None"), a locked one or several, the saved pair is equipped again.
--- Runs from game events and UI triggers only, so every client saves the same values.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for it, for the log.
--- @returns boolean True when his loadout or ancillaries changed.
local function reconcile(character, why)
	local rigs = rig_data()
	local cqi = character:command_queue_index()
	local worn = worn_rigs(character)
	local saved_weapon = cm:get_saved_value(choice_key(cqi, "weapon")) or rigs.default_weapon
	local saved_mount = cm:get_saved_value(choice_key(cqi, "mount")) or rigs.default_mount
	local changed = false
	local weapon, mount = nil, nil
	if #worn == 1 then
		weapon, mount = rig_pair(worn[1])
	end
	if weapon and pair_unlocked(character, weapon, mount) then
		local differs = weapon ~= saved_weapon or mount ~= saved_mount
		if differs and used_this_turn(cqi) then
			log("cqi " .. cqi .. " wears " .. worn[1] .. " but already changed this turn, putting back " .. saved_weapon .. " on " .. saved_mount
				.. " (check: " .. why .. ")")
		else
			if differs then
				cm:set_saved_value(choice_key(cqi, "weapon"), weapon)
				cm:set_saved_value(choice_key(cqi, "mount"), mount)
				cm:set_saved_value(changed_turn_key(cqi), cm:model():turn_number())
				changed = true
			end
			log("cqi " .. cqi .. " loadout taken from the worn rig " .. worn[1] .. ": " .. weapon .. " on " .. mount
				.. (differs and (", was " .. saved_weapon .. " on " .. saved_mount) or ", unchanged") .. " (check: " .. why .. ")")
		end
	elseif #worn == 0 then
		log("cqi " .. cqi .. " wears no rig (the Mount box None entry or a new campaign), equipping the saved pair " .. saved_weapon
			.. " on " .. saved_mount .. " (check: " .. why .. ")")
	else
		log("cqi " .. cqi .. " wears " .. table.concat(worn, ", ") .. ", not one rig of an unlocked pair, equipping the saved pair " .. saved_weapon
			.. " on " .. saved_mount .. " (check: " .. why .. ")")
	end
	local equipped = apply_pair(character)
	return changed or equipped
end

--- Reconciles every living Advisor of every human faction.
--- @param why string What asked for it, for the log.
local function apply_all(why)
	for _, faction_key in ipairs(cm:get_human_factions()) do
		local characters = cm:get_faction(faction_key):character_list()
		for i = 0, characters:num_items() - 1 do
			local character = characters:item_at(i)
			if character:character_subtype_key() == SUBTYPE and not character:is_wounded() then
				reconcile(character, why)
			end
		end
	end
end

--- Checks whether the Advisor may switch to a pair.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns boolean True when allowed.
--- @returns string Why not, or an empty string when allowed.
local function can_choose(character, weapon, mount)
	local weapon_item, mount_item = find_item("weapon", weapon), find_item("mount", mount)
	if not weapon_item or not mount_item then
		return false, "unknown weapon or mount"
	end
	if not is_unlocked(character, weapon_item) then
		return false, "weapon " .. weapon .. " is locked"
	end
	if not is_unlocked(character, mount_item) then
		return false, "mount " .. mount .. " is locked"
	end
	if not has_unit(weapon, mount) then
		return false, "no unit for " .. weapon .. " on " .. mount
	end
	if used_this_turn(character:command_queue_index()) then
		return false, "already changed this turn"
	end
	return true, ""
end

--- Saves a picked pair and equips it. Runs on every client from the UI trigger.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
local function choose_pair(character, weapon, mount)
	local cqi = character:command_queue_index()
	local old_weapon, old_mount = current_pair(character)
	log("cqi " .. cqi .. " asked for " .. weapon .. " on " .. mount .. ", was " .. old_weapon .. " on " .. old_mount .. ", unlocked weapons: "
		.. unlocked_list(character, "weapon") .. ", unlocked mounts: " .. unlocked_list(character, "mount"))
	local ok, reason = can_choose(character, weapon, mount)
	if not ok then
		log("cqi " .. cqi .. " change refused: " .. reason)
		return
	end
	cm:set_saved_value(choice_key(cqi, "weapon"), weapon)
	cm:set_saved_value(choice_key(cqi, "mount"), mount)
	cm:set_saved_value(changed_turn_key(cqi), cm:model():turn_number())
	apply_pair(character)
	local new_weapon, new_mount = current_pair(character)
	log("cqi " .. cqi .. " loadout is now " .. new_weapon .. " on " .. new_mount .. " (turn " .. cm:model():turn_number() .. ")")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI text

--- A UI text, localised when its key resolves.
--- @param id string Key of `TEXT`.
--- @returns string The text.
local function ui_text(id)
	local entry = TEXT[id]
	local text = common.get_localised_string(entry[1])
	if not text or text == "" then
		return entry[2]
	end
	return text
end

--- An item's display name, localised when its key resolves.
--- @param item table The item row.
--- @returns string The name.
local function item_name(item)
	local text = common.get_localised_string(item.name)
	if not text or text == "" then
		return item.fallback
	end
	return text
end

--- Joins two label parts with a space.
--- @param first string The first part.
--- @param second string The second part.
--- @returns string The label.
local function join_label(first, second)
	return first .. " " .. second
end

--- Whether a character is an Advisor of the local player's faction.
--- @param character CHARACTER_SCRIPT_INTERFACE|nil|boolean The character, or nil or false when there is none.
--- @returns boolean True for the local player's Advisor.
local function is_local_advisor(character)
	if not character then
		return false
	end
	return character:character_subtype_key() == SUBTYPE and character:faction():name() == cm:get_local_faction_name(true)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI components

--- The UI root, or nil when the UI is not there yet.
--- @returns UIC|nil The root.
local function ui_root()
	local ok, root = pcall(function()
		return core:get_ui_root()
	end)
	if ok and root then
		return root
	end
	return nil
end

--- A component's name, or nil when the handle is dead or not a component.
--- @param uic UIC|nil The component.
--- @returns string|nil The name.
local function component_id(uic)
	if not uic then
		return nil
	end
	local ok, id = pcall(function()
		return uic:Id()
	end)
	if ok and type(id) == "string" then
		return id
	end
	return nil
end

--- Wraps a component address only when it is the named component. `UIComponent(nil)` hands back the UI root, so a missing address is never wrapped.
--- @param address any The address from `Find` or `CreateComponent`.
--- @param name string The name the component must have.
--- @returns UIC|nil The component, or nil when the address is missing or names another component.
local function wrap_named(address, name)
	if not address then
		return nil
	end
	local uic = UIComponent(address)
	if component_id(uic) ~= name then
		return nil
	end
	return uic
end

--- Finds a named descendant of a component.
--- @param parent UIC|nil The component to search under.
--- @param name string The descendant's name.
--- @returns UIC|nil The descendant, or nil when not found.
local function find_named(parent, name)
	if not parent then
		return nil
	end
	local ok, address = pcall(function()
		return parent:Find(name, false)
	end)
	if not ok then
		return nil
	end
	return wrap_named(address, name)
end

--- Follows a path of names down from a component.
--- @param parent UIC|nil The component to start from.
--- @param path table The names, each searched under the previous one.
--- @returns UIC|nil The last component, or nil when any step is missing.
local function find_path(parent, path)
	local uic = parent
	for _, name in ipairs(path) do
		uic = find_named(uic, name)
		if not uic then
			return nil
		end
	end
	return uic
end

--- Finds a direct child of a component with exactly this name.
--- @param parent UIC|nil The component to look under.
--- @param name string The child's name.
--- @returns UIC|nil The child, or nil when it does not exist.
local function find_child(parent, name)
	if not parent then
		return nil
	end
	local ok, count = pcall(function()
		return parent:ChildCount()
	end)
	if not ok or type(count) ~= "number" then
		return nil
	end
	for i = 0, count - 1 do
		local found, address = pcall(function()
			return parent:Find(i)
		end)
		local child = found and wrap_named(address, name)
		if child then
			return child
		end
	end
	return nil
end

--- Finds one of this script's components, a direct child of the UI root with exactly this name.
--- @param name string The component's name.
--- @returns UIC|nil The component, or nil when it does not exist.
local function find_own(name)
	return find_child(ui_root(), name)
end

--- Destroys one of this script's components under a parent if it exists. Nothing but a direct child with exactly this name is touched.
--- @param parent UIC|nil The parent it was made in.
--- @param name string The component's name.
--- @param why string Why, for the log.
--- @returns boolean True when a component was destroyed.
local function destroy_child(parent, name, why)
	local uic = find_child(parent, name)
	if not uic then
		return false
	end
	if topmost[name] then
		topmost[name] = nil
		local removed, remove_err = pcall(function()
			uic:RemoveTopMost()
		end)
		if not removed then
			log("RemoveTopMost on " .. name .. " failed: " .. tostring(remove_err))
		end
	end
	local ok, err = pcall(function()
		uic:Destroy()
	end)
	log("destroyed " .. name .. " (" .. why .. ")" .. (ok and "" or (", error: " .. tostring(err))))
	return ok
end

--- Destroys one of this script's UI root children if it exists.
--- @param name string The component's name.
--- @param why string Why, for the log.
--- @returns boolean True when a component was destroyed.
local function destroy_own(name, why)
	return destroy_child(ui_root(), name, why)
end

--- Creates one of this script's components under a parent and checks the game gave back exactly that component.
--- @param parent UIC|nil The parent.
--- @param name string The new component's name.
--- @param template string The layout file.
--- @returns UIC|nil The component, or nil when it could not be made.
local function create_child(parent, name, template)
	if not parent then
		log("create " .. name .. ": no parent")
		return nil
	end
	destroy_child(parent, name, "made again")
	local ok, address = pcall(function()
		return parent:CreateComponent(name, template)
	end)
	if not ok then
		log("create " .. name .. " from " .. template .. " raised: " .. tostring(address))
		return nil
	end
	if not address then
		log("create " .. name .. " from " .. template .. " returned nothing")
		return nil
	end
	local id = component_id(UIComponent(address))
	log("created " .. name .. " from " .. template .. ", got Id " .. tostring(id))
	if id ~= name then
		log("create " .. name .. ": the game gave back " .. tostring(id) .. ", so it is left alone")
		return nil
	end
	return UIComponent(address)
end

--- Creates one of this script's components under the UI root.
--- @param name string The new component's name.
--- @param template string The layout file.
--- @returns UIC|nil The component, or nil when it could not be made.
local function create_own(name, template)
	local root = ui_root()
	if not root then
		log("create " .. name .. ": no UI root")
		return nil
	end
	return create_child(root, name, template)
end

--- The parent the button was made in: the UI root, or the vanilla row at `button_path`, found again by name.
--- @returns UIC|nil The parent, or nil when it is gone.
local function button_parent()
	if not button_path then
		return ui_root()
	end
	return find_path(ui_root(), button_path)
end

--- The Change Loadout button, found again by name under its parent.
--- @returns UIC|nil The button, or nil when it does not exist.
local function find_button()
	return find_child(button_parent(), BUTTON_NAME)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picker

--- Closes the picker if it is open.
--- @param why string Why, for the log.
local function close_picker(why)
	local was_open = picker_cqi ~= nil or next(picker_options) ~= nil
	for name in pairs(picker_options) do
		destroy_own(name, why)
	end
	picker_options = {}
	picker_cqi = nil
	if was_open then
		log("loadout picker closed: " .. why)
	end
end

--- Adds one picker option: an icon button made from the same layout as the Change Loadout button, with its label in the tooltip.
--- @param kind string `weapon` or `mount`.
--- @param item table The item row.
--- @param state string `current`, `pick` or `blocked`.
--- @returns UIC|nil The option, or nil when it could not be made.
local function add_option(kind, item, state)
	local name = option_name(kind, item)
	log_call(name, "CreateComponent " .. BUTTON_TEMPLATE)
	local option = create_own(name, BUTTON_TEMPLATE)
	if not option then
		return nil
	end
	-- Registered before it is set up, so `close_picker` removes it if a later step fails.
	picker_options[name] = { kind = kind, key = item.key, enabled = state == "pick" }
	local label = join_label(ui_text(kind), item_name(item))
	local reason = ui_text("pick")
	if state == "current" then
		label = join_label(label, ui_text("current"))
		reason = ui_text("in_use")
	elseif state == "blocked" then
		reason = ui_text(kind .. "_blocked")
	end
	local icon = OPTION_ICONS[kind] and OPTION_ICONS[kind][item.key] or BUTTON_ICON
	local ui_state = state == "current" and CURRENT_STATE or state == "blocked" and "inactive" or "active"
	local ok, err = pcall(function()
		log_call(name, "SetImagePath " .. icon .. " " .. BUTTON_ICON_INDEX)
		option:SetImagePath(icon, BUTTON_ICON_INDEX)
		log_call(name, "SetTooltipText " .. label .. "||" .. reason)
		option:SetTooltipText(label .. "||" .. reason, true)
		log_call(name, "SetState " .. ui_state)
		option:SetState(ui_state)
		log_call(name, "PropagatePriority " .. ui_priority)
		option:PropagatePriority(ui_priority)
		log_call(name, "RegisterTopMost")
		option:RegisterTopMost()
		topmost[name] = true
	end)
	if not ok then
		log("option " .. name .. " set up failed: " .. tostring(err))
		return nil
	end
	log("option " .. name .. " ready: " .. state .. ", icon " .. icon)
	return option
end

--- Opens the picker above the Change Loadout button: unlocked weapons in the left column, unlocked mounts in the right one.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
local function open_picker(character)
	close_picker("reopened")
	local button = find_button()
	if not button then
		log("loadout picker: the button is gone, not opening")
		return
	end
	local cqi = character:command_queue_index()
	local weapon, mount = current_pair(character)
	local columns = {}
	for _, kind in ipairs({ "weapon", "mount" }) do
		local column, shown = {}, {}
		for _, item in ipairs(items_of(kind)) do
			if is_unlocked(character, item) then
				local is_current = item.key == (kind == "weapon" and weapon or mount)
				local fits = kind == "weapon" and has_unit(item.key, mount) or kind == "mount" and has_unit(weapon, item.key)
				local state = is_current and "current" or fits and "pick" or "blocked"
				local option = add_option(kind, item, state)
				if not option then
					log("loadout picker not opened: option " .. kind .. " " .. item.key .. " could not be made")
					close_picker("option " .. kind .. " " .. item.key .. " could not be made")
					return
				end
				table.insert(column, { name = option_name(kind, item), uic = option })
				table.insert(shown, item.key .. "=" .. state)
			end
		end
		columns[kind] = column
		log("loadout picker cqi " .. cqi .. " " .. kind .. "s: " .. table.concat(shown, ", "))
	end
	-- Each column stacks upward from just above the button. Weapons sit in the button's column, mounts in the next one to the right.
	local ok, err = pcall(function()
		log_call(BUTTON_NAME, "Position and Dimensions")
		local button_x, button_y = button:Position()
		local size, height = button:Dimensions()
		local x = button_x
		for _, kind in ipairs({ "weapon", "mount" }) do
			local column = columns[kind]
			if #column > 0 then
				for i, entry in ipairs(column) do
					local y = math.max(0, button_y - (#column - i + 1) * (height + OPTION_GAP))
					log_call(entry.name, "MoveTo " .. x .. "," .. y)
					entry.uic:MoveTo(x, y)
				end
				x = x + size + COLUMN_GAP
			end
		end
		log("loadout picker opened for cqi " .. cqi .. " on " .. weapon .. " / " .. mount .. ", button at " .. button_x .. "," .. button_y)
	end)
	if not ok then
		close_picker("layout failed: " .. tostring(err))
		return
	end
	picker_cqi = cqi
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Button

--- Logs a show or hide decision. A check started by a click inside the character panel logs only when the decision differs from the last one.
--- @param why string What asked for the check.
--- @param outcome string What was decided and why.
local function note_decision(why, outcome)
	local from_click = string.sub(why, 1, 9) == "click on "
	if from_click and outcome == last_decision then
		return
	end
	last_decision = outcome
	log("loadout button " .. outcome .. " (check: " .. why .. ")")
end

--- Removes the button and the picker. An injected button is looked up by name under its row, so a row the game rebuilt is left alone.
--- @param why string Why, for the log.
local function hide_button(why)
	close_picker(why)
	destroy_child(button_parent(), BUTTON_NAME, why)
	button_cqi = nil
	button_path = nil
end

--- Removes the button and the picker and logs the decision.
--- @param why string What asked for it.
--- @param reason string Why it is hidden.
local function set_hidden(why, reason)
	hide_button(reason)
	note_decision(why, "hidden: " .. reason)
end

--- A component's position and size, read without changing it.
--- @param uic UIC The component.
--- @returns table|nil `{ x, y, w, h, visible }`, or nil when it cannot be read.
local function read_bounds(uic)
	local ok, x, y, w, h, visible = pcall(function()
		local px, py = uic:Position()
		local pw, ph = uic:Dimensions()
		return px, py, pw, ph, uic:Visible()
	end)
	if not ok or type(x) ~= "number" or type(w) ~= "number" then
		return nil
	end
	return { x = x, y = y, w = w, h = h, visible = visible }
end

--- The open character panel, found read only by its name.
--- @returns UIC|nil The panel, or nil when it is not there or hidden.
local function find_panel()
	local panel = find_named(ui_root(), PANEL)
	local bounds = panel and read_bounds(panel)
	if not bounds or not bounds.visible then
		return nil
	end
	return panel
end

--- The character the open panel shows, read from its context holder without changing anything.
--- @param panel UIC The character panel.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The character, or nil when it cannot be read.
--- @returns string What was seen, for the log.
local function panel_character(panel)
	local holder = find_named(panel, PANEL_CONTEXT_HOLDER)
	if not holder then
		return nil, "the panel has no " .. PANEL_CONTEXT_HOLDER
	end
	local ok, id = pcall(function()
		return holder:GetContextObjectId("CcoCampaignCharacter")
	end)
	local cqi = ok and tonumber(id)
	if not cqi then
		return nil, "the panel shows no readable character (" .. tostring(id) .. ")"
	end
	local character = cm:get_character_by_cqi(cqi)
	if not character then
		return nil, "the panel shows cqi " .. cqi .. ", which is not found"
	end
	return character, "the panel shows " .. character:character_subtype_key() .. " cqi " .. cqi
end

--- Where the button goes on the character panel: left of its bottom-right button row, else a fixed offset from the panel's corner.
--- @param panel UIC The character panel.
--- @param width number The button's width.
--- @param height number The button's height.
--- @returns number|nil The x position, or nil when the panel cannot be read either.
--- @returns number|nil The y position.
--- @returns string|nil Which rule placed it, for the log.
local function panel_position(panel, width, height)
	local row = find_path(panel, PANEL_ROW_PATH)
	local bounds = row and read_bounds(row)
	if bounds and bounds.visible then
		return math.max(0, bounds.x - width - BUTTON_GAP), math.max(0, bounds.y + math.floor((bounds.h - height) / 2)),
			"left of the panel's button row at " .. bounds.x .. "," .. bounds.y .. " size " .. bounds.w .. "x" .. bounds.h
	end
	bounds = read_bounds(panel)
	if bounds then
		return math.max(0, bounds.x + bounds.w - PANEL_FALLBACK_RIGHT), math.max(0, bounds.y + bounds.h - PANEL_FALLBACK_BOTTOM), "panel fallback"
	end
	return nil
end

--- Where the button goes on the map: on top of the right end of the character info panel, or a fixed spot when that panel cannot be read.
--- @param width number The button's width.
--- @param height number The button's height.
--- @returns number The x position.
--- @returns number The y position.
--- @returns string Which rule placed it, for the log.
local function map_position(width, height)
	local root = ui_root()
	local anchor = find_path(root, ANCHOR_PATH)
	local bounds = anchor and read_bounds(anchor)
	if bounds and bounds.visible then
		return math.max(0, bounds.x + bounds.w - width), math.max(0, bounds.y - height - BUTTON_GAP), "on " .. ANCHOR_PATH[#ANCHOR_PATH]
	end
	local ok, _, screen_height = pcall(function()
		return root:Dimensions()
	end)
	if not ok or type(screen_height) ~= "number" then
		screen_height = 1080
	end
	return FALLBACK_LEFT, math.max(0, screen_height - FALLBACK_BOTTOM - height), "screen fallback"
end

--- Logs the injected button's size next to its first vanilla sibling's, and lays the row out again when the button sits on a shown sibling.
--- @param parent UIC The row the button is in.
--- @param button UIC The button.
--- @param created boolean Whether the button was just made, so its size is logged once.
--- @returns string The button's spot, for the log.
local function check_row_layout(parent, button, created)
	local own = read_bounds(button)
	if not own then
		return "unreadable spot"
	end
	local overlap = nil
	local first = nil
	local ok, count = pcall(function()
		return parent:ChildCount()
	end)
	for i = 0, (ok and type(count) == "number") and count - 1 or -1 do
		local found, address = pcall(function()
			return parent:Find(i)
		end)
		local child = found and address and UIComponent(address)
		local id = component_id(child)
		if id and id ~= BUTTON_NAME then
			local bounds = read_bounds(child)
			if bounds then
				first = first or (id .. " " .. bounds.w .. "x" .. bounds.h)
				if bounds.visible and bounds.x == own.x and bounds.y == own.y then
					overlap = id
				end
			end
		end
	end
	if created then
		log("injected button size " .. own.w .. "x" .. own.h .. ", first vanilla sibling " .. tostring(first))
	end
	if overlap then
		log_call(component_id(parent) or "parent", "Layout, the button sits on " .. overlap)
		local laid, err = pcall(function()
			parent:Layout()
		end)
		if not laid then
			log("Layout failed: " .. tostring(err))
		end
		own = read_bounds(button) or own
	end
	return own.x .. "," .. own.y
end

--- The selected army's button strip over the hovered unit card, read only. The strip itself is hidden until a card is hovered, so only the
--- units panel has to be shown.
--- @returns UIC|nil The strip, or nil when the units panel is missing or hidden.
local function find_strip()
	local units = find_named(ui_root(), STRIP_PATH[1])
	local bounds = units and read_bounds(units)
	if not bounds or not bounds.visible then
		return nil
	end
	return find_path(ui_root(), STRIP_PATH)
end

--- Makes or updates the button inside a vanilla row: the character panel's bottom-right row, or the unit card hover strip on the map. The row's
--- layout places it, so it is never moved, raised or made top-most. It is found by name first, so there is never a second copy.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param panel UIC|nil The character panel when the button goes on it, or nil for the map strip.
--- @param why string What asked for the check, for the log.
local function show_injected(character, panel, why)
	local cqi = character:command_queue_index()
	if picker_cqi and picker_cqi ~= cqi then
		close_picker("another Advisor shown")
	end
	local path = panel and ROW_PATH or STRIP_PATH
	local where = path[#path]
	if button_path ~= path then
		hide_button("moved to " .. where)
	end
	local parent
	if panel then
		parent = find_path(panel, PANEL_ROW_PATH)
	else
		parent = find_strip()
	end
	if not parent then
		set_hidden(why, where .. " is missing or hidden")
		return
	end
	local priority = UI_PRIORITY
	if panel then
		local ok, panel_priority = pcall(function()
			return panel:Priority()
		end)
		if ok and type(panel_priority) == "number" then
			priority = math.max(priority, panel_priority + PANEL_PRIORITY_BONUS)
		end
	end
	local button = find_child(parent, BUTTON_NAME)
	local created = false
	if not button then
		log_call(BUTTON_NAME, "CreateComponent " .. BUTTON_TEMPLATE .. " in " .. where)
		button = create_child(parent, BUTTON_NAME, BUTTON_TEMPLATE)
		if not button then
			set_hidden(why, "the button could not be made in " .. where)
			return
		end
		created = true
	end
	button_path = path
	local used = used_this_turn(cqi)
	local ok, result = pcall(function()
		log_call(BUTTON_NAME, "SetImagePath " .. BUTTON_ICON .. " " .. BUTTON_ICON_INDEX)
		button:SetImagePath(BUTTON_ICON, BUTTON_ICON_INDEX)
		local state = used and "inactive" or "active"
		log_call(BUTTON_NAME, "SetState " .. state)
		button:SetState(state)
		log_call(BUTTON_NAME, "SetTooltipText " .. (used and "button_used" or "button"))
		button:SetTooltipText(ui_text(used and "button_used" or "button"), true)
		log_call(BUTTON_NAME, "SetVisible true")
		button:SetVisible(true)
		return check_row_layout(parent, button, created)
	end)
	if not ok then
		set_hidden(why, "button set up failed: " .. tostring(result))
		return
	end
	button_cqi = cqi
	ui_priority = priority
	note_decision(why, "shown for cqi " .. cqi .. " in " .. where .. " at " .. result .. ", picker priority " .. priority
		.. (used and ", locked for this turn" or ""))
end

--- Makes or updates the button for the local Advisor.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param panel UIC|nil The character panel when the button goes on it, or nil for the map spot.
--- @param why string What asked for the check, for the log.
local function show_button(character, panel, why)
	if INJECT_BUTTON then
		show_injected(character, panel, why)
		return
	end
	local cqi = character:command_queue_index()
	if picker_cqi and picker_cqi ~= cqi then
		close_picker("another Advisor shown")
	end
	local priority = UI_PRIORITY
	if panel then
		local ok, panel_priority = pcall(function()
			return panel:Priority()
		end)
		if ok and type(panel_priority) == "number" then
			priority = math.max(priority, panel_priority + PANEL_PRIORITY_BONUS)
		end
	end
	local button = find_own(BUTTON_NAME)
	if not button then
		button = create_own(BUTTON_NAME, BUTTON_TEMPLATE)
		if not button then
			set_hidden(why, "the button could not be made")
			return
		end
	end
	local used = used_this_turn(cqi)
	local ok, result = pcall(function()
		button:SetImagePath(BUTTON_ICON, BUTTON_ICON_INDEX)
		local width, height = button:Dimensions()
		local x, y, rule
		if panel then
			x, y, rule = panel_position(panel, width, height)
		end
		if not x then
			x, y, rule = map_position(width, height)
		end
		button:MoveTo(x, y)
		button:SetState(used and "inactive" or "active")
		button:SetTooltipText(ui_text(used and "button_used" or "button"), true)
		button:PropagatePriority(priority)
		if not topmost[BUTTON_NAME] then
			-- The HUD unit panel opens over the map spot, so the button stays on top to remain clickable.
			button:RegisterTopMost()
			topmost[BUTTON_NAME] = true
		end
		button:SetVisible(true)
		return x .. "," .. y .. " (" .. rule .. ")"
	end)
	if not ok then
		set_hidden(why, "button set up failed: " .. tostring(result))
		return
	end
	button_cqi = cqi
	ui_priority = priority
	note_decision(why, "shown for cqi " .. cqi .. (panel and " on the character panel" or " on the map") .. " at " .. result .. ", priority "
		.. priority .. (used and ", locked for this turn" or ""))
end

--- Names of the open blocking panels and the event panel, read from the vanilla campaign UI manager.
--- @param ignore string|nil A panel to leave out.
--- @returns string|nil The names joined by commas, or nil when none is open.
local function covering_panels(ignore)
	local ok, names = pcall(function()
		local manager = cm:get_campaign_ui_manager()
		local found = {}
		if type(manager.campaign_ui_panels_blocking_open) == "table" then
			for name, is_open in pairs(manager.campaign_ui_panels_blocking_open) do
				if is_open and name ~= ignore then
					table.insert(found, name)
				end
			end
		else
			local name = manager:get_open_blocking_panel()
			if name and name ~= ignore then
				table.insert(found, name)
			end
		end
		table.sort(found)
		return found
	end)
	if not ok or #names == 0 then
		return nil
	end
	return table.concat(names, ", ")
end

--- Whether a panel hides the button the moment it opens: a vanilla blocking panel other than the keep panels.
--- @param panel string The panel name.
--- @returns boolean True when it hides the button.
local function hides_on_open(panel)
	if KEEP_BUTTON_PANELS[panel] then
		return false
	end
	local ok, blocking = pcall(function()
		return cm:get_campaign_ui_manager().campaign_ui_panels_blocking_lookup[panel]
	end)
	return ok and blocking == true
end

--- Shows the button when the open character panel shows the local Advisor, or when he is selected on the map with no panel over it.
--- @param why string What asked for the check, for the log.
local function refresh(why)
	if panel_open then
		local panel = find_panel()
		if not panel then
			set_hidden(why, "the character panel is open but could not be read")
			return
		end
		local character, seen = panel_character(panel)
		if not is_local_advisor(character) then
			set_hidden(why, seen .. ", not the local Advisor")
			return
		end
		local over = covering_panels(PANEL)
		if over then
			set_hidden(why, seen .. ", but " .. over .. " is open over it")
			return
		end
		show_button(character, panel, why)
		return
	end
	local character = selected_cqi and cm:get_character_by_cqi(selected_cqi)
	if not character then
		set_hidden(why, selected_cqi and ("selected cqi " .. selected_cqi .. " is not found") or "nothing selected")
		return
	end
	if character:character_subtype_key() ~= SUBTYPE then
		set_hidden(why, "selected cqi " .. selected_cqi .. " is a " .. character:character_subtype_key() .. ", not an Advisor")
		return
	end
	if not is_local_advisor(character) then
		set_hidden(why, "selected Advisor cqi " .. selected_cqi .. " is not of the local faction")
		return
	end
	local over = covering_panels(nil)
	if over then
		set_hidden(why, "local Advisor selected, but " .. over .. " is open")
		return
	end
	if INJECT_BUTTON and character:is_embedded_in_military_force() then
		-- The hover strip is shared by every card of the army, so an embedded Advisor gets no strip button.
		set_hidden(why, "selected Advisor cqi " .. selected_cqi .. " is embedded, and the unit card strip is shared by the whole army")
		return
	end
	show_button(character, nil, why)
end

--- Runs a UI step and, if it raises, logs it and removes this script's components.
--- @param what string The step, for the log.
--- @param step function The step.
local function guarded(what, step)
	local ok, err = pcall(step)
	if not ok then
		log(what .. " failed: " .. tostring(err))
		pcall(set_hidden, what, what .. " failed")
	end
end

--- Checks the button once after a short delay, so the HUD and the open panel list have settled. A newer request replaces an older one.
--- @param why string What asked for the check, for the log.
local function schedule_refresh(why)
	cm:remove_real_callback(REFRESH_NAME)
	cm:real_callback(function()
		guarded("refresh", function()
			refresh(why)
		end)
	end, REFRESH_MS, REFRESH_NAME)
end

--- Runs a click's UI work once the game has finished handling the click. A newer click replaces an older one that has not run yet.
--- @param what string The step, for the log.
--- @param step function The step.
local function after_click(what, step)
	cm:remove_real_callback(CLICK_NAME)
	cm:real_callback(function()
		guarded(what, step)
	end, CLICK_MS, CLICK_NAME)
end

--- Selects the Advisor again after his loadout changed on the map, so the HUD unit card shows his new unit. Without it the card stayed stale
--- until he was deselected and selected by hand. While the character panel is open it waits until the panel closes. Skipped when he is not the
--- selected character.
--- @param cqi number The Advisor's command queue index.
local function reselect(cqi)
	if panel_open then
		pending_reselect = cqi
		log("reselect cqi " .. cqi .. " waits for the character panel to close")
		return
	end
	if selected_cqi ~= cqi then
		log("reselect cqi " .. cqi .. " skipped: he is not selected")
		return
	end
	local cleared, clear_err = pcall(function()
		CampaignUI.ClearSelection()
	end)
	log("reselect cqi " .. cqi .. ": ClearSelection " .. (cleared and "ok" or ("failed: " .. tostring(clear_err))))
	cm:remove_real_callback(RESELECT_NAME)
	cm:real_callback(function()
		local ok, err = pcall(function()
			common.call_context_command("CcoCampaignCharacter", tostring(cqi), "Select")
		end)
		log("reselect cqi " .. cqi .. ": Select " .. (ok and "sent" or ("failed: " .. tostring(err))))
	end, RESELECT_MS, RESELECT_NAME)
end

--- Selects the Advisor again after a switch from the unit card strip, so the map card shows his new unit. It sends `Select` while he is still
--- selected, without clearing first: clearing closed the units panel and rebuilt the strip, which then sat one button low until the mouse moved.
--- @param cqi number The Advisor's command queue index.
local function select_again(cqi)
	local ok, err = pcall(function()
		common.call_context_command("CcoCampaignCharacter", tostring(cqi), "Select")
	end)
	log("reselect cqi " .. cqi .. ": Select without clearing " .. (ok and "sent" or ("failed: " .. tostring(err))))
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Mount box

--- Whether a clicked component sits inside the character panel's Mount box list, found by following its parents up to `MOUNT_BOX`. Read only.
--- @param address any The clicked component's address from the click event.
--- @returns boolean True when it is inside the Mount box.
local function in_mount_box(address)
	if not address then
		return false
	end
	local uic = UIComponent(address)
	for _ = 1, MOUNT_BOX_DEPTH do
		if component_id(uic) == MOUNT_BOX then
			return true
		end
		local ok, parent = pcall(function()
			return uic:Parent()
		end)
		if not ok or not parent then
			return false
		end
		uic = UIComponent(parent)
	end
	return false
end

--- After a click in the Mount box, reads the shown Advisor's worn rig without changing anything. When it no longer matches his saved pair (a pick
--- the ancillary event missed, or "None"), it sends a UI trigger so every client reconciles him the same way.
local function check_mount_pick()
	local panel = find_panel()
	local character, seen = nil, "the character panel is closed"
	if panel then
		character, seen = panel_character(panel)
	end
	if not is_local_advisor(character) then
		log("Mount box check skipped: " .. seen)
		return
	end
	local cqi = character:command_queue_index()
	local worn = worn_rigs(character)
	local weapon, mount = current_pair(character)
	local wanted = rig_data().ancillaries[weapon .. "|" .. mount]
	if #worn == 1 and worn[1] == wanted then
		log("Mount box check cqi " .. cqi .. ": wears " .. wanted .. ", which is his saved pair, nothing to do")
		return
	end
	local trigger = RECONCILE_PREFIX .. cqi
	log("Mount box check cqi " .. cqi .. ": wears " .. (#worn > 0 and table.concat(worn, ", ") or "no rig") .. ", saved pair " .. tostring(wanted)
		.. ", sending " .. trigger)
	log_call("CampaignUI", "TriggerCampaignScriptEvent " .. trigger)
	CampaignUI.TriggerCampaignScriptEvent(character:faction():command_queue_index(), trigger)
end

--- Refreshes the local Advisor's map unit card and the button after his loadout changed outside the picker. While the character panel is open the
--- reselect waits until it closes.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param changed boolean Whether his loadout or ancillaries changed.
--- @param why string What changed it, for the log.
local function after_mount_change(character, changed, why)
	if not changed or not is_local_advisor(character) then
		return
	end
	local cqi = character:command_queue_index()
	guarded("mount change", function()
		if picker_cqi == cqi then
			close_picker("the loadout changed in the Mount box")
		end
		reselect(cqi)
	end)
	schedule_refresh(why)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_character_selected",
	"CharacterSelected",
	true,
	function(context)
		local character = context:character()
		selected_cqi = character:command_queue_index()
		local ok, details = pcall(function()
			return "subtype " .. character:character_subtype_key() .. ", faction " .. character:faction():name() .. ", local Advisor "
				.. tostring(is_local_advisor(character)) .. ", embedded " .. tostring(character:is_embedded_in_military_force())
		end)
		log("CharacterSelected cqi " .. selected_cqi .. ", " .. (ok and details or ("details failed: " .. tostring(details))))
		schedule_refresh("character " .. selected_cqi .. " selected")
	end,
	true
)

core:add_listener(
	TAG .. "_character_deselected",
	"CharacterDeselected",
	true,
	function()
		selected_cqi = nil
		schedule_refresh("character deselected")
	end,
	true
)

core:add_listener(
	TAG .. "_settlement_selected",
	"SettlementSelected",
	true,
	function()
		selected_cqi = nil
		schedule_refresh("settlement selected")
	end,
	true
)

core:add_listener(
	TAG .. "_panel_opened",
	"PanelOpenedCampaign",
	true,
	function(context)
		local panel = tostring(context.string)
		if panel == PANEL then
			panel_open = true
		end
		local hides = hides_on_open(panel)
		log("PanelOpenedCampaign " .. panel .. (hides and ", hides the button" or ", keeps the button"))
		if hides then
			guarded("panel open", function()
				set_hidden("panel " .. panel .. " opened", "panel " .. panel .. " opened")
			end)
		end
		schedule_refresh("panel " .. panel .. " opened")
	end,
	true
)

core:add_listener(
	TAG .. "_panel_closed",
	"PanelClosedCampaign",
	true,
	function(context)
		local panel = tostring(context.string)
		log("PanelClosedCampaign " .. panel)
		if panel == STRIP_PATH[1] and button_path == STRIP_PATH then
			-- The button stays in the strip: the reselect after a loadout change closes and reopens the units panel, and adding the button back
			-- while the strip is shown made the strip grow down over the card. The next refresh removes it if the Advisor is no longer selected.
			guarded("units panel close", function()
				close_picker("the units panel closed")
			end)
		end
		if panel == PANEL then
			panel_open = false
			guarded("panel close", function()
				set_hidden("panel " .. panel .. " closed", "the character panel closed")
			end)
			if pending_reselect then
				local cqi = pending_reselect
				pending_reselect = nil
				cm:real_callback(function()
					guarded("reselect", function()
						reselect(cqi)
					end)
				end, RESELECT_MS, RESELECT_NAME .. "_after_panel")
			end
		end
		schedule_refresh("panel " .. panel .. " closed")
	end,
	true
)

core:add_listener(
	TAG .. "_panel_click",
	"ComponentLClickUp",
	function(context)
		local clicked = tostring(context.string)
		return panel_open and string.sub(clicked, 1, #TAG) ~= TAG and string.sub(clicked, 1, #OPTION_PREFIX) ~= OPTION_PREFIX
	end,
	function(context)
		-- The panel's arrows, character list and tabs give no event of their own, so any click re-checks which character it shows.
		schedule_refresh("click on " .. tostring(context.string))
	end,
	true
)

core:add_listener(
	TAG .. "_button_click",
	"ComponentLClickUp",
	function(context)
		return context.string == BUTTON_NAME
	end,
	function()
		after_click("button click", function()
			if picker_cqi then
				log("loadout button clicked with the picker open")
				close_picker("button clicked again")
				return
			end
			local character = button_cqi and cm:get_character_by_cqi(button_cqi)
			if not is_local_advisor(character) then
				log("loadout button clicked but it belongs to no local Advisor")
				set_hidden("button click", "the button had no Advisor")
				return
			end
			local cqi = character:command_queue_index()
			if used_this_turn(cqi) then
				log("loadout button clicked for cqi " .. cqi .. " but he already changed this turn")
				return
			end
			log("loadout button clicked for cqi " .. cqi)
			open_picker(character)
		end)
	end,
	true
)

core:add_listener(
	TAG .. "_option_click",
	"ComponentLClickUp",
	function(context)
		return picker_options[context.string] ~= nil
	end,
	function(context)
		local clicked = context.string
		after_click("option click", function()
			local option = picker_options[clicked]
			if not option then
				log("loadout option " .. tostring(clicked) .. " clicked but the picker closed first")
				return
			end
			local cqi = picker_cqi
			local character = cqi and cm:get_character_by_cqi(cqi)
			if not character then
				log("loadout option " .. tostring(clicked) .. " clicked but its Advisor is gone")
				close_picker("its Advisor is gone")
				return
			end
			if not option.enabled then
				log("loadout option " .. option.kind .. " " .. option.key .. " clicked but it is not pickable")
				return
			end
			local weapon, mount = current_pair(character)
			if option.kind == "weapon" then
				weapon = option.key
			else
				mount = option.key
			end
			local trigger = TRIGGER_PREFIX .. cqi .. ":" .. weapon .. ":" .. mount
			log("loadout option " .. option.kind .. " " .. option.key .. " clicked, sending " .. trigger)
			close_picker("option picked")
			CampaignUI.TriggerCampaignScriptEvent(character:faction():command_queue_index(), trigger)
		end)
	end,
	true
)

core:add_listener(
	TAG .. "_loadout_trigger",
	"UITrigger",
	function(context)
		return string.sub(context:trigger(), 1, #TRIGGER_PREFIX) == TRIGGER_PREFIX
	end,
	function(context)
		local trigger = context:trigger()
		local cqi, weapon, mount = string.match(string.sub(trigger, #TRIGGER_PREFIX + 1), "^(%d+):([^:]+):([^:]+)$")
		local character = cqi and cm:get_character_by_cqi(tonumber(cqi))
		if not character or character:character_subtype_key() ~= SUBTYPE then
			log("loadout trigger " .. trigger .. " names no Advisor")
			return
		end
		if character:faction():command_queue_index() ~= context:faction_cqi() then
			log("loadout trigger " .. trigger .. " came from another faction (cqi " .. tostring(context:faction_cqi()) .. ")")
			return
		end
		choose_pair(character, weapon, mount)
		if is_local_advisor(character) then
			if button_path == STRIP_PATH then
				select_again(character:command_queue_index())
			else
				reselect(character:command_queue_index())
			end
			schedule_refresh("loadout changed")
		end
	end,
	true
)

core:add_listener(
	TAG .. "_ancillary_gained",
	"CharacterAncillaryGained",
	function(context)
		local ancillary = tostring(context:ancillary())
		return context:character():character_subtype_key() == SUBTYPE and string.sub(ancillary, 1, #RIG_PREFIX) == RIG_PREFIX
	end,
	function(context)
		local character = context:character()
		local ancillary = tostring(context:ancillary())
		log("CharacterAncillaryGained cqi " .. character:command_queue_index() .. " " .. ancillary)
		local changed = reconcile(character, "gained " .. ancillary)
		after_mount_change(character, changed, "loadout changed in the Mount box")
	end,
	true
)

core:add_listener(
	TAG .. "_mount_box_click",
	"ComponentLClickUp",
	function()
		return panel_open
	end,
	function(context)
		if not in_mount_box(context.component) then
			return
		end
		log("click on " .. tostring(context.string) .. " inside the Mount box, checking the worn rig in " .. MOUNT_PICK_MS .. " ms")
		cm:remove_real_callback(MOUNT_PICK_NAME)
		cm:real_callback(function()
			guarded("Mount box check", check_mount_pick)
		end, MOUNT_PICK_MS, MOUNT_PICK_NAME)
	end,
	true
)

core:add_listener(
	TAG .. "_reconcile_trigger",
	"UITrigger",
	function(context)
		return string.sub(context:trigger(), 1, #RECONCILE_PREFIX) == RECONCILE_PREFIX
	end,
	function(context)
		local trigger = context:trigger()
		local cqi = tonumber(string.match(string.sub(trigger, #RECONCILE_PREFIX + 1), "^(%d+)$"))
		local character = cqi and cm:get_character_by_cqi(cqi)
		if not character or character:character_subtype_key() ~= SUBTYPE then
			log("reconcile trigger " .. trigger .. " names no Advisor")
			return
		end
		if character:faction():command_queue_index() ~= context:faction_cqi() then
			log("reconcile trigger " .. trigger .. " came from another faction (cqi " .. tostring(context:faction_cqi()) .. ")")
			return
		end
		local changed = reconcile(character, "Mount box pick")
		after_mount_change(character, changed, "loadout changed in the Mount box")
	end,
	true
)

core:add_listener(
	TAG .. "_skill_unlock",
	"CharacterSkillPointAllocated",
	function(context)
		return context:character():character_subtype_key() == SUBTYPE
	end,
	function(context)
		local character = context:character()
		local skill = context:skill_point_spent_on()
		local rigs = rig_data()
		local weapon, mount = rigs.weapon_skills[skill], rigs.mount_skills[skill]
		if not weapon and not mount then
			return
		end
		local cqi = character:command_queue_index()
		log("cqi " .. cqi .. " unlocked " .. (weapon and ("weapon " .. weapon) or ("mount " .. mount)) .. ", unlocked weapons: "
			.. unlocked_list(character, "weapon") .. ", unlocked mounts: " .. unlocked_list(character, "mount"))
		-- The newly unlocked pairs go into the pool.
		reconcile(character, "skill " .. skill)
		if picker_cqi == cqi then
			guarded("unlock", function()
				close_picker("a new item was unlocked")
			end)
		end
	end,
	true
)

core:add_listener(
	TAG .. "_turn_start",
	"FactionTurnStart",
	function(context)
		return context:faction():is_human()
	end,
	function(context)
		apply_all("turn start of " .. context:faction():name())
		if context:faction():name() == cm:get_local_faction_name(true) then
			schedule_refresh("turn start")
		end
	end,
	true
)

core:add_listener(
	TAG .. "_turn_end",
	"FactionTurnEnd",
	function(context)
		return context:faction():name() == cm:get_local_faction_name(true)
	end,
	function()
		selected_cqi = nil
		panel_open = false
		cm:remove_real_callback(REFRESH_NAME)
		guarded("turn end", function()
			set_hidden("turn end", "turn ended")
		end)
	end,
	true
)

cm:add_first_tick_callback(function()
	-- advisor_overhaul_spawn.lua spawns the Advisors on the first tick of a new campaign, so this waits until they exist.
	cm:callback(function()
		apply_all("first tick")
	end, 2)
end)
