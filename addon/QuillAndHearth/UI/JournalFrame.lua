-- Quill & Hearth: the journal (stock Blizzard templates and textures only).
local _, QH = ...

local Journal = {}
QH.Journal = Journal

local DEFAULT_W, DEFAULT_H = 880, 600
local MIN_W, MIN_H = 720, 460
local LIST_WIDTH = 240
local ENTRY_ROW, HEADER_ROW = 42, 30
local INK = { 0.24, 0.15, 0.08 }      -- dark brown text on parchment
local INK_SOFT = { 0.45, 0.32, 0.20 }
local PENDING = "pending"
local MOODS = { "Weary", "Triumphant", "Troubled", "Grieving", "Hopeful", "Content" }

local RITUAL_EMOTES = {
    campfire = {
        "warms their hands by the fire, opens a worn journal, and begins to write.",
        "draws closer to the firelight and opens a leather-bound journal.",
        "settles beside the crackling fire, opens a journal, and starts to write.",
    },
    indoors = {
        "finds a quiet corner, opens a leather-bound journal, and begins to write.",
        "sets their pack down, opens a worn journal, and starts to write.",
        "smooths open a page of their journal by the lamplight and begins to write.",
    },
    default = {
        "opens a worn journal and begins to write.",
        "unclasps a leather-bound journal and begins to write.",
    },
    mood = {
        Weary = "sinks down with a long sigh, opens a worn journal, and begins to write.",
        Triumphant = "opens a leather-bound journal with a quiet smile and begins to write.",
        Troubled = "stares into the distance for a moment before opening a worn journal to write.",
        Grieving = "opens a worn journal with a heavy heart and begins to write.",
        Hopeful = "opens a leather-bound journal, eyes bright, and begins to write.",
        Content = "settles in comfortably, opens a worn journal, and begins to write.",
    },
}

--- Pick a context-aware /e emote for the writing ritual (I4).
function QH:PickRitualEmote(restKind, mood, indoors, seed)
    if mood and RITUAL_EMOTES.mood[mood] then
        return RITUAL_EMOTES.mood[mood]
    end
    local pool = (restKind == "campfire" and RITUAL_EMOTES.campfire)
        or (indoors and RITUAL_EMOTES.indoors)
        or RITUAL_EMOTES.default
    local idx = ((tonumber(seed) or GetServerTime() or 1) % #pool) + 1
    return pool[idx]
end

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
--- unwrittenRests: rests not written up yet. momentsSinceRest: events after the latest rest.
function QH:GetPendingInfo()
    local processed = self:GetProcessedThrough()
    local unwrittenRests, momentsSinceRest = 0, 0
    for _, e in ipairs(self.char and self.char.events or {}) do
        if e.seq > processed then
            if e.type == "rest" then
                unwrittenRests = unwrittenRests + 1
                momentsSinceRest = 0
            else
                momentsSinceRest = momentsSinceRest + 1
            end
        end
    end
    return unwrittenRests, momentsSinceRest
end

local function DayLabel(day, dayEnd)
    if dayEnd and dayEnd ~= day then
        return ("Days %d - %d"):format(day or 0, dayEnd)
    end
    return ("Day %d"):format(day or 0)
end

local function PlaceText(restKind, zone, subzone)
    local place = subzone and zone and subzone ~= zone and (subzone .. ", " .. zone) or zone or subzone
    if not place then return "" end
    return (restKind == "campfire" and "By a campfire near " or "Written at ") .. place
end

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- Fonts (A1: text size setting)
---------------------------------------------------------------------------
local SIZES = {
    small = { body = 13, title = 19, meta = 10, spacing = 2 },
    medium = { body = 15, title = 22, meta = 11, spacing = 4 },
    large = { body = 18, title = 25, meta = 12, spacing = 5 },
}
local fontCache = {}

local function Font(kind, size)
    local key = kind .. "_" .. size
    if not fontCache[key] then
        local base = (kind == "title" and QuestTitleFont) or (kind == "body" and QuestFont) or GameFontNormalSmall
        local file, _, flags = base:GetFont()
        local font = CreateFont("QuillAndHearthFont_" .. key)
        font:SetFont(file, SIZES[size][kind], flags or "")
        fontCache[key] = font
    end
    return fontCache[key]
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function ApplyParchment(texture)
    for _, atlas in ipairs({ "QuestBG-Parchment", "QuestDetailsBackgrounds" }) do
        if AtlasExists(atlas) then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetColorTexture(0.93, 0.87, 0.73)
end

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, 22)
    b:SetText(text)
    return b
