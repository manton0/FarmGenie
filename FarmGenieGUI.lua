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
local DrawBagCleanupPanel
local DrawRulesPanel
local DrawDebugPanel
local DrawAboutPanel

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function trim(s)
   return s:match("^%s*(.-)%s*$") or s
end

--- Register a frame for Escape-key closing, avoiding duplicate entries.
--- Call FarmGenieUnregisterESC(name) on close to clean up.
function FarmGenieRegisterESC(name, frame)
   _G[name] = frame
   -- Only add if not already present
   for _, v in ipairs(UISpecialFrames) do
      if v == name then return end
   end
   tinsert(UISpecialFrames, name)
end

function FarmGenieUnregisterESC(name)
   _G[name] = nil
   for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == name then
         table.remove(UISpecialFrames, i)
      end
   end
end

local function AddSpacer(parent)
   local spacer = AceGUI:Create("Label")
   spacer:SetText(" ")
   spacer:SetFullWidth(true)
   parent:AddChild(spacer)
end

---------------------------------------------------------------------------
-- Shared constants for rule UI
---------------------------------------------------------------------------
local QUALITY_LIST = {
   [-1] = "Any",
   [0] = "\124cff9d9d9dPoor\124r",
   [1] = "\124cffffffffCommon\124r",
   [2] = "\124cff1eff00Uncommon\124r",
   [3] = "\124cff0070ddRare\124r",
   [4] = "\124cffa335eeEpic\124r",
}
local QUALITY_ORDER = { -1, 0, 1, 2, 3, 4 }

local ITEM_TYPE_LIST = {
   [""] = "Any",
   ["Armor"] = "Armor",
   ["Consumable"] = "Consumable",
   ["Container"] = "Container",
   ["Gem"] = "Gem",
   ["Miscellaneous"] = "Miscellaneous",
   ["Projectile"] = "Projectile",
   ["Reagent"] = "Reagent",
   ["Recipe"] = "Recipe",
   ["Trade Goods"] = "Trade Goods",
   ["Weapon"] = "Weapon",
}
local ITEM_TYPE_ORDER = {
   "", "Armor", "Consumable", "Container", "Gem",
   "Miscellaneous", "Projectile", "Reagent", "Recipe",
   "Trade Goods", "Weapon",
}

local ACTION_LIST = {
   ["keep"] = "\124cff00ff00Keep\124r",
   ["delete"] = "\124cffff4444Delete\124r",
   ["sell"] = "\124cffffcc00Sell to Vendor\124r",
   ["bank"] = "\124cff69b4ffDeposit to Bank\124r",
}
local ACTION_ORDER = { "keep", "delete", "sell", "bank" }

---------------------------------------------------------------------------
-- Tree structure
---------------------------------------------------------------------------
local function GetTreeStructure()
   return {
      { value = "general",    text = "General",     icon = "Interface\\Icons\\INV_Misc_Gear_01" },
      { value = "filters",    text = "Filters",     icon = "Interface\\Icons\\INV_Misc_Spyglass_02" },
      { value = "bagcleanup", text = "Bag Cleanup", icon = "Interface\\Icons\\INV_Misc_Bag_10", children = {
         { value = "rules", text = "Rules", icon = "Interface\\Icons\\INV_Misc_Note_01" },
      }},
      { value = "debug",      text = "Debug",       icon = "Interface\\Icons\\Trade_Engineering" },
      { value = "about",      text = "About",       icon = "Interface\\Icons\\INV_Misc_Note_01" },
   }
end

---------------------------------------------------------------------------
-- Tree group callback
---------------------------------------------------------------------------
local conditionPickerFrame = nil
local overlayButtons = {}
local rulesScrollValue = nil   -- saved scroll position for rules panel redraw
local pendingConfirmAction = nil

StaticPopupDialogs["FARMGENIE_CONFIRM_DELETE"] = {
   text = "%s",
   button1 = "Delete",
   button2 = "Cancel",
   OnAccept = function()
      if pendingConfirmAction then
         pendingConfirmAction()
         pendingConfirmAction = nil
      end
   end,
   OnCancel = function()
      pendingConfirmAction = nil
   end,
   timeout = 0,
   whileDead = true,
   hideOnEscape = true,
   preferredIndex = 3,
}

