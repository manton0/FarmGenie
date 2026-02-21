-- FarmGenie GUI
-- AceGUI-based config window with TreeGroup navigation (same pattern as GearGenie)

local AceGUI = LibStub("AceGUI-3.0")

local mainFrame = nil
local treeGroup = nil

---------------------------------------------------------------------------
-- Forward declarations
---------------------------------------------------------------------------
local DrawGeneralPanel
local DrawFiltersPanel
local DrawDebugPanel
local DrawAboutPanel

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function trim(s)
   return s:match("^%s*(.-)%s*$") or s
end

---------------------------------------------------------------------------
-- Tree structure
---------------------------------------------------------------------------
local function GetTreeStructure()
   return {
      { value = "general", text = "General" },
      { value = "filters", text = "Filters" },
      { value = "debug",   text = "Debug" },
      { value = "about",   text = "About" },
   }
end

---------------------------------------------------------------------------
-- Tree group callback
---------------------------------------------------------------------------
local function OnGroupSelected(container, event, group)
   container:ReleaseChildren()

   if group == "general" then
      DrawGeneralPanel(container)
   elseif group == "filters" then
      DrawFiltersPanel(container)
   elseif group == "debug" then
      DrawDebugPanel(container)
   elseif group == "about" then
      DrawAboutPanel(container)
   end
end

---------------------------------------------------------------------------
-- General Panel
---------------------------------------------------------------------------
DrawGeneralPanel = function(container)
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   -- Header
   local header = AceGUI:Create("Heading")
   header:SetText("General Settings")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   -- Auctionator status
   local statusLabel = AceGUI:Create("Label")
   local hasAuc = FarmGenieHasAuctionator()
   if hasAuc then
      statusLabel:SetText("  Price Source: \124cff00ff00Auctionator detected\124r")
   else
      statusLabel:SetText("  Price Source: \124cffff4444Auctionator not found\124r — using vendor prices")
   end
   statusLabel:SetFullWidth(true)
   statusLabel:SetFont("Fonts\\FRIZQT__.TTF", 11)
   scroll:AddChild(statusLabel)

   -- Spacer
   local spacer = AceGUI:Create("Label")
   spacer:SetText(" ")
   spacer:SetFullWidth(true)
   scroll:AddChild(spacer)

   -- Auto-start session
   local autoStart = AceGUI:Create("CheckBox")
   autoStart:SetLabel("Auto-start session on loot")
   autoStart:SetDescription("Automatically start a new farming session when you loot an item")
   autoStart:SetFullWidth(true)
   autoStart:SetValue(FarmGenieDB.autoStart)
   autoStart:SetCallback("OnValueChanged", function(widget, event, value)
      FarmGenieDB.autoStart = value
   end)
   scroll:AddChild(autoStart)

   -- Show loot window
   local showLoot = AceGUI:Create("CheckBox")
   showLoot:SetLabel("Show loot log window on login")
   showLoot:SetDescription("Automatically show the loot log window when you log in")
   showLoot:SetFullWidth(true)
   showLoot:SetValue(FarmGenieDB.showLootWindow)
   showLoot:SetCallback("OnValueChanged", function(widget, event, value)
      FarmGenieDB.showLootWindow = value
   end)
   scroll:AddChild(showLoot)

   -- Track gold
   local trackGold = AceGUI:Create("CheckBox")
   trackGold:SetLabel("Track raw gold looted")
   trackGold:SetDescription("Track gold looted directly from mobs in session stats")
   trackGold:SetFullWidth(true)
   trackGold:SetValue(FarmGenieDB.trackGold)
   trackGold:SetCallback("OnValueChanged", function(widget, event, value)
      FarmGenieDB.trackGold = value
   end)
   scroll:AddChild(trackGold)

   -- Show item counter bar
   local showBar = AceGUI:Create("CheckBox")
   showBar:SetLabel("Show item counter bar")
   showBar:SetDescription("Display the item counter bar for tracking specific item counts")
   showBar:SetFullWidth(true)
   showBar:SetValue(not FarmGenieDB.bar or FarmGenieDB.bar.visible ~= false)
   showBar:SetCallback("OnValueChanged", function(widget, event, value)
      if FarmGenieDB.bar then
         FarmGenieDB.bar.visible = value
      end
      if value then
         if FarmGenieBarFrame then FarmGenieBarFrame:Show() end
      else
         if FarmGenieBarFrame then FarmGenieBarFrame:Hide() end
      end
   end)
   scroll:AddChild(showBar)
end

