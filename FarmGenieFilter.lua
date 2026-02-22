-- FarmGenie Filter
-- Bag cleanup engine: keep/remove rules, auto-delete, auto-vendor, clean bags

local AceGUI = LibStub("AceGUI-3.0")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local DELETE_QUEUE_INTERVAL = 0.5   -- seconds between delete queue ticks
local SELL_INTERVAL = 0.3           -- seconds between vendor sell ticks
local BANK_INTERVAL = 0.3           -- seconds between bank deposit ticks

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local deleteQueue = {}              -- { { itemID, link, bag?, slot? }, ... }
local deleteElapsed = 0
local sellQueue = {}                -- { { bag, slot, link, vendorPrice, quantity, name, quality }, ... }
local sellElapsed = 0
local sellIndex = 0
local isSelling = false
local confirmFrame = nil            -- shared confirmation popup (vendor or clean or bank)
local merchantOpen = false
local totalSold = 0
local totalSoldValue = 0
local bankQueue = {}                -- { { bag, slot, link, name, quality }, ... }
local bankElapsed = 0
local bankIndex = 0
local isBanking = false
local bankOpen = false
local totalBanked = 0

---------------------------------------------------------------------------
-- Soulbound Detection (tooltip scanner)
---------------------------------------------------------------------------
local scanTooltip = CreateFrame("GameTooltip", "FarmGenieScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

function FarmGenieIsSoulbound(bag, slot)
   scanTooltip:ClearLines()
   scanTooltip:SetBagItem(bag, slot)
   for i = 1, scanTooltip:NumLines() do
      local text = _G["FarmGenieScanTooltipTextLeft" .. i]:GetText()
      if text == ITEM_SOULBOUND then return true end
   end
   return false
end

---------------------------------------------------------------------------
-- Condition Tree (shared with GUI for condition picker)
---------------------------------------------------------------------------
FarmGenieConditionTree = {
   ["Quality"]      = { "equals", "not equals", "at least", "at most" },
   ["Item Type"]    = { "equals", "not equals" },
   ["Item Name"]    = { "contains", "not contains" },
   ["AH Price"]     = { "above", "below" },
   ["Vendor Price"] = { "above", "below" },
   ["Soulbound"]    = { "is soulbound", "is not soulbound" },
   ["Quest Item"]   = { "is quest item", "is not quest item" },
}

---------------------------------------------------------------------------
-- Rule Matching Helpers
---------------------------------------------------------------------------

--- Gather all relevant item info into a single table for condition evaluation.
local function GatherItemInfo(itemLink, bag, slot)
   local itemName, _, itemQuality, _, _, itemType = GetItemInfo(itemLink)
   if not itemName then return nil end

   local ahPrice, vendorPrice = FarmGenieGetItemValue(itemLink)
   local isSoulbound = false
   if bag and slot then
      isSoulbound = FarmGenieIsSoulbound(bag, slot)
   end

   return {
      name = itemName,
      quality = itemQuality or 0,
      itemType = itemType,
      ahPrice = ahPrice or 0,
      vendorPrice = vendorPrice or 0,
      soulbound = isSoulbound,
      questItem = (itemType == "Quest"),
   }
end

--- Evaluate a single condition against item info.
local function EvaluateCondition(cond, info)
   local subject = cond.subject
   local comparer = cond.comparer
   local value = cond.value

   if subject == "Quality" then
      local q = info.quality
      if comparer == "equals" then return q == value
      elseif comparer == "not equals" then return q ~= value
      elseif comparer == "at least" then return q >= value
      elseif comparer == "at most" then return q <= value
      end

   elseif subject == "Item Type" then
      local t = info.itemType or ""
      if comparer == "equals" then return t == value
      elseif comparer == "not equals" then return t ~= value
      end

   elseif subject == "Item Name" then
      local n = (info.name or ""):lower()
      local v = (value or ""):lower()
      if comparer == "contains" then return n:find(v, 1, true) ~= nil
      elseif comparer == "not contains" then return n:find(v, 1, true) == nil
      end

   elseif subject == "AH Price" then
      local p = info.ahPrice or 0
      if p <= 0 then
         -- No AH data: "above" → true (safe for keep), "below" → false (safe for remove)
         return comparer == "above"
      end
      if comparer == "above" then return p >= value
      elseif comparer == "below" then return p < value
      end

   elseif subject == "Vendor Price" then
      local p = info.vendorPrice or 0
      if comparer == "above" then return p >= value
      elseif comparer == "below" then return p < value
      end

   elseif subject == "Soulbound" then
      if comparer == "is soulbound" then return info.soulbound == true
      elseif comparer == "is not soulbound" then return info.soulbound ~= true
      end

   elseif subject == "Quest Item" then
      if comparer == "is quest item" then return info.questItem == true
      elseif comparer == "is not quest item" then return info.questItem ~= true
      end
   end

   return false
end

--- Check if all conditions in a rule match (AND logic).
local function MatchesRule(rule, info)
   if not rule.conditions or #rule.conditions == 0 then
      return true  -- No conditions = matches everything
   end
   for _, cond in ipairs(rule.conditions) do
      if not EvaluateCondition(cond, info) then
         return false
      end
   end
   return true
end

---------------------------------------------------------------------------
-- Core Matching Function
---------------------------------------------------------------------------

--- Determine whether an item should be removed and how.
--- @param itemLink string — WoW item link
--- @param bag number|nil — bag index (for soulbound check; nil = skip)
--- @param slot number|nil — slot index
--- @return string|nil — "delete", "sell", or nil (keep)
function FarmGenieShouldRemoveItem(itemLink, bag, slot)
   if not itemLink then return nil end
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return nil end

   local bc = FarmGenieDB.bagCleanup

   -- Global exclusions (checked before condition-based rules)
   local itemName, _, itemQuality, _, _, itemType = GetItemInfo(itemLink)
   if not itemName then return nil end
   if bc.exclusions then
      if bc.exclusions.quest and itemType == "Quest" then return nil end
      if bc.exclusions.soulbound and bag and slot then
         if FarmGenieIsSoulbound(bag, slot) then return nil end
      end
   end

   local info = GatherItemInfo(itemLink, bag, slot)
   if not info then return nil end

   if not bc.rules then return nil end

   -- Keep rules: any match → protect
   for _, rule in ipairs(bc.rules) do
      if rule.action == "keep" and MatchesRule(rule, info) then
         return nil
      end
   end

   -- Remove rules: first match → return action
   for _, rule in ipairs(bc.rules) do
      if (rule.action == "delete" or rule.action == "sell" or rule.action == "bank") and MatchesRule(rule, info) then
         return rule.action
      end
   end

   return nil
end

---------------------------------------------------------------------------
-- Auto-Delete (on loot)
---------------------------------------------------------------------------

--- Queue an item for auto-deletion if it matches a "delete" remove rule.
--- Called from FarmGenie.lua after ProcessLoot().
function FarmGenieProcessAutoDelete(itemLink)
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return end
   if not FarmGenieDB.bagCleanup.autoDelete then return end

   -- On loot we don't have bag/slot yet; soulbound checked at deletion time
   local action = FarmGenieShouldRemoveItem(itemLink, nil, nil)
   if action == "delete" then
      local itemID = tonumber(itemLink:match("item:(%d+)"))
      if itemID then
         table.insert(deleteQueue, { itemID = itemID, link = itemLink })
      end
   end
end

--- Find an item in bags by itemID and delete it.
--- Returns true if the item was found and deleted.
local function DeleteItemFromBags(itemID)
   local bc = FarmGenieDB and FarmGenieDB.bagCleanup
   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            local slotItemID = tonumber(link:match("item:(%d+)"))
            if slotItemID == itemID then
               local _, count, locked = GetContainerItemInfo(bag, slot)
               if locked then return false end
               -- Soulbound safety check at deletion time
               if bc and bc.exclusions and bc.exclusions.soulbound then
                  if FarmGenieIsSoulbound(bag, slot) then return false end
               end
               PickupContainerItem(bag, slot)
               DeleteCursorItem()
               return true
            end
         end
      end
   end
   return false
end

--- OnUpdate handler for processing the delete queue.
local function ProcessDeleteQueue(self, elapsed)
   if #deleteQueue == 0 then return end

   deleteElapsed = deleteElapsed + elapsed
   if deleteElapsed < DELETE_QUEUE_INTERVAL then return end
   deleteElapsed = 0

   local entry = table.remove(deleteQueue, 1)
   if entry then
      if DeleteItemFromBags(entry.itemID) then
         FarmGeniePrint("Auto-deleted " .. entry.link)
      end
   end
end

---------------------------------------------------------------------------
-- Auto-Vendor (at merchant)
---------------------------------------------------------------------------

--- Scan all bags for items matching "sell" remove rules.
--- Returns array of { bag, slot, link, vendorPrice, quantity, name, quality }
local function ScanBagsForVendorItems()
   local items = {}
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return items end

   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            local action = FarmGenieShouldRemoveItem(link, bag, slot)
            if action == "sell" then
               local itemName, _, itemQuality = GetItemInfo(link)
               local _, count = GetContainerItemInfo(bag, slot)
               local vendorPrice = select(11, GetItemInfo(link)) or 0
               table.insert(items, {
                  bag = bag,
                  slot = slot,
                  link = link,
                  vendorPrice = vendorPrice * (count or 1),
                  quantity = count or 1,
                  name = itemName or "Unknown",
                  quality = itemQuality or 0,
               })
            end
         end
      end
   end

   return items
end

--- Execute the vendor sell queue one item at a time.
local function ProcessSellQueue(self, elapsed)
   if not isSelling then return end
   if not merchantOpen then
      isSelling = false
      sellQueue = {}
      sellIndex = 0
      return
   end

   sellElapsed = sellElapsed + elapsed
   if sellElapsed < SELL_INTERVAL then return end
   sellElapsed = 0

   sellIndex = sellIndex + 1
   if sellIndex > #sellQueue then
      isSelling = false
      if totalSold > 0 then
         FarmGeniePrint("Sold " .. totalSold .. " items for " ..
            FarmGenieFormatMoney(totalSoldValue))
      end
      sellQueue = {}
      sellIndex = 0
      totalSold = 0
      totalSoldValue = 0
      return
   end

   local item = sellQueue[sellIndex]
   if item then
      local link = GetContainerItemLink(item.bag, item.slot)
      if link then
         UseContainerItem(item.bag, item.slot)
         totalSold = totalSold + 1
         totalSoldValue = totalSoldValue + item.vendorPrice
      end
   end
end

--- Start selling items from the sell list.
function FarmGenieExecuteVendorSell(items)
   if not merchantOpen then
      FarmGeniePrint("Merchant window is not open.")
      return
   end
   if not items or #items == 0 then return end

   sellQueue = items
   sellIndex = 0
   sellElapsed = 0
   totalSold = 0
   totalSoldValue = 0
   isSelling = true

   -- Close confirmation window if open
   if confirmFrame then
      AceGUI:Release(confirmFrame)
      confirmFrame = nil
   end
end

---------------------------------------------------------------------------
-- Confirmation Popup (shared by vendor and clean bags)
---------------------------------------------------------------------------

--- Close the confirmation popup if open.
local function CloseConfirmFrame()
   if confirmFrame then
      AceGUI:Release(confirmFrame)
      confirmFrame = nil
   end
end

--- Show a confirmation popup listing items.
--- @param title string — window title
--- @param headerText string — description above the list
--- @param items table — array of { link, quantity, displayPrice }
--- @param totalValue number — total copper value
--- @param confirmLabel string — text for the confirm button
--- @param onConfirm function — called when confirm is clicked
local function ShowConfirmPopup(title, headerText, items, totalValue, confirmLabel, onConfirm)
   CloseConfirmFrame()
   if not items or #items == 0 then return end

   local frame = AceGUI:Create("Window")
   frame:SetTitle(title)
   frame:SetWidth(350)
   frame:SetHeight(320)
   frame:SetLayout("List")
   frame.frame:SetFrameStrata("DIALOG")

   confirmFrame = frame

   FarmGenieRegisterESC("FarmGenieConfirmFrame", frame.frame)

   frame:SetCallback("OnClose", function(widget)
      FarmGenieUnregisterESC("FarmGenieConfirmFrame")
      AceGUI:Release(widget)
      confirmFrame = nil
   end)

   -- Header
   local header = AceGUI:Create("Label")
   header:SetText("  " .. headerText)
   header:SetFullWidth(true)
   header:SetFont("Fonts\\FRIZQT__.TTF", 11)
   frame:AddChild(header)

   -- Scrollable item list
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetHeight(180)
   frame:AddChild(scroll)

   for _, item in ipairs(items) do
      local label = AceGUI:Create("InteractiveLabel")
      local priceText = FarmGenieFormatMoneyColored(item.displayPrice)
      local qtyText = item.quantity > 1 and (" x" .. item.quantity) or ""
      label:SetText("  " .. item.link .. qtyText .. "  " .. priceText)
      label:SetFullWidth(true)
      label:SetFont("Fonts\\FRIZQT__.TTF", 11)
      label:SetCallback("OnEnter", function(widget)
         GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
         GameTooltip:SetHyperlink(item.link)
         GameTooltip:Show()
      end)
      label:SetCallback("OnLeave", function()
         GameTooltip:Hide()
      end)
      scroll:AddChild(label)
   end

   -- Total
   local totalLabel = AceGUI:Create("Label")
   totalLabel:SetText("  Total: " .. FarmGenieFormatMoneyColored(totalValue) ..
      "  (" .. #items .. " items)")
   totalLabel:SetFullWidth(true)
   totalLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
   frame:AddChild(totalLabel)

   -- Button row
   local btnGroup = AceGUI:Create("SimpleGroup")
   btnGroup:SetLayout("Flow")
   btnGroup:SetFullWidth(true)
   frame:AddChild(btnGroup)

   local confirmBtn = AceGUI:Create("Button")
   confirmBtn:SetText(confirmLabel)
   confirmBtn:SetWidth(140)
   confirmBtn:SetCallback("OnClick", function()
      onConfirm()
   end)
   btnGroup:AddChild(confirmBtn)

   local cancelBtn = AceGUI:Create("Button")
   cancelBtn:SetText("Cancel")
   cancelBtn:SetWidth(140)
   cancelBtn:SetCallback("OnClick", function()
      CloseConfirmFrame()
   end)
   btnGroup:AddChild(cancelBtn)
end

---------------------------------------------------------------------------
-- Vendor Confirmation
---------------------------------------------------------------------------

function FarmGenieShowVendorConfirm(items)
   if not items or #items == 0 then return end

   -- Build display items with vendorPrice as displayPrice
   local displayItems = {}
   local totalValue = 0
   for _, item in ipairs(items) do
      table.insert(displayItems, {
         link = item.link,
         quantity = item.quantity,
         displayPrice = item.vendorPrice,
      })
      totalValue = totalValue + item.vendorPrice
   end

   ShowConfirmPopup(
      "FarmGenie \226\128\148 Auto Vendor",
      "The following items will be sold:",
      displayItems,
      totalValue,
      "Sell All",
      function() FarmGenieExecuteVendorSell(items) end
   )
end

--- Process auto-vendor when merchant opens.
function FarmGenieProcessAutoVendor()
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return end
   if not FarmGenieDB.bagCleanup.autoVendor then return end

   local items = ScanBagsForVendorItems()
   if #items == 0 then return end

   if FarmGenieDB.bagCleanup.showVendorConfirm then
      FarmGenieShowVendorConfirm(items)
   else
      FarmGenieExecuteVendorSell(items)
   end
end

---------------------------------------------------------------------------
-- Clean Bags (manual delete with confirmation)
---------------------------------------------------------------------------

--- Scan bags for items matching "delete" remove rules.
--- Returns array of { bag, slot, link, ahPrice, vendorPrice, quantity, name, quality, itemID }
local function ScanBagsForDeleteItems()
   local items = {}
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return items end

   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            local action = FarmGenieShouldRemoveItem(link, bag, slot)
            if action == "delete" then
               local itemName, _, itemQuality = GetItemInfo(link)
               local _, count = GetContainerItemInfo(bag, slot)
               local ahPrice, vendorPrice = FarmGenieGetItemValue(link)
               local displayPrice = ahPrice > 0 and ahPrice or (vendorPrice or 0)
               local itemID = tonumber(link:match("item:(%d+)"))
               table.insert(items, {
                  bag = bag,
                  slot = slot,
                  link = link,
                  displayPrice = displayPrice * (count or 1),
                  quantity = count or 1,
                  name = itemName or "Unknown",
                  quality = itemQuality or 0,
                  itemID = itemID,
               })
            end
         end
      end
   end

   return items
end

--- Execute the clean bags operation: queue items for deletion.
local function ExecuteCleanBags(items)
   if not items or #items == 0 then return end
   for _, item in ipairs(items) do
      if item.itemID then
         table.insert(deleteQueue, { itemID = item.itemID, link = item.link })
      end
   end
   CloseConfirmFrame()
end

--- Scan bags and show a confirmation popup for items to delete.
function FarmGenieCleanBags()
   local items = ScanBagsForDeleteItems()
   if #items == 0 then
      FarmGeniePrint("No items to clean.")
      return
   end

   local displayItems = {}
   local totalValue = 0
   for _, item in ipairs(items) do
      table.insert(displayItems, {
         link = item.link,
         quantity = item.quantity,
         displayPrice = item.displayPrice,
      })
      totalValue = totalValue + item.displayPrice
   end

   ShowConfirmPopup(
      "FarmGenie \226\128\148 Clean Bags",
      "The following items will be deleted:",
      displayItems,
      totalValue,
      "Delete All",
      function() ExecuteCleanBags(items) end
   )
end

---------------------------------------------------------------------------
-- Auto-Bank (at bank NPC)
---------------------------------------------------------------------------

--- Scan all bags for items matching "bank" remove rules.
--- Returns array of { bag, slot, link, quantity, name, quality, displayPrice }
local function ScanBagsForBankItems()
   local items = {}
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return items end

   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            local action = FarmGenieShouldRemoveItem(link, bag, slot)
            if action == "bank" then
               local itemName, _, itemQuality = GetItemInfo(link)
               local _, count = GetContainerItemInfo(bag, slot)
               local ahPrice, vendorPrice = FarmGenieGetItemValue(link)
               local displayPrice = ahPrice > 0 and ahPrice or (vendorPrice or 0)
               table.insert(items, {
                  bag = bag,
                  slot = slot,
                  link = link,
                  displayPrice = displayPrice * (count or 1),
                  quantity = count or 1,
                  name = itemName or "Unknown",
                  quality = itemQuality or 0,
               })
            end
         end
      end
   end

   return items
end

--- Execute the bank deposit queue one item at a time.
local function ProcessBankQueue(self, elapsed)
   if not isBanking then return end
   if not bankOpen then
      isBanking = false
      bankQueue = {}
      bankIndex = 0
      return
   end

   bankElapsed = bankElapsed + elapsed
   if bankElapsed < BANK_INTERVAL then return end
   bankElapsed = 0

   bankIndex = bankIndex + 1
   if bankIndex > #bankQueue then
      isBanking = false
      if totalBanked > 0 then
         FarmGeniePrint("Deposited " .. totalBanked .. " items to bank.")
      end
      bankQueue = {}
      bankIndex = 0
      totalBanked = 0
      return
   end

   local item = bankQueue[bankIndex]
   if item then
      local link = GetContainerItemLink(item.bag, item.slot)
      if link then
         UseContainerItem(item.bag, item.slot)
         totalBanked = totalBanked + 1
      end
   end
end

--- Start depositing items from the bank list.
function FarmGenieExecuteBankDeposit(items)
   if not bankOpen then
      FarmGeniePrint("Bank window is not open.")
      return
   end
   if not items or #items == 0 then return end

   bankQueue = items
   bankIndex = 0
   bankElapsed = 0
   totalBanked = 0
   isBanking = true

   -- Close confirmation window if open
   if confirmFrame then
      AceGUI:Release(confirmFrame)
      confirmFrame = nil
   end
end

--- Show bank confirmation popup.
function FarmGenieShowBankConfirm(items)
   if not items or #items == 0 then return end

   local displayItems = {}
   local totalValue = 0
   for _, item in ipairs(items) do
      table.insert(displayItems, {
         link = item.link,
         quantity = item.quantity,
         displayPrice = item.displayPrice,
      })
      totalValue = totalValue + item.displayPrice
   end

   ShowConfirmPopup(
      "FarmGenie \226\128\148 Auto Bank",
      "The following items will be deposited:",
      displayItems,
      totalValue,
      "Deposit All",
      function() FarmGenieExecuteBankDeposit(items) end
   )
end

--- Process auto-bank when bank opens.
function FarmGenieProcessAutoBank()
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return end
   if not FarmGenieDB.bagCleanup.autoBank then return end

   local items = ScanBagsForBankItems()
   if #items == 0 then return end

   if FarmGenieDB.bagCleanup.showBankConfirm then
      FarmGenieShowBankConfirm(items)
   else
      FarmGenieExecuteBankDeposit(items)
   end
end

---------------------------------------------------------------------------
-- Migration & Initialization
---------------------------------------------------------------------------

--- Migrate v0.1 deleteRules/vendorRules → v0.2 keepRules/removeRules.
local function MigrateV1Rules()
   if not FarmGenieDB then return end
   if not FarmGenieDB.deleteRules and not FarmGenieDB.vendorRules then return end
   if FarmGenieDB.bagCleanup then return end

   local bc = {
      exclusions = { soulbound = true, quest = true },
      keepRules = {},
      removeRules = {},
      autoDelete = false,
      autoVendor = false,
      showVendorConfirm = true,
   }

   if FarmGenieDB.deleteRules then
      bc.autoDelete = FarmGenieDB.deleteRules.enabled or false
      if FarmGenieDB.deleteRules.rules then
         for _, rule in ipairs(FarmGenieDB.deleteRules.rules) do
            table.insert(bc.removeRules, {
               quality = rule.quality or 0,
               maxPrice = rule.maxPrice,
               action = "delete",
            })
         end
      end
      FarmGenieDB.deleteRules = nil
   end

   if FarmGenieDB.vendorRules then
      bc.autoVendor = FarmGenieDB.vendorRules.enabled or false
      bc.showVendorConfirm = FarmGenieDB.vendorRules.showConfirm
      if bc.showVendorConfirm == nil then bc.showVendorConfirm = true end
      if FarmGenieDB.vendorRules.rules then
         for _, rule in ipairs(FarmGenieDB.vendorRules.rules) do
            table.insert(bc.removeRules, {
               quality = rule.quality or 0,
               maxPrice = rule.maxPrice,
               action = "sell",
            })
         end
      end
      FarmGenieDB.vendorRules = nil
   end

   FarmGenieDB.bagCleanup = bc
   FarmGeniePrint("Migrated filter rules to new Bag Cleanup format.")
end

--- Migrate v0.2 keepRules/removeRules → v0.3 condition-based rules.
local function MigrateToConditionRules()
   if not FarmGenieDB or not FarmGenieDB.bagCleanup then return end
   local bc = FarmGenieDB.bagCleanup

   -- Already migrated or nothing to migrate
   if bc.rules then return end
   if not bc.keepRules and not bc.removeRules then return end

   local newRules = {}

   -- Convert keep rules
   if bc.keepRules then
      for _, old in ipairs(bc.keepRules) do
         local rule = { action = "keep", conditions = {} }
         if old.quality and old.quality ~= -1 then
            table.insert(rule.conditions, { subject = "Quality", comparer = "equals", value = old.quality })
         end
         if old.itemType then
            table.insert(rule.conditions, { subject = "Item Type", comparer = "equals", value = old.itemType })
         end
         if old.nameMatch and old.nameMatch ~= "" then
            table.insert(rule.conditions, { subject = "Item Name", comparer = "contains", value = old.nameMatch })
         end
         if old.minPrice and old.minPrice > 0 then
            table.insert(rule.conditions, { subject = "AH Price", comparer = "above", value = old.minPrice })
         end
         table.insert(newRules, rule)
      end
   end

   -- Convert remove rules
   if bc.removeRules then
      for _, old in ipairs(bc.removeRules) do
         local rule = { action = old.action or "delete", conditions = {} }
         if old.quality and old.quality ~= -1 then
            table.insert(rule.conditions, { subject = "Quality", comparer = "equals", value = old.quality })
         end
         if old.itemType then
            table.insert(rule.conditions, { subject = "Item Type", comparer = "equals", value = old.itemType })
         end
         if old.nameMatch and old.nameMatch ~= "" then
            table.insert(rule.conditions, { subject = "Item Name", comparer = "contains", value = old.nameMatch })
         end
         if old.maxPrice and old.maxPrice > 0 then
            table.insert(rule.conditions, { subject = "AH Price", comparer = "below", value = old.maxPrice })
         end
         table.insert(newRules, rule)
      end
   end

   bc.rules = newRules
   bc.keepRules = nil
   bc.removeRules = nil
   FarmGeniePrint("Migrated rules to condition-based format.")
end

function FarmGenieInitFilter()
   if not FarmGenieDB then FarmGenieDB = {} end

   -- Migrate v0.1 → v0.2 (old deleteRules/vendorRules)
   MigrateV1Rules()

   -- Ensure bagCleanup structure exists
   if not FarmGenieDB.bagCleanup then
      FarmGenieDB.bagCleanup = {
         exclusions = { soulbound = true, quest = true },
         rules = {},
         autoDelete = false,
         autoVendor = false,
         showVendorConfirm = true,
         autoBank = true,
         showBankConfirm = true,
      }
   end

   -- Migrate v0.2 → v0.3 (keepRules/removeRules → condition-based rules)
   MigrateToConditionRules()

   local bc = FarmGenieDB.bagCleanup
   if not bc.exclusions then bc.exclusions = { soulbound = true, quest = true } end
   if bc.exclusions.soulbound == nil then bc.exclusions.soulbound = true end
   if bc.exclusions.quest == nil then bc.exclusions.quest = true end
   if not bc.rules then bc.rules = {} end
   if bc.autoDelete == nil then bc.autoDelete = false end
   if bc.autoVendor == nil then bc.autoVendor = false end
   if bc.showVendorConfirm == nil then bc.showVendorConfirm = true end
   if bc.autoBank == nil then bc.autoBank = true end
   if bc.showBankConfirm == nil then bc.showBankConfirm = true end
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------

local filterEventFrame = CreateFrame("Frame")
filterEventFrame:RegisterEvent("MERCHANT_SHOW")
filterEventFrame:RegisterEvent("MERCHANT_CLOSED")
filterEventFrame:RegisterEvent("BANKFRAME_OPENED")
filterEventFrame:RegisterEvent("BANKFRAME_CLOSED")

filterEventFrame:SetScript("OnEvent", function(self, event)
   if event == "MERCHANT_SHOW" then
      merchantOpen = true
      FarmGenieProcessAutoVendor()

   elseif event == "MERCHANT_CLOSED" then
      merchantOpen = false
      -- Close confirmation window if still open
      CloseConfirmFrame()
      -- Abort any in-progress selling
      if isSelling then
         isSelling = false
         if totalSold > 0 then
            FarmGeniePrint("Sold " .. totalSold .. " items for " ..
               FarmGenieFormatMoney(totalSoldValue))
         end
         sellQueue = {}
         sellIndex = 0
         totalSold = 0
         totalSoldValue = 0
      end

   elseif event == "BANKFRAME_OPENED" then
      bankOpen = true
      FarmGenieProcessAutoBank()

   elseif event == "BANKFRAME_CLOSED" then
      bankOpen = false
      -- Close confirmation window if still open
      CloseConfirmFrame()
      -- Abort any in-progress banking
      if isBanking then
         isBanking = false
         if totalBanked > 0 then
            FarmGeniePrint("Deposited " .. totalBanked .. " items to bank.")
         end
         bankQueue = {}
         bankIndex = 0
         totalBanked = 0
      end
   end
end)

-- OnUpdate for delete queue, sell queue, and bank queue processing
filterEventFrame:SetScript("OnUpdate", function(self, elapsed)
   ProcessDeleteQueue(self, elapsed)
   ProcessSellQueue(self, elapsed)
   ProcessBankQueue(self, elapsed)
end)
