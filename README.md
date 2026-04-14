# DGate Autohunter

A modular Lua autohunting system for [Dragon's Gate](https://www.dragongate.com/) running in [Mudlet](https://www.mudlet.org/).

Handles scan-based target detection, mob prioritization, intelligent movement, and a full sustain system — healing, tactical retreat, emergency flee, safe room navigation, sleep recovery, and vigor support.

---

## Features

- Melee and spell-based hunting modes
- Scan-based target detection with PC avoidance
- Priority target list (configurable per zone)
- **Sustain system:**
  - Sit and heal between kills when HP is low
  - Tactical retreat (2 rooms) and heal at 35% HP mid-combat
  - Emergency flee to safe room at 25% HP (optional sound alert)
  - Fatigue-based sleep at configurable threshold, with auto-wake and return
  - Vigor spell support for fatigue recovery between kills and mid-combat
- Zone navigation: flee through a gate/portal to the city side, recover, return
- Death detection: auto-depart and first aid on resurrection
- Watchdog timer to recover from stuck states
- Debug logging mode

---

## Files

| File | Purpose |
|------|---------|
| `dgate_combat_core.lua` | Target tracking, attack abstraction, vital signs |
| `dgate_combat_melee.lua` | Physical weapon attacks |
| `dgate_combat_spells.lua` | Spell-based attacks with vigor support |
| `dgate_autohunt.lua` | Main hunting loop, movement, sustain, zone nav |
| `dgate_first_aid.lua` | First aid aliases and trigger documentation |
| `dgate_init.lua` | Login trigger, setme alias, session logging |

**Load order matters.** Scripts must be loaded top-to-bottom in this sequence in Mudlet's script editor:

```
1. dgate_combat_core.lua
2. dgate_combat_melee.lua
3. dgate_combat_spells.lua   (optional — spell hunting only)
4. dgate_autohunt.lua
5. dgate_first_aid.lua
6. dgate_init.lua
```

---

## Installation

1. In Mudlet, open the **Script Editor** (Alt+E)
2. Create a new script for each file above, in order
3. Paste the contents of each `.lua` file into the corresponding script
4. Save (Ctrl+S)
5. Create all aliases and triggers as documented in each file's `SETUP` section

Each script file contains a complete `SETUP` block at the bottom with copy-pasteable alias patterns, trigger patterns, and scripts. You do not need to read through the code to set it up — just follow the setup blocks in order.

---

## Configuration

All user-configurable settings are at the top of `dgate_autohunt.lua` and `dgate_combat_spells.lua`. You do not need to edit anything else.

### Zone setup (`dgate_autohunt.lua`)

Tell the hunter how to flee to safety and return:

```lua
dg.hunt.zones = {
  myzone = {
    safeRoomName     = "Outside the Gate to Somewhere",  -- room inside the zone at the exit
    safeRoomExit     = "go gate",                         -- command to exit the zone
    recoverRoomName  = "City Side - Outside the Gate",    -- room on the city side
    recoverRoomExit  = "go gate",                         -- command to re-enter the zone
    fleeDirections   = {"south", "southeast", "east"},    -- directions toward the exit
    returnDirections = {"north", "northwest", "west"},    -- directions toward the city side
  },
}

dg.hunt.currentZone = "myzone"
```

Room names come from the header line Mudlet shows when you enter a room:
`[Zone - Area - Room Name.]` — the room name is everything after the last ` - `.

### Sustain thresholds (`dgate_autohunt.lua`)

```lua
dg.hunt.thresholds = {
  sitHeal         = 0.45,   -- sit and heal between kills at this HP%
  tacticalRetreat = 0.35,   -- retreat 2 rooms and heal at this HP% (mid-combat)
  flee            = 0.25,   -- emergency flee at this HP%
  sleep           = 0.15,   -- flee and sleep when fatigue drops to this %
  wakeAt          = 0.90,   -- wake up when fatigue recovers to this %
  vigorBetweenKills = 0.37, -- cast vigor between kills below this fatigue %
  vigorMidCombat  = 0.12,   -- cast vigor mid-combat if target is pale/ashen
}
```

### Target priority (`dgate_autohunt.lua`)

```lua
dg.hunt.priorityList = {
  "skeleton",
  "zombie",
  "wight",
  "ghoul",
  -- add more mob keywords here, highest priority first
}
```

Names are matched against the last word of the mob's short name. `"shambling skeleton"` matches `"skeleton"`. Multi-word names containing `"of"` are kept whole (`"bag of bones"` → `"bag"`).

### Spell configuration (`dgate_combat_spells.lua`)

Add one entry per caster character. The key must exactly match the character name as it appears on login:

```lua
dg.combat.spell.chars = {
  YourCharacter = {
    invokeWord = "ftouch",   -- first word of your attack spell invoke
    vigorWord  = "fvig",     -- first word of your vigor spell (optional)
    weapon     = "sword",    -- weapon to remove if armed when casting
  },
}
```

If your character has no vigor spell, omit `vigorWord`.

### Emergency sound (`dgate_autohunt.lua`)

```lua
dg.hunt.emergencySound = "C:\\Users\\YourName\\AppData\\Local\\Mudlet\\alert.mp3"
-- set to nil to disable
```

---

## Commands

| Command | Action |
|---------|--------|
| `hunt` | Start hunting with melee |
| `hunt spell` | Start hunting with configured spell |
| `hunt stop` | Stop immediately |
| `hunt finish` | Stop after current kill is looted |
| `kt <target>` | Attack a specific target with melee |
| `fa <target>` | Apply first aid to a target |
| `fame` | Apply first aid to yourself |
| `fatrain on\|off` | Toggle first aid training loop |
| `setme <name>` | Set active character (called automatically on login) |

---

## Sustain System

The hunter monitors HP and fatigue on every prompt and responds automatically:

```
HP at 45% (between kills)  →  sit, apply first aid, resume
HP at 35% (mid-combat)     →  quit combat, retreat 2 rooms, sit, heal, resume in place
HP at 25% (any time)       →  emergency flee to safe room, heal/sleep, STOP (review before resuming)
Fatigue at 37% (vigor)     →  cast vigor between kills (if vigor spell configured)
Fatigue at 15%             →  flee to safe room, sleep until 90% fatigue, return to zone
```

Emergency flee plays an optional sound and stops the hunter after recovery so you can assess the situation before resuming.

---

## Per-Character Spell Hit Lines

Some DGate spell types produce a unique hit line rather than (or in addition to) the standard `You invoke .+ at .+!` line. If your spell does this, add a trigger for that line and call `dg.combat.spell.onSpellResolved()` from it.

Examples:
- Dragon Dart: `^Dragon Dart strikes .+!$`
- Resist: `^.+ resists your spell!$`

---

## Adding Mob Death Patterns

Different mob types have different death messages. Expand the kill trigger pattern as you encounter new ones:

```
^.+ (?:collapses into a pile of bones
     |staggers, then falls apart in a crash of bone
     |unravels into mist, the last trace of its presence slipping into silence
     |YOUR NEW PATTERN HERE
     )\.$
```

---

## Debug Mode

Set `dg.hunt.debug = true` in `dgate_autohunt.lua` to enable detailed logging of every decision the hunter makes. Useful for diagnosing unexpected behaviour. Set to `false` for normal use.

---

## Compatibility

- Tested on Dragon's Gate (DGate Reborn)
- Requires Mudlet 4.x or later
- No external packages required

---

## Roadmap

- v6.0: Pickpocket hunting mode
- Highlight/arrivals window integration (separate release)
- Multi-zone support improvements

---

## License

Do whatever you want with this. If you improve it, sharing back with the DGate community on Discord would be appreciated.