local function CleanupOverlayButtons()
   for i = 1, #overlayButtons do
      overlayButtons[i].frame:SetNormalTexture(nil)
      overlayButtons[i].frame:Hide()
      AceGUI:Release(overlayButtons[i])
   end
   overlayButtons = {}
end

local function CloseConditionPicker()
   if conditionPickerFrame then
      AceGUI:Release(conditionPickerFrame)
      conditionPickerFrame = nil
   end
end

local function OnGroupSelected(container, event, group)
   CleanupOverlayButtons()
   CloseConditionPicker()
   container:ReleaseChildren()

   if group == "general" then
      DrawGeneralPanel(container)
   elseif group == "filters" then
      DrawFiltersPanel(container)
   elseif group == "bagcleanup" then
      DrawBagCleanupPanel(container)
   elseif group == "bagcleanup\001rules" then
      DrawRulesPanel(container)
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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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
-- Bag Cleanup – Options Panel (parent node)
---------------------------------------------------------------------------
DrawBagCleanupPanel = function(container)
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   local bc = FarmGenieDB.bagCleanup

   -- Header
   local header = AceGUI:Create("Heading")
   header:SetText("Bag Cleanup")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   local desc = AceGUI:Create("Label")
   desc:SetText("  Automatically delete, sell, or bank items based on configurable rules.\n  Create rules with conditions in the Rules tab below.")
   desc:SetFullWidth(true)
   desc:SetFont("Fonts\\FRIZQT__.TTF", 11)
   scroll:AddChild(desc)

   AddSpacer(scroll)

   -- Global Exclusions
   local exclHeader = AceGUI:Create("Heading")
   exclHeader:SetText("Global Exclusions")
   exclHeader:SetFullWidth(true)
   scroll:AddChild(exclHeader)

   local exclDesc = AceGUI:Create("Label")
   exclDesc:SetText("  These items are always protected, regardless of remove rules.")
   exclDesc:SetFullWidth(true)
   exclDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(exclDesc)

   local soulboundCB = AceGUI:Create("CheckBox")
   soulboundCB:SetLabel("Exclude soulbound items")
   soulboundCB:SetDescription("Never delete, sell, or bank items that are soulbound")
   soulboundCB:SetFullWidth(true)
   soulboundCB:SetValue(bc.exclusions.soulbound)
   soulboundCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.exclusions.soulbound = value
   end)
   scroll:AddChild(soulboundCB)

   local questCB = AceGUI:Create("CheckBox")
   questCB:SetLabel("Exclude quest items")
   questCB:SetDescription("Never delete, sell, or bank items of type Quest")
   questCB:SetFullWidth(true)
   questCB:SetValue(bc.exclusions.quest)
   questCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.exclusions.quest = value
   end)
   scroll:AddChild(questCB)

   AddSpacer(scroll)

   -- Automation
   local autoHeader = AceGUI:Create("Heading")
   autoHeader:SetText("Automation")
   autoHeader:SetFullWidth(true)
   scroll:AddChild(autoHeader)

   local autoDeleteCB = AceGUI:Create("CheckBox")
   autoDeleteCB:SetLabel("Enable auto-delete on loot")
   autoDeleteCB:SetDescription("Automatically delete items matching 'Delete' rules as you loot them")
   autoDeleteCB:SetFullWidth(true)
   autoDeleteCB:SetValue(bc.autoDelete)
   autoDeleteCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.autoDelete = value
   end)
   scroll:AddChild(autoDeleteCB)

   local autoVendorCB = AceGUI:Create("CheckBox")
   autoVendorCB:SetLabel("Enable auto-vendor at merchants")
   autoVendorCB:SetDescription("Automatically sell items matching 'Sell' rules when opening a merchant")
   autoVendorCB:SetFullWidth(true)
   autoVendorCB:SetValue(bc.autoVendor)
   autoVendorCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.autoVendor = value
   end)
   scroll:AddChild(autoVendorCB)

   local vendorConfirmCB = AceGUI:Create("CheckBox")
   vendorConfirmCB:SetLabel("Show vendor confirmation")
   vendorConfirmCB:SetDescription("Display a confirmation window before selling items at merchants")
   vendorConfirmCB:SetFullWidth(true)
   vendorConfirmCB:SetValue(bc.showVendorConfirm)
   vendorConfirmCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.showVendorConfirm = value
   end)
   scroll:AddChild(vendorConfirmCB)

   local autoBankCB = AceGUI:Create("CheckBox")
   autoBankCB:SetLabel("Enable auto-bank at bank NPCs")
   autoBankCB:SetDescription("Automatically deposit items matching 'Bank' rules when opening a bank")
   autoBankCB:SetFullWidth(true)
   autoBankCB:SetValue(bc.autoBank)
   autoBankCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.autoBank = value
   end)
   scroll:AddChild(autoBankCB)

   local bankConfirmCB = AceGUI:Create("CheckBox")
   bankConfirmCB:SetLabel("Show bank confirmation")
   bankConfirmCB:SetDescription("Display a confirmation window before depositing items to the bank")
   bankConfirmCB:SetFullWidth(true)
   bankConfirmCB:SetValue(bc.showBankConfirm)
   bankConfirmCB:SetCallback("OnValueChanged", function(widget, event, value)
      bc.showBankConfirm = value
   end)
   scroll:AddChild(bankConfirmCB)

   AddSpacer(scroll)

   -- Manual
   local manualHeader = AceGUI:Create("Heading")
   manualHeader:SetText("Manual")
   manualHeader:SetFullWidth(true)
   scroll:AddChild(manualHeader)

   local cleanBtn = AceGUI:Create("Button")
   cleanBtn:SetText("Clean Bags Now")
   cleanBtn:SetFullWidth(true)
   cleanBtn:SetCallback("OnClick", function()
      if FarmGenieCleanBags then
         FarmGenieCleanBags()
      end
   end)
   scroll:AddChild(cleanBtn)

   local cleanDesc = AceGUI:Create("Label")
   cleanDesc:SetText("  Scans your bags and shows items matching 'Delete' rules for confirmation.\n  Also available via /fg clean")
   cleanDesc:SetFullWidth(true)
   cleanDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(cleanDesc)

   AddSpacer(scroll)

   local bankBtn = AceGUI:Create("Button")
   bankBtn:SetText("Bank Items Now")
   bankBtn:SetFullWidth(true)
   bankBtn:SetCallback("OnClick", function()
      if FarmGenieProcessAutoBank then
         FarmGenieProcessAutoBank()
      end
   end)
   scroll:AddChild(bankBtn)

   local bankDesc = AceGUI:Create("Label")
   bankDesc:SetText("  Scans your bags and shows items matching 'Bank' rules for confirmation.\n  Requires the bank window to be open. Also available via /fg bank")
   bankDesc:SetFullWidth(true)
   bankDesc:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(bankDesc)
