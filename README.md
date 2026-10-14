# Simply Fishing

**One key to re-buff, cast, and reel.** A lightweight fishing addon for World of Warcraft Retail (Midnight).

Press your fishing key and Simply Fishing works out what you need next. It might put up your lure, refresh your bobber toy, drink a phial or tea, throw back a fish for its buff, drop a raft if you're swimming, or simply cast. Once the line is out, the same key reels in the bobber. No mouse aiming, no action bar juggling.

- **Version:** 1.1.0
- **Game:** Retail, Midnight 12.1.5 (Interface 120105)
- **Dependencies:** none (no Ace3, no LibStub, no LibDBIcon)
- **Author:** Erdmann5150

---

## Features

- **Single-key fishing loop.** One keybind handles buffs, casting and reeling.
- **Cast and Reel mode.** While your line is out, the key hooks the bobber using soft-target interact, so there's no need to click it.
- **Automatic buff upkeep** for lures, bobber toys, the Oversized Bobber, phials, teas, throw-back fish and baits. Each is refreshed just before it runs out.
- **Finds your fishing items by itself.** Lures, throw-back fish, other fish baits, gathering phials and Relaxed teas in your bags are detected and sorted automatically.
- **Phial and Tea.** Keeps one gathering phial and one tea up. The key waits while you drink so you don't stand up before becoming Relaxed, and a phial never replaces another flask you have up.
- **Fish Buffs.** Fish you throw back for +25 Perception or +25 Fishing Skill are used in the order you choose, or automatically by whichever you have the most to spare.
- **Stock control.** Every lure, fish and bait shows how many you have, and you can set a minimum to keep.
- **Zone aware.** Lures and baits that only work in one place, like the Eerie Lure on The Coiled Isle, are only used there.
- **Fishing sound mode.** Sound effects at 100%, music and ambience muted, and sound kept on while alt-tabbed, so the splash is hard to miss.
- **Auto loot while fishing**, put back to your own setting afterward.
- **Raft when swimming**, and **dismount on press** when you're on a ground mount.
- **Sleep mode** turns the addon fully off with one click, and **auto-sleep** handles dungeons, raids, battlegrounds and arenas.
- **Combat safe.** Nothing secure changes during combat, and the key can't spend a consumable mid-fight.
- **Settings window and minimap button.** No config files to edit.

---

## Installation

1. Download the release and extract the `SimplyFishing` folder.
2. Place it in `World of Warcraft/_retail_/Interface/AddOns/`.
3. Restart the game or type `/reload`.

## Quick Start

1. **Right-click** the fishing icon on the minimap, or type `/sfish`.
2. Click the **Keybind** button and press the key or mouse button you want to fish with.
3. Stand by water and press it.

Lures, throw-back fish, phials and teas in your bags are found automatically. Drag your raft and bobber toys onto their slots if the defaults aren't the ones you want.

---

## How the Key Decides

Every press re-checks your buffs and picks the first thing that's needed:

| Order | Action | When |
|---|---|---|
| 1 | Dismount | You're on a ground mount (never while flying) |
| 2 | Raft | You're swimming |
| 3 | Lure | No lure buff, or it's about to run out |
| 4 | Bobber toy | Its buff is missing or about to run out |
| 5 | Oversized Bobber | Enabled, and its buff is missing or about to run out |
| 6 | Phial | No phial buff, or it's about to run out, and no other flask or phial is up |
| 7 | Tea | You aren't Relaxed, or it's about to run out, and you aren't swimming |
| 8 | Perception fish | That buff is missing or about to run out |
| 9 | Fishing Skill fish | That buff is missing or about to run out |
| 10 | Other baits | Each bait's own buff is missing or about to run out |
| 11 | **Cast Fishing** | Everything is up |

"About to run out" means less than the **Refresh Buffs Under** time (21 seconds by default). Items you don't own, are at their Keep minimum, are unticked, are on cooldown, or only work in another zone are skipped. While the line is out in Cast and Reel mode, the key reels in instead.

