local _, ns = ...

-- Built on first open, so the window costs nothing until it's used.
-- The right column is wider: lure and bait rows carry bag count and Keep columns.
-- The left column's Phial and Tea rows use a narrower version of the same row.
local LEFT_W, RIGHT_W, ROW_H = 360, 400, 22
local ROW_W = RIGHT_W - 10
local W, H = LEFT_W + RIGHT_W + 60, 686
local LEFT_X, RIGHT_X = 20 + LEFT_W / 2, 40 + LEFT_W + RIGHT_W / 2 -- column centers
local DIVIDER_X = 30 + LEFT_W

-- Right edges of the fixed row columns, measured in from the row's right side.
local COL_STATE, COL_KEEP, COL_HAVE = 24, 134, 170
local STATE_W, KEEP_W, HAVE_W = 100, 30, 30
-- Row geometry per column: center, width, and the right-edge offsets above.
-- Left-column rows have no X button, so their status sits at the edge.
local RIGHT_GEO = { cx = RIGHT_X, w = ROW_W, state = COL_STATE, stateW = STATE_W, keep = COL_KEEP, have = COL_HAVE }
local LEFT_GEO = { cx = LEFT_X, w = LEFT_W - 10, state = 2, stateW = 84, keep = 92, have = 128 }
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local frame, keyButton, capturing
local refreshers = {}
local selectors, lists = {}, {}
local oversizedStack, oversizedState, nextText, sleepButton

local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------

local function Font(parent, text, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetText(text)
	return fs
end

local function Width(o)
	if type(o) == "number" then return o end
	return (o.GetStringWidth and o:GetStringWidth()) or o:GetWidth()
end

-- Lays widgets out left to right, centered on cx at row-center y.
-- A number in the list is extra space.
local function HStack(cx, y, gap, ...)
	local n, total = select("#", ...), 0
	for i = 1, n do total = total + Width((select(i, ...))) + (i > 1 and gap or 0) end
	local x = cx - total / 2
	for i = 1, n do
		local o = select(i, ...)
		if type(o) ~= "number" then
			o:ClearAllPoints()
			o:SetPoint("LEFT", frame, "TOPLEFT", x, y)
		end
		x = x + Width(o) + gap
	end
end

local function Line(x1, x2, y)
	local t = frame:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(1, 1, 1, 0.15)
	t:SetHeight(1)
	t:SetPoint("LEFT", frame, "TOPLEFT", x1, y)
	t:SetPoint("RIGHT", frame, "TOPLEFT", x2, y)
end

-- Gold section title with a rule on each side, centered in its column.
local function Header(text, cx, y)
	local fs = Font(frame, text, "GameFontNormal")
	fs:SetPoint("CENTER", frame, "TOPLEFT", cx, y)
	local half = (cx == LEFT_X and LEFT_W or RIGHT_W) / 2
	local tw = fs:GetStringWidth() / 2 + 8
	Line(cx - half, cx - tw, y)
	Line(cx + tw, cx + half, y)
end

local function NumberBox(parent, width, getter, setter, minV, maxV)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width, 20)
	eb:SetAutoFocus(false)
	eb:SetNumeric(true)
	eb:SetMaxLetters(3)
	eb:SetJustifyH("CENTER")
	local function Commit(self)
		local n = tonumber(self:GetText())
		if n then setter(math.max(minV, math.min(maxV, n))) end
		self:SetText(tostring(getter() or ""))
		self:ClearFocus()
	end
	eb:SetScript("OnEnterPressed", Commit)
	eb:SetScript("OnEditFocusLost", Commit)
	eb:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(getter() or ""))
		self:ClearFocus()
	end)
	eb.Refresh = function()
		if not eb:HasFocus() then eb:SetText(tostring(getter() or "")) end
	end
	return eb
end

-- Lets clicks on a checkbox's label toggle it too.
local function ExtendHitRect(button, label)
	button:SetHitRectInsets(0, -(label:GetStringWidth() + 6), 0, 0)
end

local function Report(ok, msg)
	if msg then ns.Print(msg) end
	return ok
end

local function ItemFromCursor()
	local kind, id = GetCursorInfo()
	if kind == "item" or kind == "toy" then
		ClearCursor()
		return id
	end
end

