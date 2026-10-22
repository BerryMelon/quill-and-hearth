-- Quill & Hearth: manual onboarding wizard (stock Blizzard templates only).
local _, QH = ...

local Wizard = {}
QH.Wizard = Wizard

local WIDTH, HEIGHT = 540, 480
local TEXT_WIDTH = WIDTH - 70
local RADIO_COLUMNS, RADIO_COL_WIDTH, RADIO_ROW_HEIGHT = 3, 150, 24

local TRAIT_PAGES = {
    {
        title = "Their nature",
        intro = "A few quick questions. They set the tone of the journal.",
        questions = {
            { key = "temperament", label = "How would others describe their temperament?",
              options = { "Stoic", "Cheerful", "Brooding", "Hot-headed", "Gentle" } },
            { key = "outlook", label = "How do they see the world?",
              options = { "Hopeful", "Pragmatic", "Cynical" } },
            { key = "upbringing", label = "Where did they grow up?",
              options = { "Noble", "Scholarly", "Common folk", "Streetwise", "Wilderness" } },
        },
    },
    {
        title = "Their story",
        questions = {
            { key = "drive", label = "What drives them?",
              options = { "Duty", "Glory", "Coin", "Knowledge", "Faith", "Revenge" } },
            { key = "voice", label = "How do they put words to paper?",
              options = { "Plain", "Formal", "Poetic", "Terse" } },
        },
        extras = true, -- fear + past free text
    },
}

---------------------------------------------------------------------------
-- Small layout helpers (a vertical cursor per page)
---------------------------------------------------------------------------
local function Place(page, region, height, x)
    region:SetPoint("TOPLEFT", page, "TOPLEFT", x or 0, -page.cursor)
    page.cursor = page.cursor + height
end

local function AddText(page, text, font, gap)
    local fs = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(TEXT_WIDTH)
    fs:SetText(text)
    Place(page, fs, fs:GetStringHeight() + (gap or 8))
    return fs
end

local function AddEditBox(page, width, maxLetters, gap)
    local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 60)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function() Wizard:Refresh() end)
    Place(page, eb, 22 + (gap or 10), 8) -- InputBoxTemplate's border sits left of its anchor
    return eb
end

local function AddCheck(page, text, gap)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(text)
    cb.label = label
    cb:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0) -- clicking the label toggles too
    Place(page, cb, 26 + (gap or 6), -4)
    return cb
end