end

---------------------------------------------------------------------------
-- Bag Cleanup – Rules Panel (condition builder)
---------------------------------------------------------------------------

local ACTION_COLORS = {
   keep = "\124cff00ff00",
   delete = "\124cffff4444",
   sell = "\124cffffcc00",
   bank = "\124cff69b4ff",
}
local ACTION_LABELS = {
   keep = "Keep",
   delete = "Delete",
   sell = "Sell to Vendor",
   bank = "Deposit to Bank",
}

-- Quality list without "Any" (for condition picker — "any" is expressed by
-- not adding a Quality condition at all)
local QUALITY_PICKER_LIST = {
   [0] = "\124cff9d9d9dPoor\124r",
   [1] = "\124cffffffffCommon\124r",
   [2] = "\124cff1eff00Uncommon\124r",
   [3] = "\124cff0070ddRare\124r",
   [4] = "\124cffa335eeEpic\124r",
}
local QUALITY_PICKER_ORDER = { 0, 1, 2, 3, 4 }

-- Item type list without "Any" (for condition picker)
local ITEM_TYPE_PICKER_LIST = {
   ["Armor"] = "Armor",
   ["Consumable"] = "Consumable",
   ["Container"] = "Container",
   ["Gem"] = "Gem",
   ["Miscellaneous"] = "Miscellaneous",
   ["Projectile"] = "Projectile",
   ["Reagent"] = "Reagent",
   ["Recipe"] = "Recipe",
   ["Trade Goods"] = "Trade Goods",
   ["Weapon"] = "Weapon",
}
local ITEM_TYPE_PICKER_ORDER = {
   "Armor", "Consumable", "Container", "Gem",
   "Miscellaneous", "Projectile", "Reagent", "Recipe",
   "Trade Goods", "Weapon",
}

