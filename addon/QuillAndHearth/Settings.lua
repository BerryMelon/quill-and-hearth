-- Quill & Hearth: settings (account-wide) and the options panel in Options > AddOns.
local _, QH = ...

local DEFAULTS = {
    textSize = "medium",   -- small | medium | large
    length = "normal",     -- short | normal | long (AI prompt)
    autoOpen = true,       -- open the journal on the unwritten page after resting / logging back in
    moodPrompt = true,     -- offer a mood choice on the unwritten page
    ritual = true,         -- /read emote and book sounds when the journal opens after a rest
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
-- Options panel (canvas layout, stock widgets)
---------------------------------------------------------------------------
local panel
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
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
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

local function BuildPanel()
    panel = CreateFrame("Frame")
    panel.name = "Quill & Hearth"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Quill & Hearth")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Your character keeps a journal, written whenever they rest.")

    Header(panel, "Reading", -70)
    Choice(panel, "Text size", "textSize", {
        { value = "small", label = "Small" }, { value = "medium", label = "Medium" }, { value = "large", label = "Large" },
    }, -96)

    Header(panel, "Writing", -136)
    Choice(panel, "Entry length (AI)", "length", {
        { value = "short", label = "Short" }, { value = "normal", label = "Normal" }, { value = "long", label = "Long" },
    }, -162)
    Checkbox(panel, "Ask for my character's mood when I rest", "Offers a few moods on the unwritten page. It sets the tone of the entry.", "moodPrompt", -190)

    Header(panel, "Resting", -236)
    Checkbox(panel, "Open the journal when I rest", "After resting (or logging back in after a rest), the journal opens on the unwritten page.", "autoOpen", -258)
    Checkbox(panel, "Writing ritual (emote and sounds)", "Your character reads (/read) and you hear the book open when the journal opens after a rest.", "ritual", -286)

    Header(panel, "Other", -332)
    local minimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    minimap:SetPoint("TOPLEFT", 14, -354)
    local mmText = minimap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mmText:SetPoint("LEFT", minimap, "RIGHT", 2, 0)
    mmText:SetText("Show the minimap button")
    minimap:SetHitRectInsets(0, -mmText:GetStringWidth() - 8, 0, 0)
    minimap:SetScript("OnClick", function(self) QH:SetMinimapButtonShown(self:GetChecked() and true or false) end)
    table.insert(refreshers, function() minimap:SetChecked(not (QH.db.minimap and QH.db.minimap.hide)) end)

    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Quill & Hearth")
        Settings.RegisterAddOnCategory(category)
        QH.settingsCategory = category
    end
end

function QH:OpenSettings()
    if self.settingsCategory and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        QH:Print("The options panel isn't available on this client.")
    end
end

QH:Listen("READY", BuildPanel)

QH:RegisterCommand("options", "open the Quill & Hearth options", function() QH:OpenSettings() end)
