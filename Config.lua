local _, ns = ...

-- Built-in defaults. Everything is changed in-game with /sfish; this file
-- only seeds a fresh install or a reset.

-- Castable Fishing spell. 131490 is the profession ID; 131476 is included in
-- case the channel reports a different ID than the cast.
ns.FISHING_SPELL = 131474
ns.FISHING_SPELLS = { [131474] = true, [131476] = true, [131490] = true }

ns.REEL_RANGE = "30" -- soft-target interact range (yards) used in Cast and Reel mode
ns.MAX_LURES = 3
ns.MAX_BAITS = 3      -- "Other Baits": other throw-back fish and anything else you drag in
ns.MAX_FISH_ROWS = 4  -- rows shown per fish buff

-- Fish you throw back for a short buff. Found automatically in your bags.
ns.FISH_KINDS = { "perception", "skill" }
ns.FISH_LABELS = { perception = "Perception", skill = "Fishing Skill" }
-- Text matched in an item's "Use:" description to tell which buff it gives
-- (English clients). Fish must also mention throwing back.
ns.FISH_PATTERNS = { perception = "Perception", skill = "Fishing" }
-- Lures recognized by ID on any client language; others are read from their description.
ns.KNOWN_LURES = {
	[241149] = true, -- Ominous Octopus Lure
	[281022] = true, -- Eerie Lure (The Coiled Isle)
	[281021] = true, -- Eerie Lure (12.1 PTR ID)
}
-- Verified fish IDs; anything else is recognized from its description or the buff it gives.
ns.KNOWN_FISH = {
	[274587] = "perception", -- Spotted Killifish
}

-- Phial and Tea: gathering consumables found in your bags automatically.
-- One of each is kept up. Teas don't stack with each other, and a phial
-- replaces any other flask or phial you have up, so one per group.
ns.SUPPLY_KINDS = { "phial", "tea" }
ns.SUPPLY_LABELS = { phial = "Phial", tea = "Tea" }
ns.MAX_SUPPLY_ROWS = 2 -- rows shown per group
ns.KNOWN_PHIALS = {
	[241311] = true, -- Haranir Phial of Finesse (quality 1)
	[241310] = true, -- Haranir Phial of Finesse (quality 2)
}
ns.KNOWN_TEAS = {
	[242298] = true, -- Argentleaf Tea (Finesse and Speed)
	[242299] = true, -- Sanguithorn Tea (Perception and Speed)
	[242301] = true, -- Azeroot Tea (Deftness and Speed)
}
-- Gathering stats a phial must mention, and crafting stats that rule one out (English clients).
ns.PHIAL_STATS = { "finesse", "perception", "deftness" }
ns.CRAFTING_STATS = { "ingenuity", "resourcefulness", "multicraft", "crafting speed" }
-- Teas grant this buff after drinking seated for TEA_SECONDS. Its name is read
-- in English until the addon learns the buff's ID from your first tea.
ns.RELAXED = "Relaxed"
ns.TEA_SECONDS = 10
ns.TEA_WAIT = 12 -- longest the key waits on a tea before carrying on

ns.defaults = {
	mode = "reel",       -- "cast" or "reel"
	threshold = 21,      -- refresh any buff with less than this many seconds left
	audio = true,        -- raise sound effects while fishing
	muteMusic = true,    -- mute music and ambience while fishing
	bgSound = true,      -- keep game sound playing while alt-tabbed
	autoLoot = true,     -- auto loot catches while fishing
	dismount = true,     -- pressing the key on a ground mount dismounts first
	oversized = false,   -- keep Oversized Bobber active
	autoSleep = true,    -- sleep in dungeons, raids, battlegrounds and arenas
	minimapAngle = 225,  -- minimap button position in degrees
}

-- Sound and loot settings stay changed between casts and are restored once
-- you haven't cast for this many seconds (or immediately on combat or sleep).
ns.SESSION_GRACE = 15

-- Soft-target CVars may be locked in combat; their restore waits for combat to end.
ns.INTERACT_CVARS = { SoftTargetInteract = true, SoftTargetInteractRange = true }

-- Default raft: the first of these the player owns.
ns.seedRafts = {
	85500,  -- Anglers Fishing Raft
	198428, -- Tuskarr Dinghy
}

-- Oversized Bobber: the toy first, then the old consumable as a fallback.
ns.OVERSIZED = {
	{ item = 202207, toy = true }, -- Reusable Oversized Bobber (1 hr, 15 min cooldown)
	{ item = 136377 },             -- Oversized Bobber
}

-- No default lures: lures in your bags are found automatically.
ns.seedLures = {}
