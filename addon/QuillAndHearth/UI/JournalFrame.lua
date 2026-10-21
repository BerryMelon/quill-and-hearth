-- Quill & Hearth: the journal reader (stock Blizzard templates and textures only).
local _, QH = ...

local Journal = {}
QH.Journal = Journal

local WIDTH, HEIGHT = 800, 560
local LIST_WIDTH = 230
local ROW_HEIGHT = 42
local INK = { 0.24, 0.15, 0.08 }      -- dark brown text on parchment
local INK_SOFT = { 0.42, 0.30, 0.18 }

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
local function GeneratedChar()
    local gen = QuillAndHearth_Generated
    return gen and gen.characters and gen.characters[QH.charKey]
end

--- Journal entries for this character, oldest first.
function QH:GetEntries()
    local c = GeneratedChar()
    return (c and type(c.entries) == "table") and c.entries or {}
end

function QH:CompanionHasRun()
    local gen = QuillAndHearth_Generated
    return gen ~= nil and gen.generatedAt ~= nil
end

--- unwrittenRests: rests the companion hasn't written up yet ("ink drying").
--- momentsSinceRest: events recorded after the latest rest.
function QH:GetPendingInfo()
    local c = GeneratedChar()
    local processed = c and c.processedThrough or 0
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

local function DayLabel(e)
    if e.dayEnd and e.dayEnd ~= e.day then
        return ("Days %d - %d"):format(e.day or 0, e.dayEnd)
    end
    return ("Day %d"):format(e.day or 0)
end

local function PlaceLabel(e)
    local place = e.subzone and e.zone and e.subzone ~= e.zone and (e.subzone .. ", " .. e.zone) or e.zone or e.subzone
    if not place then return "" end
    return (e.restKind == "campfire" and "By a campfire near " or "Written at ") .. place
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local PARCHMENT_ATLASES = { "QuestBG-Parchment", "QuestDetailsBackgrounds" }

local function ApplyParchment(texture)
    for _, atlas in ipairs(PARCHMENT_ATLASES) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetColorTexture(0.93, 0.87, 0.73) -- plain parchment colour as a last resort
end

function Journal:Build()
    local f = CreateFrame("Frame", "QuillAndHearthJournal", UIParent, "ButtonFrameTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09") end
    table.insert(UISpecialFrames, "QuillAndHearthJournal")
    f:Hide()
    self.frame = f

    local inset = f.Inset or f

    -- Entry list (left)
    local list = CreateFrame("ScrollFrame", "QuillAndHearthJournalList", f, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
    list:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 6)
    list:SetWidth(LIST_WIDTH)
    local listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(LIST_WIDTH, 1)
    list:SetScrollChild(listChild)
    self.listChild = listChild
    self.rows = {}

    -- Reading page (right)
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", inset, "TOPLEFT", LIST_WIDTH + 34, -4)
    page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ApplyParchment(bg)

    local scroll = CreateFrame("ScrollFrame", "QuillAndHearthJournalPage", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 22, -20)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -32, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    local function Text(font, color)
        local fs = content:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        if color then fs:SetTextColor(color[1], color[2], color[3]) end
        return fs
    end
    self.dayText = Text("GameFontNormalSmall", INK_SOFT)
    self.titleText = Text("QuestTitleFont", INK)
    self.placeText = Text("GameFontNormalSmall", INK_SOFT)
    self.bodyText = Text("QuestFont", INK)
    if self.bodyText.SetSpacing then self.bodyText:SetSpacing(3) end

    self.dayText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.titleText:SetPoint("TOPLEFT", self.dayText, "BOTTOMLEFT", 0, -6)
    self.placeText:SetPoint("TOPLEFT", self.titleText, "BOTTOMLEFT", 0, -4)
    self.bodyText:SetPoint("TOPLEFT", self.placeText, "BOTTOMLEFT", 0, -14)

    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        for _, fs in ipairs({ self.dayText, self.titleText, self.placeText, self.bodyText }) do
            fs:SetWidth(width)
        end
        self:LayoutPage()
    end)

    -- Footer: status + reload
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
    self.status:SetPoint("RIGHT", f, "RIGHT", -130, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)

    self.reload = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.reload:SetSize(110, 22)
    self.reload:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)
    self.reload:SetText("Reload UI")
    self.reload:SetScript("OnClick", function() ReloadUI() end)
    self.reload:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Reload to read new entries")
        GameTooltip:AddLine("Entries written by the companion app appear after a reload.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.reload:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------
function Journal:GetRow(i)
    if self.rows[i] then return self.rows[i] end
    local row = CreateFrame("Button", nil, self.listChild)
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.16)
    row.selected:Hide()

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
    row.title:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.newTag = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    row.newTag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
    row.newTag:SetText("NEW")

    row:SetScript("OnClick", function() self:Select(row.entryIndex) end)
    self.rows[i] = row
    return row
end