local TEXTURE_CLOSE = "Interface\\AddOns\\FarmGenie\\Images\\close"
local TEXTURE_UP    = "Interface\\AddOns\\FarmGenie\\Images\\up"
local TEXTURE_DOWN  = "Interface\\AddOns\\FarmGenie\\Images\\down"

--- Create an overlay button parented to an InlineGroup frame (not added as child).
--- Uses a texture icon instead of text for a cleaner look.
local function CreateOverlayButton(parent, xOff, yOff, texture, onClick)
   local btn = AceGUI:Create("Button")
   btn:SetText("")
   btn:SetWidth(20)
   btn:SetHeight(20)
   btn:SetCallback("OnClick", onClick)

   btn.frame:ClearAllPoints()
   btn.frame:SetParent(parent.frame)
   btn.frame:SetPoint("TOPRIGHT", parent.frame, "TOPRIGHT", xOff, yOff)
   btn.frame:SetNormalTexture(texture)
   btn.frame:Show()

   table.insert(overlayButtons, btn)
   return btn
end

--- Format a condition value for display.
local function FormatConditionValue(cond)
   local subject = cond.subject
   local value = cond.value

   if subject == "Quality" then
      local names = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }
      local colors = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee" }
      local name = names[value] or tostring(value)
      local color = colors[value] or "ffffff"
      return "\124cff" .. color .. name .. "\124r"

   elseif subject == "AH Price" or subject == "Vendor Price" then
      return FarmGenieFormatMoneyColored(value)

   elseif subject == "Item Name" then
      return '"' .. tostring(value) .. '"'

   elseif subject == "Item Type" then
      return tostring(value)
   end

   return tostring(value or "")
end

--- Draw a single condition card inside a rule card.
local function DrawConditionCard(parent, rule, condIndex, cond, redraw)
   local condCard = AceGUI:Create("InlineGroup")
   condCard:SetTitle(condIndex .. ". Condition")
   condCard:SetFullWidth(true)
   parent:AddChild(condCard)

   -- Subject
   local subjectLabel = AceGUI:Create("Label")
   subjectLabel:SetFullWidth(true)
   subjectLabel:SetText("\124cFF00FF00Subject:\124r " .. (cond.subject or ""))
   condCard:AddChild(subjectLabel)

   -- Comparer
   local comparerLabel = AceGUI:Create("Label")
   comparerLabel:SetFullWidth(true)
   comparerLabel:SetText("\124cFF00FF00Comparer:\124r " .. (cond.comparer or ""))
   condCard:AddChild(comparerLabel)

   -- Value (only for conditions that have one)
   if cond.value ~= nil then
      local valueLabel = AceGUI:Create("Label")
      valueLabel:SetFullWidth(true)
      valueLabel:SetText("\124cFF00FF00Value:\124r " .. FormatConditionValue(cond))
      condCard:AddChild(valueLabel)
   end

   -- Delete condition overlay button
   CreateOverlayButton(condCard, -10, -25, TEXTURE_CLOSE, function()
      pendingConfirmAction = function()
         table.remove(rule.conditions, condIndex)
         redraw()
      end
      StaticPopup_Show("FARMGENIE_CONFIRM_DELETE",
         "Remove this condition (" .. (cond.subject or "?") .. ")?")
   end)
end

