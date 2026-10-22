-- Quill & Hearth: onboarding flow (TRP3 import or the manual wizard) and the character profile.
local _, QH = ...

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
function QH:GetProfile()
    return self.char and self.char.profile
end

function QH:SaveProfile(profile, silent)
    local now = GetServerTime()
    local old = self.char.profile
    profile.createdAt = old and old.createdAt or now
    profile.updatedAt = now
    self.char.profile = profile
    if self.SetAISessionStarted then self:SetAISessionStarted(false) end
    if not silent then
        self:Print(("Your journal now knows you as |cffffffff%s|r, %s."):format(profile.name, profile.class))
        if self.Bridge and self.Bridge.ShowSessionSetup then
            self.Bridge:ShowSessionSetup()
        end
    end
    self:Send("PROFILE_UPDATED", profile)
end

function QH:ImportFromTRP3(silent)
    local data = self.TRP3.Snapshot()
    if not data then
        if not silent then
            self:Print("Couldn't read your Total RP 3 profile. Try again in a moment, or use |cffffd100/quill setup|r.")
        end
        return
    end
    local gameName = UnitName("player")
    local gameClass = UnitClass("player")
    local fullName = data.firstName and strtrim(data.firstName .. " " .. (data.lastName or "")) or gameName

    self:SaveProfile({
        source = "trp3",
        name = fullName,
        useGameName = fullName == gameName,
        class = data.class or gameClass,
        useGameClass = data.class == nil or data.class == gameClass,
        trp3 = data,
    }, silent)
    self.char.state.trp3DismissedVersion = nil
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------
StaticPopupDialogs["QUILLANDHEARTH_ONBOARD_TRP3"] = {
    text = "|cffd8b26aQuill & Hearth|r\n\nTotal RP 3 is installed. Import your character sheet (|cffffffff%s|r) so your journal is written in your character's own voice?",
    button1 = "Import",
    button2 = "Set up manually",
    button3 = "Later",
    OnAccept = function() QH:ImportFromTRP3() end,
    OnCancel = function(_, _, reason)
        if reason == "override" or reason == "timeout" then return end
        QH.Wizard:Open()
    end,
    OnAlt = function() QH:Print("No problem. Type |cffffd100/quill setup|r whenever you're ready.") end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

StaticPopupDialogs["QUILLANDHEARTH_ONBOARD"] = {
    text = "|cffd8b26aQuill & Hearth|r\n\nYour character will keep a journal of their adventures, written whenever they rest.\n\nFirst, a few questions about who they are.",
    button1 = "Begin",
    button2 = "Later",
    OnAccept = function() QH.Wizard:Open() end,
    OnCancel = function(_, _, reason)
        if reason == "override" or reason == "timeout" then return end
        QH:Print("No problem. Type |cffffd100/quill setup|r whenever you're ready.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

StaticPopupDialogs["QUILLANDHEARTH_TRP3_CHANGED"] = {
    text = "|cffd8b26aQuill & Hearth|r\n\nYour Total RP 3 profile has changed. Update your journal's character too?",
    button1 = "Update",
    button2 = "Not now",
    OnAccept = function() QH:ImportFromTRP3() end,
    OnCancel = function(_, _, reason)
        if reason == "override" or reason == "timeout" then return end
        QH.char.state.trp3DismissedVersion = QH.TRP3.GetVersion()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

---------------------------------------------------------------------------
-- Flow
---------------------------------------------------------------------------
--- Show the right first step: TRP3 import offer if possible, otherwise the wizard intro.
function QH:StartOnboarding(skipIntro)
    if self.TRP3.IsReady() then
        StaticPopup_Show("QUILLANDHEARTH_ONBOARD_TRP3", self.TRP3.GetProfileName() or UnitName("player"))
    elseif skipIntro then
        self.Wizard:Open()
    else
        StaticPopup_Show("QUILLANDHEARTH_ONBOARD")
    end
end

local function CheckTRP3Changed()
    local profile = QH:GetProfile()
    if not (profile and profile.source == "trp3" and QH.TRP3.IsReady()) then return end
    if not (profile.trp3 and profile.trp3.uncut) then
        -- Upgrade earlier truncated TRP3 snapshots to the full uncut profile automatically.
        QH:ImportFromTRP3(true)
        return
    end
    local current = QH.TRP3.GetVersion()
    local imported = profile.trp3 and profile.trp3.version
    if current and current ~= imported and current ~= QH.char.state.trp3DismissedVersion then
        StaticPopup_Show("QUILLANDHEARTH_TRP3_CHANGED")
    end
end

local attempts = 0
local function CheckOnboarding()
    attempts = attempts + 1
    if InCombatLockdown() then
        C_Timer.After(5, CheckOnboarding)
        return
    end
    -- TRP3 selects its profile during its own startup; give it a few seconds.
    if QH.TRP3.IsInstalled() and not QH.TRP3.IsReady() and attempts < 6 then
        C_Timer.After(2, CheckOnboarding)
        return
    end

    if QH:GetProfile() then
        CheckTRP3Changed()
    else
        QH:StartOnboarding(false)
    end
end

QH:Listen("READY", function()
    C_Timer.After(4, CheckOnboarding)
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
QH:RegisterCommand("setup", "set up (or redo) your character for the journal", function()
    QH:StartOnboarding(true)
end)

QH:RegisterCommand("profile", "show what the journal knows about your character", function()
    local p = QH:GetProfile()
    if not p then
        QH:Print("No character profile yet. Type |cffffd100/quill setup|r.")
        return
    end
    QH:Print(("%s, %s |cff999999(from %s)|r"):format(p.name, p.class, p.source == "trp3" and "Total RP 3" or "setup"))
    if p.traits then
        local t = p.traits
        print(("  %s, %s, %s upbringing. Driven by %s. Writes in a %s voice."):format(
            tostring(t.temperament), tostring(t.outlook), tostring(t.upbringing),
            tostring(t.drive), tostring(t.voice)))
    end
    if p.fear then print("  Fears: " .. p.fear) end
    if p.appearance then print("  Appearance: " .. p.appearance) end
    if p.past then print("  Background: " .. (#p.past > 200 and (p.past:sub(1, 200) .. "...") or p.past)) end
    if p.trp3 then
        local d = p.trp3
        if d.personality then print(("  %d personality traits imported."):format(#d.personality)) end
        local about = d.about or {}
        local hasAbout = about.text or about.sections or about.physical or about.personality or about.history
        print("  About section: " .. (hasAbout and "imported" or "empty"))
    end
end)