end

-- Icons that exist in every client: the yellow raid-marker star, and a muted clear/delete mark.
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local DELETE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function IconButton(parent, texture, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end

--- Quiet, desaturated ink-grey delete button so it doesn't draw the eye on the page.
local function MutedDeleteButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    if AtlasExists("common-search-clearbutton") then
        tex:SetAtlas("common-search-clearbutton")
    else
        tex:SetTexture(DELETE_ICON)
    end
    tex:SetDesaturated(true)
    tex:SetVertexColor(0.38, 0.28, 0.18)
    tex:SetAlpha(0.35)
    b:SetNormalTexture(tex)
    b:HookScript("OnEnter", function() tex:SetAlpha(0.75) end)
    b:HookScript("OnLeave", function() tex:SetAlpha(0.35) end)
    return b
end

--- Star look: gold when favourited, faded grey when not.
local function SetStarLit(texture, lit)
    if not texture then return end
    texture:SetDesaturated(not lit)
    texture:SetAlpha(lit and 1 or 0.45)
end

StaticPopupDialogs["QUILLANDHEARTH_DELETE_ENTRY"] = {
    text = "Delete \"%s\"?\n\nThe entry and the prompt it was written from will be lost for good. This can't be undone.",
    button1 = DELETE or "Delete",
    button2 = CANCEL,
    OnAccept = function(_, data)
        if data and data.id then QH:DeleteEntry(data.id) end
    end,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Tooltip(widget, title, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title() or title)
        local body = type(text) == "function" and text() or text
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

function Journal:Build()
    local f = CreateFrame("Frame", "QuillAndHearthJournal", UIParent, "ButtonFrameTemplate")
    local size = QH.db.journalSize
    f:SetSize(size and size.w or DEFAULT_W, size and size.h or DEFAULT_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetPortraitToAsset then f:SetPortraitToAsset(QH.ICON or "Interface\\Icons\\INV_Misc_Book_09") end
    table.insert(UISpecialFrames, "QuillAndHearthJournal")
    f:Hide()
    self.frame = f

    -- A4: resizable window
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, 1600, 1100) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        QH.db.journalSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
    end)

    local inset = f.Inset or f

    -- Filter above the list (favourites)
    self.favFilter = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    self.favFilter:SetSize(22, 22)
    self.favFilter:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -4)
    local favText = self.favFilter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    favText:SetPoint("LEFT", self.favFilter, "RIGHT", 0, 0)
    favText:SetText("Favourites only")
    self.favFilter:SetHitRectInsets(0, -favText:GetStringWidth() - 6, 0, 0)
    self.favFilter:SetScript("OnClick", function() self:Refresh(self.selected) end)

    -- Entry list (left)
    local list = CreateFrame("ScrollFrame", "QuillAndHearthJournalList", f, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -30)
    list:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 6)
    list:SetWidth(LIST_WIDTH)
    local listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(LIST_WIDTH, 1)
    list:SetScrollChild(listChild)
    self.listChild = listChild
    self.entryRows, self.headerRows = {}, {}

    -- Reading page (right)
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", inset, "TOPLEFT", LIST_WIDTH + 34, -4)
    page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ApplyParchment(bg)
    self.page = page

    -- Page tools (top right): edit, favourite (star), delete
    self.deleteButton = MutedDeleteButton(page, 18)
    self.deleteButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -38, -12)
    self.favButton = IconButton(page, STAR_ICON, 22)
    self.favButton:SetPoint("RIGHT", self.deleteButton, "LEFT", -8, 0)
    self.editButton = SmallButton(page, "Edit", 56)
    self.editButton:SetPoint("RIGHT", self.favButton, "LEFT", -8, 0)
    self.tools = { self.editButton, self.favButton, self.deleteButton }

    self.favButton:SetScript("OnClick", function()
        local e = self.selectedEntry
        if e then QH:SetEntryFavorite(e.id, not e.favorite) end
    end)
    self.deleteButton:SetScript("OnClick", function()
        local e = self.selectedEntry
        if e then StaticPopup_Show("QUILLANDHEARTH_DELETE_ENTRY", e.title or "Untitled", nil, { id = e.id }) end
    end)
    self.editButton:SetScript("OnClick", function()
        if self.selectedEntry then QH.EditDialog:Open(self.selectedEntry) end
    end)
    Tooltip(self.favButton, function() return self.selectedEntry and self.selectedEntry.favorite and "Unfavourite" or "Favourite" end,
        "Favourite entries get a star in the list. Use \"Favourites only\" to see just those.")
    Tooltip(self.deleteButton, "Delete entry", "Delete this entry for good, including the prompt it was written from.")
    Tooltip(self.editButton, "Edit", "Change the title or the text by hand.")

    -- Text
    local scroll = CreateFrame("ScrollFrame", "QuillAndHearthJournalPage", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -40)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -38, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    local function Text(layer)
        local fs = content:CreateFontString(nil, layer or "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        return fs
    end
    self.dayText = Text()
    self.titleText = Text()
    self.placeText = Text()
    self.bodyText = Text()

    -- A2: a soft divider under the header
    self.divider = content:CreateTexture(nil, "ARTWORK")
    self.divider:SetHeight(1)
    self.dividerRight = content:CreateTexture(nil, "ARTWORK")
    self.dividerRight:SetHeight(1)

    self.dayText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.titleText:SetPoint("TOPLEFT", self.dayText, "BOTTOMLEFT", 0, -6)
    self.placeText:SetPoint("TOPLEFT", self.titleText, "BOTTOMLEFT", 0, -6)
    self.divider:SetPoint("TOPLEFT", self.placeText, "BOTTOMLEFT", 0, -12)
    self.divider:SetPoint("RIGHT", content, "CENTER", 0, 0)
    self.dividerRight:SetPoint("LEFT", self.divider, "RIGHT", 0, 0)
    self.dividerRight:SetPoint("RIGHT", content, "RIGHT", -20, 0)
    self.bodyText:SetPoint("TOPLEFT", self.divider, "BOTTOMLEFT", 0, -16)
    if self.divider.SetGradient and CreateColor then
        self.divider:SetColorTexture(1, 1, 1, 1)
        self.divider:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], 0), CreateColor(INK[1], INK[2], INK[3], 0.55))
        self.dividerRight:SetColorTexture(1, 1, 1, 1)
        self.dividerRight:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], 0.55), CreateColor(INK[1], INK[2], INK[3], 0))
    else
        self.divider:SetColorTexture(INK[1], INK[2], INK[3], 0.4)
        self.dividerRight:SetColorTexture(INK[1], INK[2], INK[3], 0.4)
    end

    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        for _, fs in ipairs({ self.dayText, self.titleText, self.placeText, self.bodyText }) do
            fs:SetWidth(width - 10)
        end
        self:LayoutPage()
    end)

    -- Mood (B2), shown on the unwritten page
    self.moodLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.moodLabel:SetTextColor(INK[1], INK[2], INK[3])
    self.moodLabel:SetText("Tonight I feel:")
    self.moodButtons = {}
    local prev
    for _, mood in ipairs(MOODS) do
        local b = SmallButton(page, mood, 78)
        b:SetHeight(20)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", self.moodLabel, "RIGHT", 6, 0) end
        b:SetScript("OnClick", function()
            local current = QH.char.state.pendingMood
            QH:SetPendingMood(current ~= mood and mood or nil)
            self:Refresh(PENDING)
        end)
        b.mood = mood
        table.insert(self.moodButtons, b)
        prev = b
    end
    self.moodLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 30, 50)

    -- Bottom buttons (meaning depends on the page)
    self.primaryButton = SmallButton(page, "", 160)
    self.primaryButton:SetHeight(24)
    self.primaryButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 28, 14)
    self.secondaryButton = SmallButton(page, "", 150)
    self.secondaryButton:SetHeight(24)
    self.secondaryButton:SetPoint("LEFT", self.primaryButton, "RIGHT", 10, 0)
    self.primaryButton:SetScript("OnClick", function() if self.primaryAction then self.primaryAction() end end)
    self.secondaryButton:SetScript("OnClick", function() if self.secondaryAction then self.secondaryAction() end end)
    Tooltip(self.primaryButton, function() return self.primaryTip and self.primaryTip[1] or "" end,
        function() return self.primaryTip and self.primaryTip[2] end)
    Tooltip(self.secondaryButton, function() return self.secondaryTip and self.secondaryTip[1] or "" end,
        function() return self.secondaryTip and self.secondaryTip[2] end)

    -- Footer: status, export, options
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
    self.status:SetPoint("RIGHT", f, "RIGHT", -300, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)

    self.optionsButton = SmallButton(f, "Options", 84)
    self.optionsButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 4)
    self.optionsButton:SetScript("OnClick", function() QH:OpenSettings() end)
    self.exportButton = SmallButton(f, "Export", 84)
    self.exportButton:SetPoint("RIGHT", self.optionsButton, "LEFT", -4, 0)
    self.exportButton:SetScript("OnClick", function() QH:ShowExport() end)
    Tooltip(self.exportButton, "Export journal", "Copy your journal as Markdown, to keep it or turn it into a PDF.")

    QH:Listen("ENTRY_WRITTEN", function()
        if self.frame:IsShown() then self:Refresh(self.selected ~= PENDING and self.selected or true) end
    end)
    QH:Listen("SETTING_CHANGED", function(key)
        if self.frame:IsShown() and (key == "textSize" or key == "moodPrompt" or key == "length") then
            self:Refresh(self.selected)
        end
    end)
