---------------------------------------------------------------------------
-- FarmGenie Item Counter Bar
-- Vertical bar of item tracking slots with live bag counts
---------------------------------------------------------------------------

local barSlots = {}           -- pool of created slot Button frames
local barEventFrame = nil     -- event frame for BAG_UPDATE
local SLOT_SIZE = 37          -- pixel size per slot
local SLOT_SPACING = 2        -- gap between slots
local HEADER_HEIGHT = 12      -- drag handle height

---------------------------------------------------------------------------
-- Forward declarations (local helpers)
---------------------------------------------------------------------------
local CreateBarSlot
local RefreshSlot
local RefreshAllSlots
local UpdateCounts
local SavePosition
local RestorePosition

---------------------------------------------------------------------------
-- Slot click handler
---------------------------------------------------------------------------
function FarmGenieBarSlotClick(self, button)
   if CursorHasItem() then
      -- Player is holding an item on the cursor (dragged from bags)
      local infoType, itemID, itemLink = GetCursorInfo()
      if infoType == "item" and itemID then
         FarmGenieBarSetItem(self.slotIndex, itemID)
         ClearCursor()
      end
   elseif button == "RightButton" and self.itemID then
      -- Right-click clears the slot
      FarmGenieBarClearItem(self.slotIndex)
   elseif button == "LeftButton" and IsShiftKeyDown() and self.itemID then
      -- Shift+click inserts item link into chat
      local _, itemLink = GetItemInfo(self.itemID)
      if itemLink and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
         ChatFrameEditBox:Insert(itemLink)
      end
   end
end

---------------------------------------------------------------------------
-- Slot tooltip handlers
---------------------------------------------------------------------------
function FarmGenieBarSlotEnter(self)
   GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
   if self.itemID then
      local _, itemLink = GetItemInfo(self.itemID)
      if itemLink then
         GameTooltip:SetHyperlink(itemLink)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Right-click to remove", 0.5, 0.5, 0.5)
      GameTooltip:Show()
   else
      GameTooltip:AddLine("Empty Slot")
      GameTooltip:AddLine("Drag an item here to track it.", 1, 1, 1, true)
      GameTooltip:Show()
   end
end

function FarmGenieBarSlotLeave(self)
   GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Slot creation
---------------------------------------------------------------------------
CreateBarSlot = function(index)
   if barSlots[index] then return barSlots[index] end

   local slotName = "FarmGenieBarSlot" .. index
   local slot = CreateFrame("Button", slotName, FarmGenieBarFrame)
   slot:SetSize(SLOT_SIZE, SLOT_SIZE)

   -- Position below header + previous slots
   local yOffset = -(HEADER_HEIGHT + (index - 1) * (SLOT_SIZE + SLOT_SPACING))
   slot:SetPoint("TOPLEFT", FarmGenieBarFrame, "TOPLEFT", 0, yOffset)

   -- Background (empty slot indicator)
   slot.bg = slot:CreateTexture(slotName .. "Bg", "BACKGROUND")
   slot.bg:SetAllPoints()
   slot.bg:SetTexture("Interface\\Buttons\\UI-Quickslot")
   slot.bg:SetAlpha(0.5)

   -- Item icon (hidden when empty)
   slot.icon = slot:CreateTexture(slotName .. "Icon", "ARTWORK")
   slot.icon:SetSize(36, 36)
   slot.icon:SetPoint("CENTER")
   slot.icon:Hide()

   -- Border
   slot.border = slot:CreateTexture(slotName .. "Border", "OVERLAY")
   slot.border:SetSize(62, 62)
   slot.border:SetPoint("CENTER")
   slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

   -- Count text
   slot.count = slot:CreateFontString(slotName .. "Count", "OVERLAY", "NumberFontNormal")
   slot.count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -3, 3)
   slot.count:SetText("")

   slot.itemID = nil
   slot.slotIndex = index

   -- Interaction
   slot:EnableMouse(true)
   slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   slot:SetScript("OnClick", FarmGenieBarSlotClick)
   slot:SetScript("OnEnter", FarmGenieBarSlotEnter)
   slot:SetScript("OnLeave", FarmGenieBarSlotLeave)
   slot:SetScript("OnReceiveDrag", function(self)
      FarmGenieBarSlotClick(self, "LeftButton")
   end)

   barSlots[index] = slot
   return slot
