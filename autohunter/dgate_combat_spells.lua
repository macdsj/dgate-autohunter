-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE SPELL COMBAT MODULE
-- dgate_combat_spells.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 1.4
-- REQUIRES: dgate_combat_core.lua (load first)
-- PURPOSE:  Spell-based combat for caster characters
--
-- Works alongside dgate_combat_melee.lua — load both, use one at a time.
--
-- SPELL LOOP:
--   attack(target) sends the invoke command and marks combat active.
--   onSpellResolved() is called by the spell resolution trigger and sends
--   the next invoke — same pattern as the melee swing trigger.
--
-- WEAPON REMOVAL:
--   If the game returns the "cannot have anything in your hands" error,
--   onWeaponError() removes the weapon and retries. Weapon name is
--   configured per character in dg.combat.spell.chars below.
--
-- VIGOR (fatigue recovery spell):
--   Cast between kills when fatigue drops below vigorBetweenKills threshold.
--   Cast mid-combat when fatigue is critical AND target is pale or ashen.
--   Characters without vigorWord fall back to normal flee behavior.
--   Vigor resolution fires the same ^You invoke .+ at .+!$ trigger —
--   the hunt script detects isHealingInPlace to know it was a vigor cast.
--
-- DIAG INSTRUMENTATION:
--   After every successful spell hit, sends diag on current target.
--   Result stored in dg.combat.spell.lastCondition for vigor decisions.
--   Condition scale: healthy → weakened → pale → ashen → dead
--   Disable by setting dg.combat.spell.diagEnabled = false
-- ═══════════════════════════════════════════════════════════════════════════

dg = dg or {}
dg.combat = dg.combat or {}
dg.combat.spell = dg.combat.spell or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CHARACTER SPELL CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Add one entry per caster character. dg.me is set by the setme alias
-- on login and determines which config is active.
--
-- invokeWord  — the first word of your attack spell, e.g. for
--               "invoke ftouch <target>", invokeWord = "ftouch"
-- vigorWord   — first word of your fatigue-recovery spell (optional).
--               omit or set to nil if your character has no vigor spell.
-- weapon      — weapon to remove if you are accidentally armed when casting.

