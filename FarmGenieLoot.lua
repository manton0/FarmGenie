-- FarmGenie Loot Log Window
-- Movable AceGUI window showing looted items and session stats

local AceGUI = LibStub("AceGUI-3.0")

---------------------------------------------------------------------------
-- Window state
---------------------------------------------------------------------------
local lootFrame = nil
local statsLabels = {}   -- references to stat label widgets for updating
local lootScroll = nil   -- ScrollFrame widget holding loot entries
local pauseBtn = nil     -- pause/resume button reference
local updateElapsed = 0

---------------------------------------------------------------------------
-- Window title and button updates based on logging state
---------------------------------------------------------------------------
local function UpdateWindowTitle()
   if not lootFrame then return end
   if not FarmGenieSession then
      lootFrame:SetTitle("FarmGenie - Loot Log")
   elseif FarmGenieSession.paused then
      lootFrame:SetTitle("FarmGenie - Loot Log  |cffFFAA00[Paused]|r")
   else
      lootFrame:SetTitle("FarmGenie - Loot Log  |cff00FF00[Active]|r")
   end
end

local function UpdatePauseButton()
   if not pauseBtn then return end
   if not FarmGenieSession then
      pauseBtn:SetText("Start")
   elseif FarmGenieSession.paused then
      pauseBtn:SetText("Resume")
   else
      pauseBtn:SetText("Pause")
   end
end

---------------------------------------------------------------------------
-- Loot window position save/restore
---------------------------------------------------------------------------
local function SaveWindowPosition()
   if not lootFrame or not FarmGenieDB then return end
   local frame = lootFrame.frame
   local top = frame:GetTop()
   local left = frame:GetLeft()
   FarmGenieDB.lootWindowPos = {
      top = top,
      left = left,
      width = frame:GetWidth(),
      height = frame:GetHeight(),
   }
end

local function RestoreWindowPosition()
   if not lootFrame or not FarmGenieDB or not FarmGenieDB.lootWindowPos then return end
   local pos = FarmGenieDB.lootWindowPos
   local frame = lootFrame.frame
   frame:ClearAllPoints()
   frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
   if pos.width then frame:SetWidth(pos.width) end
   if pos.height then frame:SetHeight(pos.height) end
end

---------------------------------------------------------------------------
-- Build summary stats area
---------------------------------------------------------------------------
local function BuildStatsArea(parent)
   statsLabels = {}

   -- Single group for all stat labels — avoids per-row SimpleGroup padding
   local statsGroup = AceGUI:Create("SimpleGroup")
   statsGroup:SetFullWidth(true)
   statsGroup:SetLayout("Flow")

   local function AddStat(text, width)
      local label = AceGUI:Create("Label")
      label:SetWidth(width)
      label:SetText(text)
      label:SetFont("Fonts\\FRIZQT__.TTF", 11)
      statsGroup:AddChild(label)
      return label
   end

   statsLabels.zone       = AddStat(" Zone: ---", 180)
   statsLabels.duration   = AddStat("Duration: 00:00:00", 180)
   statsLabels.totalValue = AddStat(" Total Value: 0g", 180)
   statsLabels.goldPerHour = AddStat("Gold/hr: 0g", 180)
   statsLabels.itemCount  = AddStat(" Items Looted: 0", 180)
   statsLabels.rawGold    = AddStat("Raw Gold: 0g", 180)

   parent:AddChild(statsGroup)

   -- Separator
   local sep = AceGUI:Create("Heading")
   sep:SetFullWidth(true)
   sep:SetText("")
   parent:AddChild(sep)
end

---------------------------------------------------------------------------
-- Update stats display (called on timer and after loot)
---------------------------------------------------------------------------
function FarmGenieUpdateStats()
   if not lootFrame or not statsLabels.zone then return end
   UpdateWindowTitle()
   UpdatePauseButton()
   local s = FarmGenieSession

   if not s then
      statsLabels.zone:SetText(" Zone: ---")
      statsLabels.duration:SetText("Duration: 00:00:00")
      statsLabels.totalValue:SetText(" Total Value: " .. FarmGenieFormatMoneyColored(0))
      statsLabels.goldPerHour:SetText("Gold/hr: " .. FarmGenieFormatMoneyColored(0))
      statsLabels.itemCount:SetText(" Items Looted: 0")
      statsLabels.rawGold:SetText("Raw Gold: " .. FarmGenieFormatMoneyColored(0))
      return
   end

   statsLabels.zone:SetText(" Zone: " .. (s.zone or "Unknown"))
   statsLabels.duration:SetText("Duration: " .. FarmGenieGetSessionDuration())
   statsLabels.totalValue:SetText(" Total Value: " .. FarmGenieFormatMoneyColored(s.totalAHValue))
   statsLabels.goldPerHour:SetText("Gold/hr: " .. FarmGenieFormatMoneyColored(FarmGenieGetGoldPerHour()))
   statsLabels.itemCount:SetText(" Items Looted: " .. (s.itemCount or 0))

   if FarmGenieDB and FarmGenieDB.trackGold then
      statsLabels.rawGold:SetText("Raw Gold: " .. FarmGenieFormatMoneyColored(s.rawGold or 0))
   else
      statsLabels.rawGold:SetText("")
   end