--- Show the condition picker window for adding a new condition to a rule.
local function ShowConditionPicker(ruleIndex, redraw)
   CloseConditionPicker()

   local bc = FarmGenieDB.bagCleanup
   local newCond = {}

   conditionPickerFrame = AceGUI:Create("Window")
   conditionPickerFrame:SetTitle("Add Condition")
   conditionPickerFrame:SetWidth(300)
   conditionPickerFrame:SetHeight(400)
   conditionPickerFrame:SetLayout("List")
   conditionPickerFrame:EnableResize(false)
   conditionPickerFrame.frame:SetFrameStrata("DIALOG")

   if mainFrame then
      conditionPickerFrame:SetPoint("TOPLEFT", mainFrame.frame, "TOPRIGHT", 4, 0)
   end

   FarmGenieRegisterESC("FarmGenieConditionPicker", conditionPickerFrame.frame)

   conditionPickerFrame:SetCallback("OnClose", function(widget)
      FarmGenieUnregisterESC("FarmGenieConditionPicker")
      AceGUI:Release(widget)
      conditionPickerFrame = nil
   end)

   -- Info
   local infoLabel = AceGUI:Create("Label")
   infoLabel:SetFullWidth(true)
   infoLabel:SetText("  Add condition to Rule #" .. ruleIndex)
   infoLabel:SetFont("Fonts\\FRIZQT__.TTF", 11)
   conditionPickerFrame:AddChild(infoLabel)

   AddSpacer(conditionPickerFrame)

   -- Tracking state
   local subjectPicked = false
   local comparerPicked = false
   local valuePicked = false
   local noValueNeeded = false

   -- Build subject list from condition tree
   local subjectOrder = {}
   for subject in pairs(FarmGenieConditionTree) do
      table.insert(subjectOrder, subject)
   end
   table.sort(subjectOrder)
   local subjectList = {}
   for i, s in ipairs(subjectOrder) do subjectList[i] = s end

   -- Create widgets (some hidden initially)
   local subjectDrop = AceGUI:Create("Dropdown")
   subjectDrop:SetLabel("Subject")
   subjectDrop:SetList(subjectList)
   subjectDrop:SetFullWidth(true)

   local comparerDrop = AceGUI:Create("Dropdown")
   comparerDrop:SetLabel("Comparer")
   comparerDrop:SetFullWidth(true)
   comparerDrop:SetList({})

   local valueDrop = AceGUI:Create("Dropdown")
   valueDrop:SetLabel("Value")
   valueDrop:SetFullWidth(true)

   local valueEdit = AceGUI:Create("EditBox")
   valueEdit:SetLabel("Value")
   valueEdit:SetFullWidth(true)

   -- Save button (disabled until all required fields are set)
   local saveBtn = AceGUI:Create("Button")
   saveBtn:SetText("Save")
   saveBtn:SetWidth(120)
   saveBtn:SetDisabled(true)

   local function UpdateSaveState()
      saveBtn:SetDisabled(not (subjectPicked and comparerPicked and (valuePicked or noValueNeeded)))
   end

   -- Subject change handler
   subjectDrop:SetCallback("OnValueChanged", function(widget, event, key)
      local subject = subjectOrder[key]
      newCond.subject = subject
      subjectPicked = true
      comparerPicked = false
      valuePicked = false
      noValueNeeded = false

      -- Update comparer list
      local comparers = FarmGenieConditionTree[subject]
      if comparers then
         local cList = {}
         for i, c in ipairs(comparers) do cList[i] = c end
         comparerDrop:SetList(cList)
         comparerDrop:SetValue(1)
         newCond.comparer = comparers[1]
         comparerPicked = true
      end

      -- Update value widget visibility
      valueDrop.frame:Hide()
      valueEdit.frame:Hide()

      if subject == "Quality" then
         valueDrop.frame:Show()
         valueDrop:SetLabel("Quality")
         valueDrop:SetList(QUALITY_PICKER_LIST, QUALITY_PICKER_ORDER)
         valueDrop:SetValue(0)
         newCond.value = 0
         valuePicked = true
      elseif subject == "Item Type" then
         valueDrop.frame:Show()
         valueDrop:SetLabel("Item Type")
         valueDrop:SetList(ITEM_TYPE_PICKER_LIST, ITEM_TYPE_PICKER_ORDER)
         valuePicked = false
      elseif subject == "Item Name" then
         valueEdit.frame:Show()
         valueEdit:SetLabel("Name text")
         valueEdit:SetText("")
         valuePicked = false
      elseif subject == "AH Price" or subject == "Vendor Price" then
         valueEdit.frame:Show()
         valueEdit:SetLabel("Gold amount")
         valueEdit:SetText("")
         valuePicked = false
      elseif subject == "Soulbound" or subject == "Quest Item" then
         noValueNeeded = true
         valuePicked = true
      end

      UpdateSaveState()
   end)

   -- Comparer change handler
   comparerDrop:SetCallback("OnValueChanged", function(widget, event, key)
      local comparers = FarmGenieConditionTree[newCond.subject]
      if comparers then
         newCond.comparer = comparers[key]
      end
      comparerPicked = true
      UpdateSaveState()
   end)

   -- Value dropdown handler (Quality, Item Type)
   valueDrop:SetCallback("OnValueChanged", function(widget, event, key)
      if newCond.subject == "Quality" then
         newCond.value = key
      elseif newCond.subject == "Item Type" then
         newCond.value = key
      end
      valuePicked = true
      UpdateSaveState()
   end)

   -- Value editbox handler (Item Name, prices)
   valueEdit:SetCallback("OnEnterPressed", function(widget, event, text)
      if newCond.subject == "Item Name" then
         newCond.value = text
         valuePicked = (text ~= "")
      elseif newCond.subject == "AH Price" or newCond.subject == "Vendor Price" then
         local gold = tonumber(text) or 0
         newCond.value = gold * 10000
         valuePicked = (gold > 0)
      end
      UpdateSaveState()
   end)

   -- Also update on text change for live validation
   valueEdit:SetCallback("OnTextChanged", function(widget, event, text)
      if newCond.subject == "Item Name" then
         newCond.value = text
         valuePicked = (text ~= "")
      elseif newCond.subject == "AH Price" or newCond.subject == "Vendor Price" then
         local gold = tonumber(text) or 0
         newCond.value = gold * 10000
         valuePicked = (gold > 0)
      end
      UpdateSaveState()
   end)

   -- Save button handler
   saveBtn:SetCallback("OnClick", function()
      if noValueNeeded then
         newCond.value = nil
      end

      if bc.rules[ruleIndex] then
         if not bc.rules[ruleIndex].conditions then
            bc.rules[ruleIndex].conditions = {}
         end
         table.insert(bc.rules[ruleIndex].conditions, {
            subject = newCond.subject,
            comparer = newCond.comparer,
            value = newCond.value,
         })
      end

      CloseConditionPicker()
      redraw()
   end)

   local cancelBtn = AceGUI:Create("Button")
   cancelBtn:SetText("Cancel")
   cancelBtn:SetWidth(120)
   cancelBtn:SetCallback("OnClick", function()
      CloseConditionPicker()
   end)

   -- Add widgets to picker window
   conditionPickerFrame:AddChild(subjectDrop)
   conditionPickerFrame:AddChild(comparerDrop)
   conditionPickerFrame:AddChild(valueDrop)
   conditionPickerFrame:AddChild(valueEdit)

   -- Initially hide value widgets until subject is selected
   valueDrop.frame:Hide()
   valueEdit.frame:Hide()

   AddSpacer(conditionPickerFrame)

   local btnGroup = AceGUI:Create("SimpleGroup")
   btnGroup:SetFullWidth(true)
   btnGroup:SetLayout("Flow")
   btnGroup:AddChild(saveBtn)
   btnGroup:AddChild(cancelBtn)
   conditionPickerFrame:AddChild(btnGroup)
