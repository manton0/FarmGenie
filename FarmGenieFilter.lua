-- FarmGenie Filter
-- Auto-delete items on loot, auto-vendor at merchants, vendor confirmation popup

local AceGUI = LibStub("AceGUI-3.0")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local DELETE_QUEUE_INTERVAL = 0.5   -- seconds between delete queue checks
local SELL_INTERVAL = 0.3           -- seconds between vendor sells

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local deleteQueue = {}              -- { { itemID = num, link = string }, ... }
local deleteElapsed = 0
local sellQueue = {}                -- { { bag = num, slot = num, link = string, vendorPrice = num }, ... }
local sellElapsed = 0
local sellIndex = 0
local isSelling = false
local vendorConfirmFrame = nil
local merchantOpen = false
local totalSold = 0
local totalSoldValue = 0

---------------------------------------------------------------------------
-- Rule Matching
---------------------------------------------------------------------------

--- Check if an item matches any rule in a ruleset.
--- Returns true if matched, false otherwise.
--- @param rules table — array of { quality = num, maxPrice = num? }
--- @param itemLink string — WoW item link
function FarmGenieMatchesRules(rules, itemLink)
   if not rules or #rules == 0 then return false end
   if not itemLink then return false end

   local itemName, _, itemQuality, _, _, itemType = GetItemInfo(itemLink)
   if not itemName then return false end
   itemQuality = itemQuality or 0

   -- Never match quest items
   if itemType == "Quest" then return false end

   local ahPrice, vendorPrice = FarmGenieGetItemValue(itemLink)

   for _, rule in ipairs(rules) do
      if itemQuality == rule.quality then
         if rule.maxPrice and rule.maxPrice > 0 then
            -- Price condition: only match if AH price is below threshold
            -- Skip items with no AH data (safe default)
            if ahPrice > 0 and ahPrice < rule.maxPrice then
               return true
            end
         else
            -- No price condition: match all items of this quality
            return true
         end
      end
   end

   return false
end

---------------------------------------------------------------------------
-- Auto-Delete
---------------------------------------------------------------------------

--- Queue an item for auto-deletion if it matches delete rules.
--- Called from FarmGenie.lua after ProcessLoot().
function FarmGenieProcessAutoDelete(itemLink)
   if not FarmGenieDB then return end
   if not FarmGenieDB.deleteRules then return end
   if not FarmGenieDB.deleteRules.enabled then return end

   if FarmGenieMatchesRules(FarmGenieDB.deleteRules.rules, itemLink) then
      local itemID = tonumber(itemLink:match("item:(%d+)"))
      if itemID then
         table.insert(deleteQueue, { itemID = itemID, link = itemLink })
      end
   end
end

--- Find an item in bags by itemID and delete it.
--- Returns true if the item was found and deleted.
local function DeleteItemFromBags(itemID)
   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            local slotItemID = tonumber(link:match("item:(%d+)"))
            if slotItemID == itemID then
               -- Check that the item isn't locked (e.g., during trade)
               local _, count, locked = GetContainerItemInfo(bag, slot)
               if not locked then
                  PickupContainerItem(bag, slot)
                  DeleteCursorItem()
                  return true
               end
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

   -- Process one item per tick
   local entry = table.remove(deleteQueue, 1)
   if entry then
      if DeleteItemFromBags(entry.itemID) then
         FarmGeniePrint("Auto-deleted " .. entry.link)
      end
   end
end

---------------------------------------------------------------------------
-- Auto-Vendor
---------------------------------------------------------------------------

--- Scan all bags for items matching vendor rules.
--- Returns array of { bag, slot, link, vendorPrice, quantity, name, quality }
local function ScanBagsForVendorItems()
   local items = {}
   if not FarmGenieDB or not FarmGenieDB.vendorRules then return items end
   if not FarmGenieDB.vendorRules.rules or #FarmGenieDB.vendorRules.rules == 0 then return items end

   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            if FarmGenieMatchesRules(FarmGenieDB.vendorRules.rules, link) then
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
      -- Merchant closed, abort
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
      -- Done selling
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
      -- Verify item is still in that bag slot
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
   if vendorConfirmFrame then
      AceGUI:Release(vendorConfirmFrame)
      vendorConfirmFrame = nil
   end
end

---------------------------------------------------------------------------
-- Vendor Confirmation Window
---------------------------------------------------------------------------