-- group = the fish buff, "phial" or "tea" the item belongs to, if any.
local function ItemTooltip(owner, e, emptyText, group)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if not e then
		GameTooltip:SetText(emptyText)
		GameTooltip:Show()
		return
	end
	GameTooltip:SetItemByID(e.item)
	if group == "tea" then
		GameTooltip:AddLine("Tracks Buff: " .. ns.RELAXED .. " (drink for " .. ns.TEA_SECONDS .. " seconds)", 0.6, 0.8, 1)
	elseif e.aura then
		GameTooltip:AddLine("Tracks Buff: " .. (C_Spell.GetSpellName(e.aura) or e.aura), 0.6, 0.8, 1)
	end
	if e.keep then
		GameTooltip:AddLine(("Keeps at least %d in your bags."):format(e.keep), 1, 0.82, 0)
	end
	if e.noBuff then
		GameTooltip:AddLine("This item gave no buff the addon can track, so it's skipped.", 1, 0.33, 0.33, true)
		local label = group and (ns.FISH_LABELS[group] or ns.SUPPLY_LABELS[group])
		GameTooltip:AddLine(label and ("Drag it onto the " .. label .. " name again to retry.")
			or "Remove and re-add it to try again.", 0.7, 0.7, 0.7)
	end
	local wait = ns.BackoffLeft(e.item)
	if wait then
		GameTooltip:AddLine(("This didn't work the last two times it was tried, so it's skipped for %ds."):format(math.ceil(wait)),
			1, 0.82, 0, true)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Key capture
---------------------------------------------------------------------------

-- The key handler exists only while capturing. Assigning an OnKeyDown script
-- turns keyboard input on for the frame, and a frame with keyboard input
-- swallows every key, movement included, for as long as it's shown.
local function StopCapture()
	capturing = false
	keyButton:SetScript("OnKeyDown", nil)
	keyButton:EnableKeyboard(false)
	ns.RefreshUI()
end

local function Bind(key)
	Report(ns.SetKey(key))
	StopCapture()
end