end

---------------------------------------------------------------------------
-- List: unwritten page, chapter headers, entries (newest first)
---------------------------------------------------------------------------
function Journal:EntryRow(i)
    if self.entryRows[i] then return self.entryRows[i] end
    local row = CreateFrame("Button", nil, self.listChild)
    row:SetSize(LIST_WIDTH, ENTRY_ROW)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.16)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.title:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -6)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -8)

    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetSize(14, 14)
    row.star:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
    row.star:SetTexture(STAR_ICON)

    row:SetScript("OnClick", function() self:Select(row.key) end)
    self.entryRows[i] = row
    return row
end

function Journal:HeaderRow(i)
    if self.headerRows[i] then return self.headerRows[i] end
    local row = CreateFrame("Button", nil, self.listChild)
    row:SetSize(LIST_WIDTH, HEADER_ROW)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.35, 0.25, 0.1, 0.35)
    row.selected = row:CreateTexture(nil, "BORDER")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.18)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function() self:Select(row.key) end)
    self.headerRows[i] = row
    return row
end

local function Visible(e, favOnly)
    if favOnly and not e.favorite then return false end
    return true
end

function Journal:RefreshList()
    local favOnly = self.favFilter:GetChecked()
    local seenBefore = self.seenBefore or 0
    local y, ei, hi = 0, 0, 0

    local function placeEntryRow(key, title, sub, icon, tag, star, dim)
        ei = ei + 1
        local row = self:EntryRow(ei)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 0, -y)
        row.key = key
        row.title:SetText(title)
        row.title:SetAlpha(dim and 0.5 or 1)
        row.sub:SetText(sub)
        row.icon:SetTexture(icon)
        row.tag:SetText(tag or "")
        row.tag:SetShown(tag ~= nil and not star)
        row.star:SetShown(star == true)
        row.selected:SetShown(self.selected == key)
        row:Show()
        y = y + ENTRY_ROW
    end

    if self.pending then
        local d = self.pending.digest
        placeEntryRow(PENDING, "|cffffffffAn unwritten page|r",
            DayLabel(d.startDay, d.endDay) .. "  |cff999999" .. (d.lastRest.zone or "") .. "|r",
            "Interface\\Icons\\INV_Misc_Note_01", "|cffffd100INK|r")
    end

    local chapters = QH:GetChapters()
    for ci = #chapters, 1, -1 do
        local ch = chapters[ci]
        local shown = {}
        for n = #ch.entries, 1, -1 do
            local e = ch.entries[n]
            if Visible(e, favOnly) then table.insert(shown, e) end
        end
        if #shown > 0 or not favOnly then
            hi = hi + 1
            local header = self:HeaderRow(hi)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 0, -y)
            header.key = "chapter:" .. ch.key
            header.text:SetText(("Chapter %s: %s"):format(ch.numeral, ch.title))
            header.selected:SetShown(self.selected == header.key)
            header:Show()
            y = y + HEADER_ROW
        end
        for _, e in ipairs(shown) do
            local icon = e.restKind == "campfire" and "Interface\\Icons\\Spell_Fire_Fire" or "Interface\\Icons\\INV_Misc_Rune_01"
            local isNew = (e.t or 0) > seenBefore
            placeEntryRow(e.id, e.title or "Untitled",
                DayLabel(e.day, e.dayEnd) .. (e.zone and ("  |cff999999" .. e.zone .. "|r") or ""),
                icon, isNew and "NEW" or nil, e.favorite == true)
        end
    end

    for n = ei + 1, #self.entryRows do self.entryRows[n]:Hide() end
    for n = hi + 1, #self.headerRows do self.headerRows[n]:Hide() end
    self.listChild:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Journal:ApplyFonts()
    local size = QH:GetSetting("textSize")
    if not SIZES[size] then size = "medium" end
    self.dayText:SetFontObject(Font("meta", size))
    self.titleText:SetFontObject(Font("title", size))
    self.placeText:SetFontObject(Font("meta", size))
    self.bodyText:SetFontObject(Font("body", size))
    if self.bodyText.SetSpacing then self.bodyText:SetSpacing(SIZES[size].spacing) end
    self.dayText:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    self.titleText:SetTextColor(INK[1], INK[2], INK[3])
    self.placeText:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    self.bodyText:SetTextColor(INK[1], INK[2], INK[3])
