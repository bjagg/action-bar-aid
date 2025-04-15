-- ActionBarAid.lua
-- A World of Warcraft addon to highlight passive/unavailable abilities and color-code by source, with debug logging and saved variables.

local ActionBarAid = {}
local DEBUG_MODE = true
ActionBarAidDebugLog = ActionBarAidDebugLog or {}

-- Functional helper
local function map(tbl, fn)
  local t = {}
  for i, v in ipairs(tbl) do
    t[i] = fn(v)
  end
  return t
end

-- Debug print
local function debugPrint(msg)
  if DEBUG_MODE then
    print("|cff00ff00[ActionBarAid]|r " .. msg)
  end
end

-- Spell source classification cache
local spellSourceMap = {}

function ActionBarAid.buildSpellSourceMap()
  wipe(spellSourceMap)

  -- 1. Hero talents (WoW 11.1+ API)
  local heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
  if heroSpecID then
    local subTreeInfo = C_Traits.GetSubTreeInfo(heroSpecID)
    for _, nodeID in ipairs(subTreeInfo.nodes or {}) do
      local nodeInfo = C_Traits.GetNodeInfo(heroSpecID, nodeID)
      for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
        local entry = C_Traits.GetEntryInfo(entryID)
        if entry and entry.definitionID then
          local def = C_Traits.GetDefinitionInfo(entry.definitionID)
          if def and def.spellID then
            spellSourceMap[def.spellID] = "hero"
          end
        end
      end
    end
  end

  -- 2. Talent Trees (General + Spec)
  local configID = C_ClassTalents.GetActiveConfigID()
  if configID then
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(configID) or {}) do
      local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
      for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
        local entry = C_Traits.GetEntryInfo(entryID)
        if entry and entry.definitionID then
          local def = C_Traits.GetDefinitionInfo(entry.definitionID)
          if def and def.spellID then
            local source = def.specID and "spec" or "talent"
            spellSourceMap[def.spellID] = source
          end
        end
      end
    end
  end
end

-- Source lookup
function ActionBarAid.getSpellSource(spellID)
  return spellSourceMap[spellID] or "core"
end

-- Passive/unavailable detection
function ActionBarAid.isPassiveOrUnavailable(spellID)
  return C_Spell.IsSpellPassive(spellID) or not IsSpellKnown(spellID)
end

-- Slot processing
function ActionBarAid.processSlot(slot)
  local actionType, id = GetActionInfo(slot)
  if actionType ~= "spell" or not id then return nil end

  return {
    slot = slot,
    spellID = id,
    source = ActionBarAid.getSpellSource(id),
    passiveOrUnavailable = ActionBarAid.isPassiveOrUnavailable(id)
  }
end

-- Scan all action bars
function ActionBarAid.scanActionBars()
  local slots = {}
  for i = 1, 120 do table.insert(slots, i) end
  return map(slots, ActionBarAid.processSlot)
end

-- Color utility
local function GetColorForSource(source)
  local colors = {
    core = {0, 1, 0},      -- Green
    talent = {0, 0, 1},    -- Blue
    spec = {1, 0.5, 0},    -- Orange
    hero = {1, 1, 0},      -- Yellow
    unknown = {1, 1, 1},   -- White
  }
  return colors[source] or {1, 1, 1}
end

-- Apply visual highlight + log
function ActionBarAid.highlightSlot(slotInfo)
  if not slotInfo then return end
  local frame = _G["ActionButton"..slotInfo.slot]
  if not frame or not frame.Border then return end

  local spellInfo = C_Spell.GetSpellInfo(slotInfo.spellID)
  local spellName = spellInfo and spellInfo.name or "Unknown"

  local entry = {
    slot = slotInfo.slot,
    spellID = slotInfo.spellID,
    source = slotInfo.source,
    passiveOrUnavailable = slotInfo.passiveOrUnavailable,
    spellName = spellName
  }

  table.insert(ActionBarAidDebugLog, entry)

  if slotInfo.passiveOrUnavailable then
    frame.Border:SetVertexColor(1, 0, 0) -- Red border
    debugPrint("Slot " .. entry.slot .. ": passive/unavailable (" .. entry.spellID .. ")")
  else
    local color = GetColorForSource(entry.source)
    frame.Border:SetVertexColor(unpack(color))
    debugPrint("Slot " .. entry.slot .. ": " .. entry.source .. " (" .. entry.spellID .. ")")
  end
end

-- Apply to all
function ActionBarAid.refresh()
  local results = ActionBarAid.scanActionBars()
  for _, slotInfo in ipairs(results) do
    ActionBarAid.highlightSlot(slotInfo)
  end
end

-- Event registration
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")

f:SetScript("OnEvent", function(event)
  if event == "PLAYER_ENTERING_WORLD" then
    ActionBarAidDebugLog = ActionBarAidDebugLog or {}
  end

  C_Timer.After(2, function()
    ActionBarAid.buildSpellSourceMap()
    ActionBarAid.refresh()
  end)
end)

-- Slash command
SLASH_ACTIONBARAID1 = "/abaid"
SlashCmdList["ACTIONBARAID"] = function(msg)
  if msg == "debug" then
    DEBUG_MODE = not DEBUG_MODE
    print("ActionBarAid debug mode: " .. (DEBUG_MODE and "ON" or "OFF"))
  elseif msg == "log" then
    for _, entry in ipairs(ActionBarAidDebugLog or {}) do
      print("Slot " .. entry.slot .. ": " .. (entry.spellName or "Unknown") .. " (" .. entry.spellID .. ") - " .. entry.source)
    end
  elseif msg == "clearlog" then
    ActionBarAidDebugLog = {}
    print("ActionBarAid debug log cleared.")
  else
    print("ActionBarAid commands:")
    print("  /abaid debug - Toggle debug output")
    print("  /abaid log - Show saved debug log")
    print("  /abaid clearlog - Clear saved debug log")
  end
end

_G.ActionBarAid = ActionBarAid