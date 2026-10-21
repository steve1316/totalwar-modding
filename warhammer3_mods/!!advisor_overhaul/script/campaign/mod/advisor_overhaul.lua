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
--- It also gives him each weapon's art bundles and the Polymath bundle for the skills he owns, and draws their boxes over the art and Polymath
--- skill cards.
---
--- The button is a child of a vanilla row: the character panel's bottom-right buttons, or the hover strip over the selected Advisor's unit card on
--- the map. The picker options are direct children of the UI root. The script only ever changes or destroys a component it found by its own
--- unique name.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Prefix of every log line and saved value.
local TAG = "advisor_overhaul"

--- When true the Advisor may change his loadout only once per turn.
local ONE_CHANGE_PER_TURN = false

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

--- State of the option he already uses. It is one of `BUTTON_TEMPLATE`'s states (active, down, down_off, hover, inactive), the pressed look.
local CURRENT_STATE = "down"

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
--- and crashed the game, so clicks only schedule their work.
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

--- Path from the panel to its bottom-right row of square buttons (replace, event feed, rename). The button is made in it.
local PANEL_ROW_PATH = { "character_context_parent", "holder_br", "bottom_buttons" }

--- The same row as `PANEL_ROW_PATH`, from the UI root: `PANEL` followed by `PANEL_ROW_PATH`.
local ROW_PATH = { PANEL }
for _, name in ipairs(PANEL_ROW_PATH) do
	table.insert(ROW_PATH, name)
end

--- Path from the UI root to the button strip over the hovered unit card (Disband, Rename). The game shows it and moves it on hover. The button is
--- made in it while the local Advisor is selected on his own.
local STRIP_PATH = { "units_panel", "main_units_panel", "button_group_unit" }

--- Draw priority added on top of the panel's own, so the button and picker draw over it.
local PANEL_PRIORITY_BONUS = 50

--- Start of the UI trigger string that carries a pick to every client.
local TRIGGER_PREFIX = TAG .. "_loadout:"

--- Start of the UI trigger string that asks every client to read the Advisor's worn rig again, after a pick in the panel's Mount box.
local RECONCILE_PREFIX = TAG .. "_reconcile:"

--- The character panel's Mount box list (ui3.pack character_details_panel_details.twui.xml). A click inside it may pick a rig or "None".
local MOUNT_BOX = "ancillary_selector_mount"

--- How many parents a clicked component is followed up to find `MOUNT_BOX`.
local MOUNT_BOX_DEPTH = 12

--- Name of the one-shot real-time callback that checks the worn rig after a click in the Mount box.
local MOUNT_PICK_NAME = TAG .. "_mount_pick"

--- Delay of that callback in milliseconds, so the game has run the native equip command first.
local MOUNT_PICK_MS = 500

--- The vanilla tooltip the game builds inside a hovered skill card. The card's `layout_path` is ui3.pack ui/campaign ui/edict_tooltip.
local SKILL_TOOLTIP = "edict_tooltip"

--- Our own box shown in place of the vanilla tooltip of an art card or the Polymath card, with the layout it is made from and its title and text
--- children.
local ART_BOX = TAG .. "_art_box"
local ART_BOX_LAYOUT = "ui/common ui/tooltip_centred_title_and_text"
local ART_BOX_TITLE = "dy_title"
local ART_BOX_TEXT = "dy_text"

--- Copy of the box's text made below its effect list, for the skills the art still needs.
local ART_BOX_FOOT = TAG .. "_art_foot"

--- The vanilla effect bundle tooltip, made only to move its effect list into the art box. The list draws the effects of the `CcoEffectBundle` it is
--- given with the game's own icons and eye tooltips.
local ART_BUNDLE = TAG .. "_art_bundle"
local ART_BUNDLE_LAYOUT = "ui/common ui/tooltip_effect_bundle"
local ART_EFFECT_LIST = "effect_list"

--- Top and bottom text padding in pixels of the foot. The text it is copied from has 10 above and below.
local ART_FOOT_PAD = { 10, 0 }

--- The lock bar the game draws in its tooltips, the part of it set to the box's width, and the part that fills while a card is hovered. The bar is
--- its own UI root child laid on the box's bottom edge, as inside the box its layout stacked the bar under the text.
local ART_BAR = TAG .. "_art_bar"
local ART_BAR_LAYOUT = "ui/templates/stick_progress_bar"
local ART_BAR_FRAME = "bar_extents_and_pos"
local ART_BAR_FILL = "auto_resizing_comp"

--- Children of the fill shown while it fills and once the box is locked, the bar's height in pixels, and pixels from its top up to the box's bottom.
--- The fill's line is drawn 2 pixels below the bar's top.
local ART_BAR_FILLING = "in_progress_comp"
local ART_BAR_DONE = "completed_comp"
local ART_BAR_H = 3
local ART_BAR_LIFT = 5

--- Gap in pixels kept between an art card and its box.
local ART_BOX_GAP = 8

--- Seconds a card is hovered before its art box locks, and seconds a locked box stays after the mouse leaves it. These match the game's
--- `ui_tooltip_stick_delay` and `ui_tooltip_removal_delay` in preferences.script.txt.
local ART_STICK_S = 0.35
local ART_REMOVAL_S = 0.15

--- Name of the real-time callback that shows the art box while the character panel is open.
local ART_TOOLTIP_NAME = TAG .. "_art_tooltip"

--- Delay in milliseconds between looks for a hovered art card, and how many looks pass between rebuilds of the art cards' texts.
local ART_TOOLTIP_MS = 20
local ART_CARD_LOOKS = 15

