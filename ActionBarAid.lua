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
local spellSourceMapByName = {}

function ActionBarAid.buildSpellSourceMap()
  wipe(spellSourceMap)
  wipe(spellSourceMapByName)

  local configID = C_ClassTalents.GetActiveConfigID()
  local heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()

  -- 1. Hero talents (WoW 11.1+ API)
  if configID and heroSpecID then
    local subTreeInfo = C_Traits.GetSubTreeInfo(configID, heroSpecID)
    for _, nodeID in ipairs(subTreeInfo.nodes or {}) do
      local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
      for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
        local entry = C_Traits.GetEntryInfo(entryID)
        if entry and entry.definitionID then
          local def = C_Traits.GetDefinitionInfo(entry.definitionID)
          if def and def.spellID then
            spellSourceMap[def.spellID] = "hero"
            local info = C_Spell.GetSpellInfo(def.spellID)
            if info and info.name then
              spellSourceMapByName[info.name] = "hero"
            end
            debugPrint("Mapped hero talent spellID " .. def.spellID .. " as 'hero'")
          end
        end
      end
    end
  end

  -- 2. Talent Trees (General + Spec)
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
            local info = C_Spell.GetSpellInfo(def.spellID)
            if info and info.name then
              spellSourceMapByName[info.name] = source
            end
            debugPrint("Mapped talent spellID " .. def.spellID .. " as '" .. source .. "'")
          end
        end
      end
    end
  end
end

-- Source lookup with fallback
function ActionBarAid.getSpellSource(spellID)
  if spellSourceMap[spellID] then
    return spellSourceMap[spellID]
  end
  local info = C_Spell.GetSpellInfo(spellID)
  if info and info.name and spellSourceMapByName[info.name] then
    return spellSourceMapByName[info.name]
  end
  return "core"
end

-- Passive/unavailable detection with logging
function ActionBarAid.isPassiveOrUnavailable(spellID)
  local isPassive = C_Spell.IsSpellPassive(spellID)
  local isKnown = IsSpellKnown(spellID)
  if DEBUG_MODE then
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or "Unknown"
    if not isKnown then
      debugPrint("Spell '" .. name .. "' (" .. spellID .. ") is not known")
    elseif isPassive then
      debugPrint("Spell '" .. name .. "' (" .. spellID .. ") is passive")
    end
  end
  return isPassive or not isKnown
end

-- Get all named action buttons from UI (WoW 11.0+ safe)
local namedButtons = {
  "ActionButton",
  "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
}

local function getAllActionButtons()
  local buttons = {}
  for _, prefix in ipairs(namedButtons) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button and button.action then
        table.insert(buttons, button)
      end
    end
  end
  return buttons
end

-- Slot processing
function ActionBarAid.processSlot(slot)
  local actionType, id = GetActionInfo(slot)

  local info = {
    slot = slot,
    actionType = actionType,
    id = id,
    valid = (actionType == "spell" and id ~= nil),
    spellID = (actionType == "spell") and id or nil,
  }

  if info.spellID then
    info.source = ActionBarAid.getSpellSource(info.spellID)
    info.passiveOrUnavailable = ActionBarAid.isPassiveOrUnavailable(info.spellID)
    local spellInfo = C_Spell.GetSpellInfo(info.spellID)
    info.spellName = spellInfo and spellInfo.name or "Unknown"
  end

  return info
end

-- Scan all visible buttons from current bars
function ActionBarAid.scanActionBars()
  local buttons = getAllActionButtons()
  return map(buttons, function(button)
    local slotInfo = ActionBarAid.processSlot(button.action)
    slotInfo.frameName = button:GetName()
    return slotInfo
  end)
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

-- Apply color to various frame parts
local function applyColorToFrame(frame, color)
  if frame.Border then
    frame.Border:SetVertexColor(unpack(color))
  elseif frame.IconBorder then
    frame.IconBorder:SetVertexColor(unpack(color))
  elseif frame.Icon then
    frame.Icon:SetVertexColor(unpack(color))
  else
    debugPrint("No colorable region found on " .. frame:GetName())
  end
end

-- Apply visual highlight + log
function ActionBarAid.highlightSlot(slotInfo)
  if not slotInfo then return end
  local frame = _G[slotInfo.frameName]
  if not frame then return end

  local entry = {
    slot = slotInfo.slot,
    spellID = slotInfo.spellID,
    source = slotInfo.source,
    passiveOrUnavailable = slotInfo.passiveOrUnavailable,
    spellName = slotInfo.spellName
  }

  table.insert(ActionBarAidDebugLog, entry)

  if slotInfo.passiveOrUnavailable then
    applyColorToFrame(frame, {1, 0, 0}) -- Red border
    debugPrint("[" .. slotInfo.frameName .. "] Slot " .. entry.slot .. ": passive/unavailable - " .. entry.spellName)
  else
    local color = GetColorForSource(entry.source)
    applyColorToFrame(frame, color)
    debugPrint("[" .. slotInfo.frameName .. "] Slot " .. entry.slot .. ": " .. entry.source .. " - " .. entry.spellName)
  end
end

-- Apply to all
function ActionBarAid.refresh()
  if DEBUG_MODE then
    debugPrint("---- Begin Action Bar Scan ----")
  end

  local results = ActionBarAid.scanActionBars()
  for _, slotInfo in ipairs(results) do
    if slotInfo.valid then
      ActionBarAid.highlightSlot(slotInfo)
    elseif DEBUG_MODE then
      debugPrint("[" .. (slotInfo.frameName or "unknown") .. "] Slot " .. slotInfo.slot .. ": " .. tostring(slotInfo.actionType) .. " (id: " .. tostring(slotInfo.id) .. ")")
    end
  end

  if DEBUG_MODE then
    debugPrint("---- End Action Bar Scan ----")
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