end

function Journal:LayoutPage()
    local height = 40
    for _, fs in ipairs({ self.dayText, self.titleText, self.placeText, self.bodyText }) do
        height = height + fs:GetStringHeight() + 12
    end
    self.content:SetHeight(math.max(1, height))
end

--- Show text on the page. buttons: { primary = {label, action, tip}, secondary = {...} }; tools: show the
--- read/edit/hide/favourite buttons; mood: show the mood row.
function Journal:ShowPage(day, title, place, body, opts)
    opts = opts or {}
    self:ApplyFonts()
    self.dayText:SetText(day or "")
    self.titleText:SetText(title or "")
    self.placeText:SetText(place or "")
    self.bodyText:SetText(body or "")

    for _, b in ipairs(self.tools) do b:SetShown(opts.tools == true) end
    local moodShown = opts.mood == true
    self.moodLabel:SetShown(moodShown)
    local current = QH.char.state.pendingMood
    for _, b in ipairs(self.moodButtons) do
        b:SetShown(moodShown)
        if b.mood == current then b:LockHighlight() else b:UnlockHighlight() end
    end

    local function setup(button, spec, which)
        if spec then
            button:SetText(spec[1])
            button:SetWidth(math.max(120, button:GetTextWidth() + 30))
            button:Show()
            self[which .. "Action"] = spec[2]
            self[which .. "Tip"] = spec[3]
        else
            button:Hide()
            self[which .. "Action"] = nil
        end
    end
    setup(self.primaryButton, opts.primary, "primary")
    setup(self.secondaryButton, opts.secondary, "secondary")

    local bottom = 16
    if opts.primary or opts.secondary then bottom = 48 end
    if moodShown then bottom = 78 end
    self.scroll:SetPoint("BOTTOMRIGHT", self.page, "BOTTOMRIGHT", -38, bottom)
    self.scroll:SetPoint("TOPLEFT", self.page, "TOPLEFT", 30, opts.tools and -40 or -22)
    self:LayoutPage()
    self.scroll:SetVerticalScroll(0)