function Journal:RefreshList()
    local entries = QH:GetEntries()
    local seenBefore = self.seenBefore or 0
    -- Newest first.
    for i = 1, #entries do
        local entryIndex = #entries - i + 1
        local e = entries[entryIndex]
        local row = self:GetRow(i)
        row.entryIndex = entryIndex
        row.title:SetText(e.title or "Untitled")
        row.sub:SetText(DayLabel(e) .. (e.zone and ("  |cff999999" .. e.zone .. "|r") or ""))
        row.newTag:SetShown((e.t or 0) > seenBefore)
        row.selected:SetShown(entryIndex == self.selectedIndex)
        row:Show()
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
    self.listChild:SetHeight(math.max(1, #entries * ROW_HEIGHT))
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Journal:LayoutPage()
    local height = 0
    for _, fs in ipairs({ self.dayText, self.titleText, self.placeText, self.bodyText }) do
        height = height + fs:GetStringHeight() + 10
    end
    self.content:SetHeight(math.max(1, height))
end

function Journal:ShowText(day, title, place, body)
    self.dayText:SetText(day or "")
    self.titleText:SetText(title or "")
    self.placeText:SetText(place or "")
    self.bodyText:SetText(body or "")
    self:LayoutPage()
    self.scroll:SetVerticalScroll(0)
end

function Journal:ShowEmptyPage()
    local unwritten, moments = QH:GetPendingInfo()
    local body
    if not QH:CompanionHasRun() then
        body = "Your journal is still empty.\n\nEntries are written by the Quill & Hearth companion app on your computer. "
            .. "Start it (npm start in the companion folder) and leave it running while you play.\n\n"
            .. "Whenever you rest, at an inn, in a city, or by a campfire, your character will write about what happened since their last rest."
    elseif unwritten > 0 then
        body = "The ink is still drying on your latest entry.\n\nOnce the companion app has finished writing, reload your UI to read it."
    else
        body = ("Your journal is still empty.\n\n%d moments have been recorded since your last rest. "
            .. "Rest at an inn, in a city, or by a campfire, and your character will write about them."):format(moments)
    end
    self:ShowText("", "A blank page", "", body)
end

function Journal:Select(entryIndex)
    local entries = QH:GetEntries()
    local e = entries[entryIndex]
    if not e then
        self.selectedIndex = nil
        self:ShowEmptyPage()
    else
        self.selectedIndex = entryIndex
        local level = e.level and ("  |cff999999(level %d)|r"):format(e.level) or ""
        self:ShowText(DayLabel(e), e.title, PlaceLabel(e) .. level, e.body)
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
        text = ("|cffffd100The ink is drying|r on %d %s. Reload once the companion has written %s.")
            :format(unwritten, unwritten == 1 and "entry" or "entries", unwritten == 1 and "it" or "them")
    elseif moments > 0 then
        text = ("%d %s await%s your quill. Rest at an inn, a city or a campfire to write.")
            :format(moments, moments == 1 and "moment" or "moments", moments == 1 and "s" or "")
    else
        text = "Nothing new since your last rest."
    end
    self.status:SetText(text)
    self.reload:SetShown(unwritten > 0)
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
function Journal:Open()
    if not QH.char then return end
    if not self.frame then self:Build() end
    local profile = QH:GetProfile()
    local name = profile and profile.name or UnitName("player")
    if self.frame.SetTitle then self.frame:SetTitle(("%s's Journal"):format(name)) end

    local state = QH.char.state
    self.seenBefore = self.seenBefore or state.lastSeenEntryT or 0
    local entries = QH:GetEntries()
    self:Select(#entries > 0 and #entries or nil)
    self:RefreshStatus()
    self.frame:Show()

    -- Mark everything as seen (NEW tags stay visible for this session).
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

---------------------------------------------------------------------------
-- Addon compartment (minimap addon menu)
---------------------------------------------------------------------------
function QuillAndHearth_OnCompartmentClick()
    Journal:Toggle()
end

function QuillAndHearth_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(type(menuButton) == "table" and menuButton or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Quill & Hearth")
    if QH.char then
        local unwritten, moments = QH:GetPendingInfo()
        GameTooltip:AddLine(("%d journal entries"):format(#QH:GetEntries()), 1, 1, 1)
        if unwritten > 0 then GameTooltip:AddLine("The ink is drying on your latest entry.", 1, 0.82, 0) end
        if moments > 0 then GameTooltip:AddLine(("%d moments since your last rest"):format(moments), 0.8, 0.8, 0.8) end
    end
    GameTooltip:AddLine("Click to open your journal.", 0.5, 0.5, 0.5)
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
        if new > 0 then
            QH:Print(("Your journal has |cffffffff%d new %s|r. Type |cffffd100/quill|r to read."):format(new, new == 1 and "entry" or "entries"))
        elseif unwritten > 0 then
            if QH:CompanionHasRun() then
                QH:Print("The ink is still drying on your latest entry. Keep the companion running, then |cffffd100/reload|r.")
            else
                QH:Print("Start the companion app so your journal can be written.")
            end
        end
    end)
end)
