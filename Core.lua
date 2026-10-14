local addonName, ns = ...

local BUTTON_NAME = "SimplyFishingButton"
local CLICK_BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"
local RECENT_WINDOW = 3   -- seconds to ignore an item after using it
local VERIFY_DELAY = 1.5  -- seconds after use to confirm the buff landed
local ATTEMPT_WINDOW = 1.5 -- a press that starts no cast within this is a failed use
local MAX_AURAS = 255
ns.CLICK_BINDING = CLICK_BINDING

BINDING_HEADER_SIMPLYFISHING = "Simply Fishing"
_G["BINDING_NAME_" .. CLICK_BINDING] = "Fish, Reel and Re-Buff"

local GREEN, YELLOW, RED, GREY, WHITE = "|cff40ff40", "|cffffd200", "|cffff5555", "|cff808080", "|cffffffff"

local db
local fishingName
local spellCache = {}   -- itemID -> use-spell ID
local spellItems = {}   -- use-spell ID -> { [itemID] = true }; fish can share one spell
local pressed           -- { item, time }: what the key last used
local entryByItem = {}  -- itemID -> entry
local recent = {}       -- itemID -> GetTime() of last successful use
local groupOf = {}      -- itemID -> "lures", "oversized" or a fish kind (one buff per group)
local groupUsed = {}    -- group -> { item, time } of its last successful use
local isBait = {}       -- itemID -> true for Other Baits entries
local removed = {}      -- itemID -> true: you removed it; not auto-added again until
                        -- you log out or press Scan Inventory (never saved)
local strikes = {}      -- itemID -> { map, n } unexplained failed uses in a row
local backoff = {}      -- itemID -> { until, wait } skipped briefly after failing (this session only)
local GCD_SPELL = 61304 -- the global cooldown
local attempt           -- the item use the last press tried
local snapshot, snapItem, snapTime -- buffs seen just before an item use
local channeling, swapped, needCleanup = false, false, false
local sessionToken = 0  -- bumped on each cast so a pending restore can tell it's stale
local current           -- last action written to the button
local applied = {}      -- cvar -> the value this addon last set, to tell our changes from the player's
local watchUntil = 0    -- item-cast events are only listened to until this time
local watching = false
local WatchItemEvents, CheckInstance -- defined with the event code below

local function Print(msg)
	print("|cff33ccffSimply Fishing:|r " .. msg)
end
ns.Print = Print

-- /sfish debug: explains each press and event, for checking behavior in-game.
local function Debug(fmt, ...)
	if db and db.debug then Print("|cff999999[Debug]|r " .. fmt:format(...)) end
end

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Changed()
	current = nil
	if ns.RefreshUI then ns.RefreshUI() end
	if ns.UpdateMinimap then ns.UpdateMinimap() end
end

function ns.ItemLabel(id)
	return C_Item.GetItemNameByID(id) or ("Item " .. id)
end
local ItemLabel = ns.ItemLabel

local function CurrentMap()
	return C_Map.GetBestMapForUnit("player")
end

function ns.ZoneName(map)
	local info = map and C_Map.GetMapInfo(map)
	return info and info.name or "this zone"
end

local function ItemSpell(itemID)
	if spellCache[itemID] == nil then
		local _, sid = C_Item.GetItemSpell(itemID)
		if not sid then
			C_Item.RequestLoadItemDataByID(itemID)
			return nil
		end
		spellCache[itemID] = sid
		spellItems[sid] = spellItems[sid] or {}
		spellItems[sid][itemID] = true
	end
	return spellCache[itemID]
end

local function ForEachEntry(fn)
	if db.raft then fn(db.raft) end
	if db.bobber then fn(db.bobber) end
	for _, e in ipairs(db.oversizedItems) do fn(e) end
	for _, e in ipairs(db.lures) do fn(e) end
	for _, e in ipairs(db.baits) do fn(e) end
	for _, kind in ipairs(ns.FISH_KINDS) do
		for _, e in ipairs(db.fish[kind].items) do fn(e) end
	end
end

local function Rebuild()
	wipe(entryByItem)
	wipe(groupOf)
	ForEachEntry(function(e)
		entryByItem[e.item] = e
		ItemSpell(e.item)
	end)
	wipe(isBait)
	for _, e in ipairs(db.baits) do isBait[e.item] = true end
	for _, e in ipairs(db.lures) do groupOf[e.item] = "lures" end
	for _, e in ipairs(db.oversizedItems) do groupOf[e.item] = "oversized" end
	for _, kind in ipairs(ns.FISH_KINDS) do
		for _, e in ipairs(db.fish[kind].items) do groupOf[e.item] = kind end
	end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function Copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = type(v) == "table" and Copy(v) or v end
	return c
end

local function ApplyDefaults()
	for k, v in pairs(ns.defaults) do
		if db[k] == nil then db[k] = v end
	end
	db.saved = db.saved or {}
	db.lures = db.lures or Copy(ns.seedLures)
	db.baits = db.baits or {}
	db.oversizedItems = db.oversizedItems or Copy(ns.OVERSIZED)
	db.fish = db.fish or {}
	for _, kind in ipairs(ns.FISH_KINDS) do
		local g = db.fish[kind] or {}
		if g.on == nil then g.on = true end
		g.mode = g.mode or "auto" -- "auto" = Automatic (most to spare first), "manual" = your order
		g.items = g.items or {}
		db.fish[kind] = g
	end
	if db.raft == nil and not db.raftCleared then
		db.raft = { item = ns.seedRafts[1], toy = true }
		db.raftAuto = true
	end
end

-- Swap the default raft for one the player actually owns.
local function PickDefaultRaft()
	if not (db.raftAuto and db.raft) or PlayerHasToy(db.raft.item) then return end
	for _, id in ipairs(ns.seedRafts) do
		if PlayerHasToy(id) then
			db.raft = { item = id, toy = true }
			return
		end
	end
end

---------------------------------------------------------------------------
-- State checks
---------------------------------------------------------------------------

local function FindAura(sid)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
	if not aura then
		local name = C_Spell.GetSpellName(sid)
		aura = name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
	end
	return aura
end

-- Refresh time in seconds for each kind of buff.
local function Threshold(kind)
	return db.threshold
end

-- Seconds of buff left; math.huge = active and not worth refreshing; nil = absent.
local function Remaining(e, threshold)
	local sid = e.aura or ItemSpell(e.item)
	local aura = sid and FindAura(sid)
	if aura then
		local exp, dur = aura.expirationTime, aura.duration
		if IsSecret(exp) or IsSecret(dur) then return math.huge end
		if not exp or exp == 0 then return math.huge end
		-- A buff shorter than the threshold could never satisfy it; don't loop on it.
		if dur and dur > 0 and dur <= (threshold or 0) then return math.huge end
		return exp - GetTime()
	end
	return nil
end

local function Owned(e)
	if not e.toy and PlayerHasToy(e.item) then e.toy = true end -- learned it since adding
	if e.toy then return PlayerHasToy(e.item) end
	return C_Item.GetItemCount(e.item) > 0
end