dg.combat.spell.chars = {
  -- Replace these example entries with your own characters.
  -- The key must exactly match the name dg.me is set to on login.

  PeanutHamper = {
    invokeWord = "ftouch",   -- e.g. "invoke ftouch <target>"
    vigorWord  = "fvig",     -- e.g. "invoke fvig <self>" — omit if no vigor
    weapon     = "sword",    -- remove this weapon if equipped when casting
  },

  Agimus = {
    invokeWord = "dart",
    vigorWord  = "vig",
    weapon     = "sword",
  },

  -- Add more characters here:
  -- YourCharacter = {
  --   invokeWord = "...",
  --   vigorWord  = "...",   -- optional
  --   weapon     = "...",
  -- },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

dg.combat.spell.weaponRemoved  = false  -- tracks if weapon was removed this session
dg.combat.spell.diagEnabled    = true   -- send diag after each hit for condition data
dg.combat.spell.lastCondition  = nil    -- last diag result: healthy/weakened/pale/ashen

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.combat.spell.getConfig()
  local name = dg.me or ""
  return dg.combat.spell.chars[name]
end

function dg.combat.spell.buildInvoke(target)
  local cfg = dg.combat.spell.getConfig()
  if not cfg then
    cecho("<red>[SPELL] No spell config for character: " .. (dg.me or "?") ..
          " — add an entry to dg.combat.spell.chars in dgate_combat_spells.lua<reset>\n")
    return nil
  end
  return "invoke " .. cfg.invokeWord .. " " .. target
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ATTACK FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.combat.spell.attack(target)
  local t = target or dg.combat.target
  if not t or t == "" then return end

  local cmd = dg.combat.spell.buildInvoke(t)
  if not cmd then return end

  dg.combat.active = true
  dg.combat.target = t
  send(cmd)
end

function dg.combat.spell.continueAttack()
  if not dg.combat.inCombat() then return end
  if not dg.combat.target then return end

  local cmd = dg.combat.spell.buildInvoke(dg.combat.target)
  if not cmd then return end

  send(cmd)
end

function dg.combat.spell.stopAttack()
  dg.combat.active = false
  dg.combat.target = nil
  dg.combat.spell.weaponRemoved = false
  dg.combat.spell.lastCondition = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGER HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Fires when a spell resolves with an invoke confirmation line
-- (hit, resist, or surge). Also fires when vigor resolves —
-- the hunt module detects isHealingInPlace and handles that case.
function dg.combat.spell.onSpellResolved()
  if not dg.combat.inCombat() then return end

  -- If the hunt module is running a between-kills vigor cast, hand control back
  if dg.hunt and dg.hunt.isHealingInPlace then
    dg.hunt.debugLog("Spell resolved during isHealingInPlace — vigor cast complete")
    dg.hunt.isHealing = false
    dg.hunt.isHealingInPlace = false
    cecho("<green>*** VIGOR CAST COMPLETE - RESUMING HUNT ***<reset>\n")
    dg.hunt.scanForTargets()
    return
  end

  -- Send diag for condition data and vigor decisions before next cast
  if dg.combat.spell.diagEnabled and dg.combat.target then
    send("diag " .. dg.combat.target)
  end

  dg.combat.spell.continueAttack()
end

-- Fires when a spell fails without producing an invoke line
-- (fizzle, backfire, shatter). Just retry immediately.
function dg.combat.spell.onSpellFailed()
  if not dg.combat.inCombat() then return end
  dg.combat.spell.continueAttack()
end

-- Fires when the target leaves the room mid-cast
function dg.combat.spell.onTargetGone()
  dg.combat.active = false
  dg.combat.target = nil
  dg.combat.spell.lastCondition = nil
  if dg.hunt and dg.hunt.active then
    dg.hunt.debugLog("Spell target departed, rescanning")
    dg.hunt.scanForTargets()
  end
end

-- Fires when out of runes — flee to safe room and stop after recovery
function dg.combat.spell.onNoRunes()
  if not dg.hunt or not dg.hunt.active then return end
  dg.combat.active = false
  dg.combat.target = nil
  cecho("<red>*** OUT OF RUNES - FLEEING TO SAFE ROOM ***<reset>\n")
  dg.hunt.outOfRunes = true
  dg.hunt.fleeToSafeRoom()
end

-- Fires when a weapon is equipped and blocks casting
function dg.combat.spell.onWeaponError()
  if not dg.combat.inCombat() then return end

  local cfg = dg.combat.spell.getConfig()
  if not cfg then return end

  if not dg.combat.spell.weaponRemoved then
    dg.combat.spell.weaponRemoved = true
    cecho("<yellow>[SPELL] Removing weapon: rem " .. cfg.weapon .. "<reset>\n")
    send("rem " .. cfg.weapon)
    tempTimer(0.5, function()
      if dg.combat.inCombat() then
        dg.combat.spell.continueAttack()
      end
    end)
  end
end

-- Fires on diag result lines — extracts condition word for vigor decisions
function dg.combat.spell.onDiagResult(line)
  if not line then return end
  local condition = line:match("^%s+(.+)$") or line

  local condWord = nil
  if     condition:find("ashen")    then condWord = "ashen"
  elseif condition:find("pale")     then condWord = "pale"
  elseif condition:find("weakened") then condWord = "weakened"
  elseif condition:find("no apparent injuries") and not condition:find("but looks") then
    condWord = "healthy"
  end

  dg.combat.spell.lastCondition = condWord
  cecho("<dim_grey>[DIAG] " .. (dg.combat.target or "?") .. ": " ..
    (condWord or condition) .. "<reset>\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate Spell Combat Module v1.4 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  hunt spell  -- start autohunter in spell mode\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
SETUP: CHARACTER CONFIGURATION
═══════════════════════════════════════════════════════════════════════════

Edit the dg.combat.spell.chars table near the top of this file.
Add one entry per caster character you want to use with this module.

The key must exactly match what the setme alias sets dg.me to — which
is your character's login name as it appears in "Logging in as <name>!".

Example:
  Myfighter = {
    invokeWord = "ftouch",   -- first word of "invoke ftouch <target>"
    vigorWord  = "fvig",     -- first word of "invoke fvig <self>" (optional)
    weapon     = "sword",    -- weapon to remove if armed when casting
  },

If your character has no vigor spell, omit vigorWord entirely or set nil.

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGERS — add all of these in Mudlet
═══════════════════════════════════════════════════════════════════════════

1. Spell resolved (hit, resist, or surge — all produce an invoke line):
   Name:    spell fired
   Pattern: ^You invoke .+ at .+!$
   Type:    perl regex
   Script:  dg.combat.spell.onSpellResolved()

2. Spell fizzled (no invoke line produced):
   Name:    spell fizzle
   Pattern: ^Your spell fizzles!$
   Type:    perl regex
   Script:  dg.combat.spell.onSpellFailed()

3. Spell backfired:
   Name:    spell backfire
   Pattern: ^The runes spiral out of control
   Type:    perl regex
   Script:  dg.combat.spell.onSpellFailed()

4. Spell shattered:
   Name:    spell shatter
   Pattern: ^The runes shatter violently and the spell collapses!$
   Type:    perl regex
   Script:  dg.combat.spell.onSpellFailed()

5. Target left room mid-cast:
   Name:    spell target gone
   Pattern: ^The runes gather but .+ has departed!
   Type:    perl regex
   Script:  dg.combat.spell.onTargetGone()

6. Out of runes:
   Name:    out of runes
   Pattern: ^You don't have enough .+ weaves to cast this spell!
   Type:    perl regex
   Script:  dg.combat.spell.onNoRunes()

7. Weapon equipped when trying to cast:
   Name:    oops i'm armed
   Pattern: ^You cannot have anything in your hands but a torch when spellcasting!$
   Type:    perl regex (can also be plain substring)
   Script:  dg.combat.spell.onWeaponError()

8. Diag result (condition data for vigor decisions):
   Name:    diag result
   Pattern: ^\s+They .+\.$
   Type:    perl regex
   Script:  dg.combat.spell.onDiagResult(matches[0])

═══════════════════════════════════════════════════════════════════════════
PER-CHARACTER SPELL HIT LINES
═══════════════════════════════════════════════════════════════════════════

Some spell types produce a unique hit line instead of (or in addition to)
the standard "You invoke .+" line. If your spell does this, add a trigger
for that line and call dg.combat.spell.onSpellResolved() from it.

Example — Dragon Dart produces: ^Dragon Dart strikes .+!$
Example — a resist produces:    ^.+ resists your spell!$

Both of these are already included in the trigger list above as "ddart fired"
and "resists" respectively if you are using the triggers from the XML export.

--]]
