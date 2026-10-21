-- Quill & Hearth: edit an entry by hand (title + text).
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

    -- Make room for the title box above the text.
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -60)
    f.scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 10)

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
        f.note:SetText(("%d words"):format(words))
    end)
    return f
end

function EditDialog:Open(entry)
    self.frame = self.frame or Build()
    local f = self.frame
    self.entryId = entry.id
    f.titleBox:SetText(entry.title or "")
    f.box:SetText(entry.body or "")
    f:Show()
    f.scroll:SetVerticalScroll(0)
    f.box:SetFocus()
    f.box:SetCursorPosition(0)
end
