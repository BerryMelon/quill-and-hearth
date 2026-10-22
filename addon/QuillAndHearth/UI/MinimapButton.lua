-- Quill & Hearth: minimap button, right-click options menu, addon compartment, login notice.
local _, QH = ...

local Journal = QH.Journal

---------------------------------------------------------------------------
-- Tooltip + options menu (shared by the minimap button and the addon compartment)
---------------------------------------------------------------------------
local function FillTooltip(tooltip)
    tooltip:SetText("Quill & Hearth")
    if QH.char then
        local unwritten, moments = QH:GetPendingInfo()
        local count = #QH:GetEntries()
        tooltip:AddLine(("%d journal %s"):format(count, count == 1 and "entry" or "entries"), 1, 1, 1)
        if unwritten > 0 then
            tooltip:AddLine("An unwritten page is waiting.", 1, 0.82, 0)
        end
        if moments > 0 then
            tooltip:AddLine(("%d %s since your last rest"):format(moments, moments == 1 and "moment" or "moments"), 0.8, 0.8, 0.8)
        end
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100Left-click|r  open your journal", 0.8, 0.8, 0.8)
    tooltip:AddLine("|cffffd100Right-click|r  rest, character profile", 0.8, 0.8, 0.8)
end

local menuFrame

local function BuildMenu()
    local f = CreateFrame("Frame", "QuillAndHearthMenu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    table.insert(UISpecialFrames, "QuillAndHearthMenu")
    f:Hide()

    -- Click anywhere outside the menu to close it.
    local catcher = CreateFrame("Button", nil, f)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    catcher:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    catcher:SetScript("OnClick", function() f:Hide() end)

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.35, 0.28, 0.16, 0.95)

    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.08, 0.07, 0.06, 0.96)

    f.rows = {}
    f.dividers = {}
    return f
end

local function MenuRow(f, i)
    if f.rows[i] then return f.rows[i] end
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(20)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.18)
    b.hl = hl
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetJustifyH("LEFT")
    f.rows[i] = b
    return b
end

local function MenuDivider(f, i)
    if f.dividers[i] then return f.dividers[i] end
    local d = f:CreateTexture(nil, "ARTWORK")
    d:SetHeight(1)
    d:SetColorTexture(0.35, 0.28, 0.16, 0.6)
    f.dividers[i] = d
    return d
end

function QH:ShowOptionsMenu(owner)
    menuFrame = menuFrame or BuildMenu()
    if menuFrame:IsShown() and menuFrame.owner == owner then
        menuFrame:Hide()
        return
    end
    menuFrame.owner = owner

    local restKind = QH:GetRestKind()
    local canRest = restKind ~= nil and not InCombatLockdown()
    local items = {
        { title = "Quill & Hearth" },
        { text = "Open journal", fn = function() Journal:Open() end },
        { text = "Rest and write", fn = function() QH:RequestRest() end, enabled = canRest,
          tipTitle = "Rest and write",
          tipBody = restKind and "Your character writes about everything since their last rest."
              or "Find an inn, a city, or sit by a campfire first." },
        { text = "Add a note...", fn = function() QH:ShowNoteDialog() end },
        { text = "Export journal...", fn = function() QH:ShowExport() end },
        { divider = true },
        { text = "Set up character...", fn = function() QH:StartOnboarding(true) end },
        { text = "AI chat session setup...", fn = function() QH.Bridge:ShowSessionSetup() end },
        { text = "Show character profile", fn = function() QH.commands.profile("") end },
        { text = "Options...", fn = function() QH:OpenSettings() end },
        { divider = true },
        { text = "Hide minimap button", fn = function() QH:SetMinimapButtonShown(false) end },
    }

    local y, ri, di, maxW = 8, 0, 0, 170
    for _, item in ipairs(items) do
        if item.divider then
            di = di + 1
            local d = MenuDivider(menuFrame, di)
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, -(y + 3))
            d:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, -(y + 3))
            d:Show()
            y = y + 7
        else
            ri = ri + 1
            local row = MenuRow(menuFrame, ri)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 4, -y)
            row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -4, -y)
            row.label:SetText(item.title or item.text)
            if item.title then
                row.label:SetFontObject("GameFontNormalSmall")
                row:Disable()
                row.hl:Hide()
                row:SetScript("OnClick", nil)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
            else
                local enabled = item.enabled ~= false
                row.label:SetFontObject(enabled and "GameFontHighlightSmall" or "GameFontDisableSmall")
                row:SetEnabled(enabled)
                row.hl:SetShown(enabled)
                row:SetScript("OnClick", function()
                    menuFrame:Hide()
                    if enabled and item.fn then item.fn() end
                end)
                if item.tipTitle then
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        GameTooltip:SetText(item.tipTitle)
                        if item.tipBody then
                            local r, g, b = 1, 1, 1
                            if not restKind then r, g, b = 1, 0.5, 0.25 end
                            GameTooltip:AddLine(item.tipBody, r, g, b, true)
                        end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", GameTooltip_Hide)
                else
                    row:SetScript("OnEnter", nil)
                    row:SetScript("OnLeave", nil)
                end
            end
            maxW = math.max(maxW, row.label:GetStringWidth() + 28)
            row:Show()
            y = y + 20
        end
    end
    for i = ri + 1, #menuFrame.rows do menuFrame.rows[i]:Hide() end
    for i = di + 1, #menuFrame.dividers do menuFrame.dividers[i]:Hide() end

    menuFrame:SetSize(maxW, y + 6)
    menuFrame:ClearAllPoints()
    if owner and owner ~= UIParent then
        menuFrame:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 4, 4)
    else
        menuFrame:SetPoint("CENTER")
    end
    menuFrame:Show()