end

---------------------------------------------------------------------------
-- Refresh a single slot's visuals from the data array
---------------------------------------------------------------------------
RefreshSlot = function(index)
   local slot = barSlots[index]
   if not slot then return end

   local items = FarmGenieDB.bar.items
   local itemID = items[index]

   slot.itemID = itemID
   slot.slotIndex = index

   if itemID then
      local iconTexture = GetItemIcon(itemID)
      if iconTexture then
         slot.icon:SetTexture(iconTexture)
      else
         -- Item info not cached yet; use placeholder
         slot.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      end
      slot.icon:Show()
      slot.bg:Hide()

      local itemCount = GetItemCount(itemID)
      slot.count:SetText(itemCount > 0 and itemCount or "0")
      if itemCount == 0 then
         slot.icon:SetVertexColor(0.4, 0.4, 0.4)
      else
         slot.icon:SetVertexColor(1, 1, 1)
      end
   else
      -- Empty slot
      slot.icon:Hide()
      slot.bg:Show()
      slot.count:SetText("")
   end
end

---------------------------------------------------------------------------
-- Refresh all slots: reposition, update content, show/hide as needed
---------------------------------------------------------------------------
RefreshAllSlots = function()
   local items = FarmGenieDB.bar.items
   local totalNeeded = #items + 1 -- items plus one trailing empty slot

   -- Create any missing slots
   for i = 1, totalNeeded do
      if not barSlots[i] then
         CreateBarSlot(i)
      end
   end

   -- Reposition and refresh each visible slot
   for i = 1, totalNeeded do
      local slot = barSlots[i]
      slot:ClearAllPoints()
      local yOffset = -(HEADER_HEIGHT + (i - 1) * (SLOT_SIZE + SLOT_SPACING))
      slot:SetPoint("TOPLEFT", FarmGenieBarFrame, "TOPLEFT", 0, yOffset)
      RefreshSlot(i)
      slot:Show()
   end

   -- Hide excess slots beyond what we need
   for i = totalNeeded + 1, #barSlots do
      barSlots[i]:Hide()
   end
end

---------------------------------------------------------------------------
-- Item management
---------------------------------------------------------------------------
function FarmGenieBarSetItem(slotIndex, itemID)
   local items = FarmGenieDB.bar.items

   -- Prevent tracking the same item twice
   for i, existingID in ipairs(items) do
      if existingID == itemID and i ~= slotIndex then
         FarmGeniePrint("That item is already being tracked in slot " .. i .. ".")
         return
      end
   end

   items[slotIndex] = itemID
   RefreshAllSlots()
   UpdateCounts()
   PlaySound("igAbilityIconDrop")
end

function FarmGenieBarClearItem(slotIndex)
   local items = FarmGenieDB.bar.items
   if slotIndex > #items then return end

   table.remove(items, slotIndex)
   RefreshAllSlots()
   PlaySound("igAbilityIconPickup")
end

---------------------------------------------------------------------------
-- Count updates (triggered by BAG_UPDATE)
---------------------------------------------------------------------------
UpdateCounts = function()
   local items = FarmGenieDB.bar and FarmGenieDB.bar.items or {}
   for i, itemID in ipairs(items) do
      local slot = barSlots[i]
      if slot and itemID then
         -- Refresh icon in case item info was not cached at init
         local iconTexture = GetItemIcon(itemID)
         if iconTexture then
            slot.icon:SetTexture(iconTexture)
         end

         local count = GetItemCount(itemID)
         slot.count:SetText(count > 0 and count or "0")
         if count == 0 then
            slot.icon:SetVertexColor(0.4, 0.4, 0.4)
         else
            slot.icon:SetVertexColor(1, 1, 1)
         end
      end
   end
end

---------------------------------------------------------------------------
-- Position save / restore
---------------------------------------------------------------------------
SavePosition = function()
   if not FarmGenieBarFrame or not FarmGenieDB.bar then return end
   local point, _, relPoint, x, y = FarmGenieBarFrame:GetPoint()
   FarmGenieDB.bar.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

