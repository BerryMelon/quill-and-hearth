-- Quill & Hearth: edit an entry by hand (title + text) or launch Rewrite with AI.
local _, QH = ...

local EditDialog = {}
QH.EditDialog = EditDialog

local function Build()
    local f = QH.Bridge.CreateTextDialog("QuillAndHearthEditDialog", "Edit entry", 640, 520)
    local inset = f.Inset or f
    f.instructions:SetText("Title")

    f.titleBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.titleBox:SetSize(400, 22)
    f.titleBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 20, -26)
    f.titleBox:SetAutoFocus(false)
    f.titleBox:SetMaxLetters(80)
    f.titleBox:SetScript("OnEnterPressed", function() f.box:SetFocus() end)
    f.titleBox:SetScript("OnEscapePressed", function() f:Hide() end)

    -- Word count at top-right next to the title box so the bottom bar stays clean.
    f.wordCount = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.wordCount:SetPoint("RIGHT", inset, "TOPRIGHT", -32, -37)
    f.wordCount:SetJustifyH("RIGHT")

    -- Make room for the title box above the text.
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -60)
    f.scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 10)

    -- "Rewrite with AI..." button on the bottom-left of the Edit window.
    f.rewrite = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.rewrite:SetSize(140, 22)
    f.rewrite:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
    f.rewrite:SetText("Rewrite with AI...")
    f.rewrite:SetScript("OnClick", function()
        local entry = EditDialog.entryId and QH:FindEntry(EditDialog.entryId)
        if entry and entry.prompt then
            f:Hide()
            QH.Bridge:Show(QH.Bridge.RewriteJob(entry))
        end
    end)
    f.rewrite:SetScript("OnEnter", function(btn)
        QH:ShowTooltip(btn, "ANCHOR_TOP", "Rewrite with AI",
            "Get a new version of this entry from any AI chat, using the prompt it was written from.")
    end)
    f.rewrite:SetScript("OnLeave", function() QH:HideTooltip() end)

    f.note:ClearAllPoints()
    f.note:SetPoint("LEFT", f.rewrite, "RIGHT", 10, 0)
    f.note:SetPoint("RIGHT", f.secondary, "LEFT", -8, 0)

    f.secondary:SetText(CANCEL or "Cancel")
    f.secondary:SetScript("OnClick", function() f:Hide() end)
    f.primary:SetText("Save changes")
    f.primary:SetScript("OnClick", function()
        local entry, err = QH:EditEntry(EditDialog.entryId, f.titleBox:GetText(), f.box:GetText())
        if not entry then
            f.note:SetText("|cffff5050" .. err .. "|r")
            return
        end
        f:Hide()
        QH:Print(('"%s" was updated.'):format(entry.title))
    end)
    f.box:SetScript("OnTextChanged", function(box)
        local words = select(2, box:GetText():gsub("%S+", ""))
        f.wordCount:SetText(("%d words"):format(words))
    end)
    return f
end

function EditDialog:Open(entry)
    self.frame = self.frame or Build()
    local f = self.frame
    self.entryId = entry.id
    f.note:SetText("")
    f.titleBox:SetText(entry.title or "")
    f.box:SetText(entry.body or "")
    f.rewrite:SetShown(entry.prompt ~= nil)
    f:Show()
    f.scroll:SetVerticalScroll(0)
    f.box:SetFocus()
    f.box:SetCursorPosition(0)
end