local function OnKeyDown(_, key)
	if MODIFIERS[key] then return end
	if key == "ESCAPE" then return StopCapture() end
	Bind((IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key)
end

local function StartCapture()
	if InCombatLockdown() then
		ns.Print("Key bindings can't be changed in combat.")
		return
	end
	capturing = true
	keyButton:SetText("Press a Key...")
	keyButton:SetScript("OnKeyDown", OnKeyDown)
	keyButton:EnableKeyboard(true)
	keyButton:SetPropagateKeyboardInput(false)
end

local function OnKeyButtonClick(_, button)
	if not capturing then return StartCapture() end
	if MOUSE_KEYS[button] then return Bind(MOUSE_KEYS[button]) end
	StopCapture() -- left or right click while capturing cancels
end

---------------------------------------------------------------------------
-- Single-item selectors (Raft, Bobber)
---------------------------------------------------------------------------

local function Selector(slotKey, cx, y, emptyHint)
	local s = { key = slotKey }

	s.slot = CreateFrame("Button", nil, frame)
	s.slot:SetSize(32, 32)
	s.slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function Drop()
		local id = ItemFromCursor()
		if id then Report(ns.SetSlot(slotKey, id)) end
	end
	s.slot:SetScript("OnReceiveDrag", Drop)
	s.slot:SetScript("OnClick", Drop)
	s.slot:SetScript("OnEnter", function(self) ItemTooltip(self, ns.db[slotKey], emptyHint) end)
	s.slot:SetScript("OnLeave", GameTooltip_Hide)

	s.block = CreateFrame("Frame", nil, frame)
	s.block:SetSize(160, 32)
	s.name = Font(s.block, "", "GameFontHighlight")
	s.name:SetPoint("TOPLEFT", 0, -2)
	s.name:SetWidth(160)
	s.name:SetJustifyH("LEFT")
	s.name:SetWordWrap(false)
	s.state = Font(s.block, "")
	s.state:SetPoint("BOTTOMLEFT", 0, 3)

	s.clear = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	s.clear:SetSize(22, 22)
	s.clear:SetScript("OnClick", function() ns.SetSlot(slotKey, nil) end)

	HStack(cx, y, 8, s.slot, s.block, s.clear)
	selectors[#selectors + 1] = s
end

local function RefreshSelector(s)
	local e = ns.db[s.key]
	if e then
		s.slot:SetNormalTexture(C_Item.GetItemIconByID(e.item) or EMPTY_SLOT)
		s.name:SetText(ns.ItemLabel(e.item))
		local txt, color = ns.EntryState(e, s.key)
		s.state:SetText(color .. txt .. "|r")
		s.clear:Show()
	else
		s.slot:SetNormalTexture(EMPTY_SLOT)
		s.name:SetText("|cff808080None Selected|r")
		s.state:SetText("|cff808080Drag a Toy Here|r")
		s.clear:Hide()
	end
end

---------------------------------------------------------------------------
-- Lists (Lures, Fish Buffs, Other Baits)
---------------------------------------------------------------------------

local ROW_LEFT, ROW_RIGHT = RIGHT_X - ROW_W / 2, RIGHT_X + ROW_W / 2
local LEFT_ROW_LEFT = LEFT_GEO.cx - LEFT_GEO.w / 2
local ACTIVE_MARK = "Interface\\ChatFrame\\ChatFrameExpandArrow"

-- Small tooltip for a widget that isn't an item.
local function HintTooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- Row layout, left to right: [on/off] [priority arrow] icon [active marker] name;
-- right to left: [X], status, Keep box, bag count.
-- opts: toggle, arrow, remove, fish (= buff kind), supply ("phial" or "tea"),
-- ownBuff (row shows its own buff time), geo (column geometry, default right).
local function CreateRow(list, i, y, opts)
	local geo = opts.geo or RIGHT_GEO
	local row = CreateFrame("Button", nil, frame)
	row.list, row.fish, row.supply, row.ownBuff = list, opts.fish, opts.supply, opts.ownBuff
	row:SetSize(geo.w, ROW_H - 2)
	row:SetPoint("CENTER", frame, "TOPLEFT", geo.cx, y)
	row:SetScript("OnEnter", function(self) ItemTooltip(self, self.entry, nil, self.fish or self.supply) end)
	row:SetScript("OnLeave", GameTooltip_Hide)

	local left = 2
	if opts.toggle then
		row.toggle = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.toggle:SetSize(20, 20)
		row.toggle:SetPoint("LEFT", 0, 0)
		row.toggle:SetScript("OnClick", function(self)
			if row.entry then ns.SetFishEnabled(row.entry, self:GetChecked()) end
		end)
		if opts.fish then
			HintTooltip(row.toggle, "Use This Fish",
				"Untick to never throw this one back. Rare fish start unticked so they aren't wasted.")
		elseif opts.supply then
			HintTooltip(row.toggle, "Use This Item", "Untick to keep it listed but never use it.")
		else
			HintTooltip(row.toggle, "Use This Item",
				"Untick to keep it listed but never use it. The X removes it until you log out or press Scan Inventory.")
		end
		left = 22
	end
	if opts.arrow then
		row.up = CreateFrame("Button", nil, row)
		row.up:SetSize(18, 18)
		row.up:SetPoint("LEFT", left - 2, 0)
		row.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
		row.up:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down")
		row.up:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")
		row.up:SetScript("OnClick", function()
			local group = row.fish or row.supply
			if group then ns.MoveFish(group, row.entry, -1) else ns.MoveItem(list, row.index, -1) end
		end)
		left = left + 20
	end

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", left, 0)

	row.marker = row:CreateTexture(nil, "ARTWORK")
	row.marker:SetSize(12, 12)
	row.marker:SetTexture(ACTIVE_MARK)
	row.marker:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)

	if opts.remove then
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.remove:SetSize(20, 20)
		row.remove:SetPoint("RIGHT")
		row.remove:SetScript("OnClick", function() ns.RemoveItem(list, row.index) end)
	end

	row.state = Font(row, "")
	row.state:SetWidth(geo.stateW)
	row.state:SetJustifyH("RIGHT")
	row.state:SetWordWrap(false)
	row.state:SetPoint("RIGHT", -geo.state, 0)

	row.keepBox = NumberBox(row, KEEP_W,
		function() return row.entry and (row.entry.keep or 0) or "" end,
		function(n) if row.entry then ns.SetKeep(row.entry, n) end end, 0, 999)
	row.keepBox:SetPoint("RIGHT", -geo.keep, 0)
	HintTooltip(row.keepBox, "Keep",
		"Stop using this item once you have this many or fewer in your bags. 0 uses them all.")

	row.have = Font(row, "", "GameFontHighlightSmall")
	row.have:SetWidth(HAVE_W)
	row.have:SetJustifyH("RIGHT")
	row.have:SetPoint("RIGHT", -geo.have, 0)

	row.name = Font(row, "", "GameFontHighlightSmall")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	return row
end

-- active = the entry giving the group's buff right now (gets the marker).
local function FillRow(row, e, i, active)
	row.entry, row.index = e, i
	if not e then return row:Hide() end
	row.icon:SetTexture(C_Item.GetItemIconByID(e.item))

	local isActive = e == active
	local off = row.toggle and e.enabled == false
	local color = off and "|cff808080" or (isActive and "|cff40ff40") or ""
	row.name:SetText(color .. ns.ItemLabel(e.item) .. (color ~= "" and "|r" or ""))
	row.marker:SetShown(isActive)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", isActive and row.marker or row.icon, "RIGHT", isActive and 2 or 6, 0)
	row.name:SetPoint("RIGHT", row.have, "LEFT", -6, 0)
	if row.toggle then row.toggle:SetChecked(e.enabled ~= false) end

	-- Lures and fish share one buff per group, shown once on the group line,
	-- so their rows only speak up about problems. Baits each have their own buff.
	local txt, c
	if row.ownBuff then
		txt, c = ns.EntryState(e, row.list)
	else
		txt, c = ns.RowProblem(e)
	end
	row.state:SetText(txt and (c .. txt .. "|r") or "")

	-- Bag count: grey when empty, yellow at or below Keep, white otherwise.
	local count = ns.BagCount(e)
	if count then
		local shown = count > 999 and "999+" or tostring(count)
		local cc = count == 0 and "|cff808080" or (e.keep and count <= e.keep and "|cffffd200") or "|cffffffff"
		row.have:SetText(cc .. shown .. "|r")
		row.keepBox:Show()
		row.keepBox.Refresh()
	else
		row.have:SetText("|cff808080Toy|r") -- toys have no stack to count or keep
		row.keepBox:Hide()
	end

	if row.up then
		row.up:SetShown(not row.fish or ns.db.fish[row.fish].mode == "manual") -- auto order has no arrows
		row.up:SetEnabled(i > 1)
	end
	row:Show()
end

-- Gray "Have" and "Keep" labels, placed directly above a list's first row.
local function ColumnLabels(y, geo)
	geo = geo or RIGHT_GEO
	local right = geo.cx + geo.w / 2
	local have = Font(frame, "Have", "GameFontDisableSmall")
	have:SetPoint("CENTER", frame, "TOPLEFT", right - geo.have - HAVE_W / 2, y)
	local keep = Font(frame, "Keep", "GameFontDisableSmall")
	keep:SetPoint("CENTER", frame, "TOPLEFT", right - geo.keep - KEEP_W / 2, y)
	return { have, keep }
end

local function DropRow(list, y, text, tip)
	local slot = CreateFrame("Button", nil, frame)
	slot:SetSize(24, 24)
	slot:SetNormalTexture(EMPTY_SLOT)
	slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	HintTooltip(slot, text, tip)
	local function Drop()
		local id = ItemFromCursor()
		if id then Report(ns.AddItem(list, id)) end
	end
	slot:SetScript("OnReceiveDrag", Drop)
	slot:SetScript("OnClick", Drop)
	HStack(RIGHT_X, y, 6, slot, Font(frame, text, "GameFontDisableSmall"))
end

-- A drag-and-drop list (Lures, Other Baits): header, [buff status] and column labels
-- on one line, rows, then a drop slot. Labels and status hide when the list is empty.
local function ListSection(list, title, max, y, opts)
	Header(title, RIGHT_X, y)
	local l = { key = list, rows = {}, statusGroup = opts.statusGroup }
	l.labels = ColumnLabels(y - 18)
	if opts.statusGroup then
		l.status = Font(frame, "", "GameFontHighlightSmall")
		l.status:SetPoint("LEFT", frame, "TOPLEFT", ROW_LEFT + 2, y - 18)
	end
	local rowsY = y - 34
	for i = 1, max do
		l.rows[i] = CreateRow(list, i, rowsY - (i - 1) * ROW_H,
			{ toggle = true, arrow = opts.arrow, remove = true, ownBuff = not opts.statusGroup })
	end
	l.empty = Font(frame, "Nothing added yet.", "GameFontDisableSmall")
	l.empty:SetPoint("CENTER", frame, "TOPLEFT", RIGHT_X, rowsY)
	DropRow(list, rowsY - max * ROW_H - 6, opts.dropText, opts.dropTip)
	lists[#lists + 1] = l
end

StaticPopupDialogs.SIMPLYFISHING_RESET = {
	text = "Reset all Simply Fishing settings to their defaults?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.Reset()
		ns.Print("Settings have been reset.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- A checkbox bound to a db option, with a clickable label and an optional tooltip.
local function Check(label, key, tip)
	local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetScript("OnClick", function(self) ns.SetOption(key, self:GetChecked() and true or false) end)
	local fs = Font(frame, label, "GameFontHighlight")
	ExtendHitRect(cb, fs)
	if tip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	refreshers[#refreshers + 1] = function() cb:SetChecked(ns.db[key]) end
	return cb, fs
end

local function BuildCasting()
	Header("Casting", LEFT_X, -36)

	-- Mode
	local function Radio(label, value)
		local rb = CreateFrame("CheckButton", nil, frame, "UIRadioButtonTemplate")
		rb:SetSize(16, 16)
		local fs = Font(frame, label, "GameFontHighlight")
		ExtendHitRect(rb, fs)
		rb:SetScript("OnClick", function() ns.SetOption("mode", value) end)
		refreshers[#refreshers + 1] = function() rb:SetChecked(ns.db.mode == value) end
		return rb, fs
	end
	local castRb, castFs = Radio("Cast Only", "cast")
	local reelRb, reelFs = Radio("Cast and Reel", "reel")
	HStack(LEFT_X, -62, 4, castRb, castFs, 16, reelRb, reelFs)

	-- Keybind
	local keyLabel = Font(frame, "Keybind", "GameFontHighlight")
	keyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	keyButton:SetSize(120, 22)
	keyButton:RegisterForClicks("AnyUp")
	keyButton:SetScript("OnClick", OnKeyButtonClick)
	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetSize(56, 22)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function() Report(ns.SetKey(nil)) end)
	HStack(LEFT_X, -92, 6, keyLabel, keyButton, clear)

	local lootCb, lootFs = Check("Auto Loot", "autoLoot",
		"Loots your catch automatically while fishing, then puts your normal setting back.")
	local mountCb, mountFs = Check("Dismount", "dismount",
		"On a ground mount, the key dismounts you first. It never dismounts you in the air.")
	HStack(LEFT_X, -120, 4, lootCb, lootFs, 18, mountCb, mountFs)
end

local function BuildSound()
	Header("Sound", LEFT_X, -156)

	local sfxCb, sfxFs = Check("Sound Effects at 100%", "audio",
		"Raises sound effects to full volume so the bobber splash is easy to hear.")
	HStack(LEFT_X, -182, 4, sfxCb, sfxFs)

	local muteCb, muteFs = Check("Mute Music and Ambience", "muteMusic",
		"Makes the bobber splash easier to hear.")
	HStack(LEFT_X, -208, 4, muteCb, muteFs)

	local bgCb, bgFs = Check("Keep Sound When Alt-Tabbed", "bgSound",
		"Lets you hear the splash while another window is in front.")
	HStack(LEFT_X, -234, 4, bgCb, bgFs)
end

local function BuildBobberAndRaft()
	Header("Raft", LEFT_X, -270)
	Selector("raft", LEFT_X, -304, "Drop a raft toy here. It is used when you're swimming.")

	Header("Bobber", LEFT_X, -346)
	Selector("bobber", LEFT_X, -380, "Drop a bobber toy here to keep it active.")

	local cb, label = Check("Use Oversized Bobber", "oversized")
	oversizedState = Font(frame, "")
	oversizedStack = function() HStack(LEFT_X, -420, 4, cb, label, 4, oversizedState) end
end

-- One fish buff group: [on] Name, its status, and the order button on one line,
-- column labels right above its rows. Drop a fish on the name to add it.
local fishEmpty -- "Nothing added yet." for the whole Fish Buffs section

local function FishGroup(kind, y)
	local label = ns.FISH_LABELS[kind]
	local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("LEFT", frame, "TOPLEFT", ROW_LEFT - 2, y)
	local name = Font(frame, label, "GameFontNormal")
	name:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	ExtendHitRect(cb, name)
	local function Drop()
		local id = ItemFromCursor()
		if id then Report(ns.AddFish(kind, id)) end
		return id
	end
	cb:SetScript("OnReceiveDrag", Drop)
	cb:SetScript("OnClick", function(self)
		if Drop() then
			self:SetChecked(ns.db.fish[kind].on) -- a drop, not a toggle
		else
			ns.SetFishOption(kind, "on", self:GetChecked() and true or false)
		end
	end)
	HintTooltip(cb, "Keep " .. label .. " Up",
		"Throws back one fish from the list below whenever the buff is missing or about to run out. "
		.. "Drag a fish onto this name to add one the bag scan didn't recognize.")

	local status = Font(frame, "", "GameFontHighlightSmall")
	status:SetPoint("LEFT", frame, "TOPLEFT", ROW_LEFT + 136, y)

	local order = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	order:SetSize(104, 22)
	order:SetPoint("RIGHT", frame, "TOPLEFT", ROW_RIGHT, y)
	order:SetScript("OnClick", function()
		ns.SetFishMode(kind, ns.db.fish[kind].mode == "auto" and "manual" or "auto")
	end)
	HintTooltip(order, "Order",
		"Automatic: uses the fish you have the most to spare (above its Keep) first, re-sorting as your counts change. New fish are turned on automatically.\n\n"
		.. "Manual Order: uses your order, set with the arrows. New fish are listed but start turned off.\n\n"
		.. "Rare fish always start turned off.")
	refreshers[#refreshers + 1] = function()
		local g = ns.db.fish[kind]
		cb:SetChecked(g.on)
		order:SetText(g.mode == "auto" and "Automatic" or "Manual Order")
	end

	local l = { key = kind, fish = kind, statusGroup = kind, status = status, rows = {},
		line = { cb, name, status, order } }
	l.labels = ColumnLabels(y - 18)
	local rowsY = y - 34
	for i = 1, ns.MAX_FISH_ROWS do
		l.rows[i] = CreateRow(kind, i, rowsY - (i - 1) * ROW_H, { toggle = true, arrow = true, fish = kind })
	end
	l.empty = Font(frame, "Nothing added yet.", "GameFontDisableSmall")
	l.empty:SetPoint("CENTER", frame, "TOPLEFT", RIGHT_X, rowsY)
	lists[#lists + 1] = l
end

-- Phial or Tea (left column): [on] Name, its status and the column labels on
-- one line, then compact rows. Drop an item on the name to add it.
local SUPPLY_TIPS = {
	phial = "Keeps one gathering phial (Finesse, Perception or Deftness) up, picked in your order. "
		.. "Waits while you have another flask or phial up, so it never replaces one.",
	tea = "Keeps you Relaxed with one tea, picked in your order. After drinking, the key waits "
		.. ns.TEA_SECONDS .. " seconds so casting doesn't stand you up before Relaxed lands.",
}

local function SupplyGroup(kind, y)
	local label = ns.SUPPLY_LABELS[kind]
	local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("LEFT", frame, "TOPLEFT", LEFT_ROW_LEFT - 2, y)
	local name = Font(frame, label, "GameFontNormal")
	name:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	ExtendHitRect(cb, name)
	local function Drop()
		local id = ItemFromCursor()
		if id then Report(ns.AddToGroup(kind, id)) end
		return id
	end
	cb:SetScript("OnReceiveDrag", Drop)
	cb:SetScript("OnClick", function(self)
		if Drop() then
			self:SetChecked(ns.db.supplies[kind].on) -- a drop, not a toggle
		else
			ns.SetGroupOption(kind, "on", self:GetChecked() and true or false)
		end
	end)
	HintTooltip(cb, "Keep " .. label .. " Up", SUPPLY_TIPS[kind]
		.. " Found in your bags automatically; drag one onto this name to add it by hand.")
	refreshers[#refreshers + 1] = function() cb:SetChecked(ns.db.supplies[kind].on) end

	local status = Font(frame, "", "GameFontHighlightSmall")
	status:SetPoint("LEFT", frame, "TOPLEFT", LEFT_ROW_LEFT + 60, y)

	local l = { key = kind, supply = kind, statusGroup = kind, status = status, rows = {} }
	l.labels = ColumnLabels(y, LEFT_GEO)
	local rowsY = y - 22
	for i = 1, ns.MAX_SUPPLY_ROWS do
		l.rows[i] = CreateRow(kind, i, rowsY - (i - 1) * ROW_H,
			{ toggle = true, arrow = true, supply = kind, geo = LEFT_GEO })
	end
	l.empty = Font(frame, "None found. Drag one onto the name.", "GameFontDisableSmall")
	l.empty:SetPoint("CENTER", frame, "TOPLEFT", LEFT_X, rowsY)
	lists[#lists + 1] = l
end

local function BuildPhialAndTea()
	Header("Phial and Tea", LEFT_X, -446)
	SupplyGroup("phial", -470)
	SupplyGroup("tea", -470 - 22 - ns.MAX_SUPPLY_ROWS * ROW_H - 2)
end

local function BuildLuresAndBaits()
	ListSection("lures", "Lures", ns.MAX_LURES, -36, {
		arrow = true, statusGroup = "lures",
		dropText = "Drag a lure here to add it.",
		dropTip = "Lures in your bags are found automatically. The highest ticked lure you own is kept active; "
			.. "the arrows change the order. Lures tied to one place are only used there.",
	})

	-- Fish Buffs: found in your bags automatically.
	Header("Fish Buffs", RIGHT_X, -176)
	fishEmpty = Font(frame, "Nothing added yet.", "GameFontDisableSmall")
	fishEmpty:SetPoint("CENTER", frame, "TOPLEFT", RIGHT_X, -200)
	FishGroup("perception", -200)
	FishGroup("skill", -200 - 34 - ns.MAX_FISH_ROWS * ROW_H - 6)

	ListSection("baits", "Other Baits", ns.MAX_BAITS, -462, {
		dropText = "Drag a bait here to add it.",
		dropTip = "Throw-back fish that don't give Perception or Fishing Skill (like water walking) are added automatically; "
			.. "drag anything else in. Every ticked bait usable where you are is kept active.",
	})
end

local function Build()
	frame = CreateFrame("Frame", "SimplyFishingConfig", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function()
		ns.ScanBags()
		ns.RefreshUI()
	end)
	frame:SetScript("OnHide", function() if capturing then StopCapture() end end)
	local acc = 0
	frame:SetScript("OnUpdate", function(_, elapsed) -- live timers, only while open
		acc = acc + elapsed
		if acc >= 1 then
			acc = 0
			ns.RefreshUI()
		end
	end)
	table.insert(UISpecialFrames, frame:GetName()) -- Esc closes it

	Font(frame, "Simply Fishing", "GameFontNormal"):SetPoint("TOP", 0, -5)

	-- Column divider
	local div = frame:CreateTexture(nil, "ARTWORK")
	div:SetColorTexture(1, 1, 1, 0.08)
	div:SetWidth(1)
	div:SetPoint("TOP", frame, "TOPLEFT", DIVIDER_X, -30)
	div:SetPoint("BOTTOM", frame, "BOTTOMLEFT", DIVIDER_X, 95)

	BuildCasting()
	BuildSound()
	BuildBobberAndRaft()
	BuildPhialAndTea()
	BuildLuresAndBaits()

	nextText = Font(frame, "", "GameFontNormal")
	nextText:SetPoint("CENTER", frame, "TOPLEFT", W / 2, -(H - 80))

	sleepButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	sleepButton:SetSize(110, 22)
	sleepButton:SetScript("OnClick", function()
		local _, msg = ns.SetAsleep(not ns.db.asleep)
		ns.Print(msg)
	end)

	local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetText("Reset Defaults")
	reset:SetScript("OnClick", function() StaticPopup_Show("SIMPLYFISHING_RESET") end)
	local autoCb, autoFs = Check("Auto-Sleep in Instances", "autoSleep",
		"Sleeps in dungeons, raids, battlegrounds and arenas, and wakes when you leave if it was awake when you went in.")

	-- One refresh time for every buff.
	local refreshFs = Font(frame, "Refresh Buffs Under", "GameFontHighlight")
	local refreshBox = NumberBox(frame, 34, function() return ns.db.threshold end,
		function(n) ns.SetOption("threshold", math.floor(n)) end, 0, 600)
	HintTooltip(refreshBox, "Refresh Buffs Under",
		"A lure, phial, tea, fish or bait buff is renewed once it has less than this many seconds left. "
		.. "21 covers a full cast, so a buff never drops mid-cast.")
	refreshers[#refreshers + 1] = refreshBox.Refresh
	HStack(W / 2, -(H - 53), 6, autoCb, autoFs, 24, refreshFs, refreshBox, Font(frame, "s", "GameFontHighlight"))
	local scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scan:SetSize(110, 22)
	scan:SetText("Scan Inventory")
	scan:SetScript("OnClick", function()
		ns.Rescan(false)
		ns.RefreshUI()
	end)
	HintTooltip(scan, "Scan Inventory",
		"Looks through your bags again from scratch for lures, fish, baits, phials and teas, including ones you removed this session. "
		.. "For a full report of what it sees, type /sfish scan.")
	HStack(W / 2, -(H - 25), 10, scan, sleepButton, reset)

	-- Debug chat messages: deliberately tiny, bottom-left corner.
	local debugCb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	debugCb:SetSize(18, 18)
	debugCb:SetPoint("BOTTOMLEFT", 12, 10)
	local debugFs = Font(frame, "Debug", "GameFontDisableSmall")
	debugFs:SetPoint("LEFT", debugCb, "RIGHT", 0, 0)
	ExtendHitRect(debugCb, debugFs)
	debugCb:SetScript("OnClick", function(self) ns.SetDebug(self:GetChecked() and true or false) end)
	HintTooltip(debugCb, "Debug Messages", "Explains each key press and event in chat. Same as /sfish debug.")
	refreshers[#refreshers + 1] = function() debugCb:SetChecked(ns.db.debug and true or false) end

	-- Minimap button visibility: tiny, bottom-right (middle-clicking the button hides it).
	local mapFs = Font(frame, "Minimap Button", "GameFontDisableSmall")
	local mapCb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	mapCb:SetSize(18, 18)
	mapCb:SetPoint("BOTTOMRIGHT", -(mapFs:GetStringWidth() + 14), 10)
	mapFs:SetPoint("LEFT", mapCb, "RIGHT", 0, 0)
	ExtendHitRect(mapCb, mapFs)
	mapCb:SetScript("OnClick", function(self) ns.SetOption("minimapHidden", not self:GetChecked() or nil) end)
	HintTooltip(mapCb, "Minimap Button", "Shows the fishing icon on the minimap. Middle-clicking the icon hides it.")
	refreshers[#refreshers + 1] = function() mapCb:SetChecked(not ns.db.minimapHidden) end

	frame:Hide() -- new frames start shown; let ToggleUI open it
end

function ns.RefreshUI()
	if not frame or not frame:IsShown() or not ns.db then return end
	if not capturing then
		local key = ns.GetKey()
		keyButton:SetText(key and (GetBindingText and GetBindingText(key) or key) or "|cffff5555Not Bound|r")
	end
	for _, fn in ipairs(refreshers) do fn() end
	for _, s in ipairs(selectors) do RefreshSelector(s) end
	local txt, color = ns.OversizedState()
	oversizedState:SetText(color .. "(" .. txt .. ")|r")
	oversizedStack() -- recenter, since the state text width changes
	-- Fish Buffs shows just "Nothing added yet." until some fish has been found.
	local anyFish = false
	for _, kind in ipairs(ns.FISH_KINDS) do
		if #ns.FishOrder(kind) > 0 then anyFish = true end
	end
	fishEmpty:SetShown(not anyFish)

	for _, l in ipairs(lists) do
		local items = (l.fish or l.supply) and ns.GroupOrder(l.key) or ns.db[l.key]
		local hidden = l.fish and not anyFish
		local active
		local more = ""
		if l.statusGroup then
			local txt, color, act = ns.BuffStatus(l.statusGroup)
			active = act
			-- More fish than rows: keep the one giving the buff on screen, note the rest.
			local n = #l.rows
			if #items > n then
				local shown = {}
				for i = 1, n do shown[i] = items[i] end
				local onScreen = false
				for i = 1, n do if shown[i] == active then onScreen = true end end
				if active and not onScreen then shown[n] = active end
				more = (l.supply and "  |cff808080+%d|r" or "  |cff808080(+%d more)|r"):format(#items - n)
				items = shown
			end
			if l.fish or l.supply then
				l.status:SetText(txt and (color .. txt .. "|r" .. more) or "")
			else
				l.status:SetText(txt and ("Lure Buff: " .. color .. txt .. "|r") or "")
			end
		end
		local empty = #items == 0
		for i, row in ipairs(l.rows) do FillRow(row, not hidden and items[i] or nil, i, active) end
		l.empty:SetShown(empty and not hidden)
		for _, w in ipairs(l.labels) do w:SetShown(not empty and not hidden) end
		if l.status and not l.fish and not l.supply then l.status:SetShown(not empty) end
		for _, w in ipairs(l.line or {}) do w:SetShown(not hidden) end
	end
	if ns.db.asleep then
		nextText:SetText(ns.db.autoSlept
			and "|cffff5555Sleeping in this instance:|r |cffffffffit wakes when you leave.|r"
			or "|cffff5555Sleeping:|r |cffffffffthe fishing key does nothing until you wake it.|r")
		sleepButton:SetText("Wake")
	else
		nextText:SetText("Next Press: |cffffffff" .. ns.NextActionText() .. "|r")
		sleepButton:SetText("Sleep")
	end
end

function ns.ToggleUI()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
end

-- Minimap addon-compartment entry (TOC: AddonCompartmentFunc).
function SimplyFishing_OnCompartmentClick()
	ns.ToggleUI()
end