end

--- Draw a single rule card with action dropdown, condition cards, and overlay buttons.
local function DrawRuleCard(parent, rule, index, totalRules, redraw)
   local bc = FarmGenieDB.bagCleanup
   local actionColor = ACTION_COLORS[rule.action] or "\124cffffffff"
   local actionLabel = ACTION_LABELS[rule.action] or "Unknown"

   local card = AceGUI:Create("InlineGroup")
   card:SetTitle(index .. ". " .. actionColor .. actionLabel .. "\124r")
   card:SetFullWidth(true)
   card:SetLayout("List")
   parent:AddChild(card)

   -- Action dropdown
   local actionDrop = AceGUI:Create("Dropdown")
   actionDrop:SetLabel("Action")
   actionDrop:SetList(ACTION_LIST, ACTION_ORDER)
   actionDrop:SetValue(rule.action)
   actionDrop:SetWidth(150)
   actionDrop:SetCallback("OnValueChanged", function(widget, event, value)
      rule.action = value
      redraw()
   end)
   card:AddChild(actionDrop)

   -- Warning for rules with no conditions
   if not rule.conditions or #rule.conditions == 0 then
      local warnLabel = AceGUI:Create("Label")
      warnLabel:SetFullWidth(true)
      warnLabel:SetText("\124cffff4444Warning: This rule has no conditions and matches ALL items.\124r")
      warnLabel:SetFont("Fonts\\FRIZQT__.TTF", 11)
      card:AddChild(warnLabel)
   else
      -- Render condition cards
      for ci, cond in ipairs(rule.conditions) do
         DrawConditionCard(card, rule, ci, cond, redraw)
      end
   end

   -- "Add Condition" button
   local addCondBtn = AceGUI:Create("Button")
   addCondBtn:SetText("Add Condition")
   addCondBtn:SetWidth(150)
   addCondBtn:SetCallback("OnClick", function()
      ShowConditionPicker(index, redraw)
   end)
   card:AddChild(addCondBtn)

   -- Overlay buttons: delete, move up, move down
   CreateOverlayButton(card, -10, -25, TEXTURE_CLOSE, function()
      pendingConfirmAction = function()
         table.remove(bc.rules, index)
         redraw()
      end
      StaticPopup_Show("FARMGENIE_CONFIRM_DELETE",
         "Delete Rule #" .. index .. " (" .. actionLabel .. ")?")
   end)

   if index > 1 then
      CreateOverlayButton(card, -35, -25, TEXTURE_UP, function()
         bc.rules[index], bc.rules[index - 1] = bc.rules[index - 1], bc.rules[index]
         redraw()
      end)
   end

   if index < totalRules then
      local downXOff = index > 1 and -60 or -35
      CreateOverlayButton(card, downXOff, -25, TEXTURE_DOWN, function()
         bc.rules[index], bc.rules[index + 1] = bc.rules[index + 1], bc.rules[index]
         redraw()
      end)
   end