end

local function SummarizeDigest(d)
    local lines = {}
    for _, thread in ipairs(d.threads) do
        for _, m in ipairs(thread.moments) do
            local what = m.note and ('your note: "' .. m.note .. '"')
                or (m.title and (m.kind .. ': "' .. m.title .. '"') or m.kind)
            table.insert(lines, ("- %s |cff7a5a3a(%s)|r"):format(what, m.place))
            if #lines >= 10 then break end
        end
        if #lines >= 10 then break end
    end
    for _, c in ipairs(d.collapsed) do table.insert(lines, "- " .. c) end
    if #lines == 0 then
        for _, j in ipairs(d.journey) do
            table.insert(lines, "- " .. j.text)
            if #lines >= 6 then break end
        end
    end
    if #lines == 0 then table.insert(lines, "- A quiet stretch with little to tell.") end
    return table.concat(lines, "\n")
end

function Journal:ShowPendingPage()
    local d = self.pending.digest
    local nights = d.nights > 1 and (" (%d nights)"):format(d.nights) or ""
    local body = "Since your last entry:\n" .. SummarizeDigest(d)
    if d.reflections and #d.reflections > 0 then
        body = body .. "\n\n|cff5a3a1aA milestone:|r " .. table.concat(d.reflections, ", ") .. ". The entry will look back on how far you've come."
    end
    body = body .. "\n\n|cff5a3a1aWrite with AI|r opens the prompt to copy into any AI chat (ChatGPT, Gemini, Claude...) and a box to paste the reply.\n"
        .. "|cff5a3a1aWrite it plainly|r writes a simple entry right now, without any AI. You can still rewrite it with AI later."
    self:ShowPage(DayLabel(d.startDay, d.endDay) .. nights, "An unwritten page",
        PlaceText(d.restKind, d.lastRest.zone, d.lastRest.subzone), body, {
            mood = QH:GetSetting("moodPrompt"),
            primary = { "Write with AI", function() QH.Bridge:Show(self.job) end,
                { "Write with AI", "Copy the prompt into any AI chat, then paste the reply. All in one window." } },
            secondary = { "Write it plainly", function()
                local entry, err = QH:WriteTemplateEntry(self.pending)
                QH:Print(entry and ('"%s" was written into your journal.'):format(entry.title) or err)
            end, { "Write it plainly", "Your character writes a simple entry right now, without any AI." } },
        })
