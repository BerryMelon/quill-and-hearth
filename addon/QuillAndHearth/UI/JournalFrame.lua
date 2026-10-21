-- Quill & Hearth: the journal reader (stock Blizzard templates and textures only).
local _, QH = ...

local Journal = {}
QH.Journal = Journal

local WIDTH, HEIGHT = 800, 560
local LIST_WIDTH = 230
local ROW_HEIGHT = 42
local INK = { 0.24, 0.15, 0.08 }      -- dark brown text on parchment
local INK_SOFT = { 0.42, 0.30, 0.18 }
local PENDING = "pending"

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
function QH:CompanionHasRun()
    local gen = QuillAndHearth_Generated
    return gen ~= nil and gen.generatedAt ~= nil
end

-- The companion rewrites Entries.lua every minute, so its timestamp doubles as a heartbeat.
-- (Entries.lua is read when the UI loads, so this reflects the moment of the last login/reload.)
local HEARTBEAT_STALE_SECONDS = 180

--- "running", "stopped" (has run before, but not recently) or "never".
function QH:GetCompanionStatus()
    local gen = QuillAndHearth_Generated
    if not (gen and gen.generatedAt) then return "never" end
    local loadedAt = QH.loadedAt or GetServerTime()
    if math.abs(loadedAt - gen.generatedAt) <= HEARTBEAT_STALE_SECONDS then return "running" end
    return "stopped"