-- Seconds until a recently failed item is tried again, or nil.
-- WoW's own "is this usable" checks aren't used to block items: they can say no
-- for items that work fine when right-clicked. Only real failed uses count.
local function BackoffLeft(itemID)
	local b = backoff[itemID]
	if not b then return nil end
	local left = b.untilTime - GetTime()
	if left > 0 then return left end
	return nil
end
ns.BackoffLeft = BackoffLeft

-- Some lures only matter in one place ("...unique fish on The Coiled Isle for 30 min.").
-- The place is read from the item's text, so it's in the client's own language.
local zoneCache = {} -- itemID -> zone name, or false for anywhere

local function LureZone(itemID)
	local z = zoneCache[itemID]
	if z ~= nil then return z or nil end
	local _, sid = C_Item.GetItemSpell(itemID)
	local desc = sid and C_Spell.GetSpellDescription(sid)
	if not desc or desc == "" then return nil end -- not loaded; ask again later
	local place = desc:match(" on (%u[^%.]-) for %d") or desc:match(" in (%u[^%.]-) for %d")
	if place and #place > 40 then place = nil end
	zoneCache[itemID] = place or false
	return place
end
ns.LureZone = LureZone

local function Norm(name)
	return name and name:lower():gsub("^the ", "") or nil
end

-- Is the player in (or inside) the named place?
local function InZone(place)
	local want = Norm(place)
	for _, fn in ipairs({ GetRealZoneText, GetZoneText, GetSubZoneText, GetMinimapZoneText }) do
		if fn and Norm(fn()) == want then return true end
	end
	local map = C_Map.GetBestMapForUnit("player")
	while map do
		local info = C_Map.GetMapInfo(map)
		if not info then break end
		if Norm(info.name) == want then return true end
		map = info.parentMapID ~= 0 and info.parentMapID or nil
	end
	return false
end

local function WrongZone(e)
	if groupOf[e.item] ~= "lures" and not isBait[e.item] then return false end
	local place = LureZone(e.item)
	return place ~= nil and not InZone(place)
end

local function UsableHere(e)
	return BackoffLeft(e.item) == nil and not WrongZone(e)
end

