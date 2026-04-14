-- ═══════════════════════════════════════════════════════════════════════════
-- DRAGON'S GATE INIT MODULE
-- dgate_init.lua
-- ═══════════════════════════════════════════════════════════════════════════
-- VERSION: 1.0
-- PURPOSE: Character identification and session logging on login
--
-- This module handles two things that need to happen as soon as you log in:
--
--   1. Sets dg.me (and the global me) to your character name so that the
--      spell module, first aid module, and autohunter all know who you are.
--
--   2. Starts Mudlet's session log automatically on login.
--
-- The login trigger fires on the line "Logging in as <name>!" which DGate
-- sends immediately after you connect. The setme alias lets you set your
-- character name manually if needed.
--
-- SPELL MODULE CONFIGURATION:
-- If you use spell hunting, the setme alias is also where you configure
-- which spell your character uses. See the SETUP section below and the
-- dg.combat.spell.chars table in dgate_combat_spells.lua.
-- ═══════════════════════════════════════════════════════════════════════════

-- Initialise globals
me    = me    or ""
dg    = dg    or {}
dg.me = dg.me or ""

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
cecho("<yellow>DGate Init Module v1.0 loaded<reset>\n")
cecho("<cyan>═══════════════════════════════════════════════════<reset>\n")
echo("  setme <name>  -- set active character name\n\n")

--[[
═══════════════════════════════════════════════════════════════════════════
REQUIRED ALIAS
═══════════════════════════════════════════════════════════════════════════

ALIAS: setme
─────────────────────────────────────────────────────────────────────────
  Name:    setme
  Pattern: ^setme (.+)$
  Type:    perl regex
  Script:

    me    = matches[2]
    dg.me = matches[2]

    cecho("\n<green>Character set to: " .. me .. "<reset>\n")

  ─────────────────────────────────────────────────────────────────────
  If you use spell hunting, also add per-character spell configuration
  here. Replace the examples with your actual character names and spell
  invoke words. The invoke word is the first word of your attack spell —
  for "invoke ftouch <target>" the invoke word is "ftouch".

  Full example with spell config:

    me    = matches[2]
    dg.me = matches[2]

    -- Per-character spell defaults (melee hunters can omit this block)
    if me == "YourCasterName" then
      -- spell config is already in dgate_combat_spells.lua;
      -- nothing extra needed here unless you want to set a default spell
    end

    cecho("\n<green>Character set to: " .. me .. "<reset>\n")

  ─────────────────────────────────────────────────────────────────────
  Note: spell configuration lives in dgate_combat_spells.lua in the
  dg.combat.spell.chars table. You do not need to duplicate it here
  unless you want to do additional per-character setup at login.

═══════════════════════════════════════════════════════════════════════════
REQUIRED TRIGGER
═══════════════════════════════════════════════════════════════════════════

TRIGGER: init name and log
─────────────────────────────────────────────────────────────────────────
  Name:    init name and log
  Pattern: ^Logging in as (.+)!$
  Type:    perl regex
  Script:
    local name = matches[2]
    if name then
      expandAlias("setme " .. name)
      startLogging(true)
      echo("\n[LOG] Logging started for " .. name .. "\n")
    end

  Note: This trigger fires once per session, immediately after the game
  confirms your login. It calls setme automatically so you do not need
  to type it manually, and starts Mudlet's built-in session logging.

  The log files are saved to Mudlet's log directory:
    Windows: %APPDATA%\Roaming\Mudlet\profiles\<profile>\log\
    Mac/Linux: ~/.config/mudlet/profiles/<profile>/log/

═══════════════════════════════════════════════════════════════════════════
LOAD ORDER REMINDER
═══════════════════════════════════════════════════════════════════════════

Scripts must be loaded in this order for everything to work correctly:

  1. dgate_combat_core.lua
  2. dgate_combat_melee.lua
  3. dgate_combat_spells.lua    (optional — only needed for spell hunting)
  4. dgate_autohunt.lua
  5. dgate_first_aid.lua
  6. dgate_init.lua             (this file)

In Mudlet's script editor, scripts execute top-to-bottom in the order
they appear in the list. Drag them into the correct order after creating
them.

--]]
