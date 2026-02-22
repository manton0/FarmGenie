-- FarmGenie Core
-- Loot tracking, price lookups, session management, initialization

---------------------------------------------------------------------------
-- Session state (global, accessible from other files)
---------------------------------------------------------------------------
FarmGenieSession = nil   -- set by FarmGenieNewSession()

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local QUALITY_COLORS = {
   [0] = "9d9d9d",  -- Poor (gray)
   [1] = "ffffff",  -- Common (white)
   [2] = "1eff00",  -- Uncommon (green)
   [3] = "0070dd",  -- Rare (blue)
   [4] = "a335ee",  -- Epic (purple)
   [5] = "ff8000",  -- Legendary (orange)
}

local QUALITY_NAMES = {
   [0] = "Poor",
   [1] = "Common",
   [2] = "Uncommon",
   [3] = "Rare",
   [4] = "Epic",
   [5] = "Legendary",
}

---------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------
local function colorText(text)
   return "\124cff00E5EE" .. text .. "\124r"
end

function FarmGeniePrint(text)
   DEFAULT_CHAT_FRAME:AddMessage(colorText("FarmGenie: " .. text))
end

function FarmGenieFormatMoney(copper)
   if not copper or copper == 0 then return "0g" end
   local negative = copper < 0
   if negative then copper = -copper end
   local gold = math.floor(copper / 10000)
   local silver = math.floor((copper % 10000) / 100)
   local cop = copper % 100
   local str = ""
   if gold > 0 then str = gold .. "g " end
   if silver > 0 or gold > 0 then str = str .. silver .. "s " end
   str = str .. cop .. "c"
   if negative then str = "-" .. str end
   return strtrim(str)
end

--- Color-coded money string for UI display (gold/silver/copper coin colors)
function FarmGenieFormatMoneyColored(copper)
   if not copper or copper == 0 then return "|cffFFD1000|rg" end
   local negative = copper < 0
   if negative then copper = -copper end
   local gold = math.floor(copper / 10000)
   local silver = math.floor((copper % 10000) / 100)
   local cop = copper % 100
   local parts = {}
   if gold > 0 then table.insert(parts, "|cffFFD100" .. gold .. "|rg") end
   if silver > 0 or gold > 0 then table.insert(parts, "|cffC7C7CF" .. silver .. "|rs") end
   table.insert(parts, "|cffF0A15A" .. cop .. "|rc")
   local str = table.concat(parts, " ")
   if negative then str = "-" .. str end
   return str
end

function FarmGenieGetSessionDuration()
   if not FarmGenieSession then return "00:00:00" end
   local endTime = FarmGenieSession.pausedAt or time()
   local elapsed = endTime - FarmGenieSession.startTime
   local hours = math.floor(elapsed / 3600)
   local mins = math.floor((elapsed % 3600) / 60)
   local secs = elapsed % 60
   return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function FarmGenieGetGoldPerHour()
   if not FarmGenieSession then return 0 end
   local endTime = FarmGenieSession.pausedAt or time()
   local elapsed = endTime - FarmGenieSession.startTime
   if elapsed < 1 then return 0 end
   local totalCopper = FarmGenieSession.totalAHValue + FarmGenieSession.rawGold
   return math.floor(totalCopper / elapsed * 3600)
end

---------------------------------------------------------------------------
-- Price Integration (Auctionator)
---------------------------------------------------------------------------
function FarmGenieHasAuctionator()
   return type(Atr_GetAuctionPrice) == "function"
end

--- Returns (ahPrice, vendorPrice, source)
--- ahPrice: auction house price in copper (0 if unavailable)
--- vendorPrice: vendor sell price in copper (0 if unavailable)
--- source: "AH" or "Vendor"
function FarmGenieGetItemValue(itemLink)
   if not itemLink then return 0, 0, "Vendor" end

   local itemName, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)
   vendorPrice = vendorPrice or 0

   local ahPrice = 0
   if FarmGenieHasAuctionator() and itemName then
      ahPrice = Atr_GetAuctionPrice(itemName) or 0
   end

   if ahPrice > 0 then
      return ahPrice, vendorPrice, "AH"
   else
      return 0, vendorPrice, "Vendor"
   end
end

--- Returns the "best" price for display: AH if available, vendor otherwise
function FarmGenieGetDisplayPrice(itemLink)
   local ahPrice, vendorPrice, source = FarmGenieGetItemValue(itemLink)
   if ahPrice > 0 then
      return ahPrice, source
   end
   return vendorPrice, "Vendor"
end

---------------------------------------------------------------------------
-- Session Management
---------------------------------------------------------------------------
function FarmGenieNewSession()
   FarmGenieSession = {
      startTime = time(),
      zone = GetZoneText() or "Unknown",
      items = {},
      totalAHValue = 0,
      totalVendor = 0,
      rawGold = 0,
      itemCount = 0,
      paused = false,
      pausedAt = nil,
   }
   FarmGeniePrint("New session started in " .. FarmGenieSession.zone)
   -- Refresh loot window if it exists
   if FarmGenieRefreshLootWindow then
      FarmGenieRefreshLootWindow()
   end