end

DrawRulesPanel = function(container)
   CleanupOverlayButtons()

   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetFullHeight(true)
   container:AddChild(scroll)

   local bc = FarmGenieDB.bagCleanup

   local header = AceGUI:Create("Heading")
   header:SetText("Cleanup Rules")
   header:SetFullWidth(true)
   scroll:AddChild(header)

   local desc = AceGUI:Create("Label")
   desc:SetText("  Rules are evaluated top to bottom. Keep rules protect items.\n  Delete/Sell/Bank rules act on items not protected by a Keep rule.\n  All conditions within a rule must match (AND logic).")
   desc:SetFullWidth(true)
   desc:SetFont("Fonts\\FRIZQT__.TTF", 11)
   scroll:AddChild(desc)

   AddSpacer(scroll)

   local function redraw()
      -- Save scroll position before the full panel rebuild
      local status = scroll.status or scroll.localstatus
      if status then
         rulesScrollValue = status.scrollvalue
      end
      if treeGroup then treeGroup:SelectByPath("bagcleanup\001rules") end
   end

   if not bc.rules or #bc.rules == 0 then
      local emptyLabel = AceGUI:Create("Label")
      emptyLabel:SetText("  No rules configured. Click 'New Rule' to create one.")
      emptyLabel:SetFullWidth(true)
      emptyLabel:SetFont("Fonts\\FRIZQT__.TTF", 11)
      scroll:AddChild(emptyLabel)
   else
      for i, rule in ipairs(bc.rules) do
         DrawRuleCard(scroll, rule, i, #bc.rules, redraw)
      end
   end

   AddSpacer(scroll)

   local addBtn = AceGUI:Create("Button")
   addBtn:SetText("New Rule")
   addBtn:SetWidth(120)
   addBtn:SetCallback("OnClick", function()
      table.insert(bc.rules, { action = "keep", conditions = {} })
      redraw()
   end)
   scroll:AddChild(addBtn)

   local infoLabel = AceGUI:Create("Label")
   infoLabel:SetText("  Tip: Items with no AH data pass 'AH Price above' (safe for Keep)\n  and fail 'AH Price below' (safe for Delete/Sell).")
   infoLabel:SetFullWidth(true)
   infoLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
   scroll:AddChild(infoLabel)

   -- Restore scroll position after a redraw (deferred one frame so layout completes)
   if rulesScrollValue then
      local pending = rulesScrollValue
      rulesScrollValue = nil
      local restoreFrame = CreateFrame("Frame")
      restoreFrame:SetScript("OnUpdate", function(self)
         self:SetScript("OnUpdate", nil)
         scroll:SetScroll(pending)
      end)
   end
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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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

   AddSpacer(scroll)

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

   AddLine(scroll, "\124cffffcc00Version:\124r 0.5.0")
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
   AddLine(scroll, "\124cffffcc00/fg vendor\124r — Run auto-vendor scan now")
   AddLine(scroll, "\124cffffcc00/fg clean\124r — Clean bags now (delete matching items)")
   AddLine(scroll, "\124cffffcc00/fg bank\124r — Deposit matching items to bank")
   AddLine(scroll, "\124cffffcc00/fg help\124r — Show available commands")
end

---------------------------------------------------------------------------
-- Toggle main config window
---------------------------------------------------------------------------
function FarmGenieToggleMainWindow()
   if mainFrame then
      CleanupOverlayButtons()
      CloseConditionPicker()
      AceGUI:Release(mainFrame)
      mainFrame = nil
      treeGroup = nil
      return
   end

   mainFrame = AceGUI:Create("Window")
   mainFrame:SetTitle("FarmGenie")
   mainFrame:SetWidth(700)
   mainFrame:SetHeight(400)
   mainFrame:SetLayout("Fill")
   mainFrame.frame:SetFrameStrata("HIGH")

   -- Escape key closes the window
   FarmGenieRegisterESC("FarmGenieMainFrame", mainFrame.frame)

   mainFrame:SetCallback("OnClose", function(widget)
      CleanupOverlayButtons()
      CloseConditionPicker()
      FarmGenieUnregisterESC("FarmGenieMainFrame")
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

   -- Expand Bag Cleanup tree node by default
   local status = treeGroup.status or treeGroup.localstatus
   if status and status.groups then
      status.groups["bagcleanup"] = true
   end
   treeGroup:RefreshTree()

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
   elseif msg == "vendor" or msg == "sell" then
      if FarmGenieProcessAutoVendor then
         FarmGenieProcessAutoVendor()
      else
         FarmGeniePrint("Auto-vendor not loaded.")
      end
   elseif msg == "clean" then
      if FarmGenieCleanBags then
         FarmGenieCleanBags()
      else
         FarmGeniePrint("Bag cleanup not loaded.")
      end
   elseif msg == "bank" then
      if FarmGenieProcessAutoBank then
         FarmGenieProcessAutoBank()
      else
         FarmGeniePrint("Bag cleanup not loaded.")
      end
   elseif msg == "help" then
      FarmGeniePrint("Commands:")
      FarmGeniePrint("  /fg — Toggle settings window")
      FarmGeniePrint("  /fg loot — Toggle loot log window")
      FarmGeniePrint("  /fg bar — Toggle item counter bar")
      FarmGeniePrint("  /fg new — Start new session")
      FarmGeniePrint("  /fg pause — Pause logging")
      FarmGeniePrint("  /fg resume — Resume logging")
      FarmGeniePrint("  /fg vendor — Run auto-vendor scan")
      FarmGeniePrint("  /fg clean — Clean bags now")
      FarmGeniePrint("  /fg bank — Deposit matching items to bank")
      FarmGeniePrint("  /fg help — Show this help")
   else
      FarmGeniePrint("Unknown command: " .. msg .. ". Type /fg help for commands.")
   end
end