RestorePosition = function()
   local pos = FarmGenieDB.bar and FarmGenieDB.bar.pos
   FarmGenieBarFrame:ClearAllPoints()
   if pos then
      FarmGenieBarFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
   else
      FarmGenieBarFrame:SetPoint("LEFT", UIParent, "LEFT", 5, 0)
   end
end

---------------------------------------------------------------------------
-- Toggle visibility
---------------------------------------------------------------------------
function FarmGenieToggleBar()
   if not FarmGenieBarFrame then return end
   if FarmGenieBarFrame:IsShown() then
      FarmGenieBarFrame:Hide()
      if FarmGenieDB.bar then FarmGenieDB.bar.visible = false end
   else
      FarmGenieBarFrame:Show()
      if FarmGenieDB.bar then FarmGenieDB.bar.visible = true end
   end
end

---------------------------------------------------------------------------
-- Initialization (called from PLAYER_LOGIN in FarmGenie.lua)
---------------------------------------------------------------------------
function FarmGenieInitBar()
   -- Ensure DB defaults
   if not FarmGenieDB.bar then
      FarmGenieDB.bar = { items = {}, pos = nil, visible = true }
   end
   if not FarmGenieDB.bar.items then
      FarmGenieDB.bar.items = {}
   end

   -- Create main container / anchor frame
   FarmGenieBarFrame = CreateFrame("Frame", "FarmGenieBarFrame", UIParent)
   FarmGenieBarFrame:SetSize(SLOT_SIZE, HEADER_HEIGHT)
   FarmGenieBarFrame:SetFrameStrata("MEDIUM")
   FarmGenieBarFrame:SetClampedToScreen(true)
   FarmGenieBarFrame:SetMovable(true)
   FarmGenieBarFrame:EnableMouse(true)
   FarmGenieBarFrame:RegisterForDrag("LeftButton")

   -- Drag handle header
   local header = FarmGenieBarFrame:CreateTexture("FarmGenieBarHeader", "BACKGROUND")
   header:SetPoint("TOPLEFT")
   header:SetSize(SLOT_SIZE, HEADER_HEIGHT)
   header:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
   header:SetVertexColor(0, 0.6, 0.8)
   header:SetAlpha(0.7)

   -- Header label
   local headerText = FarmGenieBarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   headerText:SetPoint("CENTER", header)
   headerText:SetText("FG")
   headerText:SetTextColor(1, 1, 1, 0.8)

   -- Dragging
   FarmGenieBarFrame:SetScript("OnDragStart", function(self)
      self:StartMoving()
   end)
   FarmGenieBarFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      SavePosition()
   end)

   -- Tooltip on header
   FarmGenieBarFrame:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("FarmGenie Item Bar")
      GameTooltip:AddLine("Drag items from your bags to track them.", 1, 1, 1, true)
      GameTooltip:AddLine("Right-click a slot to remove it.", 1, 1, 1, true)
      GameTooltip:Show()
   end)
   FarmGenieBarFrame:SetScript("OnLeave", function()
      GameTooltip:Hide()
   end)

   -- Also accept drops directly on the header
   FarmGenieBarFrame:SetScript("OnReceiveDrag", function()
      -- Redirect to the last (empty) slot
      local emptyIndex = #FarmGenieDB.bar.items + 1
      if barSlots[emptyIndex] then
         FarmGenieBarSlotClick(barSlots[emptyIndex], "LeftButton")
      end
   end)

   -- Event frame for BAG_UPDATE
   barEventFrame = CreateFrame("Frame")
   barEventFrame:RegisterEvent("BAG_UPDATE")
   barEventFrame:SetScript("OnEvent", function(self, event)
      if event == "BAG_UPDATE" then
         UpdateCounts()
      end
   end)

   -- Build slots from saved data + one empty slot
   RefreshAllSlots()

   -- Restore position
   RestorePosition()

   -- Apply visibility
   if FarmGenieDB.bar.visible == false then
      FarmGenieBarFrame:Hide()
   end

   -- Initial count update
   UpdateCounts()
end
