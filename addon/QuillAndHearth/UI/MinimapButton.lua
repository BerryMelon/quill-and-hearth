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
            tooltip:AddLine(QH:GetCompanionStatus() == "running" and "The ink is drying on your latest entry."
                or "An unwritten page is waiting.", 1, 0.82, 0)
        end
        if moments > 0 then
            tooltip:AddLine(("%d %s since your last rest"):format(moments, moments == 1 and "moment" or "moments"), 0.8, 0.8, 0.8)
        end
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100Left-click|r  open your journal", 0.8, 0.8, 0.8)
    tooltip:AddLine("|cffffd100Right-click|r  rest, character profile", 0.8, 0.8, 0.8)
end

function QH:ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        QH:Print("Options: |cffffd100/quill rest|r, |cffffd100/quill setup|r, |cffffd100/quill profile|r")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Quill & Hearth")
        root:CreateButton("Open journal", function() Journal:Open() end)

        local restKind = QH:GetRestKind()
        local rest = root:CreateButton("Rest and write", function() QH:RequestRest() end)
        rest:SetEnabled(restKind ~= nil and not InCombatLockdown())
        if rest.SetTooltip then
            rest:SetTooltip(function(tooltip)
                tooltip:SetText("Rest and write")
                if restKind then
                    tooltip:AddLine("Your character writes about everything since their last rest.", 1, 1, 1, true)
                else
                    tooltip:AddLine("Find an inn, a city, or sit by a campfire first.", 1, 0.5, 0.25, true)
                end
            end)
        end

        root:CreateButton("Add a note...", function() QH:ShowNoteDialog() end)

        root:CreateDivider()
        root:CreateButton("Set up character...", function() QH:StartOnboarding(true) end)
        root:CreateButton("Show character profile", function() QH.commands.profile("") end)
        root:CreateDivider()
        root:CreateButton("Hide minimap button", function() QH:SetMinimapButtonShown(false) end)
    end)
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
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
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
        local entries = QH:GetEntries()
        local lastSeen = QH.char.state.lastSeenEntryT or 0
        local new = 0
        for _, e in ipairs(entries) do
            if (e.t or 0) > lastSeen then new = new + 1 end
        end
        local unwritten = QH:GetPendingInfo()
        local companion = QH:GetCompanionStatus()
        if new > 0 then
            QH:Print(("Your journal has |cffffffff%d new %s|r. Click the book on your minimap to read."):format(new, new == 1 and "entry" or "entries"))
        end
        if companion == "running" and unwritten > 0 then
            QH:Print("The ink is still drying on your latest entry. |cffffd100/reload|r in a moment to read it.")
        elseif unwritten > 0 then
            QH:Print("An unwritten page is waiting in your journal. Click the book on your minimap to write it.")
        end
    end)
end)
