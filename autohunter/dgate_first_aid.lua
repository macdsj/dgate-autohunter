-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE FIRST AID MODULE
-- dgate_first_aid.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 1.0
-- PURPOSE: First aid automation — manual use and autohunter sustain
--
-- This module handles:
--   fa <target>       — apply first aid to a target (including yourself)
--   fame              — apply first aid to yourself (uses dg.me)
--   fatrain on|off    — toggle training mode (loops first aid continuously)
--
-- The autohunter calls expandAlias("fame") directly, so this module must
-- be loaded for the sustain system to work.
--
-- GLOBAL VARIABLES used by this module:
--   fa_target    (string)  — current first aid target
--   fa_training  (boolean) — whether training mode is active
--   me           (string)  — your character name (set by setme alias)
-- ═══════════════════════════════════════════════════════════════════════════

-- Initialise globals if not already set
fa_target   = fa_target   or ""
fa_training = fa_training or false

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate First Aid Module v1.0 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  fa <target>       -- apply first aid to target\n")
echo("  fame              -- apply first aid to yourself\n")
echo("  fatrain on|off    -- toggle training mode\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
REQUIRED ALIASES — create these in Mudlet
═══════════════════════════════════════════════════════════════════════════

ALIAS: First Aid
─────────────────────────────────────────────────────────────────────────
  Name:    First Aid
  Pattern: ^fa (.+)$
  Type:    perl regex
  Script:
    fa_target = matches[2]
    send("firstaid " .. fa_target)

ALIAS: Fame (first aid me)
─────────────────────────────────────────────────────────────────────────
  Name:    Fame
  Pattern: ^fame$
  Type:    perl regex
  Script:
    if me and me ~= "" then
      fa_target = me
      send("firstaid " .. me)
    else
      cecho("\n<red>No character set. Use 'setme <name>' first.<reset>\n")
    end

ALIAS: fatrain
─────────────────────────────────────────────────────────────────────────
  Name:    fatrain
  Pattern: ^fatrain (on|off)$
  Type:    perl regex
  Script:
    if matches[2] == "on" then
      fa_training = true
      cecho("\n<green>FA training mode ON.<reset>\n")
    else
      fa_training = false
      cecho("\n<red>FA training mode OFF.<reset>\n")
    end

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGERS — create these in Mudlet
═══════════════════════════════════════════════════════════════════════════

TRIGGER: first aid (loop while wounds remain)
─────────────────────────────────────────────────────────────────────────
  Name:    first aid
  Patterns (add both, both perl regex):
    1. ^You begin applying first aid to your wounds\.\.\.$
    2. ^You begin applying first aid to (\w+)'s wounds\.\.\.$
  Script:
    if fa_target and fa_target ~= "" then
      send("firstaid " .. fa_target)
    end

  Note: This fires when first aid begins and immediately queues the next
  application, creating a loop until the target is fully healed.

TRIGGER: stop (first aid complete or blocked)
─────────────────────────────────────────────────────────────────────────
  Name:    stop
  Patterns (add all three, all perl regex):
    1. ^You do not require first aid right now\.$
    2. ^.+ must be sitting or lying down to receive first aid\.$
    3. ^(\w+) does not require first aid right now\.$
  Script:
    if line:find("must be sitting or lying down") then
      fa_target = ""
      fa_training = false
      cecho("\n<red>First aid stopped: target must be sitting or lying down.<reset>\n")
    elseif fa_training then
      send("firstaid " .. fa_target)
    elseif dg.hunt and dg.hunt.active then
      fa_target = ""
      dg.hunt.onFirstAidDone()
    else
      fa_target = ""
      send("stand")
    end

  Note: When the autohunter is running, the "no first aid required" line
  signals that healing is complete and the hunter should resume. This
  trigger calls dg.hunt.onFirstAidDone() to hand control back.

TRIGGER: autofame (re-apply during training mode)
─────────────────────────────────────────────────────────────────────────
  Name:    autofame
  Pattern: You take   (plain substring, not regex)
  Script:
    if fa_training and me and me ~= "" then
      expandAlias("fame")
    end

  Note: The "You take" line fires when you receive coins or items. During
  training mode this re-triggers the loop. Disable fatrain when not
  actively training first aid to avoid unexpected behaviour.

═══════════════════════════════════════════════════════════════════════════
HOW THE AUTOHUNTER USES FIRST AID
═══════════════════════════════════════════════════════════════════════════

The autohunter calls expandAlias("fame") to start first aid. The loop
above handles repeated application. When the "no first aid required"
trigger fires, dg.hunt.onFirstAidDone() is called, which stands up and
resumes hunting. No manual intervention is needed.

For the sustain system to work:
  1. This module must be loaded (the script above sets the globals)
  2. The Fame alias must be created
  3. The "stop" trigger must be created with the dg.hunt.onFirstAidDone()
     call in it (as shown above)

--]]