-- Seconds of cooldown left, or nil when ready (global cooldowns don't count).
local function CooldownLeft(itemID)
	local start, dur = C_Container.GetItemCooldown(itemID)
	if IsSecret(start) or IsSecret(dur) or not start or start == 0 or not dur or dur <= 1.5 then return nil end
	local left = start + dur - GetTime()
	return left > 0 and left or nil
end

local function OnCooldown(itemID)
	return CooldownLeft(itemID) ~= nil
end

-- Bag count for a consumable; nil for toys, which have no count.
local function BagCount(e)
	if e.toy then return nil end
	return C_Item.GetItemCount(e.item)
end
ns.BagCount = BagCount

-- True when using one more would drop the stack to or below the player's Keep amount.
local function AtMinimum(e)
	local count = BagCount(e)
	return count ~= nil and count > 0 and e.keep ~= nil and count <= e.keep
end

-- Could this entry be used right now?
local function Ready(e)
	return e ~= nil and e.enabled ~= false and not e.noBuff and Owned(e) and not AtMinimum(e)
		and UsableHere(e) and not OnCooldown(e.item)
		and GetTime() - (recent[e.item] or -math.huge) > RECENT_WINDOW
end

local function NeedsRefresh(e, threshold)
	local r = Remaining(e, threshold)
	return not r or r < threshold
end

-- For pick-one lists: satisfied if any entry's buff is up.
local function AnyActive(list, threshold)
	for _, e in ipairs(list) do
		local r = Remaining(e, threshold)
		if r and r >= threshold then return true end
	end
	return false
end

local function FirstReady(list)
	for _, e in ipairs(list) do
		if Ready(e) then return e end
	end
end

-- A fish row is shown if it's turned on or you have some.
local function Visible(e)
	return e.enabled or (BagCount(e) or 0) > 0
end

-- Fish for one buff in priority order. "auto": turned-on fish first, then the
-- most to spare above your Keep amount. "manual": your order.
function ns.FishOrder(kind)
	local g = db.fish[kind]
	local out = {}
	for _, e in ipairs(g.items) do
		if Visible(e) then out[#out + 1] = e end
	end
	if g.mode == "auto" then
		local spare = {}
		for _, e in ipairs(out) do spare[e] = (BagCount(e) or 0) - (e.keep or 0) end
		table.sort(out, function(a, b)
			local ea, eb = a.enabled and 1 or 0, b.enabled and 1 or 0
			if ea ~= eb then return ea > eb end
			if spare[a] ~= spare[b] then return spare[a] > spare[b] end
			return a.item < b.item
		end)
	end
	return out
end

-- Right after one item in a group is used, give its buff time to show up
-- instead of trying the next item in the group (which would spend a second one).
local function Paused(group)
	local u = groupUsed[group]
	return u ~= nil and GetTime() - u.time <= RECENT_WINDOW
end

-- Returns the entry to use next, or nil for "cast Fishing".
local function Evaluate()
	if IsSwimming() and Ready(db.raft) then return db.raft end
	if #db.lures > 0 and not Paused("lures") and not AnyActive(db.lures, db.threshold) then
		local e = FirstReady(db.lures)
		if e then return e end
	end
	if db.bobber and NeedsRefresh(db.bobber, db.threshold) and Ready(db.bobber) then return db.bobber end
	if db.oversized and not Paused("oversized") and not AnyActive(db.oversizedItems, db.threshold) then
		local e = FirstReady(db.oversizedItems)
		if e then return e end
	end
	-- Fish buffs: one fish keeps each buff up, picked in priority order.
	for _, kind in ipairs(ns.FISH_KINDS) do
		local g = db.fish[kind]
		if g.on and not Paused(kind) and not AnyActive(g.items, db.threshold) then
			local e = FirstReady(ns.FishOrder(kind))
			if e then return e end
		end
	end
	-- Baits are independent buffs, so each one is kept up on its own.
	for _, e in ipairs(db.baits) do
		if NeedsRefresh(e, db.threshold) and Ready(e) then return e end
	end
	return nil
end
ns.Evaluate = Evaluate

local function Duration(r)
	if r >= 60 then return ("%dm"):format(math.ceil(r / 60)) end
	return ("%ds"):format(math.floor(r))
end

local function TimeLeft(r)
	return Duration(r) .. " Left"
end

local function CooldownText(itemID)
	local cd = CooldownLeft(itemID)
	return cd and ("Cooldown " .. Duration(cd))
end

-- Why an item can't be used right now, or nil if nothing's wrong.
local function Problem(e)
	if not Owned(e) then return "Not Owned", GREY end
	if AtMinimum(e) then return "At Minimum", YELLOW end
	local wait = BackoffLeft(e.item)
	if wait then return "Retry in " .. Duration(wait), YELLOW end
	if e.noBuff then return "No Buff Found", RED end
	if WrongZone(e) then return "Other Zone", GREY end
	local cd = CooldownText(e.item)
	if cd then return cd, YELLOW end
end

-- Row text for lures and fish: the buff's time is shown once for the whole
-- group, so rows only say something when that item has a problem.
function ns.RowProblem(e)
	return Problem(e)
end

-- One status for a whole buff group ("lures" or a fish kind): time left and the
-- item giving it, or why nothing is. Returns text, color, active entry.
function ns.BuffStatus(group)
	local fishGroup = db.fish[group]
	if fishGroup and not fishGroup.on then return "Off", GREY end
	local list = fishGroup and ns.FishOrder(group) or db.lures
	if #list == 0 then return nil end
	local best, bestLeft
	local last = groupUsed[group] and entryByItem[groupUsed[group].item]
	for _, e in ipairs(list) do
		local r = Remaining(e, db.threshold)
		-- Fish that share a buff all see it; credit the one you used last.
		if r and (not best or e == last) then best, bestLeft = e, r end
	end
	if best then
		if bestLeft == math.huge then return "Active", GREEN, best end
		return TimeLeft(bestLeft), bestLeft >= db.threshold and GREEN or YELLOW, best
	end
	if FirstReady(list) then return "Not Active", YELLOW end
	return "None Usable", RED
end

-- Short state text and color for the UI and /sfish status.
-- kind = "raft", "bobber", "lures" or "baits".
function ns.EntryState(e, kind)
	if kind == "raft" then
		if not Owned(e) then return "Not Owned", GREY end
		local cd = CooldownText(e.item)
		if cd then return cd, YELLOW end
		return "Ready", WHITE
	end
	local threshold = Threshold(kind)
	local r = Remaining(e, threshold)
	if r == math.huge then return "Active", GREEN end
	if r then return TimeLeft(r), r >= threshold and GREEN or YELLOW end
	if not Owned(e) then return "Not Owned", GREY end
	if AtMinimum(e) then return "At Minimum", YELLOW end
	local wait = BackoffLeft(e.item)
	if wait then return "Retry in " .. Duration(wait), YELLOW end
	if e.noBuff then return "No Buff Found", RED end
	local cd = CooldownText(e.item)
	if cd then return cd, YELLOW end
	return "Ready", WHITE
end

function ns.OversizedState()
	for _, e in ipairs(db.oversizedItems) do
		local r = Remaining(e, db.threshold)
		if r == math.huge then return "Active", GREEN end
		if r then return TimeLeft(r), r >= db.threshold and GREEN or YELLOW end
	end
	local cooling
	for _, e in ipairs(db.oversizedItems) do
		if Owned(e) then
			local cd = CooldownText(e.item)
			if not cd then return "Ready", WHITE end
			cooling = cooling or cd
		end
	end
	if cooling then return cooling, YELLOW end
	return "Not Owned", GREY
end

---------------------------------------------------------------------------
-- Buff learning and failed-use detection
---------------------------------------------------------------------------

local function ForEachBuff(fn)
	for i = 1, MAX_AURAS do
		local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if not a then return end
		if not IsSecret(a.spellId) and not IsSecret(a.expirationTime) then
			fn(a.spellId, a.expirationTime or 0)
		end
	end
end

local function TakeSnapshot(itemID)
	-- PreClick runs on key down and up; keep the first (pre-use) snapshot.
	if snapItem == itemID and GetTime() - snapTime < 2 then return end
	snapshot, snapItem, snapTime = {}, itemID, GetTime()
	ForEachBuff(function(sid, exp) snapshot[sid] = exp end)
end

-- If an item's buff isn't its own use-spell, learn it from what changed.
local function VerifyUse(itemID)
	local e = entryByItem[itemID]
	if not e or itemID == (db.raft and db.raft.item) then return end
	if Remaining(e) ~= nil then
		e.noBuff = nil
		return
	end
	local learned
	if snapshot and snapItem == itemID then
		ForEachBuff(function(sid, exp)
			local before = snapshot[sid]
			if not learned and (before == nil or (exp > 0 and exp > before + 1)) then learned = sid end
		end)
	end
	if learned then
		e.aura, e.noBuff = learned, nil
		Print(("Learned that %s gives %s."):format(ItemLabel(itemID), C_Spell.GetSpellName(learned) or learned))
	else
		e.noBuff = true
		Print(("%s didn't give a buff the addon can track, so it will be skipped. Remove and re-add it to try again.")
			:format(ItemLabel(itemID)))
	end
	Changed()
end

-- Could something other than the item itself make a use fail right now?
-- (Global cooldown after the last throw, moving, falling, another cast.)
local function ExplainableMiss(itemID)
	local gcd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(GCD_SPELL)
	if gcd and not IsSecret(gcd.duration) and gcd.duration and gcd.duration > 0 then return "global cooldown" end
	local speed = GetUnitSpeed("player")
	if not IsSecret(speed) and speed and speed > 0 then return "moving" end
	if IsFalling() then return "falling" end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then return "another cast" end
	if OnCooldown(itemID) then return "item cooldown" end
end

-- Two unexplained failures in a row: skip the item for a while, then try again
-- (1 minute, doubling up to 10). Never permanent; a success resets it.
local function Strike(itemID, map)
	if not entryByItem[itemID] then return end
	local s = strikes[itemID]
	if not s or s.map ~= map then
		s = { map = map, n = 0 }
		strikes[itemID] = s
	end
	s.n = s.n + 1
	if s.n < 2 then return end
	strikes[itemID] = nil
	local wait = math.min(((backoff[itemID] and backoff[itemID].wait) or 30) * 2, 600)
	backoff[itemID] = { untilTime = GetTime() + wait, wait = wait }
	Print(("%s didn't work just now, so it's skipped for %s and then tried again."):format(ItemLabel(itemID), Duration(wait)))
	Changed()
end

local function TrackAttempt(itemID)
	if attempt and attempt.item == itemID and GetTime() - attempt.time < ATTEMPT_WINDOW then return end
	local why = ExplainableMiss(itemID)
	local a = { item = itemID, map = CurrentMap(), time = GetTime(), excused = why }
	attempt = a
	C_Timer.After(ATTEMPT_WINDOW, function()
		if attempt ~= a then return end
		attempt = nil
		if a.cast and not a.failed then return end
		if a.excused then
			Debug("%s didn't go off (%s); not counted.", ItemLabel(a.item), a.excused)
		else
			Strike(a.item, a.map)
		end
	end)
end

local function MarkCast(itemID)
	if attempt and attempt.item == itemID then attempt.cast = true end
end

-- The item a spell event belongs to. If the cast's spell isn't the one the item
-- reports, match it to the item just pressed by name and remember the pairing.
local PRESS_MATCH = 5 -- seconds a cast is credited to the item the key just used

local function SpellMatchesItem(spellID, itemID)
	if ItemSpell(itemID) == spellID then return true end
	local name = C_Item.GetItemSpell(itemID)
	return name ~= nil and name == C_Spell.GetSpellName(spellID)
end

-- Which item a spell event belongs to, and its group. Several fish can share one
-- "throw back" spell, so the spell alone can't tell them apart: a cast right after
-- the key used an item with that spell is credited to that item. A shared spell
-- used by hand gives the group (the buff) but not the fish.
local function ItemForSpell(spellID)
	if pressed and GetTime() - pressed.time <= PRESS_MATCH and SpellMatchesItem(spellID, pressed.item) then
		spellItems[spellID] = spellItems[spellID] or {}
		spellItems[spellID][pressed.item] = true
		return pressed.item, groupOf[pressed.item]
	end
	local items = spellItems[spellID]
	if not items then return nil end
	local only, group, n = nil, nil, 0
	for id in pairs(items) do
		n = n + 1
		only = id
		local g = groupOf[id] or false
		if group == nil then group = g elseif group ~= g then group = false end
	end
	if n == 1 then return only, groupOf[only] end
	return nil, group or nil
end

---------------------------------------------------------------------------
-- Secure button
---------------------------------------------------------------------------

local btn = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "spell")
btn:SetAttribute("spell", ns.FISHING_SPELL)
btn:Hide()

-- An action is an entry table (use that item), "dismount", "sleep", or nil (cast Fishing).
local function ChooseAction()
	if db.asleep then return "sleep" end
	if db.dismount and IsMounted() and not IsFlying() then return "dismount" end
	return Evaluate()
end

local function ActionLabel(a)
	if a == "sleep" then return "Nothing (Sleeping)" end
	if a == "dismount" then return "Dismount" end
	if a then return "Use " .. ItemLabel(a.item) end
	return "Cast " .. (fishingName or "Fishing")
end

local function Apply(a)
	local key = type(a) == "table" and a.item or a or 0
	if key == current then return end
	current = key
	if a == "sleep" then
		btn:SetAttribute("type", nil) -- the key does nothing while asleep
	elseif a == "dismount" then
		btn:SetAttribute("type", "macro")
		btn:SetAttribute("macrotext", "/dismount")
	elseif not a then
		btn:SetAttribute("type", "spell")
		btn:SetAttribute("spell", fishingName or ns.FISHING_SPELL)
	elseif a.toy then
		btn:SetAttribute("type", "toy")
		btn:SetAttribute("toy", a.item)
	else
		btn:SetAttribute("type", "item")
		btn:SetAttribute("item", "item:" .. a.item)
	end
end

-- Evaluate on every press so buff timers are always fresh.
btn:SetScript("PreClick", function(_, _, down)
	if InCombatLockdown() or not db or db.asleep then return end
	local a = ChooseAction()
	Apply(a)
	Debug("Key %s (actions fire on key %s): %s", down and "down" or "up",
		C_CVar.GetCVarBool("ActionButtonUseKeyDown") and "down" or "up", ActionLabel(a))
	if type(a) == "table" then
		pressed = { item = a.item, time = GetTime() }
		WatchItemEvents()
		TakeSnapshot(a.item)
		TrackAttempt(a.item)
	end
end)

---------------------------------------------------------------------------
-- CVars and the reel binding swap
---------------------------------------------------------------------------

local function Elevate(group)
	for cvar, value in pairs(group) do
		local cur = C_CVar.GetCVar(cvar)
		if cur ~= nil then
			-- Only capture the original once, so a recast never saves elevated values.
			if db.saved[cvar] == nil then db.saved[cvar] = cur end
			applied[cvar] = value -- set first: the change event may fire during SetCVar
			C_CVar.SetCVar(cvar, value)
		end
	end
end

-- Sound settings follow sleep/wake rather than individual casts.
local SOUND_CVARS = { Sound_EnableSFX = true, Sound_SFXVolume = true, Sound_EnableMusic = true,
	Sound_EnableAmbience = true, Sound_EnableSoundWhenGameIsInBg = true }
local SOUND_OPTIONS = { audio = true, muteMusic = true, bgSound = true }

-- Puts saved settings back. Sound is left alone unless includeSound is set
-- (sleep, logout, reset). Returns true if something had to wait for combat to end.
local function RestoreCVars(includeSound)
	local pending = false
	for cvar, value in pairs(db.saved) do
		if SOUND_CVARS[cvar] and not includeSound then
			-- stays applied while awake
		elseif ns.INTERACT_CVARS[cvar] and InCombatLockdown() then
			pending = true
		else
			applied[cvar] = nil
			C_CVar.SetCVar(cvar, value)
			db.saved[cvar] = nil
			Debug("Restored %s to %s.", cvar, value)
		end
	end
	return pending
end

-- True if anything besides sound is waiting to be restored (sound stays while awake).
local function SessionSaved()
	for cvar in pairs(db.saved) do
		if not SOUND_CVARS[cvar] then return true end
	end
	return false
end

-- Sound the player asked for, applied the whole time the addon is awake.
local function WantedSound()
	local g = {}
	if db.asleep then return g end
	if db.audio then
		g.Sound_EnableSFX = "1"
		g.Sound_SFXVolume = "1" -- always 100%
	end
	if db.muteMusic then
		g.Sound_EnableMusic = "0"
		g.Sound_EnableAmbience = "0"
	end
	if db.bgSound then g.Sound_EnableSoundWhenGameIsInBg = "1" end
	return g
end

-- Brings every sound setting in line with the options: applies what's wanted,
-- and puts back the player's own value for anything no longer wanted.
local function ApplySound()
	local want = WantedSound()
	for cvar in pairs(SOUND_CVARS) do
		if want[cvar] then
			Elevate({ [cvar] = want[cvar] })
		elseif db.saved[cvar] ~= nil then
			applied[cvar] = nil
			C_CVar.SetCVar(cvar, db.saved[cvar])
			Debug("Restored %s to %s.", cvar, db.saved[cvar])
			db.saved[cvar] = nil
		end
	end
end

-- Settings changed for one fishing session (cast to a little after the last cast).
local function SessionCVars()
	local g = {}
	if db.autoLoot then g.autoLootDefault = "1" end
	return g
end

local function SwapToReel()
	if InCombatLockdown() then return end
	local keys = { GetBindingKey(CLICK_BINDING) }
	for _, key in ipairs(keys) do
		SetOverrideBinding(btn, true, key, "INTERACTTARGET")
	end
	swapped = #keys > 0
end

-- Returns false if the swap could not be undone yet (combat).
local function SwapBack()
	if not swapped then return true end
	if InCombatLockdown() then return false end
	ClearOverrideBindings(btn)
	swapped = false
	return true
end

local function StartSession()
	channeling = true
	sessionToken = sessionToken + 1
	Elevate(SessionCVars())
	if db.mode == "reel" and not InCombatLockdown() then
		Elevate({ SoftTargetInteract = "3", SoftTargetInteractRange = ns.REEL_RANGE })
		SwapToReel()
		Debug("Line cast. Reel key active on: %s", table.concat({ GetBindingKey(CLICK_BINDING) }, ", "))
	else
		Debug("Line cast (Cast Only mode).")
	end
end

-- Line ended: give the key back now; restore loot and targeting settings once
-- you've stopped fishing for a bit, so they don't flip on and off between casts.
local function StopChannel()
	channeling = false
	if not SwapBack() then needCleanup = true end
	sessionToken = sessionToken + 1
	local token = sessionToken
	Debug("Line ended. Settings restore in %ds unless you cast again.", ns.SESSION_GRACE)
	C_Timer.After(ns.SESSION_GRACE, function()
		if token ~= sessionToken or channeling or not db then return end
		if RestoreCVars() then needCleanup = true end
	end)
end

-- Immediate end of the fishing session (combat, sleep). Sound is handled by ApplySound.
local function EndSession()
	channeling = false
	sessionToken = sessionToken + 1
	local unswapped = SwapBack()
	local pending = RestoreCVars()
	needCleanup = not unswapped or pending
end

local function IsFishing(spellID)
	if not spellID or IsSecret(spellID) then return false end
	return ns.FISHING_SPELLS[spellID]
		or (fishingName ~= nil and C_Spell.GetSpellName(spellID) == fishingName)
end

---------------------------------------------------------------------------
-- API used by the settings window and slash commands
---------------------------------------------------------------------------

local function Validate(itemID)
	itemID = tonumber(itemID)
	if not itemID or not C_Item.GetItemInfoInstant(itemID) then return nil, "That isn't a valid item." end
	return itemID
end

-- slot = "raft" or "bobber"; itemID = nil clears it.
function ns.SetSlot(slot, itemID)
	if itemID == nil then
		db[slot] = nil
		if slot == "raft" then db.raftCleared, db.raftAuto = true, nil end
	else
		local id, err = Validate(itemID)
		if not id then return false, err end
		db[slot] = { item = id, toy = PlayerHasToy(id) or nil }
		if slot == "raft" then db.raftCleared, db.raftAuto = nil, nil end
	end
	Rebuild()
	Changed()
	return true
end

---------------------------------------------------------------------------
-- Fish buffs: finding and sorting fish you throw back for Perception or Skill
---------------------------------------------------------------------------

local classCache = {} -- itemID -> "perception", "skill", "lure" or false, for this session
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local fullWarned = {} -- lures already reported as not fitting, this session

-- What an item is for: a fish thrown back for "perception" or "skill", a fishing
-- "lure", or nil if neither (or not loaded yet). Descriptions are read in English.
local function Classify(itemID)
	local c = classCache[itemID]
	if c ~= nil then return c or nil end
	local kind = ns.KNOWN_FISH[itemID] or (ns.KNOWN_LURES[itemID] and "lure")
	if not kind then
		if not C_Item.IsItemDataCachedByID(itemID) then
			C_Item.RequestLoadItemDataByID(itemID)
			return nil -- try again on the next scan
		end
		-- Recipes can describe the item they teach; never treat one as the item itself.
		local classID = select(6, C_Item.GetItemInfoInstant(itemID))
		if classID == RECIPE_CLASS then
			classCache[itemID] = false
			return nil
		end
		local _, sid = C_Item.GetItemSpell(itemID)
		if not sid then
			classCache[itemID] = false
			return nil
		end
		local desc = C_Spell.GetSpellDescription(sid)
		local name = C_Item.GetItemNameByID(itemID)
		if not desc or desc == "" or not name then
			-- Not loaded yet: ask for it and try again on a later scan, rather than
			-- deciding "not a lure" for the rest of the session.
			if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(sid) end
			C_Item.RequestLoadItemDataByID(itemID)
			return nil
		end
		local low, lowName = desc:lower(), name:lower()
		if low:find("throw") then
			if desc:find(ns.FISH_PATTERNS.perception) then
				kind = "perception"
			elseif desc:find(ns.FISH_PATTERNS.skill) then
				kind = "skill"
			elseif low:find("back") or low:find("catch") or low:find("fish") then
				kind = "bait" -- another throw-back fish, e.g. Dirty Darter (water walking)
			end
		elseif not low:find("summon") and not low:find("beast") and (low:find("chance to catch")
			or (low:find("catch") and (low:find("fish") or lowName:find("lure")))
			or (low:find("fish") and (low:find("lure") or lowName:find("lure")))) then
			-- "Increases the chance to catch Ominous Octopus for 30 min."
			-- "Allows you to see unique fish on The Coiled Isle for 30 min." (Eerie Lure)
			kind = "lure"
		end
		if not kind and lowName:find("lure") then
			Debug("%s wasn't recognized as a fishing lure (\"%s\"). Drag it into Lures to add it.", name, desc)
		end
	end
	classCache[itemID] = kind or false
	return kind
end

-- Where an item already lives: "lures", "baits", a fish kind, or nil.
local function FindList(id)
	for _, key in ipairs({ "lures", "baits" }) do
		for i, e in ipairs(db[key]) do
			if e.item == id then return key, db[key], i end
		end
	end
	for _, kind in ipairs(ns.FISH_KINDS) do
		local items = db.fish[kind].items
		for i, e in ipairs(items) do
			if e.item == id then return kind, items, i end
		end
	end
end

local function ListLabel(key)
	if key == "lures" then return "Lures" end
	if key == "baits" then return "Other Baits" end
	return ns.FISH_LABELS[key]
end

-- A fish or lure found in your bags for the first time.
local function Discover(kind, itemID, quality)
	if FindList(itemID) then return end
	if kind == "lure" or kind == "bait" then
		if removed[itemID] then return end
		local key = kind == "lure" and "lures" or "baits"
		local list, max = db[key], kind == "lure" and ns.MAX_LURES or ns.MAX_BAITS
		if #list >= max then
			if not fullWarned[itemID] then
				fullWarned[itemID] = true
				Print(("Found %s, but %s is full (%d). Remove one to make room."):format(ItemLabel(itemID), ListLabel(key), max))
			end
			return
		end
		list[#list + 1] = { item = itemID }
		Print(("Found %s (%s)."):format(ItemLabel(itemID), kind == "lure" and "Lure" or "Other Baits"))
		return true
	end
	local g = db.fish[kind]
	local rare = (quality or 1) >= 3
	local e = { item = itemID, enabled = g.mode == "auto" and not rare, rare = rare or nil }
	g.items[#g.items + 1] = e
	local msg = ("Found %s (%s)."):format(ItemLabel(itemID), ns.FISH_LABELS[kind])
	if rare then
		msg = msg .. " It's rare, so it starts turned off."
	elseif not e.enabled then
		msg = msg .. " Tick it in /sfish to use it."
	end
	Print(msg)
	return true
end

-- Looks through your bags for buff fish. Runs at login, when bags change
-- (while awake), and when the settings window opens.
function ns.ScanBags()
	if not db or db.asleep then return end
	local changed = false
	-- A Perception or Skill fish in Other Baits belongs under its buff.
	for i = #db.baits, 1, -1 do
		local e = db.baits[i]
		local kind = Classify(e.item)
		if kind and db.fish[kind] then
			table.remove(db.baits, i)
			e.enabled = true
			table.insert(db.fish[kind].items, e)
			Print(("Moved %s to Fish Buffs: %s."):format(ItemLabel(e.item), ns.FISH_LABELS[kind]))
			changed = true
		end
	end
	local seen = {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not seen[id] then
				seen[id] = true
				local kind = Classify(id)
				if kind and Discover(kind, id, info.quality) then changed = true end
			end
		end
	end
	if changed then
		Rebuild()
		Changed()
	end
end

local function EntryCount()
	local n = #db.lures + #db.baits
	for _, kind in ipairs(ns.FISH_KINDS) do n = n + #db.fish[kind].items end
	return n
end

-- Scan Inventory (button) and /sfish scan: forget this session's verdicts and
-- removals, scan again from scratch. verbose = also report every lure- or
-- fish-like item in your bags, and why it was or wasn't added.
function ns.Rescan(verbose)
	wipe(classCache)
	wipe(zoneCache)
	wipe(fullWarned)
	wipe(removed)
	if db.asleep then
		Print("Sleeping, so bags aren't scanned. Wake it, then scan again.")
		return
	end
	local before = EntryCount()
	ns.ScanBags()
	if not verbose then
		local found = EntryCount() - before
		Print(found > 0 and ("Scan complete: added %d."):format(found) or "Scan complete: nothing new in your bags.")
		return
	end
	Print(("Bag scan: Lures %d of %d. Other Baits %d of %d."):format(#db.lures, ns.MAX_LURES, #db.baits, ns.MAX_BAITS))
	local seen, shown = {}, 0
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not seen[id] then
				seen[id] = true
				local name = C_Item.GetItemNameByID(id) or ("Item " .. id)
				local _, sid = C_Item.GetItemSpell(id)
				local desc = sid and C_Spell.GetSpellDescription(sid) or ""
				local text = (name .. " " .. desc):lower()
				if ns.KNOWN_LURES[id] or ns.KNOWN_FISH[id] or text:find("lure") or text:find("throw")
					or (sid and (text:find("fish") or text:find("catch"))) then
					shown = shown + 1
					local kind, where = classCache[id], FindList(id)
					local note
					if where then
						note = "|cff40ff40in " .. ListLabel(where) .. "|r"
					elseif kind == "lure" then
						note = "|cffffd200a lure, but Lures is full|r"
					elseif kind == "bait" then
						note = "|cffffd200a throw-back fish, but Other Baits is full|r"
					elseif kind == nil then
						note = "|cffffd200its text hasn't loaded yet; try again in a few seconds|r"
					elseif not sid then
						note = "|cffff5555not recognized: the game reports no Use effect for it|r"
					else
						note = "|cffff5555not recognized|r"
					end
					local zone = (kind == "lure" or kind == "bait") and LureZone(id)
					Print(("%s (ID %d): %s%s"):format(name, id, note, zone and (", only used in " .. zone) or ""))
					if not where and desc ~= "" then Print(("   Use: %s"):format(desc)) end
				end
			end
		end
	end
	if shown == 0 then Print("No lure- or fish-like items found in your bags.") end
end

function ns.ScanReport()
	ns.Rescan(true)
end

-- list = "lures" or "baits". Fish that give Perception or Skill go to their buff instead.
function ns.AddItem(list, itemID)
	local id, err = Validate(itemID)
	if not id then return false, err end
	local where = FindList(id)
	if where then return false, ("%s is already in %s."):format(ItemLabel(id), ListLabel(where)) end
	removed[id] = nil
	if list == "baits" then
		local kind = Classify(id)
		if kind == "lure" then list = "lures" end
		if kind and db.fish[kind] then
			local g = db.fish[kind]
			g.items[#g.items + 1] = { item = id, enabled = true }
			Rebuild()
			Changed()
			return true, ("%s gives %s, so it was added under Fish Buffs."):format(ItemLabel(id), ns.FISH_LABELS[kind])
		end
	end
	local max = list == "lures" and ns.MAX_LURES or ns.MAX_BAITS
	if #db[list] >= max then return false, ("You can add up to %d to %s."):format(max, ListLabel(list)) end
	db[list][#db[list] + 1] = { item = id, toy = PlayerHasToy(id) or nil }
	Rebuild()
	Changed()
	if list == "baits" and C_Item.GetItemCount(id) > 0 and C_Item.IsUsableItem(id) == false then
		return true, ("WoW says %s can't be used in %s right now. If it works when you right-click it, ignore this.")
			:format(ItemLabel(id), ns.ZoneName(CurrentMap()))
	end
	return true
end

-- Dragging an item onto a buff adds it there (moving it from any other list),
-- for fish the scan didn't recognize.
function ns.AddFish(kind, itemID)
	local id, err = Validate(itemID)
	if not id then return false, err end
	local where, items, i = FindList(id)
	if where == kind then return false, ("%s is already in %s."):format(ItemLabel(id), ns.FISH_LABELS[kind]) end
	local e = { item = id, enabled = true }
	if items then
		e = table.remove(items, i)
		e.enabled = true
	end
	classCache[id] = kind
	local g = db.fish[kind]
	g.items[#g.items + 1] = e
	Rebuild()
	Changed()
	return true
end

function ns.SetFishEnabled(e, on)
	e.enabled = on and true or false
	Changed()
end

function ns.SetFishOption(kind, key, value)
	db.fish[kind][key] = value
	Changed()
end

-- Switching to manual starts from the order you were just looking at.
function ns.SetFishMode(kind, mode)
	local g = db.fish[kind]
	if mode == "manual" and g.mode ~= "manual" then
		local items, placed = {}, {}
		for _, e in ipairs(ns.FishOrder(kind)) do
			items[#items + 1] = e
			placed[e] = true
		end
		for _, e in ipairs(g.items) do
			if not placed[e] then items[#items + 1] = e end
		end
		g.items = items
	end
	g.mode = mode
	Changed()
end

-- Manual order: swap with the neighboring shown row.
function ns.MoveFish(kind, e, delta)
	local shown = ns.FishOrder(kind)
	local pos
	for i, x in ipairs(shown) do
		if x == e then pos = i end
	end
	local other = pos and shown[pos + delta]
	if not other then return end
	local items = db.fish[kind].items
	local a, b
	for i, x in ipairs(items) do
		if x == e then a = i elseif x == other then b = i end
	end
	items[a], items[b] = items[b], items[a]
	Changed()
end

function ns.RemoveItem(list, index)
	local e = table.remove(db[list], index)
	if e then removed[e.item] = true end -- until logout or Scan Inventory
	Rebuild()
	Changed()
end

function ns.MoveItem(list, index, delta)
	local t = db[list]
	local j = index + delta
	if j < 1 or j > #t then return end
	t[index], t[j] = t[j], t[index]
	Changed()
end

-- Stop using this item once the bag count is at or below n. 0 clears it.
function ns.SetKeep(e, n)
	e.keep = n and n > 0 and n or nil
	Changed()
end

function ns.SetOption(key, value)
	db[key] = value
	if SOUND_OPTIONS[key] then ApplySound() end
	Changed()
	if key == "autoSleep" then CheckInstance() end
end

function ns.GetKey()
	return GetBindingKey(CLICK_BINDING)
end

-- key = nil clears. Returns ok, message.
function ns.SetKey(key)
	if InCombatLockdown() then return false, "Key bindings can't be changed in combat." end
	if swapped then
		ClearOverrideBindings(btn)
		swapped = false
	end
	for _, old in ipairs({ GetBindingKey(CLICK_BINDING) }) do SetBinding(old) end
	local msg
	if key then
		local prev = GetBindingAction(key)
		if prev and prev ~= "" and prev ~= CLICK_BINDING then
			msg = ("%s was unbound from %s."):format(key, _G["BINDING_NAME_" .. prev] or prev)
		end
		SetBinding(key, CLICK_BINDING)
	end
	SaveBindings(GetCurrentBindingSet())
	Changed()
	return true, msg
end

function ns.Reset()
	needCleanup = RestoreCVars()
	-- Keep things that aren't fishing settings: pending restores, sleep, minimap, debug.
	local keep = { saved = db.saved, asleep = db.asleep, autoSlept = db.autoSlept, debug = db.debug,
		minimapAngle = db.minimapAngle, minimapHidden = db.minimapHidden }
	wipe(db)
	for k, v in pairs(keep) do db[k] = v end
	ApplyDefaults()
	PickDefaultRaft()
	ApplySound() -- default sound options, keeping the player's saved originals
	wipe(recent)
	wipe(strikes)
	wipe(backoff)
	wipe(removed)
	Rebuild()
	Changed()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}
local events = CreateFrame("Frame")

-- Listened to the whole time the addon is awake.
local AWAKE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "BAG_UPDATE_DELAYED" }
local CHANNEL_EVENTS = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }
-- Every spell you cast fires these, so they're only listened to for a few
-- seconds after the key uses an item (or always in debug mode).
local ITEM_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }
local ITEM_WATCH = 10
local DEBUG_EVENT = "PLAYER_SOFT_INTERACT_CHANGED"

local function SetItemEvents(on)
	for _, ev in ipairs(ITEM_EVENTS) do
		if on then events:RegisterUnitEvent(ev, "player") else events:UnregisterEvent(ev) end
	end
end

local function SetEventsActive(on)
	for _, ev in ipairs(AWAKE_EVENTS) do
		if on then events:RegisterEvent(ev) else events:UnregisterEvent(ev) end
	end
	for _, ev in ipairs(CHANNEL_EVENTS) do
		if on then events:RegisterUnitEvent(ev, "player") else events:UnregisterEvent(ev) end
	end
	watching = false
	SetItemEvents(on and db.debug)
	-- Only watched in debug mode; pcall in case the event name changes in a patch.
	if on and db.debug then
		pcall(events.RegisterEvent, events, DEBUG_EVENT)
	else
		pcall(events.UnregisterEvent, events, DEBUG_EVENT)
	end
end

local function StopWatching()
	if not watching then return end
	if GetTime() < watchUntil then
		return C_Timer.After(watchUntil - GetTime() + 0.1, StopWatching)
	end
	watching = false
	if not db.debug then SetItemEvents(false) end
end

-- Called when the key is about to use an item.
function WatchItemEvents()
	watchUntil = GetTime() + ITEM_WATCH
	if watching then return end
	watching = true
	SetItemEvents(true)
	C_Timer.After(ITEM_WATCH + 0.1, StopWatching)
end

-- Instance auto-sleep: dungeons, raids, battlegrounds and arenas.
local SLEEP_INSTANCES = { party = true, raid = true, pvp = true, arena = true }

local function CurrentSleepInstance()
	local inInstance, kind = IsInInstance()
	if not (inInstance and SLEEP_INSTANCES[kind]) then return nil end
	return select(8, GetInstanceInfo()) or kind
end

-- Sleep: no fishing events, no per-press work, and the key does nothing.
-- auto = true when instance auto-sleep did it, so leaving can wake it again.
function ns.SetAsleep(asleep, auto)
	if InCombatLockdown() then return false, "Sleep mode can't be changed in combat." end
	db.asleep = asleep or nil
	db.autoSlept = (asleep and auto) or nil
	if not auto then db.stayAwakeIn = not asleep and CurrentSleepInstance() or nil end
	if asleep then EndSession() end
	ApplySound() -- asleep: put the player's sound back; awake: apply the options
	SetEventsActive(not asleep)
	current = nil
	Apply(ChooseAction())
	Changed()
	if not asleep then ns.ScanBags() end
	if asleep and auto then
		return true, "Sleeping while you're in this instance. It wakes when you leave."
	end
	return true, asleep and "Sleeping. The fishing key does nothing until you wake it."
		or "Awake and ready to fish."
end

function CheckInstance()
	local instance = CurrentSleepInstance()
	if not instance then db.stayAwakeIn = nil end
	-- A manual wake inside an instance holds until you leave that instance.
	local inside = db.autoSleep and instance and instance ~= db.stayAwakeIn
	local wantSleep = inside and not db.asleep
	local wantWake = not inside and db.asleep and db.autoSlept
	if not (wantSleep or wantWake) then return end
	if InCombatLockdown() then return C_Timer.After(2, CheckInstance) end
	local _, msg = ns.SetAsleep(wantSleep and true or false, true)
	Print(wantWake and "Left the instance. Awake and ready to fish." or msg)
end

function ns.SetDebug(on)
	db.debug = on or nil
	if not db.asleep then SetEventsActive(true) end
	Print(on and "Debug messages on. Type /sfish debug again to turn them off." or "Debug messages off.")
end

function handlers.ADDON_LOADED(name)
	if name ~= addonName then return end
	SimplyFishingDB = SimplyFishingDB or {}
	db = SimplyFishingDB
	ns.db = db
	ApplyDefaults()
	events:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
	fishingName = C_Spell.GetSpellName(ns.FISHING_SPELL)
	current = nil
	PickDefaultRaft()
	Rebuild()
	-- Undo anything left changed by a crash or disconnect, then apply sound if awake.
	needCleanup = RestoreCVars(true)
	ApplySound()
	SetEventsActive(not db.asleep)
	ns.ScanBags()
	-- Item and spell text often isn't loaded yet at login; look again shortly.
	for _, delay in ipairs({ 5, 20 }) do
		C_Timer.After(delay, function()
			if db.asleep then return end
			ns.ScanBags()
			if ns.RefreshUI then ns.RefreshUI() end
		end)
	end
	if not InCombatLockdown() then Apply(ChooseAction()) end
	if ns.CreateMinimapButton then ns.CreateMinimapButton() end
	events:UnregisterEvent("PLAYER_LOGIN")
end

-- Everything goes back on logout so the game saves your own settings;
-- sound is applied again at the next login if the addon is awake.
function handlers.PLAYER_LOGOUT()
	RestoreCVars(true)
end

function handlers.UNIT_SPELLCAST_CHANNEL_START(_, _, spellID)
	if IsFishing(spellID) then StartSession() end
end

function handlers.UNIT_SPELLCAST_CHANNEL_STOP()
	if channeling then StopChannel() end
end

function handlers.UNIT_SPELLCAST_SENT(_, _, _, spellID)
	if IsSecret(spellID) then return end
	local itemID = ItemForSpell(spellID)
	if db.debug then
		Debug("Cast sent: %s%s.", C_Spell.GetSpellName(spellID) or spellID, itemID and (" (" .. ItemLabel(itemID) .. ")") or "")
	end
	if itemID then MarkCast(itemID) end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if IsSecret(spellID) then return end
	local itemID, group = ItemForSpell(spellID)
	if group then groupUsed[group] = { item = itemID, time = GetTime() } end
	if not itemID then return end
	Debug("%s used successfully.", ItemLabel(itemID))
	MarkCast(itemID)
	strikes[itemID] = nil
	backoff[itemID] = nil
	recent[itemID] = GetTime()
	C_Timer.After(VERIFY_DELAY, function() VerifyUse(itemID) end)
end

-- A refused use. It only counts toward a skip if the press had no other
-- explanation (decided when the attempt window closes).
function handlers.UNIT_SPELLCAST_FAILED(_, _, spellID)
	if IsSecret(spellID) then return end
	local itemID = ItemForSpell(spellID)
	if not itemID then return end
	Debug("%s failed.", ItemLabel(itemID))
	if attempt and attempt.item == itemID then attempt.failed = true end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED(_, newTarget)
	if not channeling then return end
	if IsSecret(newTarget) then return Debug("Soft target changed (hidden by the game).") end
	local kind = newTarget and tostring(newTarget):match("^(%a+)%-")
	Debug("Soft target: %s.", kind == "GameObject" and "an object (likely your bobber)" or (kind or "none"))
end

-- Fires just before lockdown begins, so this is the last chance to change the button.
function handlers.PLAYER_REGEN_DISABLED()
	-- The button can't change during combat; make sure it won't spend a lure or bait.
	if not InCombatLockdown() then Apply(nil) end
	if channeling or swapped or SessionSaved() then EndSession() end
end

function handlers.PLAYER_REGEN_ENABLED()
	if needCleanup then EndSession() end
end

-- A setting we manage changed to something we didn't set: the player changed it
-- (e.g. in WoW's sound options). Adopt it as their own so it's what gets restored.
local function SameValue(a, b)
	local na, nb = tonumber(a), tonumber(b)
	if na and nb then return math.abs(na - nb) < 0.001 end
	return tostring(a) == tostring(b)
end

function handlers.CVAR_UPDATE(cvar, value)
	if not cvar or db.saved[cvar] == nil or applied[cvar] == nil then return end
	if value == nil then value = C_CVar.GetCVar(cvar) end
	if SameValue(value, applied[cvar]) then return end
	db.saved[cvar] = tostring(value)
	applied[cvar] = nil
	Debug("You changed %s to %s; that's now what gets restored.", cvar, tostring(value))
end

function handlers.PLAYER_ENTERING_WORLD()
	CheckInstance()
end

-- Fires once after a batch of bag changes (e.g. each catch).
function handlers.BAG_UPDATE_DELAYED()
	ns.ScanBags()
	if ns.RefreshUI then ns.RefreshUI() end -- counts and Automatic order update right away
end

events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- once per loading screen, for instance auto-sleep

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

function ns.NextActionText()
	return ActionLabel(ChooseAction())
end

local function OnOff(v) return v and "On" or "Off" end

local function Status()
	if db.asleep then Print(RED .. "Sleeping.|r Left-click the minimap button or type /sfish sleep to wake.") end
	Print(("Mode: %s. Auto Loot: %s. Dismount: %s."):format(
		db.mode == "reel" and "Cast and Reel" or "Cast Only", OnOff(db.autoLoot), OnOff(db.dismount)))
	Print(("Sound Effects: %s. Mute Music and Ambience: %s. Sound When Alt-Tabbed: %s."):format(
		db.audio and "100%" or "Off", OnOff(db.muteMusic), OnOff(db.bgSound)))
	Print(("Buffs refresh under %d seconds."):format(db.threshold))
	Print("Keybind: " .. (ns.GetKey() or (RED .. "Not Bound|r (type /sfish to set one)")))
	local function Line(label, e, kind)
		local txt, color = ns.EntryState(e, kind)
		local stock = ""
		local count = kind ~= "raft" and kind ~= "bobber" and BagCount(e)
		if count then
			stock = e.keep and (", %d in bags, keeping %d"):format(count, e.keep) or (", %d in bags"):format(count)
		end
		Print(("%s: %s (%s%s|r%s)"):format(label, ItemLabel(e.item), color, txt, stock))
	end
	if db.raft then Line("Raft", db.raft, "raft") end
	if db.bobber then Line("Bobber", db.bobber, "bobber") end
	if db.oversized then
		local txt, color = ns.OversizedState()
		Print(("Oversized Bobber: %s%s|r"):format(color, txt))
	end
	local function Group(label, group, list)
		local txt, color, active = ns.BuffStatus(group)
		if not txt then return end
		Print(("%s: %s%s|r%s"):format(label, color, txt, active and (" from " .. ItemLabel(active.item)) or ""))
		for _, e in ipairs(list) do
			local p = ns.RowProblem(e)
			local count = BagCount(e)
			Print(("  %s%s%s%s"):format(e.enabled == false and "(off) " or "", ItemLabel(e.item),
				count and (" x%d"):format(count) or "", p and (" - " .. p) or ""))
		end
	end
	Group("Lures", "lures", db.lures)
	for _, kind in ipairs(ns.FISH_KINDS) do
		local g = db.fish[kind]
		Group(("%s (%s)"):format(ns.FISH_LABELS[kind], g.mode == "auto" and "Automatic" or "Manual Order"),
			kind, ns.FishOrder(kind))
	end
	for _, e in ipairs(db.baits) do Line("Other Bait", e, "baits") end
	Print("Next Press: " .. ns.NextActionText())
end


SLASH_SIMPLYFISHING1 = "/sfish"
SLASH_SIMPLYFISHING2 = "/simplyfishing"
SlashCmdList.SIMPLYFISHING = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" or cmd == "config" then
		ns.ToggleUI()
	elseif cmd == "status" then
		Status()
	elseif cmd == "sleep" then
		local _, m = ns.SetAsleep(not db.asleep)
		Print(m)
	elseif cmd == "scan" then
		ns.ScanReport()
		if ns.RefreshUI then ns.RefreshUI() end
	elseif cmd == "debug" then
		ns.SetDebug(not db.debug)
	elseif cmd == "minimap" then
		ns.SetOption("minimapHidden", not db.minimapHidden or nil)
		Print(db.minimapHidden and "Minimap button hidden. Tick Minimap Button in /sfish to show it again."
			or "Minimap button shown.")
	elseif cmd == "timer" then
		local n = tonumber(arg)
		if n and n >= 0 and n <= 600 then
			ns.SetOption("threshold", math.floor(n))
			Print(("Buffs will refresh under %d seconds."):format(db.threshold))
		else
			Print("Usage: /sfish timer <0-600>")
		end
	elseif cmd == "reset" then
		ns.Reset()
		Print("Settings have been reset.")
	else
		Print("Commands: /sfish (settings), /sfish status, /sfish sleep, /sfish scan, /sfish debug, /sfish minimap, "
			.. "/sfish timer <seconds>, /sfish reset")
	end
end
