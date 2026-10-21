-- Quill & Hearth: the copy-paste bridge to any AI chat (no companion app needed).
-- WoW can't put text on the clipboard or call an AI itself, so we show the prompt in a
-- selectable text box (Ctrl+C) and take the reply back through another box (Ctrl+V),
-- the same way WeakAuras import/export strings work.
local _, QH = ...

local Bridge = {}
QH.Bridge = Bridge

local WIDTH, HEIGHT = 620, 460

local function CreateTextDialog(name, title, width, height)
    width, height = width or WIDTH, height or HEIGHT
    local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle(title) end
    if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09") end
    table.insert(UISpecialFrames, name)
    f:Hide()

    local inset = f.Inset or f
    f.instructions = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.instructions:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -10)
    f.instructions:SetPoint("RIGHT", inset, "RIGHT", -12, 0)
    f.instructions:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 10)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(width - 80)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Keep the scroll position following the cursor.
    box:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local offset = scroll:GetVerticalScroll()
        local viewHeight = scroll:GetHeight()
        if -y < offset then
            scroll:SetVerticalScroll(-y)
        elseif -y + height > offset + viewHeight then
            scroll:SetVerticalScroll(-y + height - viewHeight)
        end
    end)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)

    -- Clicking anywhere in the text area focuses the box.
    local clickCatcher = CreateFrame("Button", nil, f)
    clickCatcher:SetAllPoints(scroll)
    clickCatcher:SetFrameLevel(scroll:GetFrameLevel() - 1)
    clickCatcher:SetScript("OnClick", function() box:SetFocus() end)

    f.box = box
    f.scroll = scroll

    f.primary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.primary:SetSize(160, 22)
    f.primary:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

    f.secondary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.secondary:SetSize(120, 22)
    f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -8, 0)

    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
    f.note:SetPoint("RIGHT", f.secondary, "LEFT", -8, 0)
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(false)
    return f
end
Bridge.CreateTextDialog = CreateTextDialog

---------------------------------------------------------------------------
-- Step 1: show the prompt for copying
---------------------------------------------------------------------------
function Bridge:ShowPrompt(pending)
    if not self.promptFrame then
        local f = CreateTextDialog("QuillAndHearthPromptDialog", "Copy the prompt")
        f.instructions:SetText("Press |cffffd100Ctrl+C|r to copy, then paste it into any AI chat (ChatGPT, Gemini, Claude...) and send it.")
        f.secondary:SetText("Select all")
        f.secondary:SetScript("OnClick", function()
            f.box:SetFocus()
            f.box:HighlightText()
        end)
        f.primary:SetText("Next: paste the reply")
        f.primary:SetScript("OnClick", function()
            f:Hide()
            Bridge:ShowPaste(Bridge.pending)
        end)
        -- Read-only: undo any typing, keep the text selected for copying.
        f.box:SetScript("OnTextChanged", function(box, userInput)
            if userInput and box:GetText() ~= f.text then
                box:SetText(f.text)
                box:HighlightText()
            end
        end)
        f.box:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
        self.promptFrame = f
    end
    local f = self.promptFrame
    self.pending = pending
    f.text = pending.prompt
    f.box:SetText(pending.prompt)
    f.note:SetText(("%d characters. The text is selected; just press Ctrl+C."):format(#pending.prompt))
    f:Show()
    f.scroll:SetVerticalScroll(0)
    f.box:SetFocus()
    f.box:HighlightText()
end

---------------------------------------------------------------------------
-- Step 2: paste the AI's reply
---------------------------------------------------------------------------
function Bridge:ShowPaste(pending)
    if not self.pasteFrame then
        local f = CreateTextDialog("QuillAndHearthPasteDialog", "Paste the AI's reply")
        f.instructions:SetText("Copy the AI's whole reply, click in the box below and press |cffffd100Ctrl+V|r. Then save it to your journal.")
        f.secondary:SetText("Clear")
        f.secondary:SetScript("OnClick", function()
            f.box:SetText("")
            f.box:SetFocus()
        end)
        f.primary:SetText("Save to journal")
        f.primary:SetScript("OnClick", function()
            local entry, err = QH:SaveWrittenEntry(Bridge.pending, f.box:GetText())
            if not entry then
                f.note:SetText("|cffff5050" .. err .. "|r")
                return
            end
            f.box:SetText("")
            f:Hide()
            QH:Print(('"%s" was written into your journal.'):format(entry.title))
            QH.Journal:Open()
            QH.Journal:Refresh(true)
        end)
        f.box:SetScript("OnTextChanged", function(box)
            local n = #box:GetText()
            f.note:SetText(n > 0 and ("%d characters pasted."):format(n) or "Waiting for the reply...")
        end)
        self.pasteFrame = f
    end
    local f = self.pasteFrame
    self.pending = pending
    f.note:SetText("Waiting for the reply...")
    f:Show()
    f.box:SetFocus()
end