---------------------------------------------------------------------------
-- Filters Panel
---------------------------------------------------------------------------
DrawFiltersPanel = function(container)
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   -- Header
   local header = AceGUI:Create("Heading")
   header:SetText("Loot Filters")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   local desc = AceGUI:Create("Label")
   desc:SetText("  Filters apply to newly looted items. Existing session items are not affected.")
   desc:SetFullWidth(true)
   desc:SetFont("Fonts\\FRIZQT__.TTF", 11)
   scroll:AddChild(desc)

   -- Spacer
   local spacer = AceGUI:Create("Label")
   spacer:SetText(" ")
   spacer:SetFullWidth(true)
   scroll:AddChild(spacer)

   -- Quality dropdown
   local qualityDropdown = AceGUI:Create("Dropdown")
   qualityDropdown:SetLabel("Minimum Item Quality")
   qualityDropdown:SetFullWidth(true)
   qualityDropdown:SetList({
      [0] = "\124cff9d9d9dPoor\124r",
      [1] = "\124cffffffffCommon\124r",
      [2] = "\124cff1eff00Uncommon\124r",
      [3] = "\124cff0070ddRare\124r",
      [4] = "\124cffa335eeEpic\124r",
   }, { 0, 1, 2, 3, 4 })
   qualityDropdown:SetValue(FarmGenieDB.minQuality)
   qualityDropdown:SetCallback("OnValueChanged", function(widget, event, value)
      FarmGenieDB.minQuality = value
      FarmGeniePrint("Minimum quality set to " .. (({
         [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic"
      })[value] or "Unknown"))
   end)
   scroll:AddChild(qualityDropdown)

   -- Spacer
   local spacer2 = AceGUI:Create("Label")
   spacer2:SetText(" ")
   spacer2:SetFullWidth(true)
   scroll:AddChild(spacer2)

   -- Minimum AH price
   local minPriceBox = AceGUI:Create("EditBox")
   minPriceBox:SetLabel("Minimum AH Price (gold)")
   minPriceBox:SetFullWidth(true)
   minPriceBox:SetText(tostring(math.floor((FarmGenieDB.minPrice or 0) / 10000)))
   minPriceBox:SetCallback("OnEnterPressed", function(widget, event, text)
      local gold = tonumber(text) or 0
      if gold < 0 then gold = 0 end
      FarmGenieDB.minPrice = gold * 10000  -- store as copper
      widget:SetText(tostring(gold))
      FarmGeniePrint("Minimum AH price set to " .. gold .. "g")
   end)
   scroll:AddChild(minPriceBox)

   local priceDesc = AceGUI:Create("Label")
   priceDesc:SetText("  Items below this AH price will not be logged. Set to 0 to disable.")
   priceDesc:SetFullWidth(true)
   priceDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(priceDesc)

   -- Spacer
   local spacer3 = AceGUI:Create("Label")
   spacer3:SetText(" ")
   spacer3:SetFullWidth(true)
   scroll:AddChild(spacer3)

   -- Max loot entries
   local maxEntriesBox = AceGUI:Create("EditBox")
   maxEntriesBox:SetLabel("Max Loot Log Entries")
   maxEntriesBox:SetFullWidth(true)
   maxEntriesBox:SetText(tostring(FarmGenieDB.maxLootEntries or 50))
   maxEntriesBox:SetCallback("OnEnterPressed", function(widget, event, text)
      local val = tonumber(text) or 50
      if val < 10 then val = 10 end
      if val > 500 then val = 500 end
      FarmGenieDB.maxLootEntries = val
      widget:SetText(tostring(val))
      FarmGeniePrint("Max loot log entries set to " .. val)
   end)
   scroll:AddChild(maxEntriesBox)

   local maxDesc = AceGUI:Create("Label")
   maxDesc:SetText("  Only keep the most recent entries in the loot log (10-500). Reduces lag with long sessions.")
   maxDesc:SetFullWidth(true)
   maxDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(maxDesc)
end

---------------------------------------------------------------------------
-- Debug Panel
---------------------------------------------------------------------------
DrawDebugPanel = function(container)
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   -- Header
   local header = AceGUI:Create("Heading")
   header:SetText("Debug Tools")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   local desc = AceGUI:Create("Label")
   desc:SetText("  Tools for testing and troubleshooting FarmGenie.")
   desc:SetFullWidth(true)
   desc:SetFont("Fonts\\FRIZQT__.TTF", 11)
   scroll:AddChild(desc)

   -- Spacer
   local spacer = AceGUI:Create("Label")
   spacer:SetText(" ")
   spacer:SetFullWidth(true)
   scroll:AddChild(spacer)

   -- Reset saved variables button
   local resetBtn = AceGUI:Create("Button")
   resetBtn:SetText("Reset All Saved Variables")
   resetBtn:SetFullWidth(true)
   resetBtn:SetCallback("OnClick", function()
      FarmGenieDB = nil
      FarmGenieSession = nil
      -- Close loot window if open
      if FarmGenieIsLootWindowOpen and FarmGenieIsLootWindowOpen() then
         FarmGenieToggleLootWindow()
      end
      FarmGeniePrint("All saved variables reset. Reload UI to apply defaults. (/reload)")
   end)
   scroll:AddChild(resetBtn)

   local resetDesc = AceGUI:Create("Label")
   resetDesc:SetText("  Clears FarmGenieDB and session. Reload UI (/reload) to reinitialize defaults.")
   resetDesc:SetFullWidth(true)
   resetDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(resetDesc)

   -- Spacer
   local spacer2 = AceGUI:Create("Label")
   spacer2:SetText(" ")
   spacer2:SetFullWidth(true)
   scroll:AddChild(spacer2)

   -- Reset window position button
   local resetPosBtn = AceGUI:Create("Button")
   resetPosBtn:SetText("Reset Loot Window Position")
   resetPosBtn:SetFullWidth(true)
   resetPosBtn:SetCallback("OnClick", function()
      if FarmGenieDB then
         FarmGenieDB.lootWindowPos = nil
      end
      -- Close and reopen loot window to apply
      if FarmGenieIsLootWindowOpen and FarmGenieIsLootWindowOpen() then
         FarmGenieToggleLootWindow()
         FarmGenieToggleLootWindow()
      end
      FarmGeniePrint("Loot window position reset to default.")
   end)
   scroll:AddChild(resetPosBtn)

   local posDesc = AceGUI:Create("Label")
   posDesc:SetText("  Resets the loot log window to its default position and size.")
   posDesc:SetFullWidth(true)
   posDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(posDesc)

   -- Spacer
   local spacer3 = AceGUI:Create("Label")
   spacer3:SetText(" ")
   spacer3:SetFullWidth(true)
   scroll:AddChild(spacer3)

   -- Add test items button
   local testBtn = AceGUI:Create("Button")
   testBtn:SetText("Add 20 Random Items to Log")
   testBtn:SetFullWidth(true)
   testBtn:SetCallback("OnClick", function()
      if FarmGenieDebugAddBagItems then
         FarmGenieDebugAddBagItems(20)
      end
   end)
   scroll:AddChild(testBtn)

   local testDesc = AceGUI:Create("Label")
   testDesc:SetText("  Grabs random items from your bags and adds them to the loot log for testing.")
   testDesc:SetFullWidth(true)
   testDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(testDesc)

   -- Spacer
   local spacer4 = AceGUI:Create("Label")
   spacer4:SetText(" ")
   spacer4:SetFullWidth(true)
   scroll:AddChild(spacer4)

   -- Loot window info
   local infoHeader = AceGUI:Create("Heading")
   infoHeader:SetText("Loot Window Info")
   infoHeader:SetFullWidth(true)
   scroll:AddChild(infoHeader)

   local infoLabel = AceGUI:Create("Label")
   infoLabel:SetFullWidth(true)
   infoLabel:SetFont("Fonts\\FRIZQT__.TTF", 11)

   local function UpdateInfo()
      local lines = {}
      -- Live frame values (if window is open)
      local isOpen = FarmGenieIsLootWindowOpen and FarmGenieIsLootWindowOpen()
      local frame = FarmGenieGetLootFrame and FarmGenieGetLootFrame()
      if isOpen and frame then
         local left = math.floor(frame:GetLeft() or 0)
         local top = math.floor(frame:GetTop() or 0)
         local w = math.floor(frame:GetWidth() or 0)
         local h = math.floor(frame:GetHeight() or 0)
         table.insert(lines, "  \124cff00ff00Window is open\124r")
         table.insert(lines, "  Position: left=" .. left .. "  top=" .. top)
         table.insert(lines, "  Size: " .. w .. " x " .. h)
      else
         table.insert(lines, "  \124cffff4444Window is closed\124r")
      end
      -- Saved values
      if FarmGenieDB and FarmGenieDB.lootWindowPos then
         local p = FarmGenieDB.lootWindowPos
         table.insert(lines, "  Saved: left=" .. math.floor(p.left or 0) ..
            "  top=" .. math.floor(p.top or 0) ..
            "  w=" .. math.floor(p.width or 0) ..
            "  h=" .. math.floor(p.height or 0))
      else
         table.insert(lines, "  Saved: (none)")
      end
      infoLabel:SetText(table.concat(lines, "\n"))
   end

   UpdateInfo()
   scroll:AddChild(infoLabel)

   -- Refresh button
   local refreshBtn = AceGUI:Create("Button")
   refreshBtn:SetText("Refresh")
   refreshBtn:SetWidth(100)
   refreshBtn:SetCallback("OnClick", function()
      UpdateInfo()
   end)
   scroll:AddChild(refreshBtn)
end

---------------------------------------------------------------------------
-- About Panel
---------------------------------------------------------------------------
DrawAboutPanel = function(container)
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   -- Header
   local header = AceGUI:Create("Heading")
   header:SetText("About FarmGenie")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   local function AddLine(parent, text)
      local label = AceGUI:Create("Label")
      label:SetText("  " .. text)
      label:SetFullWidth(true)
      label:SetFont("Fonts\\FRIZQT__.TTF", 11)
      parent:AddChild(label)
   end

   AddLine(scroll, "\124cffffcc00Version:\124r 0.1.0")
   AddLine(scroll, "\124cffffcc00Author:\124r Discord: the_mazer")
   AddLine(scroll, " ")
   AddLine(scroll, "FarmGenie tracks items you loot while farming and shows")
   AddLine(scroll, "their auction house value from Auctionator's price database.")
   AddLine(scroll, " ")

   local cmdHeader = AceGUI:Create("Heading")
   cmdHeader:SetText("Slash Commands")
   cmdHeader:SetFullWidth(true)
   scroll:AddChild(cmdHeader)

   AddLine(scroll, "\124cffffcc00/fg\124r — Toggle this settings window")
   AddLine(scroll, "\124cffffcc00/fg loot\124r — Toggle loot log window")
   AddLine(scroll, "\124cffffcc00/fg bar\124r — Toggle item counter bar")
   AddLine(scroll, "\124cffffcc00/fg new\124r — Start a new farming session")
   AddLine(scroll, "\124cffffcc00/fg pause\124r — Pause logging")
   AddLine(scroll, "\124cffffcc00/fg resume\124r — Resume logging")
   AddLine(scroll, "\124cffffcc00/fg help\124r — Show available commands")
end

---------------------------------------------------------------------------
-- Toggle main config window
---------------------------------------------------------------------------
function FarmGenieToggleMainWindow()
   if mainFrame then
      AceGUI:Release(mainFrame)
      mainFrame = nil
      treeGroup = nil
      return
   end

   mainFrame = AceGUI:Create("Window")
   mainFrame:SetTitle("FarmGenie")
   mainFrame:SetWidth(580)
   mainFrame:SetHeight(400)
   mainFrame:SetLayout("Fill")
   mainFrame.frame:SetFrameStrata("HIGH")

   -- Escape key closes the window
   _G["FarmGenieMainFrame"] = mainFrame.frame
   tinsert(UISpecialFrames, "FarmGenieMainFrame")

   mainFrame:SetCallback("OnClose", function(widget)
      AceGUI:Release(widget)
      mainFrame = nil
      treeGroup = nil
   end)

   treeGroup = AceGUI:Create("TreeGroup")
   treeGroup:SetFullHeight(true)
   treeGroup:SetLayout("Fill")
   treeGroup:EnableButtonTooltips(false)
   treeGroup:SetTree(GetTreeStructure())
   treeGroup:SetCallback("OnGroupSelected", OnGroupSelected)
   mainFrame:AddChild(treeGroup)

   -- Default to General panel
   treeGroup:SelectByPath("general")
end

-- Open window and navigate to a specific tab
function FarmGenieOpenToTab(tabValue)
   if not mainFrame then
      FarmGenieToggleMainWindow()
   end
   if treeGroup then
      treeGroup:SelectByPath(tabValue)
   end
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------
SLASH_FARMGENIE1 = "/fg"
SLASH_FARMGENIE2 = "/farmgenie"

SlashCmdList["FARMGENIE"] = function(msg)
   msg = string.lower(trim(msg or ""))

   if msg == "" or msg == "config" or msg == "settings" then
      FarmGenieToggleMainWindow()
   elseif msg == "loot" or msg == "log" then
      FarmGenieToggleLootWindow()
   elseif msg == "new" or msg == "reset" then
      FarmGenieNewSession()
   elseif msg == "pause" or msg == "stop" then
      if FarmGenieSession and not FarmGenieSession.paused then
         FarmGeniePauseLogging()
      else
         FarmGeniePrint("No active session to pause.")
      end
   elseif msg == "resume" or msg == "start" then
      if FarmGenieSession and FarmGenieSession.paused then
         FarmGenieResumeLogging()
      elseif not FarmGenieSession then
         FarmGenieNewSession()
      else
         FarmGeniePrint("Logging is already active.")
      end
   elseif msg == "bar" then
      FarmGenieToggleBar()
   elseif msg == "help" then
      FarmGeniePrint("Commands:")
      FarmGeniePrint("  /fg — Toggle settings window")
      FarmGeniePrint("  /fg loot — Toggle loot log window")
      FarmGeniePrint("  /fg bar — Toggle item counter bar")
      FarmGeniePrint("  /fg new — Start new session")
      FarmGeniePrint("  /fg pause — Pause logging")
      FarmGeniePrint("  /fg resume — Resume logging")
      FarmGeniePrint("  /fg help — Show this help")
   else
      FarmGeniePrint("Unknown command: " .. msg .. ". Type /fg help for commands.")
   end
end
