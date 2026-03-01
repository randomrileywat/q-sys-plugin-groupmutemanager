---------------------------------------------------------------
-- Q-SYS Plugin: Group Mute Master Controller
-- Companion plugin for Group Mute Manager
-- Riley Watson
-- rwatson@onediversified.com
--
-- Current Version:
-- v260301.2 (RWatson)
--  - Feature: Added flash clock broadcast (Flash_Clock output pin,
--    FlashRate knob, FlashClock_Preview LED). GroupMuteManager
--    instances with "Clock to Master" enabled sync their fault
--    flash timing to this output for unified visual behavior.
--
-- Change Log:
-- v260301.1 (RWatson)
--  - Initial release: Master controller for multiple
--    Group Mute Manager instances via Component code names.
--  - Per-instance "All Mute" control buttons with status/connection LEDs.
--  - Global "Mute All" button affecting every connected instance.
--  - Global_Mute bidirectional text pin + GlobalMuteSet/GlobalMuteReset triggers.
--  - Settings: poll rate, auto-reconnect, color customization with previews.
--  - Controls use dot-notation (All.Mute, Group.Mute.1) for Q-SYS script access.
--  - "No Script Access" shown when controls aren't found on a connected component.
--  - Button handlers use string state logic (not Boolean toggle) to correctly
--    handle tri-state (muted/unmuted/mixed).
--
-- Description:
--  This plugin connects to multiple Group Mute Manager
--  instances by their Q-SYS code names and provides:
--    - Per-instance "All Mute" control buttons
--    - A global "Mute All" button affecting every instance
--    - Live status readback with color-coded indicators
--    - Auto-reconnect for resilience
--
--  Communication uses the Q-SYS Component API
--  (Component.New) to read/write each target instance's
--  All_Mute control. Falls back to Group_Mute_1 when the
--  target has only a single group.
--
---------------------------------------------------------------

---------------------------------------------------------------
-- Plugin Info
---------------------------------------------------------------
local MAX_INSTANCES = 32  -- Maximum number of GroupMuteManager instances

PluginInfo = {
  Name = "Group Mute Master Controller",
  Version = "260301.2",
  Id = "b7c6919b-12d4-4e57-a82f-719c16abe357",
  Author = "Riley Watson",
  Description = "Master controller for up to " .. MAX_INSTANCES .. " Group Mute Manager instances. Provides centralized All Mute control via Component code names.",
  ShowDebug = true
}

---------------------------------------------------------------
-- Pages
---------------------------------------------------------------
function GetPages(props)
  return {
    { name = "Control" },
    { name = "Settings" }
  }
end

---------------------------------------------------------------
-- Properties
---------------------------------------------------------------
function GetProperties()
  return {
    { Name = "Instance Count", Type = "integer", Min = 1, Max = MAX_INSTANCES, Value = 2 }
  }
end