Phial and Tea come before fish buffs because they last 30 to 60 minutes, while a fish buff would tick away as you sit and drink. After a tea, the key does nothing until you're Relaxed (about 10 seconds), since casting would stand you up and waste the tea. **Next Press** shows **Wait, Relaxing** with the seconds left.

The bottom of the settings window always shows **Next Press**, so you know exactly what the key will do.

---

## Settings

### Casting
| Setting | Default | What it does |
|---|---|---|
| Cast Only / Cast and Reel | Cast and Reel | In Cast and Reel, the same key reels in the bobber while your line is out |
| Keybind | none | Click, then press a key. Modifiers, middle mouse, Button4 and Button5 work. Esc cancels |
| Auto Loot | On | Catches go straight to your bags while you're fishing |
| Dismount | On | On a ground mount, the key dismounts you first |

### Sound
| Setting | Default | What it does |
|---|---|---|
| Sound Effects at 100% | On | Full sound effect volume |
| Mute Music and Ambience | On | Makes the bobber splash easier to hear |
| Keep Sound When Alt-Tabbed | On | Hear the splash with another window in front |

Sound settings apply while the addon is awake. Your own settings come back when it sleeps or you log out. If you change one of those settings yourself in WoW's options while the addon is awake, your new value is the one it restores.

Auto loot only applies while you're fishing: from your cast until 15 seconds after your last one, or until combat starts.

### Raft and Bobber
- **Raft:** one raft toy, used only when you're swimming. It defaults to the Anglers Fishing Raft or the Tuskarr Dinghy, whichever you own.
- **Bobber:** one bobber toy, kept active.
- **Use Oversized Bobber:** also keeps the Reusable Oversized Bobber toy up. If the toy is on cooldown, it uses the older consumable Oversized Bobber.

Drag a toy onto a slot to set it. The ✕ clears it.

### Lures
Up to 3. Lures in your bags are found automatically, or you can drag one in. The highest ticked lure you own is kept active, and the arrow raises an item's priority.

- **Tick:** untick a lure to keep it listed but never use it. This is saved.
- **✕:** removes it until you log out or press **Scan Inventory**, then it's found again if it's still in your bags.

Lures tied to one place, like the **Eerie Lure** ("...unique fish on The Coiled Isle"), are only used there. Elsewhere their row says **Other Zone** and the next lure in your order is used instead.

### Fish Buffs
Some fish can be thrown back for a short buff: **+25 Midnight Perception** or **+25 Midnight Fishing** for 30 seconds. Throwing more extends the buff, up to 5 minutes. Simply Fishing finds these fish in your bags and lists them under **Perception** or **Fishing Skill**.

Each buff has its own on/off checkbox and an order button:

- **Automatic** uses the fish you have the most to spare first, meaning the most above its Keep amount. The list re-sorts as your counts change, and new fish are turned on automatically.
- **Manual Order** uses your order, set with the arrows. New fish are listed but start turned off. Switching to Manual keeps the order you were looking at.

Only one fish is used per buff. Untick a fish to never use it. Rare-quality fish always start unticked so they aren't thrown away by accident.

Up to 4 fish are shown per buff. Extras are noted as "(+N more)" on the buff's line, and the fish currently giving the buff is always kept on screen.

### Other Baits
Up to 3. Throw-back fish that give something other than Perception or Fishing Skill, like the **Dirty Darter** (water walking), are added automatically. Anything else can be dragged in. Each bait is kept active on its own, so several can be up at once. Ticks and ✕ work the same as for lures.