--- UI text: loc key in text/db/advisor_overhaul_ui.loc (item names are in advisor_overhaul.loc) and the English fallback if the key does not resolve.
local TEXT = {
	--- Tooltip of the Change Loadout button.
	button = { "advisor_overhaul_ui_button_tooltip", "Change Loadout||Choose which of the Advisor's unlocked weapons and mounts he takes to war. Learn weapon and mount skills to unlock more." },
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
	--- Start of the line an art slot skill's tooltip gets for the weapon he holds, followed by the weapon's name.
	art_with = { "advisor_overhaul_ui_art_with", "With" },
	--- Start of the line an art slot skill's tooltip gets while its weapon is still locked, followed by the weapon's name.
	art_locked = { "advisor_overhaul_ui_art_locked", "Available after unlocking" },
	--- Line of the Polymath box before the disciplines that count, once he has the Polymath and before he has it.
	polymath_counted = { "advisor_overhaul_ui_polymath_counted", "Disciplines counted:" },
	polymath_counted_unlearned = { "advisor_overhaul_ui_polymath_counted_unlearned", "Disciplines counted if learned now:" },
	--- Words of a discipline's line in the Polymath box: "Memory: 1 of 5 skills".
	polymath_of = { "advisor_overhaul_ui_polymath_of", "of" },
	polymath_skills = { "advisor_overhaul_ui_polymath_skills", "skills" },
	--- Name of each Polymath discipline, by `discipline_` and its key in `ADVISOR_OVERHAUL_RIGS.polymath.disciplines`.
	discipline_arts = { "advisor_overhaul_ui_discipline_arts", "Arts" },
	discipline_memory = { "advisor_overhaul_ui_discipline_memory", "Memory" },
	discipline_magic = { "advisor_overhaul_ui_discipline_magic", "Magic" },
	discipline_hero_work = { "advisor_overhaul_ui_discipline_hero_work", "Hero work" },
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- State

--- CQI of the selected character, or nil when no character is selected.
local selected_cqi = nil

--- CQI of the Advisor the shown button belongs to, or nil when the button is hidden.
local button_cqi = nil

--- Path from the UI root to the parent the button was made in (`ROW_PATH` or `STRIP_PATH`), or nil when it is not made.
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

--- What each art card's box shows, by skill key, from `art_card_tooltip`, and the Polymath card's from `polymath_card_tooltip`. Cleared when the
--- panel opens.
local art_card_tips = {}

--- Our art box: the component, false when it could not be made while this panel is open, or nil when it is not made yet.
local art_box = nil

--- The skill key and text the art box shows, or nil while it is hidden.
local art_box_skill = nil
local art_box_text = nil

--- The vanilla effect list moved into the art box, or nil when it could not be made.
local art_box_effects = nil

--- The art box's foot copy. Made with the box.
local art_box_foot = nil

--- The art box's lock bar parts by name, nil when it could not be made, its full width in pixels, and the width and state it was last given.
local art_bar = nil
local art_bar_full = 0
local art_bar_width = nil
local art_bar_done = nil

--- When the shown art card's hover began, from `os.clock`, whether the art box is locked, and when the mouse left a locked box (nil while on it).
local art_box_since = 0
local art_box_locked = false
local art_box_left = nil

--- CQI of an Advisor whose loadout changed while the character panel was open, so he is selected again once it closes. Nil when none waits.
local pending_reselect = nil

--- Draw priority of the shown button. The picker options use the same.
local ui_priority = UI_PRIORITY

--- The last show or hide decision, so the log gets one line each time it changes.
local last_decision = nil

--- Unlock skill key -> { kind, key } of the item it unlocks, built once from the generated lists by `skill_items`.
local unlock_skills = nil

--- True while `grant_by_rank` is giving skills. Each `add_skill` fires the skill listener at once, and a grant from inside it crashed the game.
local granting = false

--- Every rig ancillary key, sorted, built once by `rig_keys`.
local sorted_rigs = nil


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Data

--- The generated pair data. Read when used, since script load order does not promise the data file loads first.
--- @returns table The `ADVISOR_OVERHAUL_RIGS` table.
local function rig_data()
	return ADVISOR_OVERHAUL_RIGS
end

--- Whether a character is an Advisor, of any faction.
--- @param character CHARACTER_SCRIPT_INTERFACE The character.
--- @returns boolean True when his subtype is the Advisor's.
local function is_advisor(character)
	return character:character_subtype_key() == rig_data().subtype
end

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
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

--- The Advisor's saved weapon and mount, or the defaults when nothing is saved. Not checked against what he has unlocked.
--- @param cqi number The Advisor's command queue index.
--- @returns string The weapon key.
--- @returns string The mount key.
local function saved_pair(cqi)
	local rigs = rig_data()
	return cm:get_saved_value(choice_key(cqi, "weapon")) or rigs.default_weapon, cm:get_saved_value(choice_key(cqi, "mount")) or rigs.default_mount
end

--- Saves the Advisor's weapon and mount.
--- @param cqi number The Advisor's command queue index.
--- @param weapon string The weapon key.
--- @param mount string The mount key.
--- @param mark_turn boolean Whether this counts as his change for this turn.
local function save_pair(cqi, weapon, mount, mark_turn)
	cm:set_saved_value(choice_key(cqi, "weapon"), weapon)
	cm:set_saved_value(choice_key(cqi, "mount"), mount)
	if mark_turn then
		cm:set_saved_value(changed_turn_key(cqi), cm:model():turn_number())
	end
end

--- The item list of a kind.
--- @param kind string `weapon` or `mount`.
--- @returns table The `weapons` or `mounts` list of `ADVISOR_OVERHAUL_RIGS`.
local function items_of(kind)
	return kind == "weapon" and rig_data().weapons or rig_data().mounts
end

--- A picker option's component name: the prefix, `w` or `m`, and the item's place in its list, e.g. `aolo_w1`.
--- @param kind string `weapon` or `mount`.
--- @param index number The item's place in its list.
--- @returns string The name.
local function option_name(kind, index)
	return OPTION_PREFIX .. string.sub(kind, 1, 1) .. index
end

--- The item each unlock skill unlocks, built from the generated weapon and mount lists on first use.
--- @returns table Unlock skill key -> { kind, key }.
local function skill_items()
	if not unlock_skills then
		unlock_skills = {}
		for _, kind in ipairs({ "weapon", "mount" }) do
			for _, item in ipairs(items_of(kind)) do
				if item.skill ~= "" then
					unlock_skills[item.skill] = { kind = kind, key = item.key }
				end
			end
		end
	end
	return unlock_skills
end

--- Every rig ancillary key, sorted, so the pool sync and its log run in a fixed order. Built on first use.
--- @returns table The ancillary keys.
local function rig_keys()
	if not sorted_rigs then
		sorted_rigs = {}
		for ancillary in pairs(rig_data().rigs) do
			table.insert(sorted_rigs, ancillary)
		end
		table.sort(sorted_rigs)
	end
	return sorted_rigs
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

--- The rig that gives the Advisor a pair's unit: the upgrade's rig (an apex form) once he owns its skill, else the pair's own.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string Weapon key.
--- @param mount string Mount key.
--- @returns string|nil The ancillary key, or nil when the pair has no unit.
local function pair_rig(character, weapon, mount)
	local upgrade = (rig_data().upgrades or {})[weapon .. "|" .. mount]
	if upgrade and character:has_skill(upgrade.skill) then
		return upgrade.ancillary
	end
	return rig_data().ancillaries[weapon .. "|" .. mount]
end

--- The weapon and mount to use: the saved choices while still unlocked (a respec can take them away), else the defaults. A pair with no unit falls
--- back first to the default weapon and then to the default mount.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns string The weapon key.
--- @returns string The mount key.
local function current_pair(character)
	local rigs = rig_data()
	local cqi = character:command_queue_index()
	local weapon, mount = saved_pair(cqi)
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

--- The arts of a weapon whose slot skill the Advisor owns.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon key.
--- @returns table The owned art rows of `ADVISOR_OVERHAUL_RIGS.arts`.
local function owned_arts(character, weapon)
	local owned = {}
	for _, art in ipairs((rig_data().arts or {})[weapon] or {}) do
		if character:has_skill(art.skill) then
			table.insert(owned, art)
		end
	end
	return owned
end

--- Puts on the Advisor the art bundles of the weapon he holds, for each art slot skill he owns, and takes every other art bundle off. Runs each
--- time his loadout is applied: a loadout change, a skill point, each load and each turn start.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param weapon string The weapon he holds.
--- @returns boolean True when a bundle was put on or taken off.
local function sync_arts(character, weapon)
	local wanted = {}
	for _, art in ipairs(owned_arts(character, weapon)) do
		wanted[art.bundle] = true
	end
	local added, removed = {}, {}
	for _, arts in pairs(rig_data().arts or {}) do
		for _, art in ipairs(arts) do
			local has = character:has_effect_bundle(art.bundle)
			if wanted[art.bundle] and not has then
				cm:apply_effect_bundle_to_character(art.bundle, character, 0)
				table.insert(added, art.bundle)
			elseif has and not wanted[art.bundle] then
				cm:remove_effect_bundle_from_character(art.bundle, character)
				table.insert(removed, art.bundle)
			end
		end
	end
	if #added > 0 or #removed > 0 then
		log("cqi " .. character:command_queue_index() .. " arts for " .. weapon .. ": added " .. table.concat(added, ", ") .. "; removed "
			.. table.concat(removed, ", "))
	end
	return #added > 0 or #removed > 0
end

--- How many skills the Advisor knows in each Polymath discipline, and the disciplines in which he knows enough for them to count.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param data table The Polymath, from `ADVISOR_OVERHAUL_RIGS.polymath`.
--- @returns table Each discipline's `name` and `owned` skills, in tree order.
--- @returns table Names of the disciplines that count, in tree order.
local function polymath_progress(character, data)
	local progress, counted = {}, {}
	for _, discipline in ipairs(data.disciplines) do
		local owned = 0
		for _, key in ipairs(discipline.skills) do
			if character:has_skill(key) then
				owned = owned + 1
			end
		end
		table.insert(progress, { name = discipline.name, owned = owned })
		if owned >= data.needed then
			table.insert(counted, discipline.name)
		end
	end
	return progress, counted
end

--- Puts on the Advisor the Polymath bundle for the number of disciplines in which he has enough skills, while he owns the Polymath, and takes every
--- other Polymath bundle off. Runs with `sync_arts`, and on every skill point.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when a bundle was put on or taken off.
local function sync_polymath(character)
	local data = rig_data().polymath
	if not data then
		return false
	end
	local counted, wanted = {}, nil
	if character:has_skill(data.skill) then
		local _, owned = polymath_progress(character, data)
		-- The first bundle is for no disciplines, so he has one whenever he owns the Polymath.
		counted, wanted = owned, data.bundles[#owned + 1]
	end
	local changed = false
	for _, bundle in ipairs(data.bundles) do
		local has = character:has_effect_bundle(bundle)
		if bundle == wanted and not has then
			cm:apply_effect_bundle_to_character(bundle, character, 0)
			changed = true
		elseif has and bundle ~= wanted then
			cm:remove_effect_bundle_from_character(bundle, character)
			changed = true
		end
	end
	if changed then
		log("cqi " .. character:command_queue_index() .. " Polymath counts " .. #counted .. " disciplines (" .. table.concat(counted, ", ") .. "), bundle "
			.. tostring(wanted))
	end
	return changed
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
	local pair = rig_data().rigs[ancillary]
	if not pair then
		return nil, nil
	end
	return pair.weapon, pair.mount
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
	for _, ancillary in ipairs(rig_keys()) do
		if character:has_ancillary(ancillary) then
			table.insert(worn, ancillary)
		end
	end
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
		if is_advisor(character) then
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

--- Whether the faction owns an ancillary, worn or in its pool. `ancillary_exists` cannot tell a pool copy from a worn one.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param ancillary string The ancillary key.
--- @returns boolean True when the faction owns it.
local function faction_owns(faction, ancillary)
	local ok, exists = pcall(function()
		return faction:ancillary_exists(ancillary)
	end)
	return ok and exists == true
end

--- Whether an unworn copy of an ancillary sits in the faction's pool: the faction owns it and no Advisor wears it.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param advisors table The faction's Advisors.
--- @param ancillary string The ancillary key.
--- @returns boolean True when a copy is in the pool.
local function in_pool(faction, advisors, ancillary)
	return not worn_by_any(advisors, ancillary) and faction_owns(faction, ancillary)
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
	local changes = {}
	for _, ancillary in ipairs(rig_keys()) do
		-- A worn rig is left alone.
		if not worn_by_any(advisors, ancillary) then
			local weapon, mount = rig_pair(ancillary)
			local unlocked = false
			for _, advisor in ipairs(advisors) do
				-- A pair's own rig stays out of the pool while his upgrade replaces it, and the upgrade's rig until then.
				unlocked = unlocked or (pair_unlocked(advisor, weapon, mount) and pair_rig(advisor, weapon, mount) == ancillary)
			end
			local pooled = faction_owns(faction, ancillary)
			if unlocked and not pooled then
				cm:add_ancillary_to_faction(faction, ancillary, true)
				table.insert(changes, "added " .. ancillary)
			elseif not unlocked and pooled then
				cm:force_remove_ancillary_from_faction(faction, ancillary)
				table.insert(changes, "removed " .. ancillary)
			end
		end
	end
	log("pool " .. faction:name() .. " (" .. why .. "): " .. (#changes > 0 and table.concat(changes, ", ") or "no change"))
end

--- Equips the mount ancillary of the Advisor's current pair. Every other pair's rig goes back to the faction pool, so the Mount box lists it. The
--- pair is saved back, so a choice a respec took away does not return when he learns the skill again. Also sets his weapon's art set. The caller
--- syncs the pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when an ancillary was equipped or removed.
local function apply_pair(character)
	local weapon, mount = current_pair(character)
	local cqi = character:command_queue_index()
	local faction = character:faction()
	save_pair(cqi, weapon, mount, false)
	local wanted = pair_rig(character, weapon, mount)
	apply_art_set(character, weapon)
	sync_arts(character, weapon)
	sync_polymath(character)
	if not wanted then
		log("cqi " .. cqi .. " has no unit for " .. weapon .. " on " .. mount .. ", nothing equipped")
		return false
	end
	local stale = {}
	for _, ancillary in ipairs(rig_keys()) do
		if ancillary ~= wanted and character:has_ancillary(ancillary) then
			table.insert(stale, ancillary)
		end
	end
	if character:has_ancillary(wanted) and #stale == 0 then
		return false
	end
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
	return true
end

--- Teleports the Advisor onto the spot he stands on, so the game works out his stats again. A bundle put on by script leaves his unit card stale
--- until he moves on the map. Reselecting or putting his rig back on did not refresh it. Skipped inside an army or a settlement.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
local function refresh_stats(character)
	local cqi = character:command_queue_index()
	if character:is_embedded_in_military_force() or character:has_garrison_residence() then
		log("cqi " .. cqi .. " stats refresh skipped: he is in an army or a settlement")
		return
	end
	local x, y = character:logical_position_x(), character:logical_position_y()
	local ok, err = pcall(function()
		cm:teleport_to(cm:char_lookup_str(cqi), x, y)
	end)
	log("cqi " .. cqi .. " teleported onto his own spot " .. x .. "," .. y .. " to refresh his stats" .. (ok and "" or (", error: " .. tostring(err))))
end

--- Gives the Advisor each weapon or mount skill that has a `grant_rank` once he has reached that rank. Runs from game events only, so every client
--- grants the same skills. A call from inside a grant does nothing, so the outer loop gives each skill in turn.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns boolean True when a skill was given.
local function grant_by_rank(character)
	if granting then
		return false
	end
	granting = true
	local granted = false
	-- A raised error must not leave `granting` set, or he would never be given another skill.
	local ok, err = pcall(function()
		for _, kind in ipairs({ "weapon", "mount" }) do
			for _, item in ipairs(items_of(kind)) do
				if item.grant_rank and item.skill ~= "" and character:rank() >= item.grant_rank and not character:has_skill(item.skill) then
					cm:add_skill(character, item.skill, true, true)
					log("cqi " .. character:command_queue_index() .. " reached rank " .. character:rank() .. ", granted " .. kind .. " " .. item.key)
					granted = true
				end
			end
		end
	end)
	granting = false
	if not ok then
		log("grant by rank failed: " .. tostring(err))
	end
	return granted
end

--- Reads which rig the Advisor wears and makes it his loadout, so a pick in the character panel's Mount box sticks. With exactly one worn rig of an
--- unlocked pair, that pair is saved as his choice. With none (the Mount box's "None"), a locked one or several, the saved pair is equipped again.
--- Runs from game events and UI triggers only, so every client saves the same values. The caller syncs the pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for it, for the log.
--- @returns boolean True when his loadout or ancillaries changed.
local function reconcile_pair(character, why)
	grant_by_rank(character)
	local cqi = character:command_queue_index()
	local worn = worn_rigs(character)
	local saved_weapon, saved_mount = saved_pair(cqi)
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
				save_pair(cqi, weapon, mount, true)
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

--- Reconciles one Advisor and syncs his faction's pool.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param why string What asked for it, for the log.
--- @returns boolean True when his loadout or ancillaries changed.
local function reconcile(character, why)
	local changed = reconcile_pair(character, why)
	sync_pool(character:faction(), why)
	return changed
end

--- Reconciles every living Advisor of a faction, then syncs its pool once.
--- @param faction FACTION_SCRIPT_INTERFACE The faction.
--- @param why string What asked for it, for the log.
local function reconcile_faction(faction, why)
	for _, character in ipairs(faction_advisors(faction)) do
		if not character:is_wounded() then
			reconcile_pair(character, why)
		end
	end
	sync_pool(faction, why)
end

--- Reconciles every living Advisor of every human faction.
--- @param why string What asked for it, for the log.
local function apply_all(why)
	for _, faction_key in ipairs(cm:get_human_factions()) do
		reconcile_faction(cm:get_faction(faction_key), why)
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
	save_pair(cqi, weapon, mount, true)
	apply_pair(character)
	sync_pool(character:faction(), "cqi " .. cqi .. " picked " .. weapon .. " on " .. mount)
	local new_weapon, new_mount = current_pair(character)
	log("cqi " .. cqi .. " loadout is now " .. new_weapon .. " on " .. new_mount .. " (turn " .. cm:model():turn_number() .. ")")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- UI text

--- A loc text, or a fallback when its key does not resolve.
--- @param key string The loc key.
--- @param fallback string The text to use when the key does not resolve.
--- @returns string The text.
local function localised(key, fallback)
	local text = common.get_localised_string(key)
	if not text or text == "" then
		return fallback
	end
	return text
end

--- A UI text, localised when its key resolves.
--- @param id string Key of `TEXT`.
--- @returns string The text.
local function ui_text(id)
	local entry = TEXT[id]
	return localised(entry[1], entry[2])
end

--- A box's flavour text with only its first paragraph in italics, so the notes after it read as plain text like a vanilla skill's.
--- @param text string The flavour text, its paragraphs split by a blank line.
--- @returns string The text in the game's markup.
local function italic_lead(text)
	local lead, notes = text:match("^(.-)(\n\n.*)$")
	if not lead then
		return "[[i]]" .. text .. "[[/i]]"
	end
	return "[[i]]" .. lead .. "[[/i]]" .. notes
end

--- An item's display name, localised when its key resolves.
--- @param item table The item row.
--- @returns string The name.
local function item_name(item)
	return localised(item.name, item.fallback)
end

--- Whether a character is an Advisor of the local player's faction.
--- @param character CHARACTER_SCRIPT_INTERFACE|nil|boolean The character, or nil or false when there is none.
--- @returns boolean True for the local player's Advisor.
local function is_local_advisor(character)
	if not character then
		return false
	end
	return is_advisor(character) and character:faction():name() == cm:get_local_faction_name(true)
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

--- The vanilla row the button was made in, found again by name at `button_path`.
--- @returns UIC|nil The row, or nil when the button is not made or the row is gone.
local function button_parent()
	if not button_path then
		return nil
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
--- @param name string The option's component name, from `option_name`.
--- @param state string `current`, `pick` or `blocked`.
--- @returns UIC|nil The option, or nil when it could not be made.
local function add_option(kind, item, name, state)
	local option = create_own(name, BUTTON_TEMPLATE)
	if not option then
		return nil
	end
	-- Registered before it is set up, so `close_picker` removes it if a later step fails.
	picker_options[name] = { kind = kind, key = item.key, enabled = state == "pick" }
	local label = ui_text(kind) .. " " .. item_name(item)
	local reason = ui_text("pick")
	if state == "current" then
		label = label .. " " .. ui_text("current")
		reason = ui_text("in_use")
	elseif state == "blocked" then
		reason = ui_text(kind .. "_blocked")
	end
	local icon = item.icon
	local ui_state = state == "current" and CURRENT_STATE or state == "blocked" and "inactive" or "active"
	local ok, err = pcall(function()
		option:SetImagePath(icon, BUTTON_ICON_INDEX)
		option:SetTooltipText(label .. "||" .. reason, true)
		option:SetState(ui_state)
		option:PropagatePriority(ui_priority)
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
		for index, item in ipairs(items_of(kind)) do
			if is_unlocked(character, item) then
				local is_current = item.key == (kind == "weapon" and weapon or mount)
				local fits = kind == "weapon" and has_unit(item.key, mount) or kind == "mount" and has_unit(weapon, item.key)
				local state = is_current and "current" or fits and "pick" or "blocked"
				local name = option_name(kind, index)
				local option = add_option(kind, item, name, state)
				if not option then
					log("loadout picker not opened: option " .. kind .. " " .. item.key .. " could not be made")
					close_picker("option " .. kind .. " " .. item.key .. " could not be made")
					return
				end
				table.insert(column, { name = name, uic = option })
				table.insert(shown, item.key .. "=" .. state)
			end
		end
		columns[kind] = column
		log("loadout picker cqi " .. cqi .. " " .. kind .. "s: " .. table.concat(shown, ", "))
	end
	-- Each column stacks upward from just above the button. Weapons sit in the button's column, mounts in the next one to the right.
	local ok, err = pcall(function()
		local button_x, button_y = button:Position()
		local size, height = button:Dimensions()
		local x = button_x
		for _, kind in ipairs({ "weapon", "mount" }) do
			local column = columns[kind]
			if #column > 0 then
				for i, entry in ipairs(column) do
					local y = math.max(0, button_y - (#column - i + 1) * (height + OPTION_GAP))
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

--- Lays the row out again when the injected button sits on a shown sibling.
--- @param parent UIC The row the button is in.
--- @param button UIC The button.
--- @returns string The button's spot, for the log.
local function check_row_layout(parent, button)
	local own = read_bounds(button)
	if not own then
		return "unreadable spot"
	end
	local overlap = nil
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
			if bounds and bounds.visible and bounds.x == own.x and bounds.y == own.y then
				overlap = id
			end
		end
	end
	if overlap then
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

--- Makes or updates the button for the local Advisor inside a vanilla row: the character panel's bottom-right row, or the unit card hover strip on
--- the map. The row's layout places it, so it is never moved, raised or made top-most. It is found by name first, so there is never a second copy.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @param panel UIC|nil The character panel when the button goes on it, or nil for the map strip.
--- @param why string What asked for the check, for the log.
local function show_button(character, panel, why)
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
	if not button then
		button = create_child(parent, BUTTON_NAME, BUTTON_TEMPLATE)
		if not button then
			set_hidden(why, "the button could not be made in " .. where)
			return
		end
	end
	button_path = path
	local used = used_this_turn(cqi)
	local ok, result = pcall(function()
		button:SetImagePath(BUTTON_ICON, BUTTON_ICON_INDEX)
		local state = used and "inactive" or "active"
		button:SetState(state)
		button:SetTooltipText(ui_text(used and "button_used" or "button"), true)
		button:SetVisible(true)
		return check_row_layout(parent, button)
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
	if not is_advisor(character) then
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
	if character:is_embedded_in_military_force() then
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

--- Sends `Select` for the Advisor without clearing the selection first. After a switch from the unit card strip it refreshes the map card while he
--- is still selected: clearing closed the units panel and rebuilt the strip, which then sat one button low until the mouse moved. `reselect`
--- calls it once the selection is cleared.
--- @param cqi number The Advisor's command queue index.
local function select_again(cqi)
	local ok, err = pcall(function()
		common.call_context_command("CcoCampaignCharacter", tostring(cqi), "Select")
	end)
	log("reselect cqi " .. cqi .. ": Select " .. (ok and "sent" or ("failed: " .. tostring(err))))
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
		select_again(cqi)
	end, RESELECT_MS, RESELECT_NAME)
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Art skill tooltips

--- Runs a step and logs it when it fails, without hiding the button: a failed art tooltip only leaves the vanilla tooltip.
--- @param what string The step, for the log.
--- @param step function The step.
local function logged(what, step)
	local ok, err = pcall(step)
	if not ok then
		log(what .. " failed: " .. tostring(err))
	end
end

--- What an art slot skill's card box shows, in the game's text markup: the skill name as its title, then the skill's flavour text and the art of
--- the weapon he holds with its description, and the skills it still needs. The effect list draws the art's effects.
--- @param art table The art row.
--- @param weapon string The weapon key.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table `title`, `text` (up to the effects), `foot` ("" for none), `bundle` and `whole` (all of it).
local function art_card_tooltip(art, weapon, character)
	local item = find_item("weapon", weapon)
	local head = {
		italic_lead(art.flavour),
		"",
		"[[col:yellow]]" .. ui_text("art_with") .. " " .. (item and item_name(item) or weapon) .. ": "
			.. localised("effect_bundles_localised_title_" .. art.bundle, art.name) .. "[[/col]]",
	}
	if art.about ~= "" then
		table.insert(head, "[[i]]" .. art.about .. "[[/i]]")
	end
	local foot = {}
	for _, required in ipairs(art.requires) do
		if not character:has_skill(required.skill) then
			table.insert(foot, "[[col:red]]" .. ui_text("art_locked") .. " \"" .. localised("character_skills_localised_name_" .. required.skill, required.name) .. "\".[[/col]]")
		end
	end
	local tip = {
		title = localised("character_skills_localised_name_" .. art.skill, art.skill_name),
		text = table.concat(head, "\n"),
		foot = table.concat(foot, "\n\n"),
		bundle = art.bundle,
	}
	tip.whole = tip.title .. "||" .. tip.text .. "\n" .. tip.bundle .. "\n" .. tip.foot
	return tip
end

--- What the Polymath card's box shows, in the game's text markup: its name as the title, its flavour, then how many skills he knows in each
--- discipline. The effect list draws the Polymath bundle he has now, or the one he would get if he learned it now.
--- @param data table The Polymath, from `ADVISOR_OVERHAUL_RIGS.polymath`.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
--- @returns table `title`, `text`, `foot` (always ""), `bundle` and `whole`, like `art_card_tooltip`.
local function polymath_card_tooltip(data, character)
	local progress, counted = polymath_progress(character, data)
	local head = { italic_lead(data.flavour), "" }
	for _, discipline in ipairs(progress) do
		local name = ui_text("discipline_" .. discipline.name)
		if discipline.owned >= data.needed then
			table.insert(head, "[[col:green]]" .. name .. ": " .. discipline.owned .. " " .. ui_text("polymath_skills") .. "[[/col]]")
		else
			table.insert(head, name .. ": " .. discipline.owned .. " " .. ui_text("polymath_of") .. " " .. data.needed .. " " .. ui_text("polymath_skills"))
		end
	end
	local line = character:has_skill(data.skill) and "polymath_counted" or "polymath_counted_unlearned"
	table.insert(head, "")
	table.insert(head, "[[col:yellow]]" .. ui_text(line) .. " " .. #counted .. " " .. ui_text("polymath_of") .. " " .. #data.disciplines .. "[[/col]]")
	local tip = {
		title = localised("character_skills_localised_name_" .. data.skill, data.name),
		text = table.concat(head, "\n"),
		foot = "",
		bundle = data.bundles[#counted + 1],
	}
	tip.whole = tip.title .. "||" .. tip.text .. "\n" .. tip.bundle
	return tip
end

--- Rebuilds the box of each art slot skill from the art of the weapon the Advisor holds, and the Polymath's box from his skills, so a weapon switch
--- or a learned skill shows up.
--- @param character CHARACTER_SCRIPT_INTERFACE The Advisor.
local function update_art_card_tips(character)
	local weapon = current_pair(character)
	local tips = {}
	--- Keeps a card's box and logs it when it differs from the one shown so far.
	--- @param skill string The card's skill key.
	--- @param tip table What the box shows.
	--- @param what string What it shows, for the log.
	local function keep(skill, tip, what)
		tips[skill] = tip
		if not art_card_tips[skill] or art_card_tips[skill].whole ~= tip.whole then
			log("art tooltip: " .. skill .. " shows " .. what)
		end
	end
	for _, art in ipairs((rig_data().arts or {})[weapon] or {}) do
		keep(art.skill, art_card_tooltip(art, weapon, character), "art " .. art.name .. " of " .. weapon)
	end
	local polymath = rig_data().polymath
	if polymath then
		local tip = polymath_card_tooltip(polymath, character)
		keep(polymath.skill, tip, tip.bundle)
	end
	art_card_tips = tips
end

--- Copies the art box's text into its foot below the effect list, hidden and left out of mouse hits until the box locks.
--- @param text UIC The box's text.
--- @returns UIC|nil The copy, or nil when it could not be made.
local function make_art_foot(text)
	local ok, address = pcall(function()
		return text:CopyComponent(ART_BOX_FOOT)
	end)
	if not ok or not address then
		log("art box: CopyComponent " .. ART_BOX_FOOT .. " failed: " .. tostring(address))
		return nil
	end
	local copy = UIComponent(address)
	copy:SetInteractive(false)
	logged("art box: SetTextYOffset on " .. ART_BOX_FOOT, function()
		copy:SetTextYOffset(ART_FOOT_PAD[1], ART_FOOT_PAD[2])
	end)
	copy:SetVisible(false)
	return copy
end

--- Makes the art box's lock bar, hidden and set to the width of the box's text. Leaves `art_bar` nil when the game refuses any of it.
--- @param width number The width in pixels of the box's text.
local function make_art_bar(width)
	local bar = create_own(ART_BAR, ART_BAR_LAYOUT)
	if not bar then
		return
	end
	local parts = { root = bar }
	for _, name in ipairs({ ART_BAR_FRAME, ART_BAR_FILL, ART_BAR_FILLING, ART_BAR_DONE }) do
		parts[name] = find_named(bar, name)
		if not parts[name] then
			log("art box: no " .. name .. " in " .. ART_BAR_LAYOUT)
			return
		end
	end
	local ok, err = pcall(function()
		bar:SetInteractive(false)
		bar:SetCanResizeWidth(true)
		bar:Resize(width, ART_BAR_H)
		for _, name in ipairs({ ART_BAR_FRAME, ART_BAR_FILL, ART_BAR_FILLING, ART_BAR_DONE }) do
			parts[name]:SetCanResizeWidth(true)
		end
		parts[ART_BAR_FRAME]:Resize(width, ART_BAR_H)
		bar:PropagatePriority(ui_priority)
		bar:RegisterTopMost()
		topmost[ART_BAR] = true
		bar:SetVisible(false)
	end)
	log("art box: lock bar " .. (ok and ("made " .. width .. " wide") or ("failed: " .. tostring(err))))
	if ok then
		art_bar, art_bar_full = parts, width
	end
end

--- Fills the art box's lock bar from its middle out, as the game's tooltips do while they wait to lock.
--- @param progress number How full, from 0 to 1.
--- @param done boolean True once the box is locked.
local function fill_art_bar(progress, done)
	if not art_bar then
		return
	end
	local width = math.max(1, math.floor(art_bar_full * math.min(1, progress) + 0.5))
	if width == art_bar_width and done == art_bar_done then
		return
	end
	art_bar_width, art_bar_done = width, done
	logged("art box: lock bar fill", function()
		for _, name in ipairs({ ART_BAR_FILL, ART_BAR_FILLING, ART_BAR_DONE }) do
			art_bar[name]:Resize(width, ART_BAR_H)
		end
		art_bar[ART_BAR_FILLING]:SetVisible(not done)
		art_bar[ART_BAR_DONE]:SetVisible(done)
	end)
end

--- Makes a vanilla effect bundle tooltip in the art box, moves its effect list under the box and removes the rest, so the list sits below the
--- box's text. Read only of the game's data: the list only draws the bundle it is given later.
--- @param box UIC The art box.
--- @param bounds table|nil Bounds of the box's text, whose width the list takes.
--- @returns UIC|nil The effect list, or nil when it could not be made.
local function make_art_effect_list(box, bounds)
	local bundle = create_child(box, ART_BUNDLE, ART_BUNDLE_LAYOUT)
	local list = bundle and find_named(bundle, ART_EFFECT_LIST)
	if not list then
		log("art box: no " .. ART_EFFECT_LIST .. " in " .. ART_BUNDLE_LAYOUT)
		destroy_child(box, ART_BUNDLE, "it has no effect list")
		return nil
	end
	local ok, err = pcall(function()
		box:Adopt(list:Address())
		if bounds then
			local _, h = list:Dimensions()
			list:SetCanResizeWidth(true)
			list:Resize(bounds.w, h)
		end
	end)
	destroy_child(box, ART_BUNDLE, "its effect list was moved into the art box")
	log("art box: vanilla effect list " .. (ok and "moved in" or ("failed: " .. tostring(err))))
	return ok and list or nil
end

--- Makes the art box under the UI root, drawn over the character panel and left out of mouse hits so it never takes the hover from the card. Its
--- text is copied once for the foot under the vanilla effect list, then the lock bar goes last.
--- @returns UIC|nil The box, or nil when it could not be made.
local function make_art_box()
	local box = create_own(ART_BOX, ART_BOX_LAYOUT)
	if not box then
		return nil
	end
	box:SetInteractive(false)
	for _, name in ipairs({ ART_BOX_TITLE, ART_BOX_TEXT }) do
		local child = find_named(box, name)
		if not child then
			log("art box: no " .. name .. " in " .. ART_BOX_LAYOUT)
			return nil
		end
		child:SetInteractive(false)
	end
	local text = find_named(box, ART_BOX_TEXT)
	-- The layout centres its text, while the skill tooltips read from the left.
	logged("art box: left align", function()
		text:SetTextHAlign("left")
	end)
	local bounds = read_bounds(text)
	art_box_effects = make_art_effect_list(box, bounds)
	art_box_foot = make_art_foot(text)
	if not art_box_foot then
		return nil
	end
	box:PropagatePriority(ui_priority)
	box:RegisterTopMost()
	topmost[ART_BOX] = true
	box:SetVisible(false)
	-- Made after the box is drawn on top, so the bar draws over the box's frame.
	make_art_bar(bounds and bounds.w or 0)
	return box
end

--- Sets the art box's texts, and points the vanilla effect list at the art's bundle.
--- @param tip table What the box shows, from `art_card_tooltip` or `polymath_card_tooltip`.
local function fill_art_box(tip)
	find_named(art_box, ART_BOX_TITLE):SetStateText(tip.title, "")
	find_named(art_box, ART_BOX_TEXT):SetStateText(tip.text, "")
	if art_box_effects then
		logged("art box: effect list context " .. tip.bundle, function()
			art_box_effects:SetContextObject(cco("CcoEffectBundle", tip.bundle))
		end)
	end
	if tip.foot ~= "" then
		art_box_foot:SetStateText(tip.foot, "")
	end
	art_box_foot:SetVisible(tip.foot ~= "")
end

--- Shows the art box with an art card's text, just below the card or just above it when it would leave the screen.
--- @param card UIC The hovered art card.
--- @param skill string The card's skill key.
local function show_art_box(card, skill)
	if art_box == nil then
		art_box = make_art_box() or false
	end
	if not art_box then
		return
	end
	local tip = art_card_tips[skill]
	if art_box_text ~= tip.whole then
		art_box_text = tip.whole
		fill_art_box(tip)
	end
	if art_box_skill ~= skill then
		art_box_skill = skill
		art_box:SetVisible(true)
		if art_bar then
			art_bar.root:SetVisible(true)
		end
	end
	-- Placed on every look, as the box may only take its full height a frame after its text is set.
	local bounds, card_bounds = read_bounds(art_box), read_bounds(card)
	if not bounds or not card_bounds then
		return
	end
	local screen_w, screen_h = core:get_screen_resolution()
	local x = math.max(0, math.min(card_bounds.x, screen_w - bounds.w))
	local y = card_bounds.y + card_bounds.h + ART_BOX_GAP
	if y + bounds.h > screen_h then
		y = math.max(0, card_bounds.y - bounds.h - ART_BOX_GAP)
	end
	if x ~= bounds.x or y ~= bounds.y then
		log("art box: " .. skill .. " placed at " .. x .. "," .. y .. ", size " .. bounds.w .. "x" .. bounds.h)
		art_box:MoveTo(x, y)
	end
	local bar_bounds = art_bar and read_bounds(art_bar.root)
	if bar_bounds then
		local bar_x, bar_y = x + math.floor((bounds.w - art_bar_full) / 2), y + bounds.h - ART_BAR_LIFT
		if bar_x ~= bar_bounds.x or bar_y ~= bar_bounds.y then
			art_bar.root:MoveTo(bar_x, bar_y)
		end
	end
end

--- Sets whether the art box and its texts take the mouse, which they do only while the box is locked, so its effects' tooltips show then.
--- @param on boolean True to take the mouse.
local function set_art_box_interactive(on)
	art_box:SetInteractive(on)
	for _, name in ipairs({ ART_BOX_TITLE, ART_BOX_TEXT }) do
		find_named(art_box, name):SetInteractive(on)
	end
	art_box_foot:SetInteractive(on)
end

--- Hides the art box if it is shown, and unlocks it.
--- @param why string Why, for the log.
local function hide_art_box(why)
	if art_box and art_box_skill then
		log("art box: hid " .. art_box_skill .. " (" .. why .. ")")
		art_box:SetVisible(false)
		if art_bar then
			art_bar.root:SetVisible(false)
		end
		if art_box_locked then
			set_art_box_interactive(false)
		end
	end
	art_box_skill, art_box_locked, art_box_left = nil, false, nil
	art_bar_width, art_bar_done = nil, nil
end

--- Removes the art box and its lock bar if made, and forgets them, so the next hover makes them again.
--- @param why string Why, for the log.
local function remove_art_box(why)
	hide_art_box(why)
	if art_box then
		destroy_own(ART_BOX, why)
	end
	if art_bar then
		destroy_own(ART_BAR, why)
	end
	art_box, art_box_text, art_box_foot, art_bar, art_box_effects = nil, nil, nil, nil, nil
end

--- Whether the mouse is over the art box or anything in it.
--- @returns boolean True when it is.
local function mouse_over_art_box()
	local ok, over = pcall(function()
		return art_box:IsMouseOverChildren()
	end)
	if not ok then
		log("art box: IsMouseOverChildren failed: " .. tostring(over))
		return false
	end
	return over == true
end

--- Shows the art box in place of the vanilla tooltip while an art card is hovered. Like the game's tooltips, the box locks once the card has been
--- hovered for `ART_STICK_S`, and a locked box stays while the mouse is over it, closing `ART_REMOVAL_S` after the mouse leaves both. The
--- vanilla tooltip is hidden, as the game keeps undoing a see-through one while it fades it in. The game removes it when the card hover ends.
--- @param panel UIC The character panel.
local function update_art_box(panel)
	local tooltip = find_named(panel, SKILL_TOOLTIP)
	local card, skill = nil, nil
	if tooltip then
		-- The game builds the tooltip inside the hovered card, and the card's parent entry is named after the skill key.
		card = UIComponent(tooltip:Parent())
		skill = component_id(UIComponent(card:Parent()))
	end
	if skill and art_card_tips[skill] then
		if tooltip:Visible() then
			tooltip:SetVisible(false)
		end
		if art_box_skill ~= skill then
			hide_art_box("another art card hovered")
			art_box_since = os.clock()
		end
		art_box_left = nil
		show_art_box(card, skill)
		if art_box and not art_box_locked then
			local held = os.clock() - art_box_since
			fill_art_bar(held / ART_STICK_S, held >= ART_STICK_S)
			if held >= ART_STICK_S then
				art_box_locked = true
				set_art_box_interactive(true)
				log("art box: locked " .. skill)
			end
		end
		return
	end
	if tooltip then
		hide_art_box("another skill hovered")
		return
	end
	if not art_box_skill then
		return
	end
	if art_box_locked and mouse_over_art_box() then
		if art_box_left then
			log("art box: mouse on the locked box of " .. art_box_skill)
		end
		art_box_left = nil
		return
	end
	art_box_left = art_box_left or os.clock()
	if not art_box_locked or os.clock() - art_box_left >= ART_REMOVAL_S then
		hide_art_box(art_box_locked and "mouse left the locked box" or "vanilla tooltip gone")
	end
end

--- While the character panel shows the local Advisor, looks for a hovered art card every `ART_TOOLTIP_MS` and rebuilds the art cards' texts
--- every `ART_CARD_LOOKS` of those looks. Removes the art box once the panel closes.
--- @param looks number Looks made since the panel opened.
local function poll_art_cards(looks)
	if not panel_open then
		remove_art_box("the character panel closed")
		return
	end
	if button_cqi ~= nil and button_path == ROW_PATH then
		logged("art tooltip", function()
			local panel = find_named(ui_root(), PANEL)
			local character = cm:get_character_by_cqi(button_cqi)
			if panel and character then
				if looks % ART_CARD_LOOKS == 0 then
					update_art_card_tips(character)
				end
				update_art_box(panel)
			end
		end)
	end
	cm:real_callback(function()
		poll_art_cards(looks + 1)
	end, ART_TOOLTIP_MS, ART_TOOLTIP_NAME)
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
	local wanted = pair_rig(character, weapon, mount)
	if #worn == 1 and worn[1] == wanted then
		log("Mount box check cqi " .. cqi .. ": wears " .. wanted .. ", which is his saved pair, nothing to do")
		return
	end
	local trigger = RECONCILE_PREFIX .. cqi
	log("Mount box check cqi " .. cqi .. ": wears " .. (#worn > 0 and table.concat(worn, ", ") or "no rig") .. ", saved pair " .. tostring(wanted)
		.. ", sending " .. trigger)
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
--- Event helpers

--- Reads one of this script's UI triggers and checks it: it must name an Advisor of the faction that sent it.
--- @param context table The `UITrigger` event context.
--- @param prefix string The trigger's prefix, `TRIGGER_PREFIX` or `RECONCILE_PREFIX`.
--- @param pattern string Pattern for the rest of the trigger. Its first capture is the Advisor's cqi.
--- @param label string The trigger's name, for the log.
--- @returns CHARACTER_SCRIPT_INTERFACE|nil The Advisor, or nil when the trigger is refused.
--- @returns string|nil The pattern's second capture.
--- @returns string|nil The pattern's third capture.
local function read_trigger(context, prefix, pattern, label)
	local trigger = context:trigger()
	local cqi, first, second = string.match(string.sub(trigger, #prefix + 1), pattern)
	local character = cqi and cm:get_character_by_cqi(tonumber(cqi))
	if not character or not is_advisor(character) then
		log(label .. " " .. trigger .. " names no Advisor")
		return nil
	end
	if character:faction():command_queue_index() ~= context:faction_cqi() then
		log(label .. " " .. trigger .. " came from another faction (cqi " .. tostring(context:faction_cqi()) .. ")")
		return nil
	end
	return character, first, second
end

--- Whether a panel opening or closing is worth a log line: the character panel, the units panel, a panel that hides the button, or any panel
--- while the button is shown.
--- @param panel string The panel name.
--- @param hides boolean Whether it hides the button.
--- @returns boolean True when it is logged.
local function worth_logging(panel, hides)
	return panel == PANEL or panel == STRIP_PATH[1] or hides or button_cqi ~= nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_character_selected",
	"CharacterSelected",
	true,
	function(context)
		selected_cqi = context:character():command_queue_index()
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
			-- The panel opens twice in a row, so any running look is stopped first to keep a single one.
			cm:remove_real_callback(ART_TOOLTIP_NAME)
			art_card_tips = {}
			remove_art_box("the character panel opened")
			poll_art_cards(0)
		end
		local hides = hides_on_open(panel)
		if worth_logging(panel, hides) then
			log("PanelOpenedCampaign " .. panel .. (hides and ", hides the button" or ", keeps the button"))
		end
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
		if worth_logging(panel, false) then
			log("PanelClosedCampaign " .. panel)
		end
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
				guarded("reselect", function()
					reselect(cqi)
				end)
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
		local character, weapon, mount = read_trigger(context, TRIGGER_PREFIX, "^(%d+):([^:]+):([^:]+)$", "loadout trigger")
		if not character then
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
		return is_advisor(context:character()) and rig_data().rigs[tostring(context:ancillary())] ~= nil
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
		-- Cheap checks first, so most clicks never walk the parents: the panel must show the local Advisor, which shows the button in its row.
		return panel_open and button_cqi ~= nil and button_path == ROW_PATH
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
		local character = read_trigger(context, RECONCILE_PREFIX, "^(%d+)$", "reconcile trigger")
		if not character then
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
		return is_advisor(context:character())
	end,
	function(context)
		local character = context:character()
		local skill = context:skill_point_spent_on()
		local unlocked = skill_items()[skill]
		-- Any skill may change how many disciplines the Polymath counts.
		local changed = sync_polymath(character)
		if not unlocked then
			-- An art slot skill puts on his held weapon's art, and an upgrade skill (an apex form) swaps his rig, both at once.
			changed = sync_arts(character, current_pair(character)) or changed
			changed = reconcile(character, "skill " .. skill) or changed
			if changed then
				refresh_stats(character)
				if is_local_advisor(character) then
					reselect(character:command_queue_index())
				end
			end
			return
		end
		local cqi = character:command_queue_index()
		log("cqi " .. cqi .. " unlocked " .. unlocked.kind .. " " .. unlocked.key .. ", unlocked weapons: "
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
	TAG .. "_rank_up",
	"CharacterRankUp",
	function(context)
		return is_advisor(context:character())
	end,
	function(context)
		local character = context:character()
		if grant_by_rank(character) then
			reconcile(character, "rank up")
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
		reconcile_faction(context:faction(), "turn start of " .. context:faction():name())
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

--- Helpers the spawn and quest scripts share. They read them when they run, since script load order is not promised.
ADVISOR_OVERHAUL = {
	--- Whether a character is an Advisor.
	is_advisor = is_advisor,
	--- Lists the Advisors of a faction.
	faction_advisors = faction_advisors,
	--- The weapon and mount an Advisor uses now.
	current_pair = current_pair,
}

cm:add_first_tick_callback(function()
	-- advisor_overhaul_spawn.lua spawns the Advisors on the first tick of a new campaign, so this waits until they exist.
	cm:callback(function()
		apply_all("first tick")
	end, 2)
end)