end

---------------------------------------------------------------------------
-- Add a single loot entry widget to the scroll area
---------------------------------------------------------------------------
local function CreateLootLabel(entry)
   local label = AceGUI:Create("InteractiveLabel")
   local priceText = FarmGenieFormatMoneyColored(entry.displayPrice)
   local qtyText = entry.quantity > 1 and (" x" .. entry.quantity) or ""
   label:SetText(" " .. entry.link .. qtyText .. "  " .. priceText)
   label:SetFullWidth(true)
   label:SetFont("Fonts\\FRIZQT__.TTF", 11)

   -- Tooltip on hover
   local itemLink = entry.link
   label:SetCallback("OnEnter", function(widget)
      GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(itemLink)
      GameTooltip:Show()
   end)
   label:SetCallback("OnLeave", function()
      GameTooltip:Hide()
   end)

   return label
end

--- Called from core when a new item is looted; rebuilds the list (newest first)
function FarmGenieAddLootEntry(entry)
   if not lootFrame or not lootScroll then return end
   -- Rebuild entire list so newest item appears at top
   FarmGenieRefreshLootWindow()
end

---------------------------------------------------------------------------
-- Rebuild entire loot list from session data
---------------------------------------------------------------------------
function FarmGenieRefreshLootWindow()
   if not lootFrame or not lootScroll then return end

   lootScroll:ReleaseChildren()
   UpdateWindowTitle()
   UpdatePauseButton()

   if not FarmGenieSession then
      -- No active session
      local msg = AceGUI:Create("Label")
      msg:SetFullWidth(true)
      msg:SetText("\n|cff888888No active session|r\nStart a new session to begin logging loot.")
      msg:SetFont("Fonts\\FRIZQT__.TTF", 13)
      msg.label:SetJustifyH("CENTER")
      lootScroll:AddChild(msg)
      FarmGenieUpdateStats()
      return
   end

   if #FarmGenieSession.items == 0 then
      -- Session exists but no items yet
      local msg = AceGUI:Create("Label")
      msg:SetFullWidth(true)
      msg:SetFont("Fonts\\FRIZQT__.TTF", 13)
      msg.label:SetJustifyH("CENTER")
      if FarmGenieSession.paused then
         msg:SetText("\n|cffFFAA00Logging paused|r\nResume to continue tracking loot.")
      else
         msg:SetText("\n|cff00FF00Logging active|r\nWaiting for loot...")
      end
      lootScroll:AddChild(msg)
   else
      -- Show items
      for _, entry in ipairs(FarmGenieSession.items) do
         lootScroll:AddChild(CreateLootLabel(entry))
      end
   end

   FarmGenieUpdateStats()
end

