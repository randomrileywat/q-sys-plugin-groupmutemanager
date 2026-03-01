---------------------------------------------------------------
-- Q-SYS Plugin for Group Mute Management
-- Riley Watson
-- rwatson@onediversified.com
--
-- Current Version:
-- v260301.1 (RWatson)
--  - Feature: Added "Clock to Master" option with settings UI
--    (checkbox, code name field, connection LED). When enabled,
--    syncs fault flash to Master Controller's Flash_Clock broadcast
--    via EventHandler for tight visual synchronization across all
--    instances. Falls back to local os.time() clock automatically
--    when master is unavailable; auto-reconnects every 5 s.
--  - Improvement: All_Mute EventHandler now uses updatingAllMute
--    guard flag instead of broken value-comparison dedup. Internal
--    writes from UpdateAllMute() are ignored; external writes from
--    Master Controller or pins always process correctly.
--  - Default Master Code Name: "GroupMuteMasterController"
--
-- Change Log:
-- v260228.1 (RWatson)
--  - Improvement: Updated default Muted and Mixed colors to use 80 opacity hex format for consistency.
--
-- v260227.1 (RWatson)
--  - Revert: Restored GetControls() to always create max controls to fix missing UI controls.
--
-- v260224.1 (RWatson)
--  - BugFix: Removed write-back to GroupAmpStatus input pin in UpdateFaultOutputs to prevent feedback loop.
--
-- v260223.1 (RWatson)
--  - Improvement: Flash timer now only runs when faults are active, reducing idle CPU usage.
--  - BugFix: Protected updatingState guard with pcall to prevent permanent lockout on error.
--  - BugFix: Fixed nil variable in groupState handler causing zone overlays not to update on pin input.
--
-- v260117.1 (RWatson) 
--  - BugFix: Corrected issue where zone mute buttons would not always update mute state.
--
-- v260112.1 (RWatson) 
--  - BugFix: Corrected issue where zone mute states could become desynced when group mute state changed via pin input.
--
-- v260110.7 (RWatson)
--  - Improvement: Reduced drift tolerance for clock sync to improve timing accuracy.
--
-- v260110.6 (RWatson)
--  - Improvement: Updated flash timing to use shared wall-clock time (os.time) for sub-second precision.
--
-- v260110.5 (RWatson)
--  - BugFix: Fixed race condition causing zone mute states to update iradically when changed via pin input.
--
-- v260110.3 (RWatson)
--  - BugFix: Zone Mute buttons now properly accept "3" and "4" as valid inputs (faulted mute states).
--
---------------------------------------------------------------

---------------------------------------------------------------
-- Plugin Info
---------------------------------------------------------------
local MAX_GROUPS  = 16   -- Maximum number of mute groups (change as needed)
local MAX_MEMBERS = 32   -- Maximum number of zone members per group (change as needed)

PluginInfo = {
  Name = "Group Mute Manager",
  Version = "260301.1",
  Id = "a695808a-01a5-4b46-913d-608505abef46",
  Author = "Riley Watson",
  Description = "Manages up to " .. MAX_GROUPS .. " group mute buttons with up to " .. MAX_MEMBERS .. " zone members each.",
  ShowDebug = true
}

---------------------------------------------------------------
-- Pages (Dynamic)
---------------------------------------------------------------
local GROUPS_PER_PAGE = 8  -- Number of groups shown per page

local function getPageList(props)
  local pages = {}
  local gCount = (props["Group Count"] and props["Group Count"].Value) or 1
  local pageStart = 1
  while pageStart <= gCount do
    local pageEnd = math.min(pageStart + GROUPS_PER_PAGE - 1, gCount)
    if pageStart == pageEnd then
      table.insert(pages, "Group " .. pageStart)
    else
      table.insert(pages, "Groups " .. pageStart .. "-" .. pageEnd)
    end
    pageStart = pageEnd + 1
  end
  table.insert(pages, "Settings")
  return pages
end

function GetPages(props)
  local out = {}
  for _, name in ipairs(getPageList(props)) do
    table.insert(out, { name = name })
  end
  return out
end

---------------------------------------------------------------
-- Properties & Controls
---------------------------------------------------------------
function GetProperties()
  return {
    { Name = "Group Count",       Type = "integer", Min = 1, Max = MAX_GROUPS,  Value = 2 },
    { Name = "Members Per Group", Type = "integer", Min = 1, Max = MAX_MEMBERS, Value = 4 }
  }
end