end

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
    self.page = page

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

    -- Write buttons (only on the unwritten page)
    self.copyButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    self.copyButton:SetSize(128, 24)
    self.copyButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 20, 14)
    self.copyButton:SetText("1. Copy prompt")
    self.copyButton:SetScript("OnClick", function()
        if self.job then QH.Bridge:ShowPrompt(self.job) end
    end)

    self.pasteButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    self.pasteButton:SetSize(128, 24)
    self.pasteButton:SetPoint("LEFT", self.copyButton, "RIGHT", 8, 0)
    self.pasteButton:SetText("2. Paste entry")
    self.pasteButton:SetScript("OnClick", function()
        if self.job then QH.Bridge:ShowPaste(self.job) end
    end)

    self.plainButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    self.plainButton:SetSize(150, 24)
    self.plainButton:SetPoint("LEFT", self.pasteButton, "RIGHT", 16, 0)
    self.plainButton:SetText("Write it plainly")
    self.plainButton:SetScript("OnClick", function()
        if not self.pending then return end
        local entry, err = QH:WriteTemplateEntry(self.pending)
        if entry then
            QH:Print(('"%s" was written into your journal.'):format(entry.title))
        else
            QH:Print(err)
        end
    end)
    self.plainButton:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Write it plainly")
        GameTooltip:AddLine("Your character writes a simple entry right now, without any AI. Shorter and plainer than an AI-written one.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.plainButton:SetScript("OnLeave", GameTooltip_Hide)

    local function WriteTooltip(btn, pendingTitle, pendingText, entryTitle, entryText)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        if self.selected == PENDING then
            GameTooltip:SetText(pendingTitle)
            GameTooltip:AddLine(pendingText, 1, 1, 1, true)
        else
            GameTooltip:SetText(entryTitle)
            GameTooltip:AddLine(entryText, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end
    self.copyButton:SetScript("OnEnter", function(btn)
        WriteTooltip(btn, "Copy prompt", "Copy the prompt into any AI chat (ChatGPT, Gemini, Claude...).",
            "Copy prompt", "The prompt this entry was written from. Paste it into any AI chat to get a new version.")
    end)
    self.copyButton:SetScript("OnLeave", GameTooltip_Hide)
    self.pasteButton:SetScript("OnEnter", function(btn)
        WriteTooltip(btn, "Paste entry", "Paste the AI's reply to write tonight's entry.",
            "Paste new version", "Paste a new AI reply to replace this entry's text.")
    end)
    self.pasteButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Footer: status + export + reload
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
    self.status:SetPoint("RIGHT", f, "RIGHT", -236, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)

    self.export = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.export:SetSize(100, 22)
    self.export:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)
    self.export:SetText("Export")
    self.export:SetScript("OnClick", function() QH:ShowExport() end)
    self.export:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Export journal")
        GameTooltip:AddLine("Copy your whole journal as Markdown, to keep it or turn it into a PDF.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.export:SetScript("OnLeave", GameTooltip_Hide)

    self.reload = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.reload:SetSize(110, 22)
    self.reload:SetPoint("RIGHT", self.export, "LEFT", -6, 0)
    self.reload:SetText("Reload UI")
    self.reload:SetScript("OnClick", function() ReloadUI() end)
    self.reload:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Reload to read new entries")
        GameTooltip:AddLine("Entries written by the companion app appear after a reload.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.reload:SetScript("OnLeave", GameTooltip_Hide)

    QH:Listen("ENTRY_WRITTEN", function()
        if self.frame:IsShown() then self:Refresh(self.selected ~= PENDING and self.selected or true) end
    end)
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

    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)

    row:SetScript("OnClick", function() self:Select(row.key) end)
    self.rows[i] = row
    return row
end

function Journal:RefreshList()
    local entries = QH:GetEntries()
    local seenBefore = self.seenBefore or 0
    local i = 0

    if self.pending then
        i = 1
        local d = self.pending.digest
        local row = self:GetRow(i)
        row.key = PENDING
        row.title:SetText("|cffffffffAn unwritten page|r")
        row.sub:SetText(DayLabel(d.startDay, d.endDay) .. "  |cff999999" .. (d.lastRest.zone or "") .. "|r")
        row.tag:SetText("|cffffd100INK|r")
        row.tag:Show()
        row.selected:SetShown(self.selected == PENDING)
        row:Show()
    end

    -- Newest first.
    for n = #entries, 1, -1 do
        local e = entries[n]
        i = i + 1
        local row = self:GetRow(i)
        row.key = e.id
        row.title:SetText(e.title or "Untitled")
        row.sub:SetText(DayLabel(e.day, e.dayEnd) .. (e.zone and ("  |cff999999" .. e.zone .. "|r") or ""))
        row.tag:SetText("NEW")
        row.tag:SetShown((e.t or 0) > seenBefore)
        row.selected:SetShown(self.selected == e.id)
        row:Show()
    end
    for n = i + 1, #self.rows do self.rows[n]:Hide() end
    self.listChild:SetHeight(math.max(1, i * ROW_HEIGHT))
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

--- mode: "pending" (unwritten page: copy / paste / write plainly), "entry" (written entry with a
--- stored prompt: copy / paste a new version), or nil (no buttons).
function Journal:ShowText(day, title, place, body, mode)
    self.dayText:SetText(day or "")
    self.titleText:SetText(title or "")
    self.placeText:SetText(place or "")
    self.bodyText:SetText(body or "")
    local showButtons = mode == "pending" or mode == "entry"
    self.copyButton:SetShown(showButtons)
    self.pasteButton:SetShown(showButtons)
    self.plainButton:SetShown(mode == "pending")
    if mode == "pending" then
        self.copyButton:SetText("1. Copy prompt")
        self.pasteButton:SetText("2. Paste entry")
    elseif mode == "entry" then
        self.copyButton:SetText("Copy prompt")
        self.pasteButton:SetText("Paste new version")
    end
    self.scroll:SetPoint("BOTTOMRIGHT", self.page, "BOTTOMRIGHT", -32, showButtons and 48 or 16)
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
            if #lines >= 8 then break end
        end
        if #lines >= 8 then break end
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
    local body = "Since your last entry:\n" .. SummarizeDigest(d) .. "\n\n"
    if QH:GetCompanionStatus() == "running" then
        body = body .. "The companion app is writing this entry. Reload your UI in a moment to read it, or write it yourself with the buttons below.\n\n"
    end
    body = body .. "|cff5a3a1aTo write it with any AI chat (ChatGPT, Gemini, Claude...):|r\n"
        .. "1. Click |cff5a3a1aCopy prompt|r and copy the text (Ctrl+C).\n"
        .. "2. Paste it into the AI chat and send it.\n"
        .. "3. Copy the AI's whole reply, click |cff5a3a1aPaste entry|r, paste it (Ctrl+V) and save.\n\n"
        .. "Or click |cff5a3a1aWrite it plainly|r for a simple entry without any AI."
    self:ShowText(DayLabel(d.startDay, d.endDay) .. nights, "An unwritten page",
        PlaceText(d.restKind, d.lastRest.zone, d.lastRest.subzone), body, "pending")
end

function Journal:ShowEmptyPage()
    local _, moments = QH:GetPendingInfo()
    local body = ("Your journal is still empty.\n\n%d %s been recorded since you began. "
        .. "Rest at an inn, in a city, or by a campfire, and your character will be ready to write about it.")
        :format(moments, moments == 1 and "moment has" or "moments have")
    self:ShowText("", "A blank page", "", body, nil)
end

function Journal:ShowEntryPage(e)
    local notes = {}
    if e.level then table.insert(notes, ("level %d"):format(e.level)) end
    if e.source == "template" then table.insert(notes, "written plainly") end
    if e.rewritten or e.rewrittenAt then table.insert(notes, "rewritten") end
    local place = PlaceText(e.restKind, e.zone, e.subzone)
    if #notes > 0 then place = place .. "  |cff999999(" .. table.concat(notes, ", ") .. ")|r" end
    self:ShowText(DayLabel(e.day, e.dayEnd), e.title, place, e.body, e.prompt and "entry" or nil)
end

--- key: PENDING or an entry id.
function Journal:Select(key)
    self.job = nil
    local entry = key and key ~= PENDING and QH:FindEntry(key)
    if key == PENDING and self.pending then
        self.selected = PENDING
        self.job = QH.Bridge.PendingJob(self.pending)
        self:ShowPendingPage()
    elseif entry then
        self.selected = entry.id
        if entry.prompt then self.job = QH.Bridge.RewriteJob(entry) end
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
    local companion = QH:GetCompanionStatus()
    local text
    if unwritten > 0 then
        text = companion == "running"
            and "|cffffd100The ink is drying.|r The companion is writing your entry; reload in a moment."
            or "|cffffd100An unwritten page is waiting.|r Copy the prompt into any AI chat, then paste the reply."
    elseif moments > 0 then
        text = ("%d %s since your last rest. Rest at an inn, a city or a campfire to write.")
            :format(moments, moments == 1 and "moment" or "moments")
    else
        text = "Nothing new since your last rest."
    end
    self.status:SetText(text)
    self.reload:SetShown(unwritten > 0 and companion == "running")
end

---------------------------------------------------------------------------
-- Open / refresh
---------------------------------------------------------------------------
--- Rebuild everything. `target`: an entry id to show, `true` for the newest entry, or nil to
--- show the unwritten page first (if there is one).
function Journal:Refresh(target)
    self.pending = QH:GetPendingWrite()
    local entries = QH:GetEntries()
    if type(target) == "string" and QH:FindEntry(target) then
        self:Select(target)
    elseif self.pending and not target then
        self:Select(PENDING)
    elseif #entries > 0 then
        self:Select(entries[#entries].id)
    else
        self:Select(nil)
    end
    self:RefreshStatus()
end

function Journal:Open()
    if not QH.char then return end
    if not self.frame then self:Build() end
    local profile = QH:GetProfile()
    local name = profile and profile.name or UnitName("player")
    if self.frame.SetTitle then self.frame:SetTitle(("%s's Journal"):format(name)) end

    local state = QH.char.state
    self.seenBefore = self.seenBefore or state.lastSeenEntryT or 0
    self:Refresh(false)
    self.frame:Show()

    -- Mark everything as seen (NEW tags stay visible for this session).
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