--- Show a confirmation popup listing items to be sold.
function FarmGenieShowVendorConfirm(items)
   -- Close existing window if any
   if vendorConfirmFrame then
      AceGUI:Release(vendorConfirmFrame)
      vendorConfirmFrame = nil
   end

   if not items or #items == 0 then return end

   local frame = AceGUI:Create("Window")
   frame:SetTitle("FarmGenie \226\128\148 Auto Vendor")
   frame:SetWidth(350)
   frame:SetHeight(320)
   frame:SetLayout("List")
   frame.frame:SetFrameStrata("DIALOG")

   vendorConfirmFrame = frame

   -- Escape key closes
   FarmGenieRegisterESC("FarmGenieVendorConfirmFrame", frame.frame)

   frame:SetCallback("OnClose", function(widget)
      FarmGenieUnregisterESC("FarmGenieVendorConfirmFrame")
      AceGUI:Release(widget)
      vendorConfirmFrame = nil
   end)

   -- Header
   local header = AceGUI:Create("Label")
   header:SetText("  The following items will be sold:")
   header:SetFullWidth(true)
   header:SetFont("Fonts\\FRIZQT__.TTF", 11)
   frame:AddChild(header)

   -- Scrollable item list
   local scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   scroll:SetFullWidth(true)
   scroll:SetHeight(180)
   frame:AddChild(scroll)

   local totalValue = 0
   for _, item in ipairs(items) do
      local label = AceGUI:Create("InteractiveLabel")
      local priceText = FarmGenieFormatMoneyColored(item.vendorPrice)
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
      totalValue = totalValue + item.vendorPrice
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

   local sellBtn = AceGUI:Create("Button")
   sellBtn:SetText("Sell All")
   sellBtn:SetWidth(140)
   sellBtn:SetCallback("OnClick", function()
      FarmGenieExecuteVendorSell(items)
   end)
   btnGroup:AddChild(sellBtn)

   local cancelBtn = AceGUI:Create("Button")
   cancelBtn:SetText("Cancel")
   cancelBtn:SetWidth(140)
   cancelBtn:SetCallback("OnClick", function()
      if vendorConfirmFrame then
         AceGUI:Release(vendorConfirmFrame)
         vendorConfirmFrame = nil
      end
   end)
   btnGroup:AddChild(cancelBtn)
end

--- Process auto-vendor when merchant opens.
function FarmGenieProcessAutoVendor()
   if not FarmGenieDB then return end
   if not FarmGenieDB.vendorRules then return end
   if not FarmGenieDB.vendorRules.enabled then return end

   local items = ScanBagsForVendorItems()
   if #items == 0 then return end

   if FarmGenieDB.vendorRules.showConfirm then
      FarmGenieShowVendorConfirm(items)
   else
      FarmGenieExecuteVendorSell(items)
   end
end

---------------------------------------------------------------------------
-- Event Handling & Initialization
---------------------------------------------------------------------------

function FarmGenieInitFilter()
   -- Ensure DB defaults
   if not FarmGenieDB then FarmGenieDB = {} end

   if FarmGenieDB.deleteRules == nil then
      FarmGenieDB.deleteRules = { enabled = false, rules = {} }
   end
   if FarmGenieDB.deleteRules.rules == nil then
      FarmGenieDB.deleteRules.rules = {}
   end

   if FarmGenieDB.vendorRules == nil then
      FarmGenieDB.vendorRules = { enabled = false, showConfirm = true, rules = {} }
   end
   if FarmGenieDB.vendorRules.rules == nil then
      FarmGenieDB.vendorRules.rules = {}
   end
   if FarmGenieDB.vendorRules.showConfirm == nil then
      FarmGenieDB.vendorRules.showConfirm = true
   end
end

-- Event frame for MERCHANT_SHOW / MERCHANT_CLOSED
local filterEventFrame = CreateFrame("Frame")
filterEventFrame:RegisterEvent("MERCHANT_SHOW")
filterEventFrame:RegisterEvent("MERCHANT_CLOSED")

filterEventFrame:SetScript("OnEvent", function(self, event)
   if event == "MERCHANT_SHOW" then
      merchantOpen = true
      FarmGenieProcessAutoVendor()

   elseif event == "MERCHANT_CLOSED" then
      merchantOpen = false
      -- Close confirmation window if still open
      if vendorConfirmFrame then
         AceGUI:Release(vendorConfirmFrame)
         vendorConfirmFrame = nil
      end
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
   end
end)

-- OnUpdate for delete queue and sell queue processing
filterEventFrame:SetScript("OnUpdate", function(self, elapsed)
   ProcessDeleteQueue(self, elapsed)
   ProcessSellQueue(self, elapsed)
end)
