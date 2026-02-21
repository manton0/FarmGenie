-------------------------------------------------------------------------------
-- GenieMinimap-1.0
-- Shared minimap button for the "Genie" addon family.
-- One button, one dropdown menu — any Genie addon can register entries.
-------------------------------------------------------------------------------
local MAJOR, MINOR = "GenieMinimap-1.0", 1
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Preserve state across library upgrades
lib.addons   = lib.addons   or {} -- { [addonName] = { entries = { {label,onClick,icon?}, ... } } }
lib.button   = lib.button   or nil
lib.menuFrame = lib.menuFrame or nil

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local ICON_TEXTURE = "Interface\\Icons\\INV_Enchant_EssenceEternalLarge"
local DEFAULT_ANGLE = 225   -- degrees, bottom-left of minimap
local RADIUS        = 80    -- pixels from minimap center

local function UpdatePosition()
    if not lib.button then return end
    local angle = math.rad(GenieMinimapDB and GenieMinimapDB.minimapPos or DEFAULT_ANGLE)
    lib.button:ClearAllPoints()
    lib.button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS,
        math.sin(angle) * RADIUS)
end

-------------------------------------------------------------------------------
-- Dropdown menu (WoW built-in UIDropDownMenu)
-------------------------------------------------------------------------------
local function InitializeMenu(frame, level)
    level = level or 1
    if level ~= 1 then return end

    -- Title
    local title = UIDropDownMenu_CreateInfo()
    title.text = "Genie Addons"
    title.isTitle = true
    title.notCheckable = true
    UIDropDownMenu_AddButton(title, level)

    -- Entries grouped by addon
    for addonName, addonData in pairs(lib.addons) do
        -- Addon header
        local header = UIDropDownMenu_CreateInfo()
        header.text = addonName
        header.isTitle = true
        header.notCheckable = true
        UIDropDownMenu_AddButton(header, level)

        for _, entry in ipairs(addonData.entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = "  " .. entry.label
            info.notCheckable = true
            info.padding = 8
            info.func = function()
                CloseDropDownMenus()
                entry.onClick()
            end
            if entry.icon then
                info.icon = entry.icon
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    -- Close button
    local close = UIDropDownMenu_CreateInfo()
    close.text = "Close"
    close.notCheckable = true
    close.func = function() CloseDropDownMenus() end
    UIDropDownMenu_AddButton(close, level)
end

local function ToggleMenu()
    if not lib.menuFrame then
        lib.menuFrame = CreateFrame("Frame", "GenieMinimapMenuFrame", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(lib.menuFrame, InitializeMenu, "MENU")
    ToggleDropDownMenu(1, nil, lib.menuFrame, lib.button, 0, 0)
end

-------------------------------------------------------------------------------
-- Minimap button frame
-------------------------------------------------------------------------------
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "GenieMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetSize(31, 31)
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Standard minimap border ring
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Icon
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(21, 21)
    icon:SetTexture(ICON_TEXTURE)
    icon:SetPoint("TOPLEFT", 7, -5)
    btn.icon = icon

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Genie Addons", 1, 1, 1)
        GameTooltip:AddLine("Click to open menu", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag to move", 0.8, 0.8, 0.8)
        for addonName in pairs(lib.addons) do
            GameTooltip:AddLine("  " .. addonName, 0.4, 0.8, 1.0)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Left-click drag to reposition; plain click opens menu
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:LockHighlight()
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale  = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            GenieMinimapDB.minimapPos = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    -- Only open menu on click if the button was NOT dragged
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        if not self.isDragging then
            ToggleMenu()
        end
    end)

    return btn
end

-------------------------------------------------------------------------------
-- Saved-variable initialization (fires after SVs are loaded)
-------------------------------------------------------------------------------
lib.eventFrame = lib.eventFrame or CreateFrame("Frame")
lib.eventFrame:RegisterEvent("PLAYER_LOGIN")
lib.eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not GenieMinimapDB then GenieMinimapDB = {} end
        if GenieMinimapDB.minimapPos == nil then
            GenieMinimapDB.minimapPos = DEFAULT_ANGLE
        end
        if GenieMinimapDB.hide == nil then
            GenieMinimapDB.hide = false
        end
        UpdatePosition()
        if GenieMinimapDB.hide and lib.button then
            lib.button:Hide()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Register an addon with the shared minimap button.
-- @param addonName  string  Unique addon identifier (e.g. "DPSGenie")
-- @param entries    table   Array of { label = string, onClick = function, icon = string|nil }
function lib:Register(addonName, entries)
    lib.addons[addonName] = { entries = entries }

    -- Create the button on first registration
    if not lib.button then
        lib.button = CreateMinimapButton()
        UpdatePosition()
    end

    if not (GenieMinimapDB and GenieMinimapDB.hide) then
        lib.button:Show()
    end
end

--- Remove an addon's entries from the dropdown.
function lib:Unregister(addonName)
    lib.addons[addonName] = nil
    if not next(lib.addons) and lib.button then
        lib.button:Hide()
    end
end

--- Show the minimap button (persisted).
function lib:Show()
    if GenieMinimapDB then GenieMinimapDB.hide = false end
    if lib.button then lib.button:Show() end
end

--- Hide the minimap button (persisted).
function lib:Hide()
    if GenieMinimapDB then GenieMinimapDB.hide = true end
    if lib.button then lib.button:Hide() end
end

--- Query visibility.
function lib:IsShown()
    return lib.button and lib.button:IsShown() or false
end
