--- Advisor Overhaul skill tree zones: groups of skills spanning two rows of the Advisor's tree, each headed by a label column.
---
--- The zones come from `ADVISOR_OVERHAUL_RIGS.zones`, which generators/advisor_overhaul.py writes from the registry. A zone's cards run top to
--- bottom, then left to right: the data puts them in its two rows by turns. While the character panel is open, this script checks the tree's rows.
--- Where a zone's cards are shown (only the Advisor has them), it heads the zone with a label two rows tall in the top row
--- (`ui/templates/advisor_overhaul_zone_label`) and a blank of the same width in the bottom row. It pads the shorter row of each zone with blanks the
--- size of a card, so both rows line up at every zone's edge. Blanks are see-through components, since a hidden skill node takes no space. The check
--- repeats, so a row the game builds again is put back in order. The script only changes or destroys components it made, found by their names.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settings

--- Prefix of every log line, component name and callback name.
local TAG = "advisor_overhaul_zones"

--- Path from the UI root to the skill tree's rows. Row N is `chainN`, and its cards are in its `chain` list.
local TREE_PATH = { "character_details_panel", "character_context_parent", "tab_panels", "skills_subpanel", "character_details_panel_skills", "listview",
	"list_clip", "list_box" }

--- Layout file of the labels (a frame, a title and a smaller description), and of the see-through blanks.
local LABEL_TEMPLATE = "ui/templates/advisor_overhaul_zone_label"
local BLANK_TEMPLATE = "ui/templates/parchment_divider_title"

--- Whether labels show their zone's description under the title. Off: the title alone, centred.
local SHOW_DESCRIPTIONS = false

--- How much shorter than two rows a label is, and the description's margin on each side.
local LABEL_GAP = 4
local TEXT_MARGIN = 12

--- How often the open panel is checked, in milliseconds.
local CHECK_MS = 500

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one log line to script_log.
--- @param text string The message.
local function log(text)
	out(TAG .. ": " .. text)
end

--- A loc text, or its fallback when the key does not resolve.
--- @param key string The loc key.
--- @param fallback string The English text.
--- @returns string The text.
local function text_of(key, fallback)
	local text = common.get_localised_string(key)
	if not text or text == "" then
		return fallback
	end
	return text
end

--- The names of a component's direct children, in order.
--- @param uic UIC The component.
--- @returns table The names.
local function child_names(uic)
	local names = {}
	for i = 0, uic:ChildCount() - 1 do
		table.insert(names, UIComponent(uic:Find(i)):Id())
	end
	return names
end

--- A named direct child, or nil.
--- @param uic UIC The parent.
--- @param name string The child's name.
--- @returns UIC|nil The child.
local function child(uic, name)
	for i = 0, uic:ChildCount() - 1 do
		local c = UIComponent(uic:Find(i))
		if c:Id() == name then
			return c
		end
	end
	return nil
end

--- Makes a component in a row at the end of its list, at the given size, unless it is there already.
--- @param row UIC The row's card list.
--- @param name string The component's name.
--- @param template string The layout file.
--- @param w number Its width.
--- @param h number Its height.
--- @returns UIC|nil The new component, or nil when it was there already.
local function make(row, name, template, w, h)
	if child(row, name) then
		return nil
	end
	local uic = UIComponent(row:CreateComponent(name, template))
	uic:SetCanResizeWidth(true)
	uic:SetCanResizeHeight(true)
	uic:Resize(w, h)
	return uic
end

--- Makes a see-through blank in a row, the size of what it stands in for, unless it is there already.
--- @param row UIC The row's card list.
--- @param name string The component's name.
--- @param w number Its width.
--- @param h number Its height.
local function make_blank(row, name, w, h)
	local uic = make(row, name, BLANK_TEMPLATE, w, h)
	if uic then
		uic:SetStateText("")
		uic:PropagateOpacity(0, true)
		uic:SetInteractive(false)
	end
end

--- Makes a zone label, unless it is there already: its title in yellow, centred, or in the top half with the description in a smaller font below
--- (`SHOW_DESCRIPTIONS`).
--- @param row UIC The row's card list.
--- @param name string The component's name.
--- @param zone table The `ADVISOR_OVERHAUL_RIGS.zones` entry.
--- @param w number Its width.
--- @param h number Its height.
local function make_label(row, name, zone, w, h)
	local uic = make(row, name, LABEL_TEMPLATE, w, h)
	if not uic then
		return
	end
	uic:SetStateText("[[col:yellow]]" .. text_of(zone.title, zone.title_fallback) .. "[[/col]]")
	local description = find_uicomponent(uic, "description")
	if not description then
		log(name .. " has no description part")
	elseif SHOW_DESCRIPTIONS then
		-- Bottom padding of half the label lifts the centred title into the top half.
		uic:SetTextYOffset(0, math.floor(h / 2))
		description:SetCanResizeWidth(true)
		description:SetCanResizeHeight(true)
		description:Resize(w - TEXT_MARGIN * 2, math.floor(h / 2))
		description:SetStateText(text_of(zone.description, zone.description_fallback))
	else
		description:SetVisible(false)
	end
end

