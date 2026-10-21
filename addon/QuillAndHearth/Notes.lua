-- Quill & Hearth: personal notes. The player writes a line about what their character felt or did;
-- it becomes a KEY moment in the next journal entry (AI prompt, companion and template writer).
local _, QH = ...

local NOTE_MAX = 500

function QH:AddNote(text)
    text = text and strtrim((text:gsub("|", ""))) or ""
    if text == "" then return false end
    if #text > NOTE_MAX then text = text:sub(1, NOTE_MAX) end
    self:Push("note", { text = text })
    QH:Print(("Noted. It will be part of your next journal entry: |cffffffff%s|r"):format(text))
    return true
end

---------------------------------------------------------------------------
-- Note dialog (multi-line, stock templates)
---------------------------------------------------------------------------
local dialog

local function BuildDialog()
    local f = QH.Bridge.CreateTextDialog("QuillAndHearthNoteDialog", "A note for your journal", 480, 280)
    f.instructions:SetText("What did your character feel, think or do? Write a line or two; it will be woven into your next entry.")
    f.secondary:SetText(CANCEL or "Cancel")
    f.secondary:SetScript("OnClick", function() f:Hide() end)
    f.primary:SetText("Add note")
    f.primary:SetScript("OnClick", function()
        if QH:AddNote(f.box:GetText()) then
            f.box:SetText("")
            f:Hide()
        else
            f.note:SetText("|cffff5050Write something first.|r")
        end
    end)
    f.box:SetMaxLetters(NOTE_MAX)
    f.box:SetScript("OnTextChanged", function(box)
        f.note:SetText(("%d / %d"):format(#box:GetText(), NOTE_MAX))
    end)
    return f
end

function QH:ShowNoteDialog()
    dialog = dialog or BuildDialog()
    dialog.note:SetText(("0 / %d"):format(NOTE_MAX))
    dialog:Show()
    dialog.box:SetFocus()
end

QH:RegisterCommand("note", "add a personal note to your next entry (/quill note <text>, or no text for a window)", function(text)
    if text and strtrim(text) ~= "" then
        QH:AddNote(text)
    else
        QH:ShowNoteDialog()
    end
end)
