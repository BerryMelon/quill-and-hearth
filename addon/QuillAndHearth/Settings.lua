-- Quill & Hearth: settings (account-wide) and standalone options window.
local _, QH = ...

local DEFAULTS = {
    textSize = "medium",   -- small | medium | large
    length = "normal",     -- short | normal | long (AI prompt)
    autoOpen = true,       -- open the journal on the unwritten page after resting / logging back in
    ritual = true,         -- book sound when the journal opens after a rest
    ritualEmote = true,    -- also show a context-aware journal emote in chat when resting to write
}
QH.SETTING_DEFAULTS = DEFAULTS

function QH:GetSetting(key)
    local s = self.db and self.db.settings
    local v = s and s[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

function QH:SetSetting(key, value)
    self.db.settings = self.db.settings or {}
    self.db.settings[key] = value
    self:Send("SETTING_CHANGED", key, value)
end

---------------------------------------------------------------------------
-- Standalone options window (avoids tainting Blizzard's protected SettingsPanel)
---------------------------------------------------------------------------
local frame
local refreshers = {}

local function Header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    return fs
end

local function Checkbox(parent, label, tooltip, key, y, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)
    cb:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        QH:SetSetting(key, value)
        if onChange then onChange(value) end
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            QH:ShowTooltip(self, "ANCHOR_TOP", label, tooltip)
        end)
        cb:SetScript("OnLeave", function() QH:HideTooltip() end)
    end
    table.insert(refreshers, function() cb:SetChecked(QH:GetSetting(key)) end)
    return cb
end

local function Choice(parent, label, key, options, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 20, y)
    title:SetText(label)
    local buttons = {}
    local x = 190
    for _, opt in ipairs(options) do
        local b = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        b:SetPoint("TOPLEFT", x, y + 2)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", b, "RIGHT", 4, 0)
        text:SetText(opt.label)
        b:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)
        b:SetScript("OnClick", function()
            QH:SetSetting(key, opt.value)
            for _, other in ipairs(buttons) do other:SetChecked(other.value == opt.value) end
        end)
        b.value = opt.value
        table.insert(buttons, b)
        x = x + text:GetStringWidth() + 46
    end
    table.insert(refreshers, function()
        local current = QH:GetSetting(key)
        for _, b in ipairs(buttons) do b:SetChecked(b.value == current) end
    end)
end

local function BuildWindow()
    local f = CreateFrame("Frame", "QuillAndHearthOptions", UIParent, "ButtonFrameTemplate")
    f:SetSize(480, 410)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle("Quill & Hearth Options") end
    if f.SetPortraitToAsset then f:SetPortraitToAsset(QH.ICON or "Interface\\Icons\\INV_Misc_Book_09") end
    f:Hide()

    local panel = f.Inset or f

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 16, -12)
    sub:SetText("Your character keeps a journal, written whenever they rest.")

    Header(panel, "Reading", -40)
    Choice(panel, "Text size", "textSize", {
        { value = "small", label = "Small" }, { value = "medium", label = "Medium" }, { value = "large", label = "Large" },
    }, -66)

    Header(panel, "Writing", -106)
    Choice(panel, "Entry length (AI)", "length", {
        { value = "short", label = "Short" }, { value = "normal", label = "Normal" }, { value = "long", label = "Long" },
    }, -132)

    Header(panel, "Resting", -172)
    Checkbox(panel, "Open the journal when I rest", "After resting (or logging back in after a rest), the journal opens on the unwritten page.", "autoOpen", -194)
    Checkbox(panel, "Writing ritual (book sound)", "Play the book-opening sound when resting to write.", "ritual", -222)
    Checkbox(panel, "Show a journal emote in chat when resting", "Shows a context-aware journal emote (campfire or tavern) in your chat window when the writing ritual plays.", "ritualEmote", -250)

    Header(panel, "Other", -294)
    local minimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    minimap:SetPoint("TOPLEFT", 14, -316)
    local mmText = minimap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mmText:SetPoint("LEFT", minimap, "RIGHT", 2, 0)
    mmText:SetText("Show the minimap button")
    minimap:SetHitRectInsets(0, -mmText:GetStringWidth() - 8, 0, 0)
    minimap:SetScript("OnClick", function(self) QH:SetMinimapButtonShown(self:GetChecked() and true or false) end)
    table.insert(refreshers, function() minimap:SetChecked(not (QH.db.minimap and QH.db.minimap.hide)) end)

    f:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)

    return f
end

function QH:OpenSettings()
    frame = frame or BuildWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

QH:RegisterCommand("options", "open the Quill & Hearth options", function() QH:OpenSettings() end)