end

function FarmGeniePauseLogging()
   if FarmGenieSession and not FarmGenieSession.paused then
      FarmGenieSession.paused = true
      FarmGenieSession.pausedAt = time()
      FarmGeniePrint("Logging paused.")
      if FarmGenieRefreshLootWindow then FarmGenieRefreshLootWindow() end
   end
end

function FarmGenieResumeLogging()
   if FarmGenieSession and FarmGenieSession.paused then
      -- Adjust startTime to exclude paused duration
      local pausedDuration = time() - FarmGenieSession.pausedAt
      FarmGenieSession.startTime = FarmGenieSession.startTime + pausedDuration
      FarmGenieSession.paused = false
      FarmGenieSession.pausedAt = nil
      FarmGeniePrint("Logging resumed.")
      if FarmGenieRefreshLootWindow then FarmGenieRefreshLootWindow() end
   end
end

function FarmGenieIsLogging()
   return FarmGenieSession ~= nil and not FarmGenieSession.paused
end

--- Debug: add random items from bags to the current session (bypasses filters)
function FarmGenieDebugAddBagItems(count)
   count = count or 20
   if not FarmGenieSession then
      FarmGenieNewSession()
   end

   -- Collect all item links from bags
   local bagItems = {}
   for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
         local link = GetContainerItemLink(bag, slot)
         if link then
            table.insert(bagItems, link)
         end
      end
   end

   if #bagItems == 0 then
      FarmGeniePrint("Debug: No items found in bags.")
      return
   end

   local added = 0
   for i = 1, count do
      local link = bagItems[math.random(#bagItems)]
      local quantity = math.random(1, 5)
      local itemName, _, itemQuality, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(link)
      if itemName then
         local ahPrice, vPrice, source = FarmGenieGetItemValue(link)
         local displayPrice = ahPrice > 0 and ahPrice or (vPrice or 0)
         local itemID = tonumber(link:match("item:(%d+)"))

         local entry = {
            link = link,
            itemID = itemID,
            name = itemName,
            quantity = quantity,
            ahPrice = ahPrice * quantity,
            vendorPrice = (vPrice or 0) * quantity,
            quality = itemQuality or 0,
            time = time(),
            source = source,
            displayPrice = displayPrice * quantity,
         }

         table.insert(FarmGenieSession.items, 1, entry)
         FarmGenieSession.totalAHValue = FarmGenieSession.totalAHValue + entry.displayPrice
         FarmGenieSession.totalVendor = FarmGenieSession.totalVendor + entry.vendorPrice
         FarmGenieSession.itemCount = FarmGenieSession.itemCount + quantity
         added = added + 1
      end
   end

   FarmGeniePrint("Debug: Added " .. added .. " random items from bags.")
   if FarmGenieRefreshLootWindow then FarmGenieRefreshLootWindow() end
end

---------------------------------------------------------------------------
-- Loot Parsing
---------------------------------------------------------------------------
-- Pattern to extract item link and quantity from CHAT_MSG_LOOT
-- "You receive loot: [Item Link]x5." or "You receive loot: [Item Link]."
local LOOT_SELF_PATTERN
local LOOT_SELF_MULTIPLE_PATTERN

local function InitLootPatterns()
   -- LOOT_ITEM_SELF = "You receive loot: %s."
   -- LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
   -- Convert WoW format strings to Lua capture patterns.
   -- Important: escape dots BEFORE inserting capture groups,
   -- otherwise the dot inside (.+) gets escaped to (%.+).
   local single = LOOT_ITEM_SELF or "You receive loot: %s."
   single = single:gsub("%.", "%%.")
   single = single:gsub("%%s", "(.+)")
   LOOT_SELF_PATTERN = "^" .. single .. "$"

   local multi = LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."
   multi = multi:gsub("%.", "%%.")
   multi = multi:gsub("%%s", "(.+)")
   multi = multi:gsub("%%d", "(%%d+)")
   LOOT_SELF_MULTIPLE_PATTERN = "^" .. multi .. "$"
end

local function ParseLootMessage(message)
   if not LOOT_SELF_PATTERN then InitLootPatterns() end

   -- Try multiple quantity first
   local link, quantity = message:match(LOOT_SELF_MULTIPLE_PATTERN)
   if link and quantity then
      return link, tonumber(quantity)
   end

   -- Try single item
   link = message:match(LOOT_SELF_PATTERN)
   if link then
      return link, 1
   end

   return nil, nil
end

local function ParseMoneyMessage(message)
   -- "You loot 1 Gold 25 Silver 10 Copper"
   local gold = tonumber(message:match("(%d+) Gold")) or 0
   local silver = tonumber(message:match("(%d+) Silver")) or 0
   local copper = tonumber(message:match("(%d+) Copper")) or 0
   return gold * 10000 + silver * 100 + copper
end

---------------------------------------------------------------------------
-- Loot Processing
---------------------------------------------------------------------------
local function ProcessLoot(itemLink, quantity)
   if not FarmGenieSession then
      if FarmGenieDB and FarmGenieDB.autoStart then
         FarmGenieNewSession()
      else
         return  -- No active session and auto-start is off
      end
   end

   if FarmGenieSession.paused then return end

   -- Get item info
   local itemName, _, itemQuality, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)
   if not itemName then return end  -- item not cached yet
   itemQuality = itemQuality or 0

   -- Quality filter
   if itemQuality < (FarmGenieDB.minQuality or 0) then return end

   -- Get price
   local ahPrice, vPrice, source = FarmGenieGetItemValue(itemLink)
   local displayPrice = ahPrice > 0 and ahPrice or vPrice

   -- Min price filter (compare against AH price only)
   local minPriceCopper = (FarmGenieDB.minPrice or 0)
   if minPriceCopper > 0 and ahPrice < minPriceCopper then return end

   -- Extract itemID from link
   local itemID = tonumber(itemLink:match("item:(%d+)"))

   -- Add to session
   local entry = {
      link = itemLink,
      itemID = itemID,
      name = itemName,
      quantity = quantity,
      ahPrice = ahPrice * quantity,
      vendorPrice = vPrice * quantity,
      quality = itemQuality,
      time = time(),
      source = source,
      displayPrice = displayPrice * quantity,
   }

   table.insert(FarmGenieSession.items, 1, entry)  -- newest first
   FarmGenieSession.totalAHValue = FarmGenieSession.totalAHValue + entry.displayPrice
   FarmGenieSession.totalVendor = FarmGenieSession.totalVendor + entry.vendorPrice
   FarmGenieSession.itemCount = FarmGenieSession.itemCount + quantity

   -- Trim old entries to keep the loot list from growing unbounded
   local maxEntries = FarmGenieDB.maxLootEntries or 50
   if maxEntries > 0 then
      while #FarmGenieSession.items > maxEntries do
         table.remove(FarmGenieSession.items)
      end
   end

   -- Update loot window
   if FarmGenieAddLootEntry then
      FarmGenieAddLootEntry(entry)
   end
   if FarmGenieUpdateStats then
      FarmGenieUpdateStats()
   end
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("CHAT_MSG_MONEY")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
   if event == "PLAYER_LOGIN" then
      -- Initialize saved variables with defaults
      if not FarmGenieDB then FarmGenieDB = {} end
      if FarmGenieDB.minQuality == nil then FarmGenieDB.minQuality = 2 end
      if FarmGenieDB.minPrice == nil then FarmGenieDB.minPrice = 0 end
      if FarmGenieDB.trackGold == nil then FarmGenieDB.trackGold = true end
      if FarmGenieDB.autoStart == nil then FarmGenieDB.autoStart = false end
      if FarmGenieDB.showLootWindow == nil then FarmGenieDB.showLootWindow = true end
      if FarmGenieDB.maxLootEntries == nil then FarmGenieDB.maxLootEntries = 50 end

      -- Initialize loot patterns
      InitLootPatterns()

      -- Register with the shared Genie minimap button
      local GenieMinimap = LibStub("GenieMinimap-1.0", true)
      if GenieMinimap then
         GenieMinimap:Register("FarmGenie", {
            { label = "Loot Log",    onClick = function() FarmGenieToggleLootWindow() end },
            { label = "Item Bar",    onClick = function() FarmGenieToggleBar() end },
            { label = "Settings",    onClick = function() FarmGenieToggleMainWindow() end },
            { label = "New Session", onClick = function() FarmGenieNewSession() end },
         })
      end

      -- Initialize item counter bar
      if FarmGenieInitBar then
         FarmGenieInitBar()
      end

      -- Initialize loot filter / auto-vendor
      if FarmGenieInitFilter then
         FarmGenieInitFilter()
      end

      -- Print status
      local priceStatus = FarmGenieHasAuctionator() and "Auctionator detected" or "Auctionator not found (using vendor prices)"
      FarmGeniePrint("loaded. " .. priceStatus .. ". Type /fg for settings.")

   elseif event == "CHAT_MSG_LOOT" then
      local message = ...
      local itemLink, quantity = ParseLootMessage(message)
      if itemLink then
         ProcessLoot(itemLink, quantity)
         -- Auto-delete check (FarmGenieFilter.lua)
         if FarmGenieProcessAutoDelete then
            FarmGenieProcessAutoDelete(itemLink)
         end
      end

   elseif event == "CHAT_MSG_MONEY" then
      if not FarmGenieSession then return end
      if FarmGenieSession.paused then return end
      if not FarmGenieDB.trackGold then return end
      local message = ...
      local copper = ParseMoneyMessage(message)
      if copper > 0 then
         FarmGenieSession.rawGold = FarmGenieSession.rawGold + copper
         if FarmGenieUpdateStats then
            FarmGenieUpdateStats()
         end
      end

   elseif event == "ZONE_CHANGED_NEW_AREA" then
      if FarmGenieSession then
         FarmGenieSession.zone = GetZoneText() or "Unknown"
         if FarmGenieUpdateStats then
            FarmGenieUpdateStats()
         end
      end
   end
end)

FarmGeniePrint("loading...")