--- Puts a row's children in the given order, each moved to its place in turn, when they are not in it already.
--- @param row UIC The row's card list.
--- @param order table Child names, first to last.
--- @returns boolean True when the row was rearranged.
local function arrange(row, order)
	local now = child_names(row)
	local same = #now >= #order
	for i, name in ipairs(order) do
		same = same and now[i] == name
	end
	if same then
		return false
	end
	for i, name in ipairs(order) do
		local uic = child(row, name)
		if uic then
			row:Divorce(uic:Address())
			row:Adopt(uic:Address(), i - 1)
		end
	end
	return true
end

--- Destroys this script's labels and blanks in a row, for when the panel moves on to a tree that is not his.
--- @param row UIC The row's card list.
local function clear(row)
	local removed = 0
	for _, name in ipairs(child_names(row)) do
		if name:sub(1, #TAG) == TAG then
			local uic = child(row, name)
			if uic then
				uic:Destroy()
				removed = removed + 1
			end
		end
	end
	if removed > 0 then
		log("removed " .. removed .. " zone parts from a tree that is not his")
	end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Zones

--- Lays out the zones of one pair of rows: labels, blanks, the zones' cards, then any other card of the rows in its own order.
--- @param tree UIC The skill tree's row list.
--- @param top_index number The top row.
--- @param bottom_index number The bottom row.
local function lay_out(tree, top_index, bottom_index)
	local top = find_uicomponent(tree, "chain" .. top_index, "chain")
	local bottom = find_uicomponent(tree, "chain" .. bottom_index, "chain")
	if not top or not bottom then
		return
	end
	local zones = {}
	for i, zone in ipairs(ADVISOR_OVERHAUL_RIGS.zones or {}) do
		if zone.top == top_index and zone.bottom == bottom_index then
			table.insert(zones, { index = i, zone = zone })
		end
	end
	-- A card of the first zone sizes every part. Its absence means the panel shows someone else's tree, which keeps none of ours.
	local sample = zones[1] and (child(top, zones[1].zone.cards[1]) or child(bottom, zones[1].zone.cards[1]))
	if not sample then
		clear(top)
		clear(bottom)
		return
	end
	local card_w, card_h = sample:Dimensions()
	local orders, placed = { top = {}, bottom = {} }, {}
	for _, entry in ipairs(zones) do
		local i, zone = entry.index, entry.zone
		local label, label_blank = TAG .. "_label_" .. i, TAG .. "_label_blank_" .. i
		make_label(top, label, zone, card_w, card_h * 2 - LABEL_GAP)
		make_blank(bottom, label_blank, card_w, card_h)
		table.insert(orders.top, label)
		table.insert(orders.bottom, label_blank)
		local counts = { top = 0, bottom = 0 }
		for _, card in ipairs(zone.cards) do
			local side = child(top, card) and "top" or child(bottom, card) and "bottom"
			if side then
				table.insert(orders[side], card)
				counts[side] = counts[side] + 1
				placed[card] = true
			end
		end
		-- The shorter row is padded to the longer one, so the next zone starts in the same place on both.
		for side, row in pairs({ top = top, bottom = bottom }) do
			local other = side == "top" and "bottom" or "top"
			for n = 1, counts[other] - counts[side] do
				local name = TAG .. "_pad_" .. i .. "_" .. side .. "_" .. n
				make_blank(row, name, card_w, card_h)
				table.insert(orders[side], name)
			end
		end
	end
	-- Cards in no zone keep their place after the zones.
	for side, row in pairs({ top = top, bottom = bottom }) do
		for _, name in ipairs(child_names(row)) do
			if not placed[name] and name:sub(1, #TAG) ~= TAG then
				table.insert(orders[side], name)
			end
		end
	end
	local moved_top, moved_bottom = arrange(top, orders.top), arrange(bottom, orders.bottom)
	if moved_top or moved_bottom then
		log("rows " .. top_index .. " and " .. bottom_index .. " laid out in " .. #zones .. " zones, card " .. card_w .. "x" .. card_h .. ", top: "
			.. table.concat(orders.top, ", ") .. " | bottom: " .. table.concat(orders.bottom, ", "))
	end
end

--- Lays out every pair of rows that has zones, in the open character panel.
local function check()
	local tree = find_uicomponent(core:get_ui_root(), unpack(TREE_PATH))
	if not tree then
		return
	end
	local pairs_done = {}
	for _, zone in ipairs(ADVISOR_OVERHAUL_RIGS.zones or {}) do
		local key = zone.top .. "|" .. zone.bottom
		if not pairs_done[key] then
			pairs_done[key] = true
			lay_out(tree, zone.top, zone.bottom)
		end
	end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners

core:add_listener(
	TAG .. "_opened",
	"PanelOpenedCampaign",
	function(context) return context.string == "character_details_panel" end,
	function()
		cm:remove_real_callback(TAG)
		cm:repeat_real_callback(function()
			local ok, err = pcall(check)
			if not ok then
				log("check failed: " .. tostring(err))
			end
		end, CHECK_MS, TAG)
	end,
	true
)

core:add_listener(
	TAG .. "_closed",
	"PanelClosedCampaign",
	function(context) return context.string == "character_details_panel" end,
	function()
		cm:remove_real_callback(TAG)
	end,
	true
)
