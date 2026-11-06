-- Quill & Hearth: core (namespace, event dispatch, slash commands, init)
local ADDON_NAME, QH = ...

QH.name = ADDON_NAME
QH.title = "Quill & Hearth"
QH.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
QH.ICON = "Interface\\AddOns\\QuillAndHearth\\Media\\Icon"
QH.DB_VERSION = 1

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function QH:Print(...)
    print("|cffd8b26aQuill & Hearth|r:", ...)
end

--- True if the value is a Midnight/Forever "secret value" we must not inspect.
function QH.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

--- Returns v if it is a usable (non-secret) value, else nil.
function QH.Safe(v)
    if QH.IsSecret(v) then return nil end
    return v
end

function QH.Truncate(s, maxLen)
    if type(s) ~= "string" or QH.IsSecret(s) then return nil end
    if s == "" then return nil end
    if #s > maxLen then
        return s:sub(1, maxLen) .. "..."
    end
    return s
end

---------------------------------------------------------------------------
-- Zero-taint confirmation popup (avoids touching Blizzard's StaticPopup1)
---------------------------------------------------------------------------
local confirmFrame

local function BuildConfirmFrame()
    local f = CreateFrame("Frame", "QuillAndHearthConfirmDialog", UIParent)
    f:SetSize(380, 150)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.42, 0.33, 0.18, 0.96)

    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.09, 0.08, 0.06, 0.96)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 20, -18)
    f.text:SetPoint("TOPRIGHT", -20, -18)
    f.text:SetJustifyH("CENTER")
    f.text:SetSpacing(2)

    f.buttons = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetHeight(24)
        f.buttons[i] = b
    end
    return f
end

--- Show a self-contained confirmation dialog without touching Blizzard's StaticPopup frames.
--- spec: { text, button1, button2, button3, onAccept, onCancel, onAlt }
function QH:ShowConfirm(spec)
    confirmFrame = confirmFrame or BuildConfirmFrame()
    local f = confirmFrame
    f.text:SetText(spec.text or "")

    local defs = {
        { label = spec.button1 or OKAY or "Okay", fn = spec.onAccept },
        spec.button2 and { label = spec.button2, fn = spec.onCancel } or nil,
        spec.button3 and { label = spec.button3, fn = spec.onAlt } or nil,
    }
    local count = #defs
    local totalW = 0
    local gap = 10
    for i = 1, 3 do
        local b = f.buttons[i]
        local d = defs[i]
        if d then
            b:SetText(d.label)
            local w = math.max(96, b:GetTextWidth() + 28)
            b:SetWidth(w)
            b:SetScript("OnClick", function()
                f:Hide()
                if d.fn then d.fn() end
            end)
            b:Show()
            totalW = totalW + w + (i > 1 and gap or 0)
        else
            b:Hide()
        end
    end

    local x = -totalW / 2
    for i = 1, count do
        local b = f.buttons[i]
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOM", x, 16)
        x = x + b:GetWidth() + gap
    end

    local textH = math.max(36, f.text:GetStringHeight())
    f:SetSize(math.max(380, totalW + 44), textH + 74)
    f:Show()
end

---------------------------------------------------------------------------
-- Zero-taint tooltip (avoids touching Blizzard's shared GameTooltip)
---------------------------------------------------------------------------
local tipFrame

local function BuildTooltipFrame()
    local f = CreateFrame("Frame", "QuillAndHearthTooltip", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:Hide()

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.38, 0.30, 0.16, 0.96)

    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.06, 0.05, 0.04, 0.96)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetJustifyH("LEFT")

    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(2)
    return f
end

function QH:ShowTooltip(owner, anchor, title, body, r, g, b)
    if not title or title == "" then return end
    tipFrame = tipFrame or BuildTooltipFrame()
    local f = tipFrame
    f.title:SetWidth(0)
    f.title:SetText(title)
    local titleW = math.min(280, f.title:GetStringWidth())
    f.title:SetWidth(titleW)

    local w, h = titleW, f.title:GetStringHeight()
    if body and body ~= "" then
        f.body:SetWidth(0)
        f.body:SetText(body)
        f.body:SetTextColor(r or 1, g or 1, b or 1)
        local bodyW = math.min(280, math.max(titleW, f.body:GetStringWidth()))
        f.body:SetWidth(bodyW)
        f.body:Show()
        w = math.max(w, bodyW)
        h = h + 4 + f.body:GetStringHeight()
    else
        f.body:SetText("")
        f.body:Hide()
    end

    f:SetSize(w + 20, h + 16)
    f:ClearAllPoints()
    if owner and owner ~= UIParent then
        if anchor == "ANCHOR_LEFT" then
            f:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", -4, 4)
        elseif anchor == "ANCHOR_RIGHT" then
            f:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
        else
            f:SetPoint("BOTTOM", owner, "TOP", 0, 6)
        end
    else
        f:SetPoint("CENTER")
    end
    f:Show()
end

function QH:HideTooltip()
    if tipFrame then tipFrame:Hide() end
end

---------------------------------------------------------------------------
-- Event dispatch (WoW events + internal messages)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

function QH:On(event, fn)
    if not eventHandlers[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then return end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

--- Internal messages, e.g. "READY" once the character's data is available.
function QH:Listen(message, fn)
    messageHandlers[message] = messageHandlers[message] or {}
    table.insert(messageHandlers[message], fn)
end

function QH:Send(message, ...)
    local list = messageHandlers[message]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
QH.commands = {}
QH.commandHelp = {}

function QH:RegisterCommand(name, help, fn)
    self.commands[name] = fn
    table.insert(self.commandHelp, { name = name, help = help })
end

local function ShowHelp()
    QH:Print("v" .. QH.version .. " commands:")
    for _, c in ipairs(QH.commandHelp) do
        print(("  |cffffd100/quill %s|r - %s"):format(c.name, c.help))
    end
end

SLASH_QUILLANDHEARTH1 = "/quill"
SLASH_QUILLANDHEARTH2 = "/qh"
SlashCmdList.QUILLANDHEARTH = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local fn = QH.commands[cmd]
    if fn then
        fn(rest)
    elseif cmd == "" and QH.commands.journal then
        QH.commands.journal("")
    else
        ShowHelp()
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
QH:On("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= ADDON_NAME then return end
    QuillAndHearthDB = QuillAndHearthDB or {}
    local db = QuillAndHearthDB
    db.version = db.version or QH.DB_VERSION
    db.characters = db.characters or {}
    QH.db = db
end)

QH:On("PLAYER_LOGIN", function()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    QH.charKey = name .. "-" .. realm
    QH:InitCharacter()
    QH:Send("READY")
end)