--- A radio group. Options are strings, or { value = ..., label = ... } tables.
--- `onSelect(value)` is called when the player picks an option.
local function AddRadioGroup(page, options, onSelect, columns)
    columns = columns or RADIO_COLUMNS
    local group = { buttons = {} }
    local top = page.cursor
    for i, option in ipairs(options) do
        local value = type(option) == "table" and option.value or option
        local text = type(option) == "table" and option.label or option
        local b = CreateFrame("CheckButton", nil, page, "UIRadioButtonTemplate")
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", 6 + col * RADIO_COL_WIDTH, -(top + row * RADIO_ROW_HEIGHT))
        local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        label:SetText(text)
        b.label = label
        b:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0)
        b.value = value
        b:SetScript("OnClick", function(self)
            group:Set(self.value)
            onSelect(self.value)
        end)
        group.buttons[i] = b
    end
    function group:Set(value)
        for _, btn in ipairs(self.buttons) do btn:SetChecked(btn.value == value) end
    end
    page.cursor = top + math.ceil(#options / columns) * RADIO_ROW_HEIGHT + 10
    return group
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
function Wizard:Build()
    local f = CreateFrame("Frame", "QuillAndHearthWizard", UIParent, "ButtonFrameTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle("Quill & Hearth") end
    if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09") end
    table.insert(UISpecialFrames, "QuillAndHearthWizard") -- Escape closes it
    f:Hide()
    self.frame = f

    local anchor = f.Inset or f
    self.pages = {}
    local function NewPage()
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", anchor, "TOPLEFT", 18, -16)
        page:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -18, 16)
        page.cursor = 0
        page:Hide()
        table.insert(self.pages, page)
        return page
    end

    local gameName = UnitName("player")
    local gameClass = UnitClass("player")

    -- Page 1: name
    local p1 = NewPage()
    AddText(p1, "Who are you?", "GameFontNormalLarge", 10)
    AddText(p1, "Your journal is written in your character's own words. First, what is their name?", nil, 16)
    AddText(p1, "Full name", "GameFontNormal", 4)
    self.nameBox = AddEditBox(p1, 280, 60, 6)
    self.useGameName = AddCheck(p1, ("Use my in-game name (%s)"):format(gameName))
    self.useGameName:SetScript("OnClick", function() self:Refresh() end)
    p1.validate = function()
        return self.useGameName:GetChecked() or strtrim(self.nameBox:GetText()) ~= ""
    end

    -- Page 2: class
    local p2 = NewPage()
    AddText(p2, "Your calling", "GameFontNormalLarge", 10)
    AddText(p2, ("Is your character simply a %s, or do they see themselves as something more particular?"):format(gameClass), nil, 16)
    self.classGroup = AddRadioGroup(p2, {
        { value = "game", label = ("Use my in-game class (%s)"):format(gameClass) },
        { value = "rp", label = "Use a roleplay class:" },
    }, function(value)
        self.state.classChoice = value
        self:Refresh()
    end, 1)
    local radioRP = self.classGroup.buttons[2]
    self.rpClassBox = AddEditBox(p2, 240, 40, 4)
    p2.cursor = p2.cursor - 26 -- the box sits beside the radio, not below it
    self.rpClassBox:ClearAllPoints()
    self.rpClassBox:SetPoint("LEFT", radioRP.label, "RIGHT", 14, 0)
    self.rpClassBox:SetScript("OnEditFocusGained", function()
        self.classGroup:Set("rp")
        self.state.classChoice = "rp"
        self:Refresh()
    end)
    AddText(p2, "|cff999999e.g. Tinker, Flame Master, Plague Doctor, Wandering Bard|r", "GameFontHighlightSmall", 8)
    p2.validate = function()
        return self.state.classChoice == "game"
            or (self.state.classChoice == "rp" and strtrim(self.rpClassBox:GetText()) ~= "")
    end

    -- Pages 3-4: traits
    self.traitGroups = {}
    for _, def in ipairs(TRAIT_PAGES) do
        local page = NewPage()
        AddText(page, def.title, "GameFontNormalLarge", 10)
        if def.intro then AddText(page, def.intro, nil, 12) end
        for _, q in ipairs(def.questions) do
            AddText(page, q.label, "GameFontNormal", 6)
            self.traitGroups[q.key] = AddRadioGroup(page, q.options, function(value)
                self.state.traits[q.key] = value
                self:Refresh()
            end)
        end
        if def.extras then
            AddText(page, "Something they fear or hate |cff999999(optional — becomes a personal hook in the journal)|r", "GameFontNormal", 4)
            self.fearBox = AddEditBox(page, 420, 160, 8)
            AddText(page, "Appearance & notable details |cff999999(optional — e.g. scars, homeland, mannerisms)|r", "GameFontNormal", 4)
            self.appearanceBox = AddEditBox(page, 420, 240, 8)
        end
        page.validate = function()
            for _, q in ipairs(def.questions) do
                if not self.state.traits[q.key] then return false end
            end
            return true
        end
    end

    -- Page 5: full character background / biography (multi-line)
    local p5 = NewPage()
    AddText(p5, "Their background", "GameFontNormalLarge", 10)
    AddText(p5, "Write or paste as much as you like about your character's history, homeland, family, beliefs, or how their journey began. The AI will know all of this when writing their journal. |cff999999(optional)|r", nil, 12)
    AddText(p5, "Background & history", "GameFontNormal", 6)

    local bgScroll = CreateFrame("ScrollFrame", "QuillAndHearthWizardPastScroll", p5, "UIPanelScrollFrameTemplate")
    bgScroll:SetPoint("TOPLEFT", p5, "TOPLEFT", 4, -p5.cursor)
    bgScroll:SetPoint("BOTTOMRIGHT", p5, "BOTTOMRIGHT", -24, 24)
    local bgBackdrop = p5:CreateTexture(nil, "BACKGROUND")
    bgBackdrop:SetPoint("TOPLEFT", bgScroll, "TOPLEFT", -4, 4)
    bgBackdrop:SetPoint("BOTTOMRIGHT", bgScroll, "BOTTOMRIGHT", 4, -4)
    bgBackdrop:SetColorTexture(0, 0, 0, 0.35)

    local pastBox = CreateFrame("EditBox", nil, bgScroll)
    pastBox:SetMultiLine(true)
    pastBox:SetAutoFocus(false)
    pastBox:SetMaxLetters(10000)
    pastBox:SetFontObject("ChatFontNormal")
    pastBox:SetWidth(TEXT_WIDTH - 24)
    pastBox:SetScript("OnEscapePressed", pastBox.ClearFocus)
    pastBox:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local offset = bgScroll:GetVerticalScroll()
        local viewH = bgScroll:GetHeight()
        if -y < offset then
            bgScroll:SetVerticalScroll(-y)
        elseif -y + h > offset + viewH then
            bgScroll:SetVerticalScroll(-y + h - viewH)
        end
    end)
    bgScroll:SetScrollChild(pastBox)
    bgScroll:SetScript("OnSizeChanged", function(_, w) pastBox:SetWidth(w) end)
    bgScroll:EnableMouse(true)
    bgScroll:SetScript("OnMouseDown", function() pastBox:SetFocus() end)
    self.pastBox = pastBox

    self.pastCount = p5:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.pastCount:SetPoint("TOPLEFT", bgScroll, "BOTTOMLEFT", 0, -6)
    pastBox:SetScript("OnTextChanged", function(box)
        self.pastCount:SetText(("%d / 10000 characters"):format(#(box:GetText() or "")))
    end)

    -- Footer
    self.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.back:SetSize(96, 22)
    self.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
    self.back:SetText(BACK or "Back")
    self.back:SetScript("OnClick", function() self:ShowPage(self.pageIndex - 1) end)

    self.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.next:SetSize(96, 22)
    self.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)
    self.next:SetScript("OnClick", function()
        if self.pageIndex < #self.pages then
            self:ShowPage(self.pageIndex + 1)
        else
            self:Finish()
        end
    end)

    self.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.step:SetPoint("BOTTOM", f, "BOTTOM", 0, 9)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function Wizard:LoadState()
    local p = QH:GetProfile()
    local manual = p and p.source == "manual" and p or nil
    self.state = {
        classChoice = manual and (manual.useGameClass and "game" or "rp") or nil,
        traits = {},
    }
    if manual and manual.traits then
        for k, v in pairs(manual.traits) do self.state.traits[k] = v end
    end

    self.useGameName:SetChecked(manual == nil or manual.useGameName)
    self.nameBox:SetText(manual and not manual.useGameName and manual.name or "")
    self.rpClassBox:SetText(manual and not manual.useGameClass and manual.class or "")
    self.classGroup:Set(self.state.classChoice)
    for key, group in pairs(self.traitGroups) do group:Set(self.state.traits[key]) end
    self.fearBox:SetText(manual and manual.fear or "")
    self.appearanceBox:SetText(manual and manual.appearance or "")
    self.pastBox:SetText(manual and manual.past or "")
    self.pastCount:SetText(("%d / 10000 characters"):format(#(self.pastBox:GetText() or "")))
end

function Wizard:Refresh()
    if not self.frame or not self.pageIndex then return end
    local useGame = self.useGameName:GetChecked()
    self.nameBox:SetEnabled(not useGame)
    self.nameBox:SetAlpha(useGame and 0.5 or 1)

    local page = self.pages[self.pageIndex]
    self.back:SetEnabled(self.pageIndex > 1)
    self.next:SetText(self.pageIndex == #self.pages and "Finish" or (NEXT or "Next"))
    self.next:SetEnabled(page.validate == nil or page.validate())
    self.step:SetText(("Step %d of %d"):format(self.pageIndex, #self.pages))
end

function Wizard:ShowPage(index)
    if index < 1 or index > #self.pages then return end
    for i, page in ipairs(self.pages) do page:SetShown(i == index) end
    self.pageIndex = index
    self:Refresh()
end

function Wizard:Open()
    if InCombatLockdown() then
        QH:Print("Finish your fight first, then type |cffffd100/quill setup|r.")
        return
    end
    if not self.frame then self:Build() end
    self:LoadState()
    self:ShowPage(1)
    self.frame:Show()
end

local function OptionalText(editBox)
    local text = strtrim(editBox:GetText() or "")
    return text ~= "" and text or nil
end

function Wizard:Finish()
    local useGameName = self.useGameName:GetChecked() and true or false
    local useGameClass = self.state.classChoice == "game"
    local traits = {}
    for k, v in pairs(self.state.traits) do traits[k] = v end

    QH:SaveProfile({
        source = "manual",
        name = useGameName and UnitName("player") or strtrim(self.nameBox:GetText()),
        useGameName = useGameName,
        class = useGameClass and UnitClass("player") or strtrim(self.rpClassBox:GetText()),
        useGameClass = useGameClass,
        traits = traits,
        fear = OptionalText(self.fearBox),
        appearance = OptionalText(self.appearanceBox),
        past = OptionalText(self.pastBox),
    })
    self.frame:Hide()
    QH:Print("Your journal is ready. It will be written whenever you rest at an inn, a city, or a campfire.")
end