Baits tied to one place, like the **Sulfurous Sludgefish** (Atal'Utek), are only used there. The Sludgefish is rubbed on rather than thrown back, so it isn't added automatically; drag it in if you want it.

If WoW reports a bait as unusable where you are when you add it, you'll get a note. Ignore it if the bait works when you right-click it.

### Phial and Tea
Gathering consumables that are found in your bags automatically and kept up while you fish. Each group has an on/off checkbox and keeps **one** item up, picked in your order (set with the arrows). Untick an item to keep it listed but never use it. Drag an item onto **Phial** or **Tea** to add one the scan didn't recognize.

- **Phial:** gathering phials that give Finesse, Perception or Deftness, like the **Haranir Phial of Finesse** and **Haranir Phial of Perception**. Crafting phials and combat flasks are ignored. A phial replaces whatever flask or phial you have up, so while any other flask or phial is active the Phial group waits and its line says **Other Flask Up**. It never overwrites a raid flask.
- **Tea:** teas that make you **Relaxed** after 10 seconds of drinking, like **Argentleaf Tea** (Finesse and Speed), **Sanguithorn Tea** (Perception and Speed) and **Azeroot Tea** (Deftness and Speed). Teas don't stack, so one is used. After you drink, the key waits until Relaxed lands. If you stand up early, nothing is held against the tea and the next press drinks again. A tea that doesn't make you Relaxed after you sat for the full time is skipped; drag it onto **Tea** again to retry.

Up to 2 rows are shown per group. Extras are noted as "+N" on the group's line, and the item giving the buff is always kept on screen.

It isn't confirmed how much Finesse, Perception or Deftness affect fishing. Untick a group if you'd rather not spend them.

### Have and Keep
Every lure, phial, tea, fish and bait row shows **Have**, the number in your bags, and a **Keep** box. Once your stack is at or below its Keep number, that item stops being used and the next one in priority takes over. Keep is set per item; 0 uses them all. The count turns yellow when you're at your minimum.

### Status
Status is shown once per buff, not repeated on every row. The Lures line and each fish buff's line show the time left. A small arrow and a green name mark the item giving the buff right now. Item rows only show a word when something needs your attention:

| Status | Meaning |
|---|---|
| Not Owned | None in your bags (or the toy isn't learned) |
| At Minimum | At or below your Keep amount |
| Cooldown 12m | The item is on cooldown |
| Retry in 45s | It failed twice for no clear reason; it'll be tried again |
| No Buff Found | Using it gave no buff the addon can track |
| Other Zone | A lure or bait that only works somewhere else (e.g. the Eerie Lure off The Coiled Isle) |

Two more show on group lines only: **Other Flask Up** on Phial (another flask or phial is active, so none is used) and **Relaxing 6s** on Tea (you're drinking; the key waits).

### Footer
| Setting | Default | What it does |
|---|---|---|
| Auto-Sleep in Instances | On | Sleeps in dungeons, raids, battlegrounds and arenas, and wakes when you leave |
| Refresh Buffs Under | 21s | Renews a buff once it has less than this left. 21 seconds covers a full cast |
| Scan Inventory | | Looks through your bags again from scratch for lures, fish, baits, phials and teas, including items you removed this session |
| Sleep / Wake | | Turns the addon off or on |
| Reset Defaults | | Resets every setting and list (asks first) |
| Debug | Off | Explains each key press in chat |
| Minimap Button | On | Shows the minimap icon |

---

## Minimap Button

| Click | Action |
|---|---|
| Left-Click | Sleep or wake |
| Right-Click | Open settings |
| Middle-Click | Hide the button. Tick **Minimap Button** in the settings window to bring it back |
| Drag | Move it around the minimap |

The icon turns gray while the addon is asleep. Simply Fishing also appears in the minimap's addon menu.

## Sleep and Auto-Sleep

While asleep, the addon does no work and the fishing key does nothing. It only listens for logout and loading screens. Your own sound and loot settings are restored immediately.

**Auto-Sleep in Instances** puts it to sleep when you enter a dungeon, raid, battleground or arena, and wakes it when you leave, but only if it was awake when you went in. If you wake it by hand inside an instance, it stays awake until you leave that instance. Delves and other scenarios don't trigger it.

---

## Slash Commands

`/sfish` and `/simplyfishing` both work.

| Command | What it does |
|---|---|
| `/sfish` | Open or close the settings window |
| `/sfish status` | Print every setting, item and the next action to chat |
| `/sfish sleep` | Sleep or wake |
| `/sfish scan` | Like the Scan Inventory button, plus a report of every lure, fish, phial and tea it sees and why it was or wasn't added |
| `/sfish debug` | Turn debug messages on or off |
| `/sfish minimap` | Show or hide the minimap button |
| `/sfish timer <seconds>` | Set Refresh Buffs Under (0 to 600) |
| `/sfish reset` | Reset all settings and lists |

---

## Safety and Fair Play

- **One press, one action.** Simply Fishing never acts on its own. Every cast, reel and item use comes from you pressing the key, the same as clicking an action bar button.
- **No bite detection.** WoW gives addons no way to know when a fish bites. You still watch or listen for the splash and press the key yourself.
- **Combat safe.** When combat starts, the key switches to plain Fishing so a press mid-fight can't spend a lure or bait. Nothing else secure changes until combat ends.
- **Your settings are put back.** Every game setting the addon changes is saved first and restored on sleep, logout, or the next login after a crash.
- **No wasted items.** After an item is used, its group waits a moment for the buff to appear, so quick presses never spend two. An item that fails twice for no clear reason is skipped briefly, starting at 1 minute and doubling up to 10, then tried again. Nothing is ever marked unusable permanently.

---

## Troubleshooting

**The key fires twice per press.**
Turn on Debug and press once. If you see two "Cast sent" lines, open `Core.lua` and change `RegisterForClicks("AnyUp", "AnyDown")` to `RegisterForClicks("AnyDown")`.

**The key doesn't reel in.**
Make sure **Cast and Reel** is selected, and clear any selected NPC target, since a hard target can take priority over the bobber. With Debug on, "Soft target: an object (likely your bobber)" after casting means the bobber was found.

**A fish or lure isn't detected.**
Type `/sfish scan`. It re-checks your bags from scratch and says, for each lure or fish, whether it was added and if not, why: the list is full, its text hasn't loaded yet, or it wasn't recognized (with its Use text). Dragging the item onto the Lures or Other Baits slot always works too. Detection reads the item's description in English; on other client languages, drag fish onto the **Perception** or **Fishing Skill** name, or drag lures and baits onto their slots.

**An item says "No Buff Found".**
Using it didn't produce a buff the addon could track, so it's skipped. For lures and baits, remove it and add it again to retry. For fish, phials and teas, drag it onto its group's name again.

**The phial is never used.**
Check the Phial line. **Other Flask Up** means another flask or phial is active; a new phial would replace it, so the addon waits until it's gone.

**The key does nothing for a few seconds after a tea.**
That's on purpose: you need to stay seated for 10 seconds to become Relaxed. **Next Press** counts it down.

**Something else looks wrong.**
**Reset Defaults** in the footer starts clean. If you report a bug, include what `/sfish status` and `/sfish scan` print.

---

## Known Limitations

- Fish, lure, phial and tea detection by description only works on English clients. Other languages can drag items in by hand. Known phials and teas are recognized by ID on any language.
- The Relaxed buff is found by its English name until your first tea teaches the addon its ID, and the "other flask" check reads flask and phial names in English.
- Guides disagree on how much Perception affects fishing. Fishing Skill is the safer buff if you only want one.
- The minimap button uses a round-minimap layout and may sit slightly off on square minimap skins.

---

## Changelog

### 1.1.0
- New **Phial and Tea** section: gathering phials and Relaxed teas in your bags are found and kept up automatically, with Have, Keep, ticks and order arrows.
- The key waits while you drink a tea so casting doesn't stand you up before Relaxed lands.
- A phial is never used while another flask or phial is up, so it can't overwrite a raid flask.
- Phials or teas added to Lures or Other Baits in 1.0 are moved to their new group.
- Fish, phials and teas marked "No Buff Found" can be retried by dragging them onto their group's name again.
- The settings window is a little wider to fit the new section.

### 1.0.0
- Initial release.
