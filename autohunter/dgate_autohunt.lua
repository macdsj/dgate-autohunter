-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE AUTO-HUNTING SYSTEM
-- dgate_autohunt.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 5.2
-- REQUIRES: dgate_combat_core.lua, dgate_combat_melee.lua
-- OPTIONAL: dgate_combat_spells.lua  (for "hunt spell")
-- OPTIONAL: dgate_first_aid.lua      (required for sustain / healing)
--
-- COMMANDS:
--   hunt            start hunting with melee
--   hunt spell      start hunting with your configured spell
--   hunt stop       stop immediately
--   hunt finish     stop after the current kill is looted
--
-- FEATURES:
--   Scan-based target detection with PC avoidance
--   Intelligent movement toward nearby targets
--   Priority target list (configurable below)
--   Sustain: sit + first aid between kills when HP low
--   Sustain: tactical retreat 2 rooms + heal at 35% HP mid-combat
--   Sustain: flee to safe room + sleep when fatigue critical
--   Sustain: emergency flee at 25% HP (sound alert, stops after recovery)
--   Vigor support: fatigue top-off between kills and mid-combat
--   Death detection: auto-depart and first aid on resurrection
--   Zone navigation: flee out and return through a gate/portal
--
-- CHANGELOG:
--   v5.2 — kill-during-flee race condition fix; isHealingInPlace flag for
--           between-kills healing; vigor support; crypt wraith kill pattern
--   v5.1 — spell hunting via dgate_combat_spells.lua; hunt spell alias
--   v4.1.x — full sustain system: tactical retreat, emergency flee,
--             safe room recovery, return navigation, sleep recovery
-- ═══════════════════════════════════════════════════════════════════════════

dg       = dg       or {}
dg.hunt  = dg.hunt  or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE  (do not edit these — they are managed at runtime)
-- ═══════════════════════════════════════════════════════════════════════════

dg.hunt.active        = false
dg.hunt.attackMethod  = nil
dg.hunt.justKilled    = false

dg.hunt.availableTargets    = {}
dg.hunt.nearbyTargets       = {}
dg.hunt.pcInRoom            = false
dg.hunt.forbiddenDirections = {}

dg.hunt.availableExits = {}
dg.hunt.failedMoves    = 0
dg.hunt.isMoving       = false

dg.hunt.isHealing        = false
dg.hunt.isHealingInPlace = false
dg.hunt.isSleeping       = false
dg.hunt.isFleeing        = false
dg.hunt.isReturning      = false
dg.hunt.isRecovering     = false
dg.hunt.emergencyFlee    = false
dg.hunt.outOfRunes       = false
dg.hunt.isTacticalRetreat    = false
dg.hunt.tacticalRetreatSteps = 0
dg.hunt.tacticalRetreatDir1  = nil
dg.hunt.currentRoom          = nil

dg.hunt.watchdogTimer      = nil
dg.hunt.sleepRecoveryTimer = nil
dg.hunt.fleeStepTimer      = nil

dg.hunt.stopAfterKill  = false
dg.hunt.lastScanTime   = 0
dg.hunt.scanThrottle   = 2.0
dg.hunt.lastActionTime = 0

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE CONFIGURATION  ← EDIT THIS FOR YOUR HUNTING AREA
-- ═══════════════════════════════════════════════════════════════════════════
-- Configure one zone entry per hunting area. The autohunter uses room names
-- from the "[Zone - Room Name.]" header line to navigate.
--
-- safeRoomName    — the room name of the gate/portal room inside the zone
--                   (the last room before the exit to the city)
-- safeRoomExit    — command to exit the zone from that room (e.g. "go gate")
-- recoverRoomName — room name on the CITY side of that gate
-- recoverRoomExit — command to re-enter the zone from the city side
-- fleeDirections  — priority list of directions to move when fleeing out
-- returnDirections — priority list of directions to move when returning in

dg.hunt.zones = {
  -- Example zone: an undead graveyard accessible through a gate.
  -- Replace these room names with the actual room names in your hunting area.
  -- Room names come from lines like: [Spur - Ironward - An Accursed Cemetery.]
  -- The name is everything after the last " - " and before the period.

  graveyard = {
    safeRoomName     = "Outside the Gate to Ironward North",
    safeRoomExit     = "go gate",
    recoverRoomName  = "Ironward North - Outside the Gate to an Accursed Cemetery",
    recoverRoomExit  = "go gate",
    fleeDirections   = {"south", "southeast", "southwest", "east", "west"},
    returnDirections = {"north", "northwest", "northeast", "west", "east"},
  },

  -- Add more zones here as needed:
  -- myzone = {
  --   safeRoomName     = "...",
  --   safeRoomExit     = "go gate",
  --   recoverRoomName  = "...",
  --   recoverRoomExit  = "go gate",
  --   fleeDirections   = {"south", "east", "west"},
  --   returnDirections = {"north", "east", "west"},
  -- },
}

dg.hunt.currentZone = "graveyard"   -- ← set this to your active zone key

-- ═══════════════════════════════════════════════════════════════════════════
-- SUSTAIN THRESHOLDS  ← TUNE THESE PER CHARACTER
-- ═══════════════════════════════════════════════════════════════════════════
-- All values are fractions (0.0–1.0) of maximum HP or fatigue.
-- Example: 0.45 means "when at or below 45% of max".

dg.hunt.thresholds = {
  sitHeal         = 0.45,  -- sit and heal between kills at this HP%
  tacticalRetreat = 0.35,  -- retreat 2 rooms and heal at this HP% (mid-combat)
  flee            = 0.25,  -- emergency flee to safe room at this HP%
  sleep           = 0.15,  -- flee and sleep when fatigue drops to this %
  wakeAt          = 0.90,  -- wake up and return when fatigue recovers to this %
  vigorBetweenKills = 0.37, -- cast vigor between kills when fatigue below this %
  vigorMidCombat  = 0.12,  -- cast vigor mid-combat if target is pale or ashen
}

