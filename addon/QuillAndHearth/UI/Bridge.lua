-- Quill & Hearth: the copy-paste bridge to any AI chat.
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

    -- Clicking anywhere in the text area (even below a short or empty text) focuses the box.
    -- The scroll frame itself takes the click; the box is its child, so clicks on text still reach the box.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        box:SetFocus()
    end)

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
-- Jobs: what the prompt is and what happens to the pasted reply.
--   job.prompt   text to copy
--   job.save     function(replyText) -> result | nil, errorMessage
--   job.kind     "entry" (tonight's page), "rewrite" (replace an entry), "chapter" (chapter summary)
--   job.select   journal selection to show after saving (entry id or chapter key)
---------------------------------------------------------------------------
function Bridge.PendingJob(pending)
    return {
        kind = "entry",
        prompt = pending.prompt,
        fullPrompt = pending.fullPrompt or pending.prompt,
        sessionPrompt = pending.sessionPrompt or pending.prompt,
        save = function(text) return QH:SaveWrittenEntry(pending, text) end,
    }
end

function Bridge.RewriteJob(entry)
    local profile = QH:GetProfile()
    local name = (profile and profile.name) or (QH.char and QH.char.meta and QH.char.meta.name)
    return {
        kind = "rewrite",
        prompt = entry.prompt,
        fullPrompt = entry.prompt,
        sessionPrompt = QH.Pipeline.ShortenPrompt(entry.prompt, name),
        select = entry.id,
        save = function(text) return QH:RewriteEntry(entry.id, text) end,
    }
end

function Bridge.ChapterJob(chapter)
    return {
        kind = "chapter",
        prompt = QH:GetChapterPrompt(chapter),
        select = "chapter:" .. chapter.key,
        save = function(text) return QH:SaveChapterSummary(chapter.key, text) end,
    }
end

local TEXTS = {
    entry = { title = "Write with AI", save = "Save to journal",
        done = '"%s" was written into your journal.' },
    rewrite = { title = "Rewrite with AI", save = "Replace entry",
        done = 'Your entry was rewritten: "%s".' },
    chapter = { title = "Chapter summary with AI", save = "Save summary",
        done = 'Chapter summary saved: "%s".' },
}

---------------------------------------------------------------------------
-- One window: copy the prompt at the top, paste the reply underneath.
---------------------------------------------------------------------------
local function CreateBox(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, -4)
    bg:SetColorTexture(0, 0, 0, 0.35)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(500)
    box:SetScript("OnEscapePressed", function() parent:Hide() end)
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

    -- Clicking anywhere in the box area (even when it's empty) focuses it.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        box:SetFocus()
    end)
    return scroll, box
end

local function BuildWriteDialog()
    local f = CreateFrame("Frame", "QuillAndHearthWriteDialog", UIParent, "ButtonFrameTemplate")
    f:SetSize(640, 560)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09") end
    table.insert(UISpecialFrames, "QuillAndHearthWriteDialog")
    f:Hide()
    local inset = f.Inset or f

    -- Step 1
    f.step1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.step1:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -10)
    f.step1:SetPoint("RIGHT", inset, "RIGHT", -12, 0)
    f.step1:SetJustifyH("LEFT")
    f.step1:SetText("1. Copy this prompt (|cffffffffCtrl+C|r) and send it to any AI chat (ChatGPT, Gemini, Claude...).")

    f.promptScroll, f.promptBox = CreateBox(f, "QuillAndHearthWritePrompt")
    f.promptScroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -32)
    f.promptScroll:SetPoint("RIGHT", inset, "RIGHT", -30, 0)
    f.promptScroll:SetHeight(150)

    f.selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.selectAll:SetSize(110, 22)
    f.selectAll:SetPoint("TOPRIGHT", f.promptScroll, "BOTTOMRIGHT", 26, -6)
    f.selectAll:SetText("Select all")
    f.selectAll:SetScript("OnClick", function()
        f.promptBox:SetFocus()
        f.promptBox:HighlightText()
    end)

    -- Session toggle: when continuing the same AI chat thread, only send tonight's moments.
    -- Checking this box includes the full rules, uncut character sheet, and story so far.
    f.fullToggle = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.fullToggle:SetSize(22, 22)
    f.fullToggle:SetPoint("TOPLEFT", f.promptScroll, "BOTTOMLEFT", -6, -6)
    f.fullToggleText = f.fullToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.fullToggleText:SetPoint("LEFT", f.fullToggle, "RIGHT", 2, 0)
    f.fullToggleText:SetText("New AI chat / reset session (include full character & rules)")
    f.fullToggle:SetHitRectInsets(0, -f.fullToggleText:GetStringWidth() - 6, 0, 0)
    f.fullToggle:SetScript("OnClick", function(cb)
        local job = Bridge.job
        if not job then return end
        local useFull = cb:GetChecked() and true or false
        QH:SetAISessionStarted(not useFull)
        local text = useFull and (job.fullPrompt or job.prompt) or (job.sessionPrompt or job.prompt)
        f.promptText = text
        f.promptBox:SetText(text)
        f.promptScroll:SetVerticalScroll(0)
        f.promptBox:SetFocus()
        f.promptBox:HighlightText()
    end)
    f.fullToggle:SetScript("OnEnter", function(cb)
        GameTooltip:SetOwner(cb, "ANCHOR_TOP")
        GameTooltip:SetText("AI Chat Session")
        GameTooltip:AddLine("Unchecked: sends only tonight's new moments (best when pasting into the same ongoing AI chat).", 1, 1, 1, true)
        GameTooltip:AddLine("Checked: includes the full rules, uncut character sheet, and story so far (use for a brand-new AI chat or if the AI forgot your character).", 0.9, 0.82, 0.6, true)
        GameTooltip:Show()
    end)
    f.fullToggle:SetScript("OnLeave", GameTooltip_Hide)

    -- Read-only prompt that stays selected.
    f.promptBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput and box:GetText() ~= f.promptText then
            box:SetText(f.promptText)
            box:HighlightText()
        end
    end)
    f.promptBox:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)

    -- Step 2
    f.step2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.step2:SetPoint("TOPLEFT", f.promptScroll, "BOTTOMLEFT", -2, -36)
    f.step2:SetPoint("RIGHT", inset, "RIGHT", -12, 0)
    f.step2:SetJustifyH("LEFT")
    f.step2:SetText("2. Paste the AI's whole reply here (|cffffffffCtrl+V|r). It saves by itself when it's recognised.")

    f.replyScroll, f.replyBox = CreateBox(f, "QuillAndHearthWriteReply")
    f.replyScroll:SetPoint("TOPLEFT", f.step2, "BOTTOMLEFT", 2, -8)
    f.replyScroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 12)

    f.save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.save:SetSize(150, 22)
    f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
    f.note:SetPoint("RIGHT", f.save, "LEFT", -8, 0)
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(false)

    local function TrySave(automatic)
        local job = Bridge.job
        if not job or f.saving then return end
        local text = f.replyBox:GetText()
        if strtrim(text) == "" then
            f.note:SetText("|cffff5050Paste the AI's reply first.|r")
            return
        end
        f.saving = true
        local result, err = job.save(text)
        f.saving = false
        if not result then
            if not automatic then f.note:SetText("|cffff5050" .. err .. "|r") end
            return
        end
        f.replyBox:SetText("")
        f:Hide()
        QH:Print((TEXTS[job.kind] or TEXTS.entry).done:format(result.title or "Untitled"))
        QH.Journal:Open()
        QH.Journal:Refresh(job.select or result.id or true)
    end
    f.save:SetScript("OnClick", function() TrySave(false) end)

    -- C2: a complete reply (TITLE: + ENTRY:) saves itself right after pasting.
    f.replyBox:SetScript("OnTextChanged", function(box, userInput)
        local text = box:GetText()
        if text == "" then
            f.note:SetText("Waiting for the reply...")
            return
        end
        f.note:SetText(("%d characters pasted."):format(#text))
        local lower = text:lower()
        if userInput and lower:find("title%s*:") and lower:find("entry%s*:") then
            C_Timer.After(0.3, function()
                if f:IsShown() and box:GetText() == text then TrySave(true) end
            end)
        end
    end)
    return f
end

--- Open the write dialog for a job (copy the prompt + paste the reply in one window).
function Bridge:Show(job)
    self.dialog = self.dialog or BuildWriteDialog()
    local f = self.dialog
    local texts = TEXTS[job.kind] or TEXTS.entry
    self.job = job
    if f.SetTitle then f:SetTitle(texts.title) end
    f.save:SetText(texts.save)

    local hasSessionModes = job.fullPrompt ~= nil and job.sessionPrompt ~= nil and job.fullPrompt ~= job.sessionPrompt
    f.fullToggle:SetShown(hasSessionModes)
    local useFull = not QH:IsAISessionStarted()
    f.fullToggle:SetChecked(useFull)
    local activePrompt = hasSessionModes and (useFull and job.fullPrompt or job.sessionPrompt) or job.prompt

    f.promptText = activePrompt
    f.promptBox:SetText(activePrompt)
    f.replyBox:SetText("")
    f.note:SetText(job.kind == "rewrite" and "Saving replaces this entry's current text." or "Waiting for the reply...")
    f:Show()
    f.promptScroll:SetVerticalScroll(0)
    f.promptBox:SetFocus()
    f.promptBox:HighlightText()
end

---------------------------------------------------------------------------
-- Standalone AI Session Setup / Reset dialog
---------------------------------------------------------------------------
function Bridge:ShowSessionSetup()
    if not self.setupDialog then
        local f = CreateTextDialog("QuillAndHearthSessionDialog", "AI Chat Session Setup", 640, 480)
        f.instructions:SetText("Copy this setup prompt (|cffffffffCtrl+C|r) into a new ChatGPT, Gemini, or Claude chat. It gives the AI your full, uncut character sheet and rules once, so future prompts only need to send each night's new moments.")
        f.box:SetScript("OnTextChanged", function(box, userInput)
            if userInput and box:GetText() ~= f.promptText then
                box:SetText(f.promptText)
                box:HighlightText()
            end
        end)
        f.box:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)

        f.primary:SetText("Done (session ready)")
        f.primary:SetScript("OnClick", function()
            QH:SetAISessionStarted(true)
            f:Hide()
            QH:Print("AI chat session marked as ready. Next time you write, the prompt will only send that night's new moments.")
        end)
        f.secondary:SetText("Select all")
        f.secondary:SetScript("OnClick", function()
            f.box:SetFocus()
            f.box:HighlightText()
        end)
        self.setupDialog = f
    end

    local f = self.setupDialog
    local text = QH:GetSetupPrompt()
    f.promptText = text
    f.box:SetText(text)
    f.note:SetText(("%d characters (full character sheet + rules)"):format(#text))
    f:Show()
    f.scroll:SetVerticalScroll(0)
    f.box:SetFocus()
    f.box:HighlightText()
end

QH:RegisterCommand("session", "open the initial/reset AI chat session setup prompt", function()
    Bridge:ShowSessionSetup()
end)
