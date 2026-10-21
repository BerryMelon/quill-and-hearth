-- Quill & Hearth: export the whole journal as Markdown.
-- An addon can't write files, so the journal is shown pre-selected in a read-only box (Ctrl+C);
-- Markdown reads fine as plain text and converts to PDF / Docs / Obsidian easily.
local _, QH = ...

local Export = {}
QH.Export = Export

local function DayLabel(e)
    if e.dayEnd and e.dayEnd ~= e.day then
        return ("Days %d-%d"):format(e.day or 0, e.dayEnd)
    end
    return ("Day %d"):format(e.day or 0)
end

local function PlaceLine(e)
    local place = e.subzone and e.zone and e.subzone ~= e.zone and (e.subzone .. ", " .. e.zone) or e.zone or e.subzone
    local parts = {}
    if place then
        table.insert(parts, (e.restKind == "campfire" and "By a campfire near " or "Written at ") .. place)
    end
    if e.level then table.insert(parts, ("level %d"):format(e.level)) end
    return table.concat(parts, " · ")
end

--- Build the Markdown document. Pure function (no WoW API), so it can be tested outside the game.
---   info: { name, race, class, realm, exportedOn }
function Export.ToMarkdown(entries, info)
    local out = {}
    local function add(s) table.insert(out, s or "") end

    add(("# %s's Journal"):format(info.name or "An Adventurer"))
    local who = {}
    if info.race then table.insert(who, info.race) end
    if info.class then table.insert(who, info.class) end
    local subtitle = table.concat(who, " ")
    if info.realm then subtitle = subtitle .. (subtitle ~= "" and " of " or "") .. info.realm end
    if subtitle ~= "" then
        add("*" .. subtitle .. "*")
        add() -- separate paragraph, or Markdown joins the two lines
    end
    add(("*%d %s · exported %s with Quill & Hearth*"):format(#entries, #entries == 1 and "entry" or "entries",
        info.exportedOn or "today"))
    add()

    if #entries == 0 then
        add("*The pages are still blank.*")
    end

    for i, e in ipairs(entries) do
        add("---")
        add()
        add(("## %s: %s"):format(DayLabel(e), e.title or "Untitled"))
        local place = PlaceLine(e)
        if place ~= "" then add("*" .. place .. "*") end
        add()
        local body = (e.body or ""):gsub("\r\n?", "\n")
        add(body)
        add()
    end
    return table.concat(out, "\n")
end

function QH:BuildJournalMarkdown()
    local profile = self:GetProfile()
    local meta = self.char and self.char.meta or {}
    return Export.ToMarkdown(self:GetEntries(), {
        name = profile and profile.name or meta.name or UnitName("player"),
        race = profile and profile.trp3 and profile.trp3.race or meta.race,
        class = profile and profile.class or meta.class,
        realm = meta.realm,
        exportedOn = date and date("%Y-%m-%d") or nil,
    })
end

---------------------------------------------------------------------------
-- Dialog
---------------------------------------------------------------------------
local dialog

local function BuildDialog()
    local f = QH.Bridge.CreateTextDialog("QuillAndHearthExportDialog", "Export your journal", 640, 500)
    f.instructions:SetText("Press |cffffd100Ctrl+C|r to copy, then paste into a file (e.g. |cffffffffjournal.md|r), Obsidian, Notion or Google Docs. It's Markdown: readable as plain text, and easy to turn into a PDF.")
    f.secondary:SetText("Select all")
    f.secondary:SetScript("OnClick", function()
        f.box:SetFocus()
        f.box:HighlightText()
    end)
    f.primary:SetText(CLOSE or "Close")
    f.primary:SetScript("OnClick", function() f:Hide() end)
    -- Read-only: undo any typing, keep everything selected.
    f.box:SetScript("OnTextChanged", function(box, userInput)
        if userInput and box:GetText() ~= f.text then
            box:SetText(f.text)
            box:HighlightText()
        end
    end)
    f.box:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
    return f
end

function QH:ShowExport()
    if not self.char then return end
    dialog = dialog or BuildDialog()
    local text = self:BuildJournalMarkdown()
    local count = #self:GetEntries()
    dialog.text = text
    dialog.box:SetText(text)
    dialog.note:SetText(("%d %s, %d characters. Everything is selected; just press Ctrl+C.")
        :format(count, count == 1 and "entry" or "entries", #text))
    dialog:Show()
    dialog.scroll:SetVerticalScroll(0)
    dialog.box:SetFocus()
    dialog.box:HighlightText()
end

QH:RegisterCommand("export", "export your whole journal as Markdown (copy it out)", function()
    QH:ShowExport()
end)