end

function Journal:ShowEntryPage(e)
    local notes = {}
    if e.level then table.insert(notes, ("level %d"):format(e.level)) end
    if e.mood then table.insert(notes, e.mood:lower()) end
    if e.source == "template" then table.insert(notes, "written plainly") end
    if e.rewrittenAt then table.insert(notes, "rewritten") end
    if e.editedAt then table.insert(notes, "edited") end
    local place = PlaceText(e.restKind, e.zone, e.subzone)
    if #notes > 0 then place = place .. "  |cff8a7a6a(" .. table.concat(notes, ", ") .. ")|r" end
    self:ShowPage(DayLabel(e.day, e.dayEnd), e.title, place, e.body, {
        tools = true,
        primary = e.prompt and { "Rewrite with AI", function() QH.Bridge:Show(QH.Bridge.RewriteJob(e)) end,
            { "Rewrite with AI", "Get a new version of this entry from any AI chat, using the prompt it was written from." } } or nil,
    })
    SetStarLit(self.favButton:GetNormalTexture(), e.favorite)
end

function Journal:ShowChapterPage(ch)
    local lines = {}
    if ch.summary then
        table.insert(lines, ch.summary)
        table.insert(lines, "")
    else
        table.insert(lines, "|cff8a7a6aThis chapter has no summary yet.|r")
        table.insert(lines, "")
    end
    table.insert(lines, "|cff5a3a1aIn this chapter:|r")
    for _, e in ipairs(ch.entries) do
        table.insert(lines, ("- %s: %s"):format(DayLabel(e.day, e.dayEnd), e.title or "Untitled"))
    end
    local levels = ch.minLevel and (ch.minLevel == ch.maxLevel and ("level %d"):format(ch.minLevel)
        or ("levels %d-%d"):format(ch.minLevel, ch.maxLevel)) or nil
    local meta = table.concat({ DayLabel(ch.firstDay, ch.lastDay), levels or nil }, " · ")
    local zones = table.concat(ch.zoneOrder or {}, ", ")
    self:ShowPage(("Chapter %s"):format(ch.numeral) .. (ch.isOpen and "  |cff8a7a6a(still being written)|r" or ""),
        ch.title, meta .. (zones ~= "" and ("  ·  " .. zones) or ""), table.concat(lines, "\n"), {
            primary = { ch.summary and "Rewrite summary with AI" or "Summary with AI",
                function() QH.Bridge:Show(QH.Bridge.ChapterJob(ch)) end,
                { "Chapter summary with AI", "Copy a prompt with this chapter's entries into any AI chat for a title and a summary." } },
            secondary = { "Write it plainly", function() QH:WriteChapterPlainly(ch.key) end,
                { "Write it plainly", "A simple summary listing what happened, without any AI." } },
        })
