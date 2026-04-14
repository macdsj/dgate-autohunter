-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE COMBAT CORE
-- dgate_combat_core.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 1.0
-- PURPOSE: Central combat management for all attack types
--
-- Load order: this file first, then dgate_combat_melee.lua and/or
-- dgate_combat_spells.lua, then dgate_autohunt.lua
--
-- This module provides:
--   - Target tracking (dg.combat.target)
--   - Attack method abstraction (melee or spell, swappable at runtime)
--   - Vital sign tracking (HP and fatigue from prompt)
--   - Coordination between hunting and combat modules
-- ═══════════════════════════════════════════════════════════════════════════

dg = dg or {}
dg.combat = dg.combat or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

dg.combat.target     = nil    -- current attack target
dg.combat.attackMethod = nil  -- function: executes one attack cycle
dg.combat.active     = false  -- true while attacking

-- Vitals — updated every prompt by the autohunter's onPrompt handler.
-- hp/maxHp are set by the hunt module; health/maxHealth by updateVitals().
-- Both paths are kept so the core works standalone or under the hunter.
dg.combat.vitals = {
  health    = 0,
  maxHealth = 0,
  fatigue   = 0,
  maxFatigue = 0,
  hp        = 0,
  maxHp     = 0,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.combat.setTarget(target)
  dg.combat.target = target
  cecho("<cyan>*** TARGET SET: " .. target .. " ***<reset>\n")
end

function dg.combat.clearTarget()
  if dg.combat.target then
    cecho("<dim_grey>*** TARGET CLEARED: " .. dg.combat.target .. " ***<reset>\n")
  end
  dg.combat.target = nil
  dg.combat.active = false
end

function dg.combat.startAttack(target, attackMethod)
  if not target or target == "" then
    cecho("<red>Error: No target specified<reset>\n")
    return false
  end
  if not attackMethod then
    cecho("<red>Error: No attack method specified<reset>\n")
    return false
  end

  dg.combat.setTarget(target)
  dg.combat.attackMethod = attackMethod
  dg.combat.active = true

  cecho("<green>*** ATTACKING: " .. target .. " ***<reset>\n")
  attackMethod()
  return true
end

function dg.combat.continueAttack()
  if not dg.combat.active then return end
  if not dg.combat.target then return end
  if not dg.combat.attackMethod then return end
  dg.combat.attackMethod()
end

function dg.combat.stopAttack()
  dg.combat.active = false
  dg.combat.clearTarget()
end

-- Called by the update vitals trigger (standalone use without hunt module)
function dg.combat.updateVitals(health, maxHealth, fatigue, maxFatigue)
  dg.combat.vitals.health    = tonumber(health)    or 0
  dg.combat.vitals.maxHealth = tonumber(maxHealth) or 0
  dg.combat.vitals.fatigue   = tonumber(fatigue)   or 0
  dg.combat.vitals.maxFatigue = tonumber(maxFatigue) or 0
end

function dg.combat.inCombat()
  return dg.combat.active and dg.combat.target ~= nil
end

function dg.combat.getFatiguePercent()
  if dg.combat.vitals.maxFatigue == 0 then return 0 end
  return (dg.combat.vitals.fatigue / dg.combat.vitals.maxFatigue) * 100
end

function dg.combat.status()
  echo("\n=== COMBAT CORE STATUS ===\n")
  if dg.combat.active then
    cecho("<green>ACTIVE<reset>\n")
  else
    cecho("<red>INACTIVE<reset>\n")
  end
  echo("Target: " .. (dg.combat.target or "none") .. "\n")
  echo("Attack method: " .. (dg.combat.attackMethod and "configured" or "none") .. "\n")
  echo(string.format("Fatigue: %d/%d (%.1f%%)\n",
    dg.combat.vitals.fatigue,
    dg.combat.vitals.maxFatigue,
    dg.combat.getFatiguePercent()))
  echo("\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate Combat Core v1.0 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  lua dg.combat.status()  -- show combat status\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGER
═══════════════════════════════════════════════════════════════════════════

This trigger keeps the combat core aware of your HP and fatigue. It is
required for the autohunter's sustain system to function.

  Trigger name:  update vitals
  Pattern:       ^\[Health: (\d+)/(\d+) - Fatigue: (\d+)/(\d+)\]
  Type:          perl regex
  Script:
    dg.combat.updateVitals(matches[2], matches[3], matches[4], matches[5])

Note: if you are using the autohunter, the hunt module's onPrompt() handler
also updates vitals — you only need one of the two triggers, not both.
The autohunter's prompt trigger is listed in dgate_autohunt.lua.

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGER (continued)
═══════════════════════════════════════════════════════════════════════════

  Trigger name:  target died or missing
  Pattern:       ^That target does not exist\.$
  Type:          perl regex
  Script:
    if dg.combat.inCombat() then
      dg.combat.clearTarget()
    end

--]]