---------------------------------------------------------------------------
-- Create / Toggle Loot Window
---------------------------------------------------------------------------
function FarmGenieToggleLootWindow()
   if lootFrame then
      -- Use the intentional Hide path so OnHide doesn't re-show
      lootFrame:Hide()
      return
   end

   lootFrame = AceGUI:Create("Window")
   lootFrame:SetTitle("FarmGenie - Loot Log")
   lootFrame:SetWidth(400)
   lootFrame:SetHeight(240)
   lootFrame:SetLayout("Flow")
   lootFrame.frame:SetFrameStrata("MEDIUM")

   -- Prevent the loot window from closing when the map or other panels open.
   -- WoW calls CloseSpecialWindows() which fires OnHide on FULLSCREEN_DIALOG
   -- frames. We override OnHide to only fire when we intentionally close it,
   -- and use a flag so the AceGUI OnClose callback only runs on real closes.
   local intentionalClose = false
   lootFrame.frame:SetScript("OnHide", function(self)
      if intentionalClose then
         self.obj:Fire("OnClose")
      else
         -- Re-show immediately — something else tried to hide us
         self:Show()
      end
   end)

   -- Override the AceGUI Hide method so only our toggle/X-button works
   local origHide = lootFrame.Hide
   lootFrame.Hide = function(self)
      intentionalClose = true
      origHide(self)
   end

   -- Also handle the X button (closebutton) which calls obj:Hide()
   if lootFrame.closebutton then
      lootFrame.closebutton:SetScript("OnClick", function(btn)
         PlaySound("gsTitleOptionExit")
         intentionalClose = true
         btn.obj:Hide()
      end)
   end

   lootFrame:SetCallback("OnClose", function(widget)
      SaveWindowPosition()
      AceGUI:Release(widget)
      lootFrame = nil
      lootScroll = nil
      pauseBtn = nil
      statsLabels = {}
   end)

   -- Stats area
   BuildStatsArea(lootFrame)

   -- Scrollable loot list
   lootScroll = AceGUI:Create("ScrollFrame")
   lootScroll:SetLayout("List")
   lootScroll:SetFullWidth(true)
   lootScroll:SetHeight(80)
   lootFrame:AddChild(lootScroll)

   -- Constrain resize: fixed width, flexible height only
   lootFrame.frame:SetMinResize(400, 200)
   lootFrame.frame:SetMaxResize(400, 600)

   -- When height changes, grow/shrink only the loot scroll area
   local baseHeight = 240
   local baseScrollHeight = 80
   lootFrame.frame:SetScript("OnSizeChanged", function(self, width, height)
      if lootScroll then
         local newScrollHeight = baseScrollHeight + (height - baseHeight)
         if newScrollHeight < 40 then newScrollHeight = 40 end
         lootScroll:SetHeight(newScrollHeight)
      end
      SaveWindowPosition()
   end)

   -- Spacer before buttons
   local btnSpacer = AceGUI:Create("Label")
   btnSpacer:SetFullWidth(true)
   btnSpacer:SetText(" ")
   lootFrame:AddChild(btnSpacer)

   -- Button row
   local btnGroup = AceGUI:Create("SimpleGroup")
   btnGroup:SetFullWidth(true)
   btnGroup:SetLayout("Flow")

   pauseBtn = AceGUI:Create("Button")
   pauseBtn:SetText("Start")
   pauseBtn:SetWidth(100)
   pauseBtn:SetCallback("OnClick", function()
      if not FarmGenieSession then
         FarmGenieNewSession()
      elseif FarmGenieSession.paused then
         FarmGenieResumeLogging()
      else
         FarmGeniePauseLogging()
      end
   end)
   btnGroup:AddChild(pauseBtn)

   local newBtn = AceGUI:Create("Button")
   newBtn:SetText("New Session")
   newBtn:SetWidth(100)
   newBtn:SetCallback("OnClick", function()
      FarmGenieNewSession()
   end)
   btnGroup:AddChild(newBtn)

   local settingsBtn = AceGUI:Create("Button")
   settingsBtn:SetText("Settings")
   settingsBtn:SetWidth(100)
   settingsBtn:SetCallback("OnClick", function()
      if FarmGenieToggleMainWindow then
         FarmGenieToggleMainWindow()
      end
   end)
   btnGroup:AddChild(settingsBtn)

   lootFrame:AddChild(btnGroup)

   -- Restore saved position
   RestoreWindowPosition()

   -- 1-second update timer for duration/gold-per-hour
   updateElapsed = 0
   lootFrame.frame:SetScript("OnUpdate", function(self, dt)
      updateElapsed = updateElapsed + dt
      if updateElapsed >= 1 then
         updateElapsed = 0
         FarmGenieUpdateStats()
         SaveWindowPosition()
      end
   end)

   -- Populate with existing session data
   FarmGenieRefreshLootWindow()

   -- Auto-start session if none exists and auto-start is on
   if not FarmGenieSession and FarmGenieDB and FarmGenieDB.autoStart then
      FarmGenieNewSession()
   end
end

---------------------------------------------------------------------------
-- Check if loot window is open
---------------------------------------------------------------------------
function FarmGenieIsLootWindowOpen()
   return lootFrame ~= nil
end

function FarmGenieGetLootFrame()
   return lootFrame and lootFrame.frame or nil
end
