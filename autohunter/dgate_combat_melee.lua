-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE MELEE COMBAT
-- dgate_combat_melee.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 1.0
-- REQUIRES: dgate_combat_core.lua (load first)
-- PURPOSE:  Physical weapon attacks
--
-- Usage:
--   kt <target>   start attacking with melee
--   hunt          start the autohunter in melee mode
-- ═══════════════════════════════════════════════════════════════════════════

dg = dg or {}
dg.combat = dg.combat or {}
dg.combat.melee = dg.combat.melee or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- MELEE ATTACK
-- ═══════════════════════════════════════════════════════════════════════════

function dg.combat.melee.attack()
  if not dg.combat.target then
    cecho("<red>No target set<reset>\n")
    return
  end
  send("k " .. dg.combat.target)
end

function dg.combat.melee.start(target)
  return dg.combat.startAttack(target, dg.combat.melee.attack)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate Melee Combat v1.0 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  kt <target>  -- start melee attack\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
REQUIRED ALIAS
═══════════════════════════════════════════════════════════════════════════

  Alias name:  kt (kill target)
  Pattern:     ^kt (.+)$
  Type:        perl regex
  Script:
    dg.combat.melee.start(matches[2])

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGER
═══════════════════════════════════════════════════════════════════════════

This trigger fires after each swing completes and sends the next attack.
Use ONLY this trigger when using the autohunter — the hunt-aware version
below handles the inCombat() check so attacks don't queue up after a kill.

  Trigger name:  melee swing complete
  Pattern:       ^You swing .+ at .+!$
  Type:          perl regex
  Script:
    if dg.combat.inCombat() then
      dg.combat.continueAttack()
    end

Note: This pattern fires on every swing attempt regardless of hit or miss.
The delay between swings varies with your character's skill level.

--]]