-- ═══════════════════════════════════════════════════════════════════════════
-- EMERGENCY FLEE SOUND  ← SET YOUR SOUND FILE PATH
-- ═══════════════════════════════════════════════════════════════════════════
-- This sound plays immediately when HP drops below the flee threshold.
-- Set to nil to disable, or replace with the full path to your sound file.
-- Windows example: "C:\\Users\\YourName\\AppData\\Local\\Mudlet\\alert.mp3"
-- Mac example:     "/Users/yourname/sounds/alert.mp3"

dg.hunt.emergencySound = nil   -- set to a file path string to enable

-- ═══════════════════════════════════════════════════════════════════════════
-- TARGET PRIORITY LIST  ← EDIT FOR YOUR ZONE
-- ═══════════════════════════════════════════════════════════════════════════
-- The hunter attacks mobs in this priority order. Names are matched against
-- the last word of the mob's short name (e.g. "shambling skeleton" → "skeleton").
-- Multi-word names containing "of" are kept whole ("bag of bones" → "bag").
-- If no priority match is found, any mob in the room is attacked.

dg.hunt.priorityList = {
  "skeleton",
  "zombie",
  "wight",
  "ghoul",
  "bag",
  -- Add more mob keywords here in priority order (highest first):
  -- "wraith",
  -- "specter",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEBUG MODE
-- ═══════════════════════════════════════════════════════════════════════════
-- Set to true to see detailed logging of every decision the hunter makes.
-- Useful for diagnosing problems. Set to false for normal use.

dg.hunt.debug = false

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.debugLog(message)
  if dg.hunt.debug then
    cecho("<dim_grey>[DEBUG] " .. message .. "<reset>\n")
  end
end

function dg.hunt.start(attackMethod)
  dg.hunt.debugLog("start() called")

  dg.combat.active = false
  dg.combat.target = nil
  dg.hunt.justKilled           = false
  dg.hunt.isMoving             = false
  dg.hunt.pcInRoom             = false
  dg.hunt.isHealing            = false
  dg.hunt.isHealingInPlace     = false
  dg.hunt.isSleeping           = false
  dg.hunt.isFleeing            = false
  dg.hunt.isReturning          = false
  dg.hunt.isRecovering         = false
  dg.hunt.emergencyFlee        = false
  dg.hunt.outOfRunes           = false
  dg.hunt.isTacticalRetreat    = false
  dg.hunt.tacticalRetreatSteps = 0
  dg.hunt.tacticalRetreatDir1  = nil

  dg.hunt.active        = true
  dg.hunt.lastActionTime = getEpoch()
  dg.hunt.attackMethod  = attackMethod or dg.combat.melee.attack

  cecho("<green>*** AUTO-HUNTING STARTED ***<reset>\n")
  cecho("<yellow>Scanning for targets...<reset>\n")

  dg.hunt.startWatchdog()
  dg.hunt.scanForTargets()
end

function dg.hunt.stop()
  dg.hunt.active           = false
  dg.hunt.isHealing        = false
  dg.hunt.isHealingInPlace = false
  dg.hunt.isSleeping       = false
  dg.hunt.isFleeing        = false
  dg.hunt.isReturning      = false
  dg.hunt.isRecovering     = false
  dg.hunt.emergencyFlee    = false
  dg.hunt.outOfRunes       = false
  dg.hunt.isTacticalRetreat    = false
  dg.hunt.tacticalRetreatSteps = 0
  dg.hunt.tacticalRetreatDir1  = nil
  dg.combat.stopAttack()

  if dg.hunt.watchdogTimer      then killTimer(dg.hunt.watchdogTimer);      dg.hunt.watchdogTimer      = nil end
  if dg.hunt.sleepRecoveryTimer then killTimer(dg.hunt.sleepRecoveryTimer); dg.hunt.sleepRecoveryTimer = nil end
  if dg.hunt.fleeStepTimer      then killTimer(dg.hunt.fleeStepTimer);      dg.hunt.fleeStepTimer      = nil end

  cecho("<red>*** AUTO-HUNTING STOPPED ***<reset>\n")
end

function dg.hunt.stopAfterNextKill()
  dg.hunt.stopAfterKill = true
  cecho("<yellow>*** Will stop after next kill ***<reset>\n")
end

function dg.hunt.recordAction()
  dg.hunt.lastActionTime = getEpoch()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DEATH HANDLING
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.onDeath()
  cecho("<red>*** DEAD - DEPARTING ***<reset>\n")
  dg.hunt.stop()
  send("die")
  tempTimer(11, function()
    expandAlias("fame")
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ROOM TRACKING
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.onRoomEntered(roomName)
  local cleanName = roomName:gsub("%.$", "")
  dg.hunt.currentRoom = cleanName
  dg.hunt.debugLog("Room entered: " .. cleanName)

  local zone = dg.hunt.zones[dg.hunt.currentZone]
  if not zone then return end

  if dg.hunt.isFleeing then
    if cleanName:find(zone.safeRoomName, 1, true) then
      dg.hunt.debugLog("Reached gate room while fleeing, going through")
      cecho("<green>*** SAFE ROOM EXIT FOUND - GOING THROUGH ***<reset>\n")
      dg.hunt.isFleeing    = false
      dg.hunt.isRecovering = true
      dg.hunt.isMoving     = false

      if dg.hunt.fleeStepTimer then killTimer(dg.hunt.fleeStepTimer); dg.hunt.fleeStepTimer = nil end

      send(zone.safeRoomExit)
      tempTimer(1.5, function()
        if not dg.hunt.active then return end
        if not dg.hunt.isRecovering then return end
        dg.hunt.safeRoomRecover()
      end)
    end
    return
  end

  if dg.hunt.isReturning then
    if zone.recoverRoomName and cleanName:find(zone.recoverRoomName, 1, true) then
      dg.hunt.debugLog("Reached recover room, going through gate")
      cecho("<green>*** ZONE ENTRY FOUND - GOING IN ***<reset>\n")
      dg.hunt.isReturning = false
      dg.hunt.isMoving    = false

      if dg.hunt.fleeStepTimer then killTimer(dg.hunt.fleeStepTimer); dg.hunt.fleeStepTimer = nil end

      send(zone.recoverRoomExit)
      tempTimer(1.5, function()
        if dg.hunt.active then dg.hunt.scanForTargets() end
      end)
    end
  end

  if dg.hunt.isTacticalRetreat and dg.hunt.tacticalRetreatSteps < 2 then
    dg.hunt.tacticalRetreatSteps = dg.hunt.tacticalRetreatSteps + 1
    dg.hunt.debugLog("Tactical retreat: moved to room " .. dg.hunt.tacticalRetreatSteps)
    tempTimer(0.5, function()
      if dg.hunt.isTacticalRetreat and dg.hunt.active then
        dg.hunt.tacticalRetreatStep()
      end
    end)
  end
end

function dg.hunt.safeRoomRecover()
  if not dg.hunt.isRecovering then return end
  dg.hunt.isRecovering = false

  local hpPct  = dg.combat.vitals.hp / dg.combat.vitals.maxHp
  local ftgPct = dg.combat.vitals.fatigue / dg.combat.vitals.maxFatigue

  dg.hunt.debugLog(string.format("Safe room recovery: %.0f%% HP, %.0f%% FTG", hpPct*100, ftgPct*100))

  if ftgPct <= dg.hunt.thresholds.sleep * 2 then
    cecho("<yellow>*** SLEEPING TO RECOVER ***<reset>\n")
    dg.hunt.isSleeping = true
    send("sleep")
    dg.hunt.checkSleepRecovery()
    return
  end

  if hpPct <= dg.hunt.thresholds.sitHeal then
    cecho("<yellow>*** SITTING TO HEAL ***<reset>\n")
    dg.hunt.isHealing = true
    send("sit")
    tempTimer(0.5, function() expandAlias("fame") end)
    return
  end

  if dg.hunt.emergencyFlee then
    cecho("<red>*** EMERGENCY FLEE RECOVERY COMPLETE ***<reset>\n")
    cecho("<red>*** REVIEW SITUATION BEFORE RESUMING ***<reset>\n")
    dg.hunt.stop()
    return
  end

  if dg.hunt.outOfRunes then
    cecho("<red>*** OUT OF RUNES - RECHARGE BEFORE RESUMING ***<reset>\n")
    dg.hunt.stop()
    return
  end

  dg.hunt.returnToZone()
end

function dg.hunt.returnToZone()
  if not dg.hunt.active then return end

  local zone = dg.hunt.zones[dg.hunt.currentZone]
  if not zone then
    cecho("<red>*** NO ZONE CONFIG - STOPPING ***<reset>\n")
    dg.hunt.stop()
    return
  end

  if zone.recoverRoomName and dg.hunt.currentRoom and
     dg.hunt.currentRoom:find(zone.recoverRoomName, 1, true) then
    dg.hunt.debugLog("In recover room, going through gate")
    cecho("<green>*** RETURNING TO ZONE ***<reset>\n")
    send(zone.recoverRoomExit)
    tempTimer(1.5, function()
      if dg.hunt.active then dg.hunt.scanForTargets() end
    end)
    return
  end

  dg.hunt.debugLog("Navigating to recover room")
  cecho("<yellow>*** NAVIGATING TO ZONE ENTRY ***<reset>\n")
  dg.hunt.isReturning = true
  send("look")
  tempTimer(0.5, function() dg.hunt.returnStep() end)
end

function dg.hunt.returnStep()
  if not dg.hunt.active or not dg.hunt.isReturning then return end

  if dg.hunt.fleeStepTimer then killTimer(dg.hunt.fleeStepTimer); dg.hunt.fleeStepTimer = nil end

  local zone = dg.hunt.zones[dg.hunt.currentZone]
  if not zone then return end

  local chosen = nil
  for _, dir in ipairs(zone.returnDirections) do
    for _, available in ipairs(dg.hunt.availableExits) do
      if available == dir then chosen = dir; break end
    end
    if chosen then break end
  end

  if not chosen then
    chosen = zone.returnDirections[1]
    dg.hunt.debugLog("No return exit found, trying: " .. chosen)
  else
    dg.hunt.debugLog("Return step: " .. chosen)
  end

  send(chosen)

  dg.hunt.fleeStepTimer = tempTimer(2.0, function()
    dg.hunt.fleeStepTimer = nil
    if dg.hunt.isReturning and dg.hunt.active then dg.hunt.returnStep() end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WATCHDOG
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.startWatchdog()
  if dg.hunt.watchdogTimer then killTimer(dg.hunt.watchdogTimer) end
  dg.hunt.watchdogTimer = tempTimer(5, function() dg.hunt.checkWatchdog() end, true)
end

function dg.hunt.checkWatchdog()
  if not dg.hunt.active then return end

  if dg.combat.inCombat() or dg.hunt.justKilled or dg.hunt.isMoving or
     dg.hunt.isHealing or dg.hunt.isSleeping or dg.hunt.isFleeing or
     dg.hunt.isReturning or dg.hunt.isRecovering or dg.hunt.isTacticalRetreat then
    dg.hunt.lastActionTime = getEpoch()
    return
  end

  local timeSince = getEpoch() - (dg.hunt.lastActionTime or 0)
  if timeSince > 15 then
    cecho("<yellow>*** WATCHDOG: No activity, restarting scan ***<reset>\n")
    dg.hunt.lastActionTime = getEpoch()
    dg.hunt.scanForTargets()
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROMPT PARSING
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.onPrompt(hp, maxHp, fatigue, maxFatigue)
  dg.combat.vitals.hp        = tonumber(hp)       or 0
  dg.combat.vitals.maxHp     = tonumber(maxHp)    or 0
  dg.combat.vitals.fatigue   = tonumber(fatigue)  or 0
  dg.combat.vitals.maxFatigue = tonumber(maxFatigue) or 0

  if not dg.hunt.active then return end
  if dg.hunt.isSleeping or dg.hunt.isFleeing or dg.hunt.isTacticalRetreat or
     dg.hunt.isHealing or dg.hunt.isReturning or dg.hunt.isRecovering then return end

  local hpPct  = dg.combat.vitals.hp / dg.combat.vitals.maxHp
  local ftgPct = dg.combat.vitals.fatigue / dg.combat.vitals.maxFatigue

  -- Fatigue critical: vigor if target is low, otherwise flee
  if ftgPct <= dg.hunt.thresholds.sleep then
    local cfg      = dg.combat.spell and dg.combat.spell.getConfig and dg.combat.spell.getConfig()
    local lastCond = dg.combat.spell and dg.combat.spell.lastCondition
    local targetLow = lastCond == "pale" or lastCond == "ashen"

    if dg.combat.inCombat() and cfg and cfg.vigorWord and targetLow then
      dg.hunt.debugLog(string.format("Fatigue critical (%.0f%%) but target is %s — casting vigor", ftgPct*100, lastCond))
      cecho("<yellow>*** FATIGUE CRITICAL - TARGET LOW - CASTING VIGOR ***<reset>\n")
      send("invoke " .. cfg.vigorWord .. " " .. (dg.me or ""))
      return
    end

    dg.hunt.debugLog(string.format("Fatigue critical (%.0f%%), fleeing", ftgPct*100))
    dg.hunt.fleeToSafeRoom()
    return
  end

  -- HP critical: emergency flee
  if hpPct <= dg.hunt.thresholds.flee then
    dg.hunt.debugLog(string.format("HP critical (%.0f%%), emergency flee", hpPct*100))
    dg.hunt.emergencyFlee = true
    if dg.hunt.emergencySound then
      playSoundFile(dg.hunt.emergencySound)
    end
    dg.hunt.fleeToSafeRoom()
    return
  end

  -- HP low mid-combat: tactical retreat
  if hpPct <= dg.hunt.thresholds.tacticalRetreat and dg.combat.inCombat() then
    dg.hunt.debugLog(string.format("HP low (%.0f%%), tactical retreat", hpPct*100))
    dg.hunt.startTacticalRetreat()
    return
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SUSTAIN
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.fleeToSafeRoom()
  if dg.hunt.isFleeing or dg.hunt.isSleeping then return end

  dg.hunt.isFleeing    = true
  dg.hunt.isHealing    = false
  dg.combat.active     = false
  dg.combat.target     = nil
  dg.hunt.isMoving     = false
  dg.hunt.justKilled   = false

  send("q c")
  cecho("<red>*** FLEEING TO SAFE ROOM ***<reset>\n")
  send("look")

  tempTimer(0.5, function() dg.hunt.fleeStep() end)
end

-- Direction exclusion map for tactical retreat step 2.
-- Excludes directions that share a component with the opposite of step 1.
local tacticalExclude = {
  north     = {"south","southeast","southwest"},
  south     = {"north","northeast","northwest"},
  east      = {"west","southwest","northwest"},
  west      = {"east","southeast","northeast"},
  northeast = {"south","southwest","west","northwest","southeast"},
  northwest = {"south","southeast","east","northeast","southwest"},
  southeast = {"north","northwest","west","southwest","northeast"},
  southwest = {"north","northeast","east","southeast","northwest"},
}

function dg.hunt.startTacticalRetreat()
  if dg.hunt.isTacticalRetreat then return end

  dg.hunt.isTacticalRetreat    = true
  dg.hunt.tacticalRetreatSteps = 0
  dg.hunt.tacticalRetreatDir1  = nil
  dg.combat.active = false
  dg.combat.target = nil
  dg.hunt.justKilled = false

  send("q c")
  cecho("<yellow>*** HP LOW - TACTICAL RETREAT ***<reset>\n")
  send("look")

  tempTimer(0.5, function() dg.hunt.tacticalRetreatStep() end)
end

function dg.hunt.tacticalRetreatStep()
  if not dg.hunt.active or not dg.hunt.isTacticalRetreat then return end

  if dg.hunt.tacticalRetreatSteps >= 2 then
    dg.hunt.debugLog("Tactical retreat: 2 rooms moved, sitting to heal")
    cecho("<yellow>*** SITTING TO HEAL ***<reset>\n")
    dg.hunt.isHealing = true
    send("sit")
    tempTimer(0.5, function() expandAlias("fame") end)
    return
  end

  local excluded = {}
  if dg.hunt.tacticalRetreatSteps == 1 and dg.hunt.tacticalRetreatDir1 then
    for _, d in ipairs(tacticalExclude[dg.hunt.tacticalRetreatDir1] or {}) do
      excluded[d] = true
    end
  end

  local chosen = nil
  for _, available in ipairs(dg.hunt.availableExits) do
    if not excluded[available] then chosen = available; break end
  end

  if not chosen then
    chosen = dg.hunt.availableExits[1]
    dg.hunt.debugLog("Tactical retreat: no safe exit, using: " .. (chosen or "none"))
  end

  if not chosen then
    dg.hunt.debugLog("Tactical retreat: no exits, healing in place")
    dg.hunt.isHealing = true
    send("sit")
    tempTimer(0.5, function() expandAlias("fame") end)
    return
  end

  if dg.hunt.tacticalRetreatSteps == 0 then
    dg.hunt.tacticalRetreatDir1 = chosen
  end

  send(chosen)
end

function dg.hunt.fleeStep()
  if not dg.hunt.active or not dg.hunt.isFleeing then return end

  if dg.hunt.fleeStepTimer then killTimer(dg.hunt.fleeStepTimer); dg.hunt.fleeStepTimer = nil end

  local zone = dg.hunt.zones[dg.hunt.currentZone]
  if not zone then dg.hunt.stop(); return end

  local chosen = nil
  for _, dir in ipairs(zone.fleeDirections) do
    for _, available in ipairs(dg.hunt.availableExits) do
      if available == dir then chosen = dir; break end
    end
    if chosen then break end
  end

  if not chosen then
    chosen = zone.fleeDirections[1]
    dg.hunt.debugLog("No flee exit found, trying: " .. chosen)
  else
    dg.hunt.debugLog("Flee step: " .. chosen)
  end

  send(chosen)

  dg.hunt.fleeStepTimer = tempTimer(2.0, function()
    dg.hunt.fleeStepTimer = nil
    if dg.hunt.isFleeing and dg.hunt.active then dg.hunt.fleeStep() end
  end)
end

function dg.hunt.onHitWhileSleeping()
  if not dg.hunt.isSleeping then return end
  cecho("<red>*** HIT WHILE SLEEPING - WAKING AND FLEEING ***<reset>\n")

  if dg.hunt.sleepRecoveryTimer then killTimer(dg.hunt.sleepRecoveryTimer); dg.hunt.sleepRecoveryTimer = nil end

  dg.hunt.isSleeping = false
  send("stand")
  tempTimer(1.0, function()
    if dg.hunt.active then dg.hunt.fleeToSafeRoom() end
  end)
end

function dg.hunt.checkSleepRecovery()
  if not dg.hunt.active or not dg.hunt.isSleeping then return end

  dg.hunt.sleepRecoveryTimer = tempTimer(5, function()
    if not dg.hunt.active or not dg.hunt.isSleeping then return end

    local ftgPct = dg.combat.vitals.fatigue / dg.combat.vitals.maxFatigue
    dg.hunt.debugLog(string.format("Sleep recovery check: fatigue %.0f%%", ftgPct*100))

    if ftgPct >= dg.hunt.thresholds.wakeAt then
      cecho("<green>*** RECOVERED - RETURNING TO ZONE ***<reset>\n")
      send("stand")
      dg.hunt.isSleeping = false
      dg.hunt.sleepRecoveryTimer = nil
      tempTimer(1.0, function() dg.hunt.returnToZone() end)
    else
      dg.hunt.checkSleepRecovery()
    end
  end)
end

function dg.hunt.onFirstAidDone()
  if not dg.hunt.active then return end
  if not dg.hunt.isHealing then return end

  dg.hunt.debugLog("First aid complete")
  dg.hunt.isHealing = false

  send("stand")

  tempTimer(1.0, function()
    if not dg.hunt.active then return end

    if dg.hunt.emergencyFlee then
      cecho("<red>*** EMERGENCY FLEE RECOVERY COMPLETE ***<reset>\n")
      cecho("<red>*** REVIEW SITUATION BEFORE RESUMING ***<reset>\n")
      dg.hunt.stop()
    elseif dg.hunt.outOfRunes then
      cecho("<red>*** OUT OF RUNES - RECHARGE BEFORE RESUMING ***<reset>\n")
      dg.hunt.stop()
    elseif dg.hunt.isTacticalRetreat then
      dg.hunt.debugLog("Tactical retreat heal complete, resuming hunt")
      cecho("<green>*** HEALED - RESUMING HUNT ***<reset>\n")
      dg.hunt.isTacticalRetreat    = false
      dg.hunt.tacticalRetreatSteps = 0
      dg.hunt.tacticalRetreatDir1  = nil
      dg.hunt.scanForTargets()
    elseif dg.hunt.isHealingInPlace then
      dg.hunt.debugLog("In-place heal complete, resuming hunt")
      cecho("<green>*** HEALED - RESUMING HUNT ***<reset>\n")
      dg.hunt.isHealingInPlace = false
      dg.hunt.scanForTargets()
    else
      cecho("<green>*** HEALED - RETURNING TO ZONE ***<reset>\n")
      dg.hunt.returnToZone()
    end
  end)
end

function dg.hunt.checkHealBetweenKills()
  if not dg.hunt.active then return end

  local hpPct  = dg.combat.vitals.hp / dg.combat.vitals.maxHp
  local ftgPct = dg.combat.vitals.fatigue / dg.combat.vitals.maxFatigue

  dg.hunt.debugLog(string.format("Post-kill check: %.0f%% HP, %.0f%% FTG", hpPct*100, ftgPct*100))

  if ftgPct <= dg.hunt.thresholds.sleep then
    dg.hunt.fleeToSafeRoom(); return
  end

  if hpPct <= dg.hunt.thresholds.flee then
    dg.hunt.fleeToSafeRoom(); return
  end

  if hpPct <= dg.hunt.thresholds.sitHeal then
    cecho("<yellow>*** HP LOW - SITTING TO HEAL ***<reset>\n")
    dg.hunt.isHealingInPlace = true
    dg.hunt.isHealing        = true
    send("sit")
    tempTimer(0.5, function() expandAlias("fame") end)
    return
  end

  -- Cast vigor between kills if fatigue is low
  if ftgPct <= dg.hunt.thresholds.vigorBetweenKills then
    local cfg = dg.combat.spell and dg.combat.spell.getConfig and dg.combat.spell.getConfig()
    if cfg and cfg.vigorWord then
      cecho("<yellow>*** FATIGUE LOW - CASTING VIGOR ***<reset>\n")
      dg.hunt.isHealingInPlace = true
      dg.hunt.isHealing        = true
      send("invoke " .. cfg.vigorWord .. " " .. (dg.me or ""))
      return
    end
  end

  dg.hunt.scanForTargets()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SCANNING
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.scanForTargets()
  if not dg.hunt.active then return end
  if dg.hunt.isHealing or dg.hunt.isSleeping or dg.hunt.isFleeing then return end

  dg.hunt.debugLog("scanForTargets() called")

  local timeSince = getEpoch() - dg.hunt.lastScanTime

  if timeSince >= dg.hunt.scanThrottle then
    dg.hunt.lastScanTime = getEpoch()
    dg.hunt.recordAction()
    send("scan")
    tempTimer(0.5, function()
      if dg.hunt.active and not dg.hunt.isHealing and
         not dg.hunt.isSleeping and not dg.hunt.isFleeing then
        dg.hunt.processScanResults()
      end
    end)
  else
    local wait = dg.hunt.scanThrottle - timeSince
    dg.hunt.debugLog(string.format("Scan throttled, waiting %.1fs", wait))
    tempTimer(wait, function() dg.hunt.scanForTargets() end)
  end
end

function dg.hunt.onScanStart()
  if not dg.hunt.active then return end
  dg.hunt.availableTargets    = {}
  dg.hunt.nearbyTargets       = {}
  dg.hunt.forbiddenDirections = {}
end

function dg.hunt.onScan(mobName, location)
  if not dg.hunt.active then return end

  dg.hunt.failedMoves = 0

  local firstChar = mobName:sub(1,1)
  if firstChar == firstChar:upper() and not mobName:match("^A ")
     and not mobName:match("^An ") and not mobName:match("^The ") then
    if location:match("right here") then
      cecho("<red>*** PC IN ROOM: " .. mobName .. " ***<reset>\n")
      dg.hunt.pcInRoom = true
    else
      local direction = location:match("nearby to the (%w+)")
      if direction then
        dg.hunt.forbiddenDirections[direction] = true
        cecho("<red>*** PC NEARBY (" .. direction .. "): " .. mobName .. " - AVOIDING ***<reset>\n")
      end
    end
    return
  end

  local cleanName = mobName:lower():gsub("^a ",""):gsub("^an ",""):gsub("^the ","")
  local shortName = cleanName
  if not cleanName:match(" of ") then
    shortName = cleanName:match("(%w+)%s*$") or cleanName
  end

  if location:match("right here") then
    dg.hunt.availableTargets[shortName] = true
    cecho("<yellow>Found in room: " .. shortName .. " (full: " .. cleanName .. ")<reset>\n")
  elseif location:match("nearby") then
    local direction = location:match("nearby to the (%w+)")
    if direction then
      dg.hunt.nearbyTargets[direction] = dg.hunt.nearbyTargets[direction] or {}
      table.insert(dg.hunt.nearbyTargets[direction], shortName)
      cecho("<dim_grey>Found nearby (" .. direction .. "): " .. shortName .. "<reset>\n")
    end
  end
end

function dg.hunt.processScanResults()
  if not dg.hunt.active then return end
  if dg.hunt.isHealing or dg.hunt.isSleeping or dg.hunt.isFleeing then return end

  dg.hunt.debugLog("processScanResults() pcInRoom=" .. tostring(dg.hunt.pcInRoom))

  if dg.hunt.pcInRoom then
    cecho("<yellow>PC in room, moving away<reset>\n")
    dg.hunt.pcInRoom         = false
    dg.hunt.availableTargets = {}
    dg.hunt.nearbyTargets    = {}
    dg.hunt.moveToNextRoom()
    return
  end

  if next(dg.hunt.availableTargets) then
    dg.hunt.pickAndAttack()
  else
    local best = dg.hunt.pickBestNearbyDirection()
    if best then
      cecho("<cyan>*** MOVING " .. best:upper() .. " TOWARD TARGETS ***<reset>\n")
      dg.hunt.moveToDirection(best)
    else
      cecho("<yellow>*** NO TARGETS NEARBY - MOVING RANDOMLY ***<reset>\n")
      dg.hunt.moveToNextRoom()
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TARGET SELECTION
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.pickBestTarget()
  for _, mobName in ipairs(dg.hunt.priorityList) do
    if dg.hunt.availableTargets[mobName] then return mobName end
  end
  for mobName, _ in pairs(dg.hunt.availableTargets) do
    if mobName and mobName ~= "" and mobName ~= "." and #mobName > 1 then
      return mobName
    end
  end
  return nil
end

function dg.hunt.pickAndAttack()
  dg.hunt.debugLog("pickAndAttack() inCombat=" .. tostring(dg.combat.inCombat()) ..
    " justKilled=" .. tostring(dg.hunt.justKilled) ..
    " pcInRoom=" .. tostring(dg.hunt.pcInRoom))

  if dg.combat.inCombat() then
    dg.hunt.recordAction(); return
  end
  if dg.hunt.justKilled then return end
  if dg.hunt.pcInRoom then
    cecho("<red>*** PC IN ROOM - NOT ATTACKING ***<reset>\n")
    dg.hunt.pcInRoom = false
    dg.hunt.moveToNextRoom()
    return
  end

  local target = dg.hunt.pickBestTarget()
  if target then
    dg.hunt.debugLog("Attacking: " .. target)
    cecho("<cyan>*** NEW TARGET: " .. target .. " ***<reset>\n")
    dg.hunt.availableTargets = {}
    dg.combat.startAttack(target, dg.hunt.attackMethod)
    dg.hunt.recordAction()
  else
    dg.hunt.availableTargets = {}
    dg.hunt.moveToNextRoom()
  end
end

function dg.hunt.pickBestNearbyDirection()
  local bestDir      = nil
  local bestPriority = 999

  for direction, mobs in pairs(dg.hunt.nearbyTargets) do
    if not dg.hunt.forbiddenDirections[direction] then
      for _, mobName in ipairs(mobs) do
        for priority, priorityMob in ipairs(dg.hunt.priorityList) do
          if mobName == priorityMob and priority < bestPriority then
            bestPriority = priority
            bestDir = direction
            break
          end
        end
      end
    end
  end

  if not bestDir then
    for direction, _ in pairs(dg.hunt.nearbyTargets) do
      if not dg.hunt.forbiddenDirections[direction] then
        bestDir = direction; break
      end
    end
  end

  return bestDir
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MOVEMENT
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.parseExits(exitsString)
  if not dg.hunt.active then return end
  dg.hunt.availableExits = {}
  for exit in exitsString:gmatch("%S+") do
    table.insert(dg.hunt.availableExits, exit:gsub("%*",""))
  end
end

local function moveCommon(direction)
  if dg.hunt.isMoving then return end
  dg.hunt.isMoving = true
  dg.hunt.pcInRoom = false

  cecho("<cyan>Moving: " .. direction .. "<reset>\n")
  send(direction)

  tempTimer(0.5, function()
    if dg.hunt.active then send("look") end
  end)

  tempTimer(3.0, function()
    dg.hunt.isMoving = false
    if dg.hunt.justKilled then return end
    if dg.hunt.isHealing or dg.hunt.isSleeping or dg.hunt.isFleeing then return end
    if dg.hunt.active then dg.hunt.scanForTargets() end
  end)
end

function dg.hunt.moveToDirection(direction)
  if not dg.hunt.active then return end
  moveCommon(direction)
end

function dg.hunt.moveToNextRoom()
  if not dg.hunt.active then return end

  local exits = dg.hunt.availableExits
  if #exits == 0 then
    exits = {"north","south","east","west","northeast","northwest","southeast","southwest"}
  end

  moveCommon(exits[math.random(#exits)])
end

function dg.hunt.onMoveFailed()
  if not dg.hunt.active then return end
  if dg.hunt.isFleeing then return end

  dg.hunt.failedMoves = dg.hunt.failedMoves + 1
  if dg.hunt.failedMoves >= 3 then
    cecho("<red>*** STUCK - STOPPING ***<reset>\n")
    dg.hunt.stop()
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMBAT EVENTS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.onKill()
  if not dg.hunt.active then return end

  dg.hunt.debugLog("onKill() fired")

  if dg.hunt.isFleeing then
    dg.hunt.debugLog("Kill during flee — skipping loot, continuing escape")
    dg.combat.active = false
    dg.combat.target = nil
    return
  end

  cecho("<green>*** TARGET KILLED - LOOTING ***<reset>\n")
  send("q c")

  dg.combat.active   = false
  dg.combat.target   = nil
  dg.hunt.justKilled = true
  dg.hunt.isMoving   = false

  tempTimer(0.3, function() send("get all") end)

  if dg.hunt.stopAfterKill then
    tempTimer(1.0, function()
      dg.hunt.stop()
      dg.hunt.stopAfterKill = false
    end)
    return
  end

  tempTimer(4.0, function()
    dg.hunt.justKilled = false
    dg.hunt.checkHealBetweenKills()
  end)
end

function dg.hunt.onTargetMissing()
  if not dg.hunt.active then return end
  cecho("<yellow>*** TARGET MISSING - SCANNING ***<reset>\n")
  dg.combat.clearTarget()
  tempTimer(1.0, function() dg.hunt.scanForTargets() end)
end

function dg.hunt.autoStand()
  cecho("<yellow>*** STANDING UP ***<reset>\n")
  send("stand")
  tempTimer(0.5, function() dg.hunt.scanForTargets() end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STATUS
-- ═══════════════════════════════════════════════════════════════════════════

function dg.hunt.status()
  echo("\n=== AUTO-HUNTING STATUS ===\n")

  if dg.hunt.active then cecho("<green>ACTIVE<reset>\n") else cecho("<red>INACTIVE<reset>\n") end

  if     dg.hunt.isFleeing  then cecho("<red>MODE: Fleeing<reset>\n")
  elseif dg.hunt.isHealing  then cecho("<yellow>MODE: Healing<reset>\n")
  elseif dg.hunt.isSleeping then cecho("<yellow>MODE: Sleeping<reset>\n")
  else                           cecho("<green>MODE: Hunting<reset>\n") end

  echo(string.format("Zone: %s\nRoom: %s\n",
    dg.hunt.currentZone or "none",
    dg.hunt.currentRoom or "unknown"))

  echo("\nThresholds:\n")
  echo(string.format("  Sit/Heal:        %.0f%% HP\n",  dg.hunt.thresholds.sitHeal * 100))
  echo(string.format("  Tactical retreat:%.0f%% HP\n",  dg.hunt.thresholds.tacticalRetreat * 100))
  echo(string.format("  Emergency flee:  %.0f%% HP\n",  dg.hunt.thresholds.flee * 100))
  echo(string.format("  Sleep:           %.0f%% FTG\n", dg.hunt.thresholds.sleep * 100))
  echo(string.format("  Wake at:         %.0f%% FTG\n", dg.hunt.thresholds.wakeAt * 100))

  echo("\nPriority List:\n")
  for i, mobName in ipairs(dg.hunt.priorityList) do
    echo("  " .. i .. ". " .. mobName .. "\n")
  end
  echo("\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate Auto-Hunting System v5.2 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  hunt            -- start hunting (melee)\n")
echo("  hunt spell      -- start hunting (spell)\n")
echo("  hunt stop       -- stop immediately\n")
echo("  hunt finish     -- stop after current kill\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
QUICK SETUP CHECKLIST
═══════════════════════════════════════════════════════════════════════════

Before your first hunt, edit the following sections in this file:

  [ ] dg.hunt.zones        — set safeRoomName / recoverRoomName for your zone
  [ ] dg.hunt.currentZone  — set to the key of your active zone
  [ ] dg.hunt.thresholds   — tune HP/fatigue thresholds for your character
  [ ] dg.hunt.priorityList — add the mob keywords you want to hunt
  [ ] dg.hunt.emergencySound — optional: set path to an alert sound file
  [ ] dg.hunt.debug        — set to true while testing, false for normal use

Then create all the aliases and triggers listed below.

═══════════════════════════════════════════════════════════════════════════
REQUIRED ALIASES
═══════════════════════════════════════════════════════════════════════════

  hunt          ^hunt$          dg.hunt.start()
  hunt spell    ^hunt spell$    dg.hunt.start(dg.combat.spell.attack)
  hunt stop     ^hunt stop$     dg.hunt.stop()
  hunt finish   ^hunt finish$   dg.hunt.stopAfterNextKill()

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGERS
═══════════════════════════════════════════════════════════════════════════

All patterns are perl regex unless noted.

1.  Scan started
    ^You quickly scan the area!$
    → dg.hunt.onScanStart()

2.  Parse scan results
    ^(.+?), (.+)$
    → dg.hunt.onScan(matches[2], matches[3])

3.  Parse exits
    ^Obvious Exits:\s*(.+)$
    → dg.hunt.parseExits(matches[2])

4.  Mob killed
    ^.+ (?:collapses into a pile of bones|staggers, then falls apart in a crash of bone|unravels into mist, the last trace of its presence slipping into silence)\.$
    → dg.hunt.onKill()
    Note: add more death patterns for other mob types you encounter.

5.  Movement failed
    ^.+ does not exist as an exit\.$
    → dg.hunt.onMoveFailed()

6.  Auto stand
    ^You can't use this command while sitting\.$
    → dg.hunt.autoStand()

7.  Target missing
    ^That target does not exist\.$
    → dg.hunt.onTargetMissing()

8.  Prompt (HP and fatigue tracking — required for sustain)
    ^\[Health: (\d+)/(\d+) - Fatigue: (\d+)/(\d+)\]
    → dg.hunt.onPrompt(matches[2], matches[3], matches[4], matches[5])

9.  First aid done (hand control back to hunter after healing)
    ^You do not require first aid right now\.$
    → dg.hunt.onFirstAidDone()
    Note: if you created the "stop" trigger in dgate_first_aid.lua,
    that trigger already calls dg.hunt.onFirstAidDone() — you do not
    need a second trigger for the same pattern.

10. Death
    ^You have been killed by .+!$
    → dg.hunt.onDeath()

11. Room entered (for zone navigation)
    ^\[.+? - (.+)\.\]$
    → dg.hunt.onRoomEntered(matches[2])
    Note: matches the room name header line, e.g.:
    [Spur - Ironward North - An Accursed Cemetery.]
    captures "An Accursed Cemetery." (trailing period is stripped in code).

12. Hit while sleeping (conditional — only fire when sleeping)
    ^.+ attacks you!$
    → dg.hunt.onHitWhileSleeping()
    In Mudlet, add a Lua condition to this trigger:
      return dg.hunt.isSleeping == true
    This prevents the trigger from firing during normal combat.

═══════════════════════════════════════════════════════════════════════════
ZONE CONFIGURATION GUIDE
═══════════════════════════════════════════════════════════════════════════

The zone config tells the hunter how to flee to safety and return.

To find your room names:
  1. Go to the gate/portal room inside your hunting zone
  2. Note the room name from the header line (after the last " - ")
  3. Go through the gate to the city side
  4. Note that room name
  5. Fill in safeRoomName and recoverRoomName above

fleeDirections should point toward the gate room from inside the zone.
returnDirections should point toward the city-side recover room.

If your zone has a simple layout (e.g. south exits the zone), just put
{"south"} first in fleeDirections and {"north"} first in returnDirections.

═══════════════════════════════════════════════════════════════════════════
ADDING MORE MOB DEATH PATTERNS (trigger 4)
═══════════════════════════════════════════════════════════════════════════

Different mob types in DGate have different death messages. Expand the
kill trigger pattern as you encounter new ones:

  ^.+ (?:collapses into a pile of bones
       |staggers, then falls apart in a crash of bone
       |unravels into mist, the last trace of its presence slipping into silence
       |crumples to the ground, lifeless
       |YOUR NEW PATTERN HERE
       )\.$

Each alternative goes on its own line inside (?:...) separated by |.

--]]