end

---------------------------------------------------------------------------
-- Minimap button (classic round look, drag to move around the minimap)
---------------------------------------------------------------------------
local button

local function MinimapDB()
    QH.db.minimap = QH.db.minimap or { angle = 200, hide = false }
    return QH.db.minimap
end

local function UpdatePosition()
    local angle = math.rad(MinimapDB().angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local isSquare = GetMinimapShape and GetMinimapShape() == "SQUARE"
    if isSquare then
        -- Push the button to the square's edge instead of a circle.
        x = math.max(-1, math.min(1, x * 1.4142))
        y = math.max(-1, math.min(1, y * 1.4142))
    end
    local rx = Minimap:GetWidth() / 2 + 6
    local ry = Minimap:GetHeight() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * rx, y * ry)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    MinimapDB().angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function CreateMinimapButton()
    button = CreateFrame("Button", "QuillAndHearthMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(QH.ICON or "Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(self, mouseButton)
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            QH:ShowOptionsMenu(self)
        else
            Journal:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        FillTooltip(GameTooltip)
        GameTooltip:AddLine("|cffffd100Drag|r  move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
end

function QH:SetMinimapButtonShown(shown)
    MinimapDB().hide = not shown
    if shown then
        if not button then CreateMinimapButton() end
        button:Show()
    elseif button then
        button:Hide()
        QH:Print("Minimap button hidden. Type |cffffd100/quill minimap|r to bring it back.")
    end
end

QH:RegisterCommand("minimap", "show or hide the minimap button", function()
    QH:SetMinimapButtonShown(MinimapDB().hide == true)
end)

QH:Listen("READY", function()
    if not MinimapDB().hide then
        CreateMinimapButton()
    end
end)

---------------------------------------------------------------------------
-- Addon compartment (the minimap's addon menu): same left/right behaviour
---------------------------------------------------------------------------
function QuillAndHearth_OnCompartmentClick(_, inputData, menuFrame)
    local mouseButton = type(inputData) == "table" and inputData.buttonName or inputData
    if mouseButton == "RightButton" then
        QH:ShowOptionsMenu(type(menuFrame) == "table" and menuFrame or UIParent)
    else
        Journal:Toggle()
    end
end

function QuillAndHearth_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(type(menuButton) == "table" and menuButton or UIParent, "ANCHOR_LEFT")
    FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function QuillAndHearth_OnCompartmentLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Login notice
---------------------------------------------------------------------------
QH:Listen("READY", function()
    C_Timer.After(6, function()
        local unwritten = QH:GetPendingInfo()
        if unwritten == 0 then return end
        -- C3: open on the unwritten page after a logout rest (if enabled and safe to do so).
        if QH:GetSetting("autoOpen") and not InCombatLockdown() and not (QH.Wizard.frame and QH.Wizard.frame:IsShown()) then
            Journal:Open({ ritual = true, emote = false })
        else
            QH:Print("An unwritten page is waiting in your journal. Click the book on your minimap to write it.")
        end
    end)
end)