---------------------------------------------------------------
-- Controls
---------------------------------------------------------------
function GetControls(props)
  local ctrls = {}

  -- Global Mute
  table.insert(ctrls, { Name = "GlobalMuteButton", ControlType = "Button", ButtonType = "Toggle" })
  table.insert(ctrls, { Name = "Global_Mute", ControlType = "Text", UserPin = true, PinStyle = "Both" })
  table.insert(ctrls, { Name = "GlobalMuteSet", ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input" })
  table.insert(ctrls, { Name = "GlobalMuteReset", ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input" })

  -- Per-instance controls (always create MAX so pins stay stable)
  for i = 1, MAX_INSTANCES do
    table.insert(ctrls, { Name = "CodeName_" .. i,            ControlType = "Text" })
    table.insert(ctrls, { Name = "InstanceLabel_" .. i,       ControlType = "Text" })
    table.insert(ctrls, { Name = "InstanceMuteButton_" .. i,  ControlType = "Button", ButtonType = "Toggle" })
    table.insert(ctrls, { Name = "InstanceStatus_" .. i,      ControlType = "Indicator", IndicatorType = "Text" })
    table.insert(ctrls, { Name = "ConnectionStatus_" .. i,    ControlType = "Indicator", IndicatorType = "Led" })
  end

  -- Settings
  table.insert(ctrls, { Name = "PollRate",       ControlType = "Knob", ControlUnit = "Integer", Min = 100, Max = 5000, Value = 500 })
  table.insert(ctrls, { Name = "AutoReconnect",  ControlType = "Button", ButtonType = "Toggle" })
  table.insert(ctrls, { Name = "ReconnectAll",   ControlType = "Button", ButtonType = "Trigger" })

  table.insert(ctrls, { Name = "ColorMuted",        ControlType = "Text" })
  table.insert(ctrls, { Name = "ColorUnmuted",      ControlType = "Text" })
  table.insert(ctrls, { Name = "ColorMixed",        ControlType = "Text" })
  table.insert(ctrls, { Name = "ColorDisconnected", ControlType = "Text" })

  table.insert(ctrls, { Name = "ColorMuted_Preview",        ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorUnmuted_Preview",      ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorMixed_Preview",        ControlType = "Indicator", IndicatorType = "Led" })
  table.insert(ctrls, { Name = "ColorDisconnected_Preview", ControlType = "Indicator", IndicatorType = "Led" })

  -- Flash clock broadcast
  table.insert(ctrls, { Name = "FlashRate", ControlType = "Knob", ControlUnit = "Integer", Min = 1, Max = 100, Value = 80 })
  table.insert(ctrls, { Name = "Flash_Clock", ControlType = "Text", UserPin = true, PinStyle = "Output" })
  table.insert(ctrls, { Name = "FlashClock_Preview", ControlType = "Indicator", IndicatorType = "Led" })

  return ctrls
end

---------------------------------------------------------------
-- Layout
---------------------------------------------------------------
function GetControlLayout(props)
  local pages      = { "Control", "Settings" }
  local page_index = props["page_index"].Value
  local current_page = pages[page_index] or "Control"

  local layout, graphics = {}, {}
  local iCount = math.max(1, math.min(MAX_INSTANCES, props["Instance Count"].Value or 2))

  -----------------------------------------------------------
  -- Control Page
  -----------------------------------------------------------
  if current_page == "Control" then

    -- Title bar
    table.insert(graphics, {
      Type = "Header", Position = {0, 0}, Size = {600, 32},
      Text = "Group Mute Master Controller", HTextAlign = "Center",
      FontSize = 14, IsBold = true
    })

    -- Global Mute button (full width)
    layout["GlobalMuteButton"] = {
      Legend = "GLOBAL MUTE ALL",
      Style  = "Button",
      Position = {10, 36}, Size = {580, 34}
    }
    layout["Global_Mute"] = {
      PrettyName = "Global Mute", Style = "Text",
      Position = {0, 0}, Size = {0, 0}
    }
    layout["GlobalMuteSet"] = {
      PrettyName = "Global Mute~Set", Style = "Button",
      Position = {0, 0}, Size = {0, 0}
    }
    layout["GlobalMuteReset"] = {
      PrettyName = "Global Mute~Reset", Style = "Button",
      Position = {0, 0}, Size = {0, 0}
    }

    -- Column headers
    local hdrY = 78
    local colHdr = {
      { x =  10, w = 140, text = "Code Name" },
      { x = 158, w = 120, text = "Label" },
      { x = 286, w = 160, text = "All Mute" },
      { x = 454, w = 100, text = "Status" },
      { x = 562, w =  28, text = "Link" },
    }
    for _, h in ipairs(colHdr) do
      table.insert(graphics, {
        Type = "Label", Position = {h.x, hdrY}, Size = {h.w, 16},
        Text = h.text, HTextAlign = "Center", FontSize = 9, IsBold = true
      })
    end

    -- Instance rows
    local rowY, rowH = 98, 28
    for i = 1, iCount do
      local y = rowY + (i - 1) * rowH

      layout["CodeName_" .. i] = {
        PrettyName = "Instance " .. i .. "~Code Name",
        Style = "Text", Position = {10, y}, Size = {140, 22}
      }
      layout["InstanceLabel_" .. i] = {
        PrettyName = "Instance " .. i .. "~Label",
        Style = "Text", Position = {158, y}, Size = {120, 22}
      }
      layout["InstanceMuteButton_" .. i] = {
        PrettyName = "Instance " .. i .. "~Mute",
        Legend = "Instance " .. i,
        Style = "Button", Position = {286, y}, Size = {160, 22}
      }
      layout["InstanceStatus_" .. i] = {
        PrettyName = "Instance " .. i .. "~Status",
        Style = "Text", Position = {454, y}, Size = {100, 22}
      }
      layout["ConnectionStatus_" .. i] = {
        PrettyName = "Instance " .. i .. "~Link",
        Style = "LED", Position = {566, y}, Size = {20, 20}
      }
    end

  -----------------------------------------------------------
  -- Settings Page
  -----------------------------------------------------------
  elseif current_page == "Settings" then

    local labels = {
      { text = "Poll Rate (ms)",       y = 30 },
      { text = "Auto-Reconnect",       y = 66 },
      { text = "Reconnect Now",        y = 86 },
      { text = "Color - Muted",        y = 116 },
      { text = "Color - Unmuted",      y = 136 },
      { text = "Color - Mixed",        y = 156 },
      { text = "Color - Disconnected", y = 176 },
      { text = "Flash Rate",           y = 210 },
    }
    for _, item in ipairs(labels) do
      table.insert(graphics, {
        Type = "Label", Position = {8, item.y}, Size = {150, 16},
        Text = item.text, HTextAlign = "Right"
      })
    end
    table.insert(graphics, {
      Type = "Label", Position = {8, 250}, Size = {340, 16},
      Text = "Plugin Version: " .. (PluginInfo.Version or "Unknown"),
      HTextAlign = "Left"
    })

    layout["PollRate"]      = { Style = "Knob",   Position = {170, 16}, Size = {36, 36} }
    layout["AutoReconnect"] = { Style = "Button",  Legend = "", Position = {170, 66}, Size = {16, 16} }
    layout["ReconnectAll"]  = { Style = "Button",  Legend = "Reconnect", Position = {170, 86}, Size = {80, 16} }

    layout["ColorMuted"]        = { Style = "Text", Position = {170, 116}, Size = {130, 16}, Padding = 0 }
    layout["ColorUnmuted"]      = { Style = "Text", Position = {170, 136}, Size = {130, 16}, Padding = 0 }
    layout["ColorMixed"]        = { Style = "Text", Position = {170, 156}, Size = {130, 16}, Padding = 0 }
    layout["ColorDisconnected"] = { Style = "Text", Position = {170, 176}, Size = {130, 16}, Padding = 0 }

    layout["ColorMuted_Preview"]        = { Style = "LED", Position = {310, 114}, Size = {20, 20} }
    layout["ColorUnmuted_Preview"]      = { Style = "LED", Position = {310, 134}, Size = {20, 20} }
    layout["ColorMixed_Preview"]        = { Style = "LED", Position = {310, 154}, Size = {20, 20} }
    layout["ColorDisconnected_Preview"] = { Style = "LED", Position = {310, 174}, Size = {20, 20} }

    layout["FlashRate"]          = { Style = "Knob", Position = {170, 196}, Size = {36, 36} }
    layout["Flash_Clock"]        = { PrettyName = "Flash~Clock", Style = "Text", Position = {0, 0}, Size = {0, 0} }
    layout["FlashClock_Preview"] = { Style = "LED", Position = {216, 198}, Size = {20, 20} }
  end

  return layout, graphics
end

---------------------------------------------------------------
-- Runtime
---------------------------------------------------------------
if Controls then

local DEBUG_LOG_ON = true
local function dbg(msg) if DEBUG_LOG_ON then print(msg) end end

local iCount = Properties["Instance Count"].Value

-- Instance tracking: { comp, connected, codeName, muteCtrlName }
local Instances = {}
for i = 1, iCount do
  Instances[i] = { comp = nil, connected = false, codeName = "", muteCtrlName = nil }
end

local DefaultColors = {
  Muted        = "#80FF0000",
  Unmuted      = "#8000530f",
  Mixed        = "#80FFFF00",
  Disconnected = "#80808080"
}

local PollTimer            = Timer.New()
local updatingFromRemote   = false
local suppressGlobalPin    = false

-- Flash clock broadcast
local FlashTimer           = Timer.New()
local flash_sync_time_base = nil
local flash_sync_clock_base = nil

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function GetColorOrDefault(name, key)
  local c = Controls[name]
  if c and c.String and c.String:match("%S") then return c.String else return DefaultColors[key] end
end

local function BaseFromStateCode(s)
  if s == "3" then return "0"
  elseif s == "4" then return "1"
  elseif s == "5" then return "2"
  else return s end
end

local function StateLabel(s)
  local base = BaseFromStateCode(s or "0")
  if base == "1" then return "Muted"
  elseif base == "0" then return "Unmuted"
  elseif base == "2" then return "Mixed"
  else return "Unknown" end
end

local function ParseMuteInput(str)
  str = string.lower(str or "")
  if str == "muted"   or str == "true"  then return "1" end
  if str == "unmuted" or str == "false" then return "0" end
  if str == "mixed"   then return "2" end
  if str == "0" or str == "3" then return "0" end
  if str == "1" or str == "4" then return "1" end
  if str == "2" or str == "5" then return "2" end
  return nil
end

local function GetInstanceDisplayName(i)
  local label = Controls["InstanceLabel_" .. i].String or ""
  if label:match("%S") then return label end
  local code = Controls["CodeName_" .. i].String or ""
  if code:match("%S") then return code end
  return "Instance " .. i
end

local function UpdateColorPreview(textName, defaultKey, previewName)
  local preview = Controls[previewName]; if not preview then return end
  local ctrl = Controls[textName]
  local s = (ctrl and ctrl.String) or ""
  preview.Color   = s:match("%S") and s or DefaultColors[defaultKey]
  preview.Boolean = true
end

local function UpdateAllColorPreviews()
  UpdateColorPreview("ColorMuted",        "Muted",        "ColorMuted_Preview")
  UpdateColorPreview("ColorUnmuted",      "Unmuted",      "ColorUnmuted_Preview")
  UpdateColorPreview("ColorMixed",        "Mixed",        "ColorMixed_Preview")
  UpdateColorPreview("ColorDisconnected", "Disconnected", "ColorDisconnected_Preview")
end

---------------------------------------------------------------
-- Flash Clock Broadcast
---------------------------------------------------------------
local MASTER_FLASH_DUTY = 0.25

local function master_period_s()
  local rate = (Controls.FlashRate and Controls.FlashRate.Value) or 80
  rate = math.max(1, math.min(100, rate))
  local T_fast, T_slow = 0.5, 12.0
  local t = (100 - rate) / 99.0
  return T_fast + (T_slow - T_fast) * t
end

function update_master_flash()
  local T = master_period_s()
  local current_time = os.time()
  local current_clock = os.clock()

  if flash_sync_time_base == nil or current_time ~= flash_sync_time_base then
    flash_sync_time_base = current_time
    flash_sync_clock_base = current_clock
  end

  local tmono = flash_sync_time_base + (current_clock - flash_sync_clock_base)
  local within = tmono % T
  local phase  = within / T
  local shifted_phase = (phase + 0.375) % 1.0
  local isOn = (shifted_phase >= 0.0 and shifted_phase < MASTER_FLASH_DUTY)

  Controls.Flash_Clock.String = isOn and "1" or "0"
  if Controls.FlashClock_Preview then
    Controls.FlashClock_Preview.Boolean = isOn
    Controls.FlashClock_Preview.Color = isOn and "#FFFF0000" or "#80808080"
  end

  local to_next = isOn
    and (MASTER_FLASH_DUTY - shifted_phase) * T
    or  ((1.0 - shifted_phase + MASTER_FLASH_DUTY) % 1.0) * T
  if to_next < 0.01 then to_next = T end
  local delay = math.max(0.01, math.min(0.10, to_next * 0.5))
  FlashTimer:Start(delay)
end

---------------------------------------------------------------
-- Forward declarations
---------------------------------------------------------------
local ReadInstanceState
local UpdateGlobalState
local ConnectInstance
local DisconnectInstance

---------------------------------------------------------------
-- State Reading
---------------------------------------------------------------
ReadInstanceState = function(i)
  local inst = Instances[i]
  if not inst or not inst.connected or not inst.comp then return end

  local ok, err = pcall(function()
    local remoteCtrl = inst.comp[inst.muteCtrlName]
    if not remoteCtrl then
      error("Control '" .. tostring(inst.muteCtrlName) .. "' not accessible")
    end

    local state = remoteCtrl.String or "0"
    local base  = BaseFromStateCode(state)

    updatingFromRemote = true

    Controls["InstanceStatus_" .. i].String = StateLabel(state)

    local color, legend
    local displayName = GetInstanceDisplayName(i)

    if base == "1" then
      color  = GetColorOrDefault("ColorMuted", "Muted")
      Controls["InstanceMuteButton_" .. i].Boolean = true
      legend = displayName .. " (Muted)"
    elseif base == "0" then
      color  = GetColorOrDefault("ColorUnmuted", "Unmuted")
      Controls["InstanceMuteButton_" .. i].Boolean = false
      legend = displayName .. " (Unmuted)"
    else
      color  = GetColorOrDefault("ColorMixed", "Mixed")
      Controls["InstanceMuteButton_" .. i].Boolean = true
      legend = displayName .. " (Mixed)"
    end

    Controls["InstanceMuteButton_" .. i].Color  = color
    Controls["InstanceMuteButton_" .. i].Legend  = legend

    updatingFromRemote = false
  end)

  if not ok then
    updatingFromRemote = false
    dbg("[INSTANCE " .. i .. "] Read error: " .. tostring(err))
    inst.connected = false
    Controls["ConnectionStatus_" .. i].Boolean = false
    Controls["ConnectionStatus_" .. i].Color   = "Red"
    Controls["InstanceStatus_" .. i].String    = "Error"
    Controls["InstanceMuteButton_" .. i].Color  = GetColorOrDefault("ColorDisconnected", "Disconnected")
    Controls["InstanceMuteButton_" .. i].Legend  = GetInstanceDisplayName(i) .. " (Error)"
  end
end

---------------------------------------------------------------
-- State Writing
---------------------------------------------------------------
local function WriteInstanceMute(i, muteStr)
  local inst = Instances[i]
  if not inst or not inst.connected or not inst.comp then return false end

  local ok, err = pcall(function()
    local remoteCtrl = inst.comp[inst.muteCtrlName]
    if remoteCtrl then remoteCtrl.String = muteStr end
  end)

  if not ok then
    dbg("[INSTANCE " .. i .. "] Write error: " .. tostring(err))
    return false
  end
  return true
end

---------------------------------------------------------------
-- Connection Management
---------------------------------------------------------------
DisconnectInstance = function(i)
  Instances[i] = { comp = nil, connected = false, codeName = "", muteCtrlName = nil }
  Controls["ConnectionStatus_" .. i].Boolean = false
  Controls["ConnectionStatus_" .. i].Color   = GetColorOrDefault("ColorDisconnected", "Disconnected")
  Controls["InstanceStatus_" .. i].String    = ""
  Controls["InstanceMuteButton_" .. i].Color  = GetColorOrDefault("ColorDisconnected", "Disconnected")
  Controls["InstanceMuteButton_" .. i].Legend  = GetInstanceDisplayName(i)
end

ConnectInstance = function(i)
  local codeName = (Controls["CodeName_" .. i].String or ""):gsub("^%s*(.-)%s*$", "%1")

  if codeName == "" then
    DisconnectInstance(i)
    return
  end

  -- Guard: Component API availability
  if type(Component) ~= "table" or type(Component.New) ~= "function" then
    dbg("[INSTANCE " .. i .. "] Component API not available in this environment")
    Controls["ConnectionStatus_" .. i].Boolean = false
    Controls["ConnectionStatus_" .. i].Color   = "Red"
    Controls["InstanceStatus_" .. i].String    = "No API"
    Controls["InstanceMuteButton_" .. i].Color  = GetColorOrDefault("ColorDisconnected", "Disconnected")
    Controls["InstanceMuteButton_" .. i].Legend  = GetInstanceDisplayName(i) .. " (No API)"
    return
  end

  local ok, comp = pcall(Component.New, codeName)
  if not ok or not comp then
    Instances[i] = { comp = nil, connected = false, codeName = codeName, muteCtrlName = nil }
    Controls["ConnectionStatus_" .. i].Boolean = false
    Controls["ConnectionStatus_" .. i].Color   = "Red"
    Controls["InstanceStatus_" .. i].String    = "Not Found"
    Controls["InstanceMuteButton_" .. i].Color  = GetColorOrDefault("ColorDisconnected", "Disconnected")
    Controls["InstanceMuteButton_" .. i].Legend  = GetInstanceDisplayName(i) .. " (N/C)"
    dbg("[INSTANCE " .. i .. "] Failed: '" .. codeName .. "' – " .. tostring(comp))
    return
  end

  -- Determine mute control: prefer All.Mute (multi-group), fall back to Group.Mute.1 (single-group).
  -- Q-SYS exposes plugin controls via dot-notation when Script Access is enabled.
  local muteCtrlName = nil
  local namesToTry = { "All.Mute", "Group.Mute.1" }

  for _, tryName in ipairs(namesToTry) do
    local testOk, _ = pcall(function()
      local ctrl = comp[tryName]
      if ctrl then
        local _ = ctrl.String
        muteCtrlName = tryName
      end
    end)
    if muteCtrlName then
      dbg("[INSTANCE " .. i .. "] Found mute control: '" .. muteCtrlName .. "'")
      break
    end
  end

  if not muteCtrlName then
    Instances[i] = { comp = nil, connected = false, codeName = codeName, muteCtrlName = nil }
    Controls["ConnectionStatus_" .. i].Boolean = false
    Controls["ConnectionStatus_" .. i].Color   = "Red"
    Controls["InstanceStatus_" .. i].String    = "No Script Access"
    Controls["InstanceMuteButton_" .. i].Color  = GetColorOrDefault("ColorDisconnected", "Disconnected")
    Controls["InstanceMuteButton_" .. i].Legend  = GetInstanceDisplayName(i) .. " (No Script Access)"
    dbg("[INSTANCE " .. i .. "] No mute control found on '" .. codeName .. "'. Ensure Script Access is enabled on the target plugin (right-click > Properties > Script Access).")
    return
  end

  Instances[i] = { comp = comp, connected = true, codeName = codeName, muteCtrlName = muteCtrlName }
  Controls["ConnectionStatus_" .. i].Boolean = true
  Controls["ConnectionStatus_" .. i].Color   = "#00FF00"
  dbg("[INSTANCE " .. i .. "] Connected to '" .. codeName .. "' via '" .. muteCtrlName .. "'")

  -- Try event-driven updates (nice-to-have; poll is the safety net)
  pcall(function()
    comp[muteCtrlName].EventHandler = function()
      ReadInstanceState(i)
      UpdateGlobalState()
    end
  end)

  ReadInstanceState(i)
end

---------------------------------------------------------------
-- Global State
---------------------------------------------------------------
UpdateGlobalState = function()
  local muted, unmuted, mixed = 0, 0, 0
  local connected = 0

  for i = 1, iCount do
    local inst = Instances[i]
    if inst and inst.connected then
      connected = connected + 1
      local status = Controls["InstanceStatus_" .. i].String or ""
      if     status == "Muted"   then muted   = muted   + 1
      elseif status == "Unmuted" then unmuted  = unmuted + 1
      elseif status == "Mixed"   then mixed    = mixed   + 1 end
    end
  end

  if connected == 0 then
    Controls.GlobalMuteButton.Color   = GetColorOrDefault("ColorDisconnected", "Disconnected")
    Controls.GlobalMuteButton.Legend   = "GLOBAL MUTE ALL (No Connections)"
    Controls.GlobalMuteButton.Boolean  = false
    suppressGlobalPin = true
    Controls.Global_Mute.String = ""
    suppressGlobalPin = false
    return
  end

  local state, color, legend

  if mixed > 0 or (muted > 0 and unmuted > 0) then
    state  = "2"
    color  = GetColorOrDefault("ColorMixed", "Mixed")
    Controls.GlobalMuteButton.Boolean = true
    legend = "GLOBAL MUTE ALL (Mixed)"
  elseif muted == connected then
    state  = "1"
    color  = GetColorOrDefault("ColorMuted", "Muted")
    Controls.GlobalMuteButton.Boolean = true
    legend = "GLOBAL MUTE ALL (Muted)"
  else
    state  = "0"
    color  = GetColorOrDefault("ColorUnmuted", "Unmuted")
    Controls.GlobalMuteButton.Boolean = false
    legend = "GLOBAL MUTE ALL (Unmuted)"
  end

  Controls.GlobalMuteButton.Color  = color
  Controls.GlobalMuteButton.Legend  = legend

  suppressGlobalPin = true
  Controls.Global_Mute.String = state
  suppressGlobalPin = false
end

---------------------------------------------------------------
-- Refresh helpers
---------------------------------------------------------------
local function RefreshInstanceColors()
  for i = 1, iCount do
    local inst = Instances[i]
    if inst and inst.connected then
      ReadInstanceState(i)
    else
      Controls["InstanceMuteButton_" .. i].Color = GetColorOrDefault("ColorDisconnected", "Disconnected")
      Controls["ConnectionStatus_" .. i].Color   = GetColorOrDefault("ColorDisconnected", "Disconnected")
    end
  end
  UpdateGlobalState()
end

---------------------------------------------------------------
-- Polling
---------------------------------------------------------------
local function PollAllInstances()
  local autoReconnect = Controls.AutoReconnect and Controls.AutoReconnect.Boolean

  for i = 1, iCount do
    local inst     = Instances[i]
    local codeName = (Controls["CodeName_" .. i].String or ""):gsub("^%s*(.-)%s*$", "%1")

    if codeName ~= "" then
      if inst.connected then
        ReadInstanceState(i)
      elseif autoReconnect then
        ConnectInstance(i)
      end
    end
  end

  UpdateGlobalState()
end

---------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------
local function BindControls()
  dbg("BindControls()")

  -- Code-name change → reconnect
  for i = 1, iCount do
    Controls["CodeName_" .. i].EventHandler = function()
      ConnectInstance(i)
      UpdateGlobalState()
    end
  end

  -- Label change → refresh legend
  for i = 1, iCount do
    Controls["InstanceLabel_" .. i].EventHandler = function()
      if Instances[i] and Instances[i].connected then
        ReadInstanceState(i)
      else
        Controls["InstanceMuteButton_" .. i].Legend = GetInstanceDisplayName(i)
      end
    end
  end

  -- Per-instance mute toggle
  for i = 1, iCount do
    Controls["InstanceMuteButton_" .. i].EventHandler = function()
      if updatingFromRemote then return end
      local inst = Instances[i]
      if not inst or not inst.connected then return end
      -- Use string state to determine action, not Boolean toggle.
      -- InstanceStatus holds "Muted", "Unmuted", or "Mixed".
      local status = Controls["InstanceStatus_" .. i].String or ""
      local target = (status == "Muted") and "0" or "1"  -- Unmuted or Mixed → mute
      Controls["InstanceMuteButton_" .. i].Boolean = (target == "1")
      WriteInstanceMute(i, target)
      Timer.CallAfter(function()
        ReadInstanceState(i)
        UpdateGlobalState()
      end, 0.05)
    end
  end

  -- Global mute button — use string state to determine action, not Boolean toggle.
  -- "0" (unmuted) or "2" (mixed) → mute all ("1"). "1" (muted) → unmute all ("0").
  Controls.GlobalMuteButton.EventHandler = function()
    if updatingFromRemote then return end
    local currentBase = BaseFromStateCode(Controls.Global_Mute and Controls.Global_Mute.String or "0")
    local target = (currentBase == "1") and "0" or "1"
    Controls.GlobalMuteButton.Boolean = (target == "1")
    for i = 1, iCount do
      if Instances[i] and Instances[i].connected then
        WriteInstanceMute(i, target)
      end
    end
    Timer.CallAfter(function() PollAllInstances() end, 0.05)
  end

  -- Global mute pin input (external control)
  Controls.Global_Mute.EventHandler = function()
    if suppressGlobalPin then return end
    local val = ParseMuteInput(Controls.Global_Mute.String)
    if not val or val == "2" then return end  -- ignore "mixed" commands
    local muteStr = val
    for i = 1, iCount do
      if Instances[i] and Instances[i].connected then
        WriteInstanceMute(i, muteStr)
      end
    end
    Timer.CallAfter(function() PollAllInstances() end, 0.05)
  end

  -- Global mute Set trigger (mute all)
  Controls.GlobalMuteSet.EventHandler = function()
    Controls.GlobalMuteButton.Boolean = true
    local target = "1"
    for i = 1, iCount do
      if Instances[i] and Instances[i].connected then
        WriteInstanceMute(i, target)
      end
    end
    Timer.CallAfter(function() PollAllInstances() end, 0.05)
  end

  -- Global mute Reset trigger (unmute all)
  Controls.GlobalMuteReset.EventHandler = function()
    Controls.GlobalMuteButton.Boolean = false
    local target = "0"
    for i = 1, iCount do
      if Instances[i] and Instances[i].connected then
        WriteInstanceMute(i, target)
      end
    end
    Timer.CallAfter(function() PollAllInstances() end, 0.05)
  end

  -- Reconnect All button
  if Controls.ReconnectAll then
    Controls.ReconnectAll.EventHandler = function()
      dbg("[RECONNECT] Reconnecting all instances…")
      for i = 1, iCount do ConnectInstance(i) end
      UpdateGlobalState()
    end
  end

  -- Auto-Reconnect default ON
  if Controls.AutoReconnect and not Controls.AutoReconnect.Boolean then
    Controls.AutoReconnect.Boolean = true
  end

  -- Poll rate knob
  if Controls.PollRate then
    Controls.PollRate.EventHandler = function()
      PollTimer:Stop()
      local ms = math.max(100, math.min(5000, Controls.PollRate.Value or 500))
      PollTimer:Start(ms / 1000)
      dbg("[POLL] Rate changed to " .. ms .. " ms")
    end
  end

  -- Color controls → refresh visuals
  local colorCtrls = { Controls.ColorMuted, Controls.ColorUnmuted, Controls.ColorMixed, Controls.ColorDisconnected }
  for _, ctrl in ipairs(colorCtrls) do
    if ctrl then
      ctrl.EventHandler = function()
        RefreshInstanceColors()
        UpdateAllColorPreviews()
      end
    end
  end

  -- Start poll timer
  PollTimer.EventHandler = function() PollAllInstances() end
  local pollMs = math.max(100, math.min(5000, (Controls.PollRate and Controls.PollRate.Value) or 500))
  PollTimer:Start(pollMs / 1000)
  dbg("[POLL] Started at " .. pollMs .. " ms")

  -- Flash clock broadcast
  FlashTimer.EventHandler = function() update_master_flash() end
  if Controls.FlashRate then
    Controls.FlashRate.EventHandler = function()
      flash_sync_time_base = nil  -- Force resync on rate change
    end
  end
  update_master_flash()
  dbg("[FLASH] Master flash clock started")
end

---------------------------------------------------------------
-- Initialize
---------------------------------------------------------------
Timer.CallAfter(function()
  BindControls()
  for i = 1, iCount do ConnectInstance(i) end
  UpdateGlobalState()
  UpdateAllColorPreviews()
  dbg("[INIT] Group Mute Master Controller ready (" .. iCount .. " instances)")
end, 0.2)

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