function GetControls(props)
  local ctrls = {}

  if props["Group Count"].Value > 1 then
    table.insert(ctrls, { Name = "AllMuteButton", ControlType = "Button", ButtonType = "Toggle" })
    table.insert(ctrls, { Name = "All_Mute", ControlType = "Text", UserPin = true, PinStyle = "Both" })
  end

  local gMax = props["Group Count"].Value
  local mMax = props["Members Per Group"].Value

  for g = 1, MAX_GROUPS do
    table.insert(ctrls, { Name = "GroupButton_" .. g, ControlType = "Button", ButtonType = "Toggle" })
    table.insert(ctrls, { Name = "Group_Mute_" .. g, ControlType = "Text", UserPin = true, PinStyle = "Both" })
    table.insert(ctrls, { Name = "GroupAmpStatus_" .. g, ControlType = "Indicator", IndicatorType = "Text", UserPin = true, PinStyle = "Both" })
    table.insert(ctrls, { Name = "GroupAllMuteEnable_" .. g, ControlType = "Button", ButtonType = "Toggle", UserPin = true, PinStyle = "Both" })

    for m = 1, MAX_MEMBERS do
      table.insert(ctrls, { Name = "Zone_Mute_G" .. g .. "-M" .. m, ControlType = "Button", ButtonType = "Toggle" })
      table.insert(ctrls, { Name = "ZoneMute_" .. g .. "_" .. m, ControlType = "Text", UserPin = true, PinStyle = "Both" })
      table.insert(ctrls, { Name = "ZoneAmpStatus_" .. g .. "_" .. m, ControlType = "Indicator", IndicatorType = "Text", UserPin = true, PinStyle = "Both" })
      table.insert(ctrls, { Name = "ZoneLabel_" .. g .. "_" .. m, ControlType = "Text", UserPin = true, PinStyle = "Both" })
    end
  end

  table.insert(ctrls, { Name = "AnyFault", ControlType = "Text" })

  table.insert(ctrls, { Name = "AmpFlashRate", ControlType = "Knob", ControlUnit = "Integer", Min = 1, Max = 100, Value = 80 })
  table.insert(ctrls, { Name = "ColorMuted", ControlType = "Text"})
  table.insert(ctrls, { Name = "ColorUnmuted", ControlType = "Text"})
  table.insert(ctrls, { Name = "ColorMixed", ControlType = "Text"})
  table.insert(ctrls, { Name = "ColorAmpFault", ControlType = "Text"})
  table.insert(ctrls, { Name = "SuppressStatusFlash", ControlType = "Button", ButtonType = "Toggle" })
  table.insert(ctrls, { Name = "ColorMuted_Preview",     ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorUnmuted_Preview",   ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorMixed_Preview",     ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorAmpFault_Preview",  ControlType = "Indicator", IndicatorType = "Led" })

  -- Clock to Master
  table.insert(ctrls, { Name = "ClockToMaster",     ControlType = "Button", ButtonType = "Toggle", Value = true })
  table.insert(ctrls, { Name = "MasterCodeName",    ControlType = "Text" })
  table.insert(ctrls, { Name = "MasterClockStatus", ControlType = "Indicator", IndicatorType = "Led" })

  return ctrls
end

---------------------------------------------------------------
-- Layout
---------------------------------------------------------------
function GetControlLayout(props)
  local pages = getPageList(props)
  local page_index = props["page_index"].Value
  local current_page = pages[page_index] or pages[#pages]

  local layout, graphics = {}, {}
  local gCount = math.max(1, math.min(MAX_GROUPS, props["Group Count"].Value or 1))
  local mCount = math.max(1, math.min(MAX_MEMBERS, props["Members Per Group"].Value or 1))

  local startX, startY = 0, 0
  local spacingY = 36
  local allButtonWidth, allButtonHeight = 100, 25
  local groupButtonWidth, groupButtonHeight = 100, 25
  local zoneButtonWidth, zoneButtonHeight = 60, 25
  local zoneButtonSpacing = 70

  local function parseRangeFromPageName(name, maxG)
    if name == "Settings" then return nil, nil end
    local single = name:match("^Group%s+(%d+)$")
    if single then
      local n = tonumber(single)
      n = math.max(1, math.min(n, maxG))
      return n, n
    end
    local a, b = name:match("^Groups%s+(%d+)%s*%-%s*(%d+)$")
    if a and b then
      local lo, hi = tonumber(a), tonumber(b)
      if lo > hi then lo, hi = hi, lo end
      lo = math.max(1, lo)
      hi = math.max(lo, math.min(hi, maxG))
      return lo, hi
    end
    return 1, math.min(8, maxG)
  end

  local function draw_control_page(g_lo, g_hi)
    local y0 = startY
    if gCount > 1 then
      layout["AllMuteButton"] = { Legend="All Mute", Style="Button", Position={startX,y0}, Size={allButtonWidth,allButtonHeight} }
      layout["All_Mute"]      = { PrettyName="All Mute", Style="Text", Position={0,0}, Size={0,0} }
      y0 = y0 + spacingY
    end
    for g = g_lo, math.min(g_hi, gCount) do
      local y = y0 + (g - g_lo) * spacingY
      layout["GroupButton_"..g]    = { Legend="Group "..g, Style="", Position={startX,y}, Size={groupButtonWidth,groupButtonHeight} }
      layout["Group_Mute_"..g]     = { PrettyName="Group Mute~G"..g, Style="Text", Position={0,0}, Size={0,0} }
      layout["GroupAmpStatus_"..g] = { PrettyName="Group Status~G"..g, Style="Text", Position={0,0}, Size={0,0} }

      for m = 1, mCount do
        local x = startX + groupButtonWidth + 10 + (m - 1) * zoneButtonSpacing
        layout["Zone_Mute_G"..g.."-M"..m]   = { Legend="Zone "..m, Style="Button", Position={x,y}, Size={zoneButtonWidth,zoneButtonHeight} }
        layout["ZoneMute_"..g.."_"..m]      = { PrettyName="Zone Mute~G"..g.."-M"..m, Style="Text", Position={0,0}, Size={0,0} }
        layout["ZoneAmpStatus_"..g.."_"..m] = { PrettyName="Zone Status~G"..g.."-M"..m, Style="Text", Position={0,0}, Size={0,0} }
      end
    end
  end

  if current_page == "Settings" then
    local labels = {
      { text="Amp Status Flash Rate", y=26 },
      { text="Color - Muted",        y=46 },
      { text="Color - Unmuted",      y=66 },
      { text="Color - Mixed",        y=86 },
      { text="Color - Amp Fault",    y=106 },
      { text="Disable Status Flash", y=126 },
      { text="Clock to Master",      y=150 },
      { text="Master Code Name",     y=170 },
    }
    for _, item in ipairs(labels) do
      table.insert(graphics, { Type="Label", Position={8,item.y}, Size={140,16}, Text=item.text, HTextAlign="Right" })
    end
    table.insert(graphics, { Type="Label", Position={8, 200}, Size={200,16}, Text="Plugin Version: "..(PluginInfo.Version or "Unknown"), HTextAlign="Left" })

    layout["AmpFlashRate"]        = { Style="Knob", Position={160,10},   Size={36,36} }
    layout["ColorMuted"]          = { Style="Text", Position={160,46},   Size={130,16}, Padding=0 }
    layout["ColorUnmuted"]        = { Style="Text", Position={160,66},   Size={130,16}, Padding=0 }
    layout["ColorMixed"]          = { Style="Text", Position={160,86},   Size={130,16}, Padding=0 }
    layout["ColorAmpFault"]       = { Style="Text", Position={160,106},  Size={130,16}, Padding=0 }
    layout["SuppressStatusFlash"] = { Style="Button", Legend="", Position={150,126}, Size={16,16} }
    layout["ClockToMaster"]       = { Style="Button", Legend="", Position={160,150}, Size={16,16} }
    layout["MasterCodeName"]      = { Style="Text", Position={160,170}, Size={130,16}, Padding=0 }
    layout["MasterClockStatus"]   = { Style="LED", Position={296,168}, Size={20,20} }
    layout["ColorMuted_Preview"]    = { Style="LED", Position={290,44},  Size={20,20} }
    layout["ColorUnmuted_Preview"]  = { Style="LED", Position={290,64},  Size={20,20} }
    layout["ColorMixed_Preview"]    = { Style="LED", Position={290,84},  Size={20,20} }
    layout["ColorAmpFault_Preview"] = { Style="LED", Position={290,104}, Size={20,20} }

    local btnSize,rowH = 16,18
    local col1_label_x, col1_btn_x = 340, 400
    local col2_label_x, col2_btn_x = 480, 540
    local header_y, firstRowY = 8,22
    table.insert(graphics, { Type="Label", Position={col1_label_x, header_y}, Size={260,16}, Text="Respect All Mute (per group)", HTextAlign="Left" })
    local leftMax = math.min(gCount, 8)
    for g=1,leftMax do
      local y = firstRowY + (g * rowH)
      table.insert(graphics, { Type="Label", Position={col1_label_x, y}, Size={80,16}, Text=("Group %d"):format(g), HTextAlign="Left" })
      layout["GroupAllMuteEnable_"..g] = { PrettyName="All Mute Enable~Group "..g, Style="Button", Legend="", Position={col1_btn_x,y}, Size={btnSize,btnSize} }
    end
    if gCount > 8 then
      for g=9,gCount do
        local y = firstRowY + ((g-8) * rowH)
        table.insert(graphics, { Type="Label", Position={col2_label_x, y}, Size={80,16}, Text=("Group %d"):format(g), HTextAlign="Left" })
        layout["GroupAllMuteEnable_"..g] = { PrettyName="All Mute Enable~Group "..g, Style="Button", Legend="", Position={col2_btn_x,y}, Size={btnSize,btnSize} }
      end
    end
  else
    local lo, hi = parseRangeFromPageName(current_page, gCount)
    if lo and hi then draw_control_page(lo, hi) end
  end

  return layout, graphics
end

---------------------------------------------------------------
-- Runtime
---------------------------------------------------------------
if Controls then

local PIN_DEBOUNCE_MS = 0
local DEBUG_LOG_ON    = true
local function dbg(msg) if DEBUG_LOG_ON then print(msg) end end

local gCount = Properties["Group Count"].Value
local mCount = Properties["Members Per Group"].Value

local Groups = {}
local PinState = { Group = {}, All = nil }
local PinLastAt = { Group = {}, All = 0 }
local GroupAmpStatus, ZoneAmpStatus = {}, {}
local AllRespect = {}
local colorControls = { Controls.ColorMuted, Controls.ColorUnmuted, Controls.ColorMixed, Controls.ColorAmpFault }
local DefaultColors = { Muted = "#80FF0000", Unmuted = "#8000530f", Mixed = "#80FFFF00", AmpFault = "Orange" }

local FlashState        = false
local FlashTicker       = Timer.New()
local lastFlashState    = nil
local syncedOnce        = false
local phase_offset_s    = 0.0
local FLASH_DUTY        = 0.25
local flashTimerRunning = false

-- Sync tracking for smooth sub-second timing
local sync_time_base  = nil   -- Last os.time() value we synced to
local sync_clock_base = nil   -- os.clock() at that sync point

local faulted_groups = {}
local updatingState    = false  -- Guard flag to prevent recursive event handling
local updatingAllMute  = false  -- Guard flag to prevent All_Mute EventHandler from re-entering during internal writes
local pendingGroupUpdates = {}  -- Track groups needing deferred update
local deferredUpdateTimer = Timer.New()

-- Master clock sync
local masterComp          = nil
local masterConnected     = false
local masterReconnTimer   = Timer.New()
local MASTER_RECONNECT_S  = 5.0   -- Seconds between reconnect attempts

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function now_ms() return math.floor(os.clock() * 1000) end
local function debounce_ok(last_at) 
  return (now_ms() - (last_at or -1e9)) >= PIN_DEBOUNCE_MS 
end

-- State encodings
local function BaseFromStateCode(s)
  if s == "3" then return "0" 
  elseif s == "4" then return "1"
  elseif s == "5" then return "2"
  else return s end
end

local function FaultedFromBase(baseStr, isFault)
  if not isFault then return baseStr end
  if baseStr == "0" then return "3"
  elseif baseStr == "1" then return "4"
  elseif baseStr == "2" then return "5"
  else return baseStr end
end

local function StateFromBoolean(val)
  if val == nil then return "2" end
  return val and "1" or "0"
end

local function GetColorOrDefault(name, key)
  local c = Controls[name]
  if c and c.String and c.String:match("%S") then return c.String else return DefaultColors[key] end
end

local function ResolveColorForPreview(textControlName, defaultKey)
  local ctrl = Controls[textControlName]
  local s = (ctrl and ctrl.String) or ""
  if s:match("%S") then
    return s
  end
  return DefaultColors[defaultKey]
end

local function UpdateColorPreview(textName, defaultKey, previewName)
  local preview = Controls[previewName]
  if not preview then return end
  preview.Color = ResolveColorForPreview(textName, defaultKey)
  preview.Boolean = true
end

local function UpdateAllColorPreviews()
  UpdateColorPreview("ColorMuted",     "Muted",   "ColorMuted_Preview")
  UpdateColorPreview("ColorUnmuted",   "Unmuted", "ColorUnmuted_Preview")
  UpdateColorPreview("ColorMixed",     "Mixed",   "ColorMixed_Preview")
  UpdateColorPreview("ColorAmpFault",  "AmpFault","ColorAmpFault_Preview")
end

local function ParseMuteInput(str)
  str = string.lower(str or "")
  if str == "muted" or str == "true"  then return "1" end
  if str == "unmuted" or str == "false" then return "0" end
  if str == "mixed" then return "2" end
  if str == "0" or str == "3" then return "0" end
  if str == "1" or str == "4" then return "1" end
  if str == "2" or str == "5" then return "2" end
  return nil
end

local function ParseAmpStatus(v)
  if v == nil then return 0 end
  local s = tostring(v):lower():gsub("^%s*(.-)%s*$","%1")
  if s == "" or s == "0" or s == "ok" then return 0 end
  if s:sub(1,2) == "ok" then return 0 end
  if s:find("200 ok", 1, true) then return 0 end
  return 1
end

local function period_s()
  local rate = (Controls.AmpFlashRate and Controls.AmpFlashRate.Value) or 100
  if rate > 100 then rate = 100 end
  if rate < 1   then rate = 1   end
  local T_fast, T_slow = 0.5, 12.0
  local t = (100 - rate) / 99.0
  return T_fast + (T_slow - T_fast) * t
end

local function AnyFaultActive()
  for g = 1, gCount do
    if faulted_groups[g] then return true end
  end
  return false
end

local function UsingMasterClock()
  return Controls.ClockToMaster and Controls.ClockToMaster.Boolean
         and masterConnected and masterComp
end

local function ReadMasterFlashNow()
  -- Immediately read master's current state and apply it
  if not masterComp then return end
  pcall(function()
    local isOn = (masterComp["Flash.Clock"].String == "1")
    FlashState = (not flash_suppressed()) and isOn or false
    OnFlashEdge()
  end)
end

local function StartFlashIfNeeded()
  if AnyFaultActive() then
    if UsingMasterClock() then
      -- Master's EventHandler drives flash; stop local timer
      if flashTimerRunning then
        FlashTicker:Stop()
        flashTimerRunning = false
        dbg("[FLASH] Local timer stopped (master drives)")
      end
      -- Apply master's current state immediately so we're in sync
      ReadMasterFlashNow()
    else
      -- Local clock mode
      if not flashTimerRunning then
        flashTimerRunning = true
        syncedOnce = false
        update_flash_state_and_schedule()
      end
    end
  else
    -- No faults: stop everything, clear flash
    if flashTimerRunning then
      FlashTicker:Stop()
      flashTimerRunning = false
      dbg("[FLASH] Timer stopped (no faults)")
    end
    FlashState = false
    syncedOnce = false
    lastFlashState = nil
    OnFlashEdge()
  end
end

local function recompute_group_fault(g)
  local any = (GroupAmpStatus[g] ~= 0)
  if not any and ZoneAmpStatus[g] then
    for m = 1, mCount do
      if ZoneAmpStatus[g][m] and ZoneAmpStatus[g][m] ~= 0 then 
        any = true; break 
      end
    end
  end
  faulted_groups[g] = any or nil
  return any and 1 or 0
end

local function UpdateFaultOutputs()
  local any = 0
  for g = 1, gCount do
    local gf = recompute_group_fault(g)
    if gf == 1 then any = 1 end
    local out = Controls["GroupFault_" .. g]
    if out then out.String = tostring(gf) end
  end
  if Controls.AnyFault then Controls.AnyFault.String = tostring(any) end
end

local function flash_suppressed() 
  return Controls.SuppressStatusFlash and Controls.SuppressStatusFlash.Boolean
end

---------------------------------------------------------------
-- Visual updaters
---------------------------------------------------------------
local function UpdateAllMute()
  if not Controls.All_Mute then return end

  local trues, falses, mixed = 0, 0, 0
  local anyFault = 0
  for g = 1, gCount do
    local group = Groups[g]
    if group then
      local s = BaseFromStateCode(group.GroupState.String or "0")
      if s == "1" then trues = trues + 1
      elseif s == "0" then falses = falses + 1
      elseif s == "2" then mixed  = mixed  + 1 end
    end
    if faulted_groups[g] then anyFault = 1 end
  end

  local base, color
  if mixed > 0 or (trues > 0 and falses > 0) then
    base  = "2"; color = GetColorOrDefault("ColorMixed","Mixed"); if Controls.AllMuteButton then Controls.AllMuteButton.Boolean = true end
  elseif trues == gCount then
    base  = "1"; color = GetColorOrDefault("ColorMuted","Muted"); if Controls.AllMuteButton then Controls.AllMuteButton.Boolean = true end
  else
    base  = "0"; color = GetColorOrDefault("ColorUnmuted","Unmuted"); if Controls.AllMuteButton then Controls.AllMuteButton.Boolean = false end
  end

  if Controls.AllMuteButton then Controls.AllMuteButton.Color = color end
  updatingAllMute = true
  Controls.All_Mute.String = FaultedFromBase(base, anyFault == 1)
  updatingAllMute = false
end

local function UpdateAllMuteOverlay()
  if not Controls.AllMuteButton then return end
  local mutedColor    = GetColorOrDefault("ColorMuted","Muted")
  local unmutedColor  = GetColorOrDefault("ColorUnmuted","Unmuted")
  local mixedColor    = GetColorOrDefault("ColorMixed","Mixed")
  local ampFaultColor = GetColorOrDefault("ColorAmpFault","AmpFault")

  local anyFault=false
    for g=1,gCount do 
      if faulted_groups[g] then 
        anyFault=true; break 
      end 
    end

  local color
  local effectiveFlash = (not flash_suppressed()) and FlashState
  if anyFault and effectiveFlash then 
    color = ampFaultColor
  else
    local s = BaseFromStateCode(Controls.All_Mute and Controls.All_Mute.String or "0")
    if s == "1" then color = mutedColor
    elseif s == "0" then color = unmutedColor
    else color = mixedColor end
  end

  Controls.AllMuteButton.Color = color
end

local function UpdateZoneAmpOverlay(g, m)
  local member = Groups[g].Members[m]; if not member then return end
  local zoneFault  = (ZoneAmpStatus[g][m] or 0) ~= 0
  local groupFault = (GroupAmpStatus[g] or 0) ~= 0
  local isMuted    = member.button.Boolean

  local mutedColor    = GetColorOrDefault("ColorMuted","Muted")
  local unmutedColor  = GetColorOrDefault("ColorUnmuted","Unmuted")
  local ampFaultColor = GetColorOrDefault("ColorAmpFault","AmpFault")
  local normalColor   = isMuted and mutedColor or unmutedColor

  local shouldFlash   = zoneFault or groupFault
  local effectiveFlash= (not flash_suppressed()) and FlashState

  if shouldFlash and effectiveFlash then
    member.button.Color = ampFaultColor
  else
    member.button.Color = normalColor
  end
end

local function UpdateGroupAmpOverlay(g)
  local group = Groups[g]; if not group then return end
  local mutedColor    = GetColorOrDefault("ColorMuted","Muted")
  local unmutedColor  = GetColorOrDefault("ColorUnmuted","Unmuted")
  local mixedColor    = GetColorOrDefault("ColorMixed","Mixed")
  local ampFaultColor = GetColorOrDefault("ColorAmpFault","AmpFault")
  local anyFault = faulted_groups[g] ~= nil
  local effectiveFlash = (not flash_suppressed()) and FlashState
  local color

  if anyFault and effectiveFlash then 
    color = ampFaultColor
  else
    local s = BaseFromStateCode(group.GroupState.String or "0")
    if s == "1" then 
      color = mutedColor 
    elseif s == "0" then 
      color = unmutedColor 
    else 
      color = mixedColor
    end
  end
  group.GroupButton.Color = color
end

local function UpdateGroupState(g)
  local group = Groups[g]; if not group then return end
  local trues,falses = 0,0

  for _, m in ipairs(group.Members) do 
    if m.button.Boolean then 
      trues = trues+1 
    else 
      falses = falses+1 
    end 
  end

  local stateStr,color

  if trues>0 and falses>0 then 
    stateStr = "2"; 
    color = GetColorOrDefault("ColorMixed","Mixed"); 
    group.GroupButton.Boolean=true
  elseif trues == #group.Members then 
    stateStr = "1"; 
    color = GetColorOrDefault("ColorMuted","Muted"); 
    group.GroupButton.Boolean=true
  else 
    stateStr = "0"; 
    color = GetColorOrDefault("ColorUnmuted","Unmuted"); 
    group.GroupButton.Boolean=false 
  end

  group.GroupButton.Color = color

  local groupFault = (GroupAmpStatus[g] ~= 0)
  for m = 1,mCount do 
    if ZoneAmpStatus[g][m] and ZoneAmpStatus[g][m] ~= 0 then 
      groupFault = true; break 
    end 
  end

  group.GroupState.String = FaultedFromBase(stateStr, groupFault)

  updatingState = true  -- Set guard to prevent recursive event handling
  local ok, err = pcall(function()
    for m, member in ipairs(group.Members) do
      local base = StateFromBoolean(member.button.Boolean)
      -- Zone mute outputs only 0 or 1 (no fault encoding on output)
      member.state.String = base
      UpdateZoneAmpOverlay(g, m)
    end
  end)
  updatingState = false  -- Always clear guard, even on error
  if not ok then dbg("[ERROR] UpdateGroupState: " .. tostring(err)) end
end

local function OnFlashEdge()
  for g = 1, gCount do
    if faulted_groups[g] then
      UpdateGroupAmpOverlay(g)
      for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
    end
  end
  UpdateAllMuteOverlay()
end

local function UpdateAllOverlays(g, m)
  UpdateGroupAmpOverlay(g)
  UpdateZoneAmpOverlay(g, m)
end

---------------------------------------------------------------
-- Master Clock Connection
---------------------------------------------------------------
local function UpdateMasterClockIndicator()
  if not Controls.MasterClockStatus then return end
  if masterConnected then
    Controls.MasterClockStatus.Boolean = true
    Controls.MasterClockStatus.Color   = "#00FF00"
  else
    Controls.MasterClockStatus.Boolean = false
    Controls.MasterClockStatus.Color   = "#80808080"
  end
end

local function DisconnectFromMaster()
  masterComp = nil
  masterConnected = false
  UpdateMasterClockIndicator()
  dbg("[MASTER CLOCK] Disconnected")
  -- Fall back to local flash timer if faults are active
  syncedOnce = false
  StartFlashIfNeeded()
end

local function ConnectToMaster()
  local codeName = (Controls.MasterCodeName and Controls.MasterCodeName.String or ""):gsub("^%s*(.-)%s*$", "%1")
  if codeName == "" then DisconnectFromMaster(); return end

  if type(Component) ~= "table" or type(Component.New) ~= "function" then
    dbg("[MASTER CLOCK] Component API not available")
    DisconnectFromMaster()
    return
  end

  local ok, comp = pcall(Component.New, codeName)
  if not ok or not comp then
    dbg("[MASTER CLOCK] '" .. codeName .. "' not found: " .. tostring(comp))
    DisconnectFromMaster()
    return
  end

  local flashCtrl = nil
  pcall(function()
    local ctrl = comp["Flash.Clock"]
    if ctrl then local _ = ctrl.String; flashCtrl = ctrl end
  end)

  if not flashCtrl then
    dbg("[MASTER CLOCK] Flash.Clock not accessible on '" .. codeName .. "'")
    DisconnectFromMaster()
    return
  end

  masterComp = comp
  masterConnected = true
  UpdateMasterClockIndicator()
  dbg("[MASTER CLOCK] Connected to '" .. codeName .. "'")

  -- EventHandler is the SOLE driver of flash in master mode.
  -- Always track master state so FlashState is pre-synced when faults appear.
  pcall(function()
    flashCtrl.EventHandler = function()
      if not (Controls.ClockToMaster and Controls.ClockToMaster.Boolean) then return end
      if not masterConnected then return end
      local isOn = (flashCtrl.String == "1")
      FlashState = (not flash_suppressed()) and isOn or false
      if AnyFaultActive() then OnFlashEdge() end
    end
  end)

  -- Master takes over: stop local FlashTicker
  if flashTimerRunning then
    FlashTicker:Stop()
    flashTimerRunning = false
    dbg("[FLASH] Local timer stopped (master connected)")
  end

  -- Immediately read current master state
  ReadMasterFlashNow()
end

local function StartMasterReconnect()
  masterReconnTimer:Stop()
  if Controls.ClockToMaster and Controls.ClockToMaster.Boolean and not masterConnected then
    masterReconnTimer:Start(MASTER_RECONNECT_S)
  end
end

local function StopMasterReconnect()
  masterReconnTimer:Stop()
end

---------------------------------------------------------------
-- Wiring + Initialization
---------------------------------------------------------------
local function BindRuntimeSettings()
  dbg("BindRuntimeSettings()")

  -- Setup deferred update timer handler
  deferredUpdateTimer.EventHandler = function()
    deferredUpdateTimer:Stop()
    for g, _ in pairs(pendingGroupUpdates) do
      UpdateGroupState(g)
      for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
    end
    pendingGroupUpdates = {}
    UpdateAllMute()
  end

  for g = 1, gCount do
    ZoneAmpStatus[g] = {}
    GroupAmpStatus[g] = 0

    for m = 1,mCount do 
      ZoneAmpStatus[g][m] = 0 end
    end

  for g = 1, gCount do
    local groupButton = Controls["GroupButton_" .. g]
    local groupState  = Controls["Group_Mute_" .. g]
    local groupAmp    = Controls["GroupAmpStatus_" .. g]
    local respectCtl  = Controls["GroupAllMuteEnable_" .. g]
    local members     = {}

    if respectCtl and respectCtl.Boolean ~= true then respectCtl.Boolean = true end
    AllRespect[g] = respectCtl and respectCtl.Boolean or true
    if respectCtl then respectCtl.EventHandler = function(c) AllRespect[g] = c.Boolean end end

    if groupAmp then
      groupAmp.EventHandler = function(ctrl)
        GroupAmpStatus[g] = ParseAmpStatus(ctrl.String)
        faulted_groups[g] = (GroupAmpStatus[g] ~= 0) or nil
        UpdateGroupAmpOverlay(g); UpdateAllMute(); UpdateFaultOutputs()
        StartFlashIfNeeded()
      end
    end

    for m = 1, mCount do
      local zbtn  = Controls["Zone_Mute_G" .. g .. "-M" .. m]
      local zst   = Controls["ZoneMute_" .. g .. "_" .. m]
      local zamp  = Controls["ZoneAmpStatus_" .. g .. "_" .. m]
      local zlbl  = Controls["ZoneLabel_" .. g .. "_" .. m]

      table.insert(members, { button = zbtn, state = zst })

      if zbtn then
        zbtn.EventHandler = function()
          UpdateGroupState(g); UpdateAllMute(); UpdateZoneAmpOverlay(g, m)
        end
      end

      if zst then
        zst.EventHandler = function()
          if updatingState then return end  -- Prevent recursive calls during state update
          local val = ParseMuteInput(zst.String); if not val then return end
          -- Only process mute (1) or unmute (0) commands, ignore mixed (2)
          if val == "1" then 
            zbtn.Boolean = true
          elseif val == "0" then 
            zbtn.Boolean = false
          else
            return  -- Ignore "2" (mixed) - zones can only be muted or unmuted
          end
          -- Defer UpdateGroupState to allow simultaneous pin changes to settle
          pendingGroupUpdates[g] = true
          deferredUpdateTimer:Stop()
          deferredUpdateTimer:Start(0.01)  -- 10ms delay to batch simultaneous changes
        end
      end

      if zamp then
        zamp.EventHandler = function(ctrl)
          ZoneAmpStatus[g][m] = ParseAmpStatus(ctrl.String)
          if ZoneAmpStatus[g][m] ~= 0 then faulted_groups[g] = true else faulted_groups[g] = (GroupAmpStatus[g] ~= 0) and true or nil end
            UpdateAllMute(); UpdateFaultOutputs(); UpdateAllOverlays(g, m)
            StartFlashIfNeeded()
        end
      end
    end

    Groups[g] = { GroupButton = groupButton, GroupState = groupState, Members = members }

    if groupButton then
      groupButton.EventHandler = function()
        local state = groupButton.Boolean
        for _, member in ipairs(members) do member.button.Boolean = state end
        for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
        UpdateGroupState(g); UpdateAllMute()
      end
    end

    if groupState then
      groupState.EventHandler = function()
        local n = now_ms(); if not debounce_ok(PinLastAt.Group[g]) then return end
        local val = ParseMuteInput(groupState.String); if not val then return end
        if PinState.Group[g] == val and ((val == "0" and not groupButton.Boolean) or (val == "1" and groupButton.Boolean)) then return end
        PinLastAt.Group[g] = n; PinState.Group[g] = val
        if val == "2" then
          groupButton.Color = Controls.ColorMixed.String
          groupState.String = "2"
          UpdateAllMute()
          return
        end
        groupButton.Boolean = (val ~= "0")
        for _, member in ipairs(members) do member.button.Boolean = (val == "1") end
        for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
        UpdateGroupState(g); UpdateAllMute()
        UpdateGroupAmpOverlay(g)
        for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
      end
    end
    UpdateGroupState(g)
  end


  if gCount > 1 and Controls.AllMuteButton and Controls.All_Mute then
    PinState.All = StateFromBoolean(Controls.AllMuteButton.Boolean)

    Controls.AllMuteButton.EventHandler = function()
      local state = Controls.AllMuteButton.Boolean
      for g = 1, gCount do
        if AllRespect[g] then
          for _, member in ipairs(Groups[g].Members) do member.button.Boolean = state end
          for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
          UpdateGroupState(g)
        end
      end
      UpdateAllMute()
    end

    Controls.All_Mute.EventHandler = function()
      if updatingAllMute then return end  -- Ignore internal write-backs from UpdateAllMute()
      local val = ParseMuteInput(Controls.All_Mute.String); if not val then return end
      if val == "2" then
        Controls.AllMuteButton.Boolean = true
        Controls.AllMuteButton.Color   = Controls.ColorMixed.String
        Controls.All_Mute.String = "2"
        return
      end
      local target = (val == "1")
      Controls.AllMuteButton.Boolean = target
      for g = 1, gCount do
        if AllRespect[g] then
          for _, member in ipairs(Groups[g].Members) do member.button.Boolean = target end
          for m = 1, mCount do UpdateZoneAmpOverlay(g, m) end
          UpdateGroupState(g)
        end
      end
      UpdateAllMute()
    end
  end

  for _, ctrl in ipairs(colorControls) do
    if ctrl then 
      ctrl.EventHandler = function() 
        UpdateAllMute()
        UpdateAllMuteOverlay()
        OnFlashEdge()
        UpdateAllColorPreviews()
      end 
    end
  end

  for g = 1, gCount do
    local gctrl = Controls["GroupAmpStatus_" .. g]
    GroupAmpStatus[g] = ParseAmpStatus(gctrl and gctrl.String)
    local groupAny = (GroupAmpStatus[g] ~= 0)
    for m = 1, mCount do
      local zctrl = Controls["ZoneAmpStatus_" .. g .. "_" .. m]
      ZoneAmpStatus[g][m] = ParseAmpStatus(zctrl and zctrl.String)
      if ZoneAmpStatus[g][m] ~= 0 then groupAny = true end
    end
    faulted_groups[g] = groupAny or nil
  end

  for g = 1, gCount do
    UpdateGroupAmpOverlay(g)
    for m = 1, mCount do 
      UpdateZoneAmpOverlay(g, m) 
    end
  end

  UpdateAllMute()
  UpdateAllMuteOverlay()
  UpdateFaultOutputs()

  -- Master clock sync
  if Controls.ClockToMaster then
    Controls.ClockToMaster.EventHandler = function()
      if Controls.ClockToMaster.Boolean then
        ConnectToMaster()
        if masterConnected then StopMasterReconnect() else StartMasterReconnect() end
      else
        StopMasterReconnect()
        DisconnectFromMaster()
      end
      syncedOnce = false
      StartFlashIfNeeded()
    end
  end

  if Controls.MasterCodeName then
    if not (Controls.MasterCodeName.String or ""):match("%S") then
      Controls.MasterCodeName.String = "GroupMuteMasterController"
    end
    Controls.MasterCodeName.EventHandler = function()
      if Controls.ClockToMaster and Controls.ClockToMaster.Boolean then
        ConnectToMaster()
        if masterConnected then StopMasterReconnect() else StartMasterReconnect() end
        syncedOnce = false
        StartFlashIfNeeded()
      end
    end
  end

  masterReconnTimer.EventHandler = function()
    masterReconnTimer:Stop()
    if Controls.ClockToMaster and Controls.ClockToMaster.Boolean and not masterConnected then
      ConnectToMaster()
      if masterConnected then StopMasterReconnect() else StartMasterReconnect() end
      syncedOnce = false
      StartFlashIfNeeded()
    end
  end

  -- Initial master connection
  if Controls.ClockToMaster and Controls.ClockToMaster.Boolean then
    ConnectToMaster()
    if not masterConnected then StartMasterReconnect() end
  end
  UpdateMasterClockIndicator()

  syncedOnce, lastFlashState = false, nil
  StartFlashIfNeeded()
end

---------------------------------------------------------------
-- Flash subsystem
---------------------------------------------------------------
function update_flash_state_and_schedule()
  -- This function is the LOCAL clock only.
  -- When clocked to master, the master's EventHandler drives flash;
  -- this function should not be called in that mode.
  local T = period_s()
  
  -- Use os.time() as shared reference, os.clock() for sub-second smoothness
  -- Re-sync at each second boundary to prevent drift
  local current_time = os.time()
  local current_clock = os.clock()
  
  if sync_time_base == nil or current_time ~= sync_time_base then
    -- New second boundary - resync
    sync_time_base = current_time
    sync_clock_base = current_clock
  end
  
  -- Compute smooth time: wall-clock seconds + sub-second interpolation
  local tmono = sync_time_base + (current_clock - sync_clock_base)
  local within = tmono % T
  local phase  = within / T
  
  -- Shift phase so sync point (phase=0) occurs in middle of OFF period
  -- With FLASH_DUTY=0.25: ON from shifted phase 0.0-0.25, OFF from 0.25-1.0
  -- This way any timing resets happen during the OFF state
  local shifted_phase = (phase + 0.375) % 1.0
  local isOn = (shifted_phase >= 0.0 and shifted_phase < FLASH_DUTY)

  if not syncedOnce then
    dbg(string.format("[FLASH] Synchronized (sync=true, T=%.0f ms, duty=%.0f%%)", T*1000, FLASH_DUTY*100))
    syncedOnce, lastFlashState = true, isOn
  end
  if lastFlashState ~= isOn then
    dbg(string.format(isOn and "[FLASH] Flash ON  (phase=%.3f, T=%.0f ms)" or "[FLASH] Flash OFF (phase=%.3f, T=%.0f ms)", shifted_phase, T*1000))
    lastFlashState = isOn
  end

  FlashState = (not (Controls.SuppressStatusFlash and Controls.SuppressStatusFlash.Boolean)) and isOn or false
  OnFlashEdge()

  -- If no faults remain, stop the timer and exit
  if not AnyFaultActive() then
    FlashTicker:Stop()
    flashTimerRunning = false
    FlashState = false
    OnFlashEdge()
    dbg("[FLASH] Timer stopped (no faults)")
    return
  end

  -- Calculate time to next transition based on shifted phase
  local to_next = isOn and (FLASH_DUTY - shifted_phase) * T or ((1.0 - shifted_phase + FLASH_DUTY) % 1.0) * T
  if to_next < 0.01 then to_next = T end  -- Safety: avoid too-short delays
  local delay   = math.max(0.01, math.min(0.10, to_next * 0.5))
  flashTimerRunning = true
  FlashTicker:Start(delay)
end

FlashTicker.EventHandler = function() update_flash_state_and_schedule() end

if Controls.AmpFlashRate then
  Controls.AmpFlashRate.EventHandler = function()
    syncedOnce = false
    StartFlashIfNeeded()
  end
end

if Controls.SuppressStatusFlash then
  Controls.SuppressStatusFlash.EventHandler = function()
    OnFlashEdge()
  end
end

---------------------------------------------------------------
-- Initialize
---------------------------------------------------------------
Timer.CallAfter(function()
  BindRuntimeSettings()
  UpdateAllColorPreviews()
end, 0.1)

end -- if Controls

--[[Copyright 2026 Riley Watson
Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial 
portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.]]