end

function Journal:ShowEmptyPage()
    local _, moments = QH:GetPendingInfo()
    local body = ("Your journal is still empty.\n\n%d %s been recorded since you began. "
        .. "Rest at an inn, in a city, or by a campfire, and your character will be ready to write about it.")
        :format(moments, moments == 1 and "moment has" or "moments have")
    self:ShowPage("", "A blank page", "", body, {})
end

--- key: PENDING, an entry id, or "chapter:<key>".
function Journal:Select(key)
    self.job, self.selectedEntry = nil, nil
    if key == PENDING and self.pending then
        self.selected = PENDING
        self.job = QH.Bridge.PendingJob(self.pending)
        self:ShowPendingPage()
    elseif type(key) == "string" and key:find("^chapter:") then
        local ch = QH:FindChapter(key:sub(9))
        if ch then
            self.selected = key
            self:ShowChapterPage(ch)
        else
            return self:Select(nil)
        end
    elseif key and QH:FindEntry(key) then
        local entry = QH:FindEntry(key)
        self.selected = entry.id
        self.selectedEntry = entry
        self:ShowEntryPage(entry)
    else
        self.selected = nil
        self:ShowEmptyPage()
    end
    self:RefreshList()
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function Journal:RefreshStatus()
    local unwritten, moments = QH:GetPendingInfo()
    local text
    if unwritten > 0 then
        text = "|cffffd100An unwritten page is waiting.|r Write it with AI, or plainly."
    elseif moments > 0 then
        text = ("%d %s since your last rest. Rest at an inn, a city or a campfire to write.")
            :format(moments, moments == 1 and "moment" or "moments")
    else
        text = "Nothing new since your last rest."
    end
    self.status:SetText(text)
end

---------------------------------------------------------------------------
-- Open / refresh
---------------------------------------------------------------------------
--- target: a selection key (entry id or "chapter:.."), `true` for the newest entry, or nil
--- to show the unwritten page first (if there is one).
function Journal:Refresh(target)
    self.pending = QH:GetPendingWrite()
    local entries = QH:GetEntries()
    if type(target) == "string" and target ~= PENDING then
        self:Select(target)
    elseif self.pending and (not target or target == PENDING) then
        self:Select(PENDING)
    elseif #entries > 0 then
        self:Select(entries[#entries].id)
    else
        self:Select(nil)
    end
    self:RefreshStatus()
end

--- opts.ritual: play the writing ritual (book sound, /sit + /e emote) if enabled.
function Journal:Open(opts)
    if not QH.char then return end
    if not self.frame then self:Build() end
    local profile = QH:GetProfile()
    local name = profile and profile.name or UnitName("player")
    if self.frame.SetTitle then self.frame:SetTitle(("%s's Journal"):format(name)) end

    local state = QH.char.state
    self.seenBefore = self.seenBefore or state.lastSeenEntryT or 0
    local wasShown = self.frame:IsShown()
    self:Refresh(nil)
    self.frame:Show()

    if opts and opts.ritual and QH:GetSetting("ritual") and not wasShown then
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
        if opts.emote ~= false and not InCombatLockdown() then
            if DoEmote then pcall(DoEmote, "SIT") end
            if QH:GetSetting("ritualEmote") and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                local d = self.pending and self.pending.digest
                local restKind = (d and d.restKind) or QH:GetRestKind()
                local indoors = (d and d.indoors) or (IsIndoors and QH.Safe(IsIndoors()))
                local emote = QH:PickRitualEmote(restKind, state.pendingMood, indoors)
                local who = QH.Safe(UnitName("player")) or name or "Your character"
                DEFAULT_CHAT_FRAME:AddMessage(("|cffff8040%s %s|r"):format(who, emote))
            end
        end
    elseif not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then
        PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
    end

    local entries = QH:GetEntries()
    local newest = entries[#entries]
    if newest and newest.t then state.lastSeenEntryT = math.max(state.lastSeenEntryT or 0, newest.t) end
end

function Journal:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

QH:RegisterCommand("journal", "open your journal (also just /quill)", function() Journal:Toggle() end)
