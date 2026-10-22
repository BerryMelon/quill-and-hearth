-- Quill & Hearth: optional Total RP 3 import.
-- Field names verified against the Total RP 3 source (github.com/Total-RP/Total-RP-3):
--   profile.player.characteristics: FN, LN, TI, FT, RA, CL, AG, EC, HE, WE, BP, RE, MI (misc), PS (personality)
--   profile.player.about: TE (template 1-3), T1.TX, T2[i].TX, T3.PH/PS/HI.TX
--   profile.player.character: CU (currently)
local _, QH = ...

local TRP3 = {}
QH.TRP3 = TRP3

local MAX_ABOUT_TEXT = 20000

-- TRP3's built-in personality trait pairs (characteristics.PS[i].ID). English names from TRP3's enUS locale.
local PSYCHO_PRESETS = {
    { "Chaotic", "Lawful" },
    { "Chaste", "Lustful" },
    { "Forgiving", "Vindictive" },
    { "Altruistic", "Selfish" },
    { "Truthful", "Deceitful" },
    { "Gentle", "Brutal" },
    { "Superstitious", "Rational" },
    { "Renegade", "Paragon" },
    { "Cautious", "Impulsive" },
    { "Ascetic", "Bon vivant" },
    { "Valorous", "Spineless" },
}
local PSYCHO_MAX = 20 -- V2 ranges 0..20; V2 is the strength of the LEFT trait.

-- TRP3_API.MiscInfoType -> English name (used when a misc field has no custom name).
local MISC_NAMES = {
    [2] = "House name", [3] = "Nickname", [4] = "Motto", [5] = "Facial features",
    [6] = "Piercings", [7] = "Pronouns", [8] = "Guild name", [9] = "Guild rank",
    [10] = "Tattoos", [11] = "Voice reference",
}

local function Str(v, maxLen)
    if type(v) ~= "string" then return nil end
    v = strtrim(v)
    if v == "" then return nil end
    return QH.Truncate(v, maxLen or 200)
end

local function GetPlayerProfile()
    if not (TRP3_API and TRP3_API.profile and TRP3_API.profile.getPlayerCurrentProfile) then
        return nil
    end
    local ok, profile = pcall(TRP3_API.profile.getPlayerCurrentProfile)
    if ok and type(profile) == "table" and type(profile.player) == "table" then
        return profile
    end
    return nil
end

function TRP3.IsInstalled()
    return C_AddOns.IsAddOnLoaded("totalRP3")
end

--- True once TRP3 is loaded AND has selected a profile for this character.
function TRP3.IsReady()
    return TRP3.IsInstalled() and GetPlayerProfile() ~= nil
end

--- Changes whenever the player edits their TRP3 characteristics or "About" (or switches profile).
function TRP3.GetVersion()
    local profile = GetPlayerProfile()
    if not profile then return nil end
    local c = profile.player.characteristics or {}
    local a = profile.player.about or {}
    local id = TRP3_API.profile.getPlayerCurrentProfileID and TRP3_API.profile.getPlayerCurrentProfileID() or "?"
    return ("%s|%s|%s"):format(tostring(id), tostring(c.v or 0), tostring(a.v or 0))
end

function TRP3.GetProfileName()
    local profile = GetPlayerProfile()
    return profile and Str(profile.profileName)
end

--- Snapshot of the player's current TRP3 profile, as plain data for SavedVariables.
function TRP3.Snapshot()
    local profile = GetPlayerProfile()
    if not profile then return nil end
    local player = profile.player
    local c = player.characteristics or {}

    local data = {
        profileName = Str(profile.profileName),
        firstName = Str(c.FN),
        lastName = Str(c.LN),
        title = Str(c.TI),
        fullTitle = Str(c.FT, 300),
        race = Str(c.RA),
        class = Str(c.CL),
        age = Str(c.AG),
        eyes = Str(c.EC),
        height = Str(c.HE),
        weight = Str(c.WE),
        birthplace = Str(c.BP),
        residence = Str(c.RE),
        version = TRP3.GetVersion(),
        uncut = true,
    }

    if type(c.MI) == "table" then
        local misc = {}
        for _, m in ipairs(c.MI) do
            local name = Str(m.NA) or MISC_NAMES[m.ID]
            local value = Str(m.VA, 1000)
            if name and value then
                table.insert(misc, { name = name, value = value })
            end
        end
        data.misc = #misc > 0 and misc or nil
    end

    if type(c.PS) == "table" then
        local traits = {}
        for _, p in ipairs(c.PS) do
            local left, right
            if p.ID and PSYCHO_PRESETS[p.ID] then
                left, right = PSYCHO_PRESETS[p.ID][1], PSYCHO_PRESETS[p.ID][2]
            else
                left, right = Str(p.LT), Str(p.RT)
            end
            if left and right then
                table.insert(traits, {
                    left = left,
                    right = right,
                    leftStrength = tonumber(p.V2) or (PSYCHO_MAX / 2),
                    max = PSYCHO_MAX,
                })
            end
        end
        data.personality = #traits > 0 and traits or nil
    end

    local a = player.about or {}
    local template = a.TE or 1
    local about = { template = template }
    if template == 1 and type(a.T1) == "table" then
        about.text = Str(a.T1.TX, MAX_ABOUT_TEXT)
    elseif template == 2 and type(a.T2) == "table" then
        local sections = {}
        for _, s in ipairs(a.T2) do
            local tx = Str(s.TX, MAX_ABOUT_TEXT)
            if tx then table.insert(sections, tx) end
        end
        about.sections = #sections > 0 and sections or nil
    elseif template == 3 and type(a.T3) == "table" then
        about.physical = Str(a.T3.PH and a.T3.PH.TX, MAX_ABOUT_TEXT)
        about.personality = Str(a.T3.PS and a.T3.PS.TX, MAX_ABOUT_TEXT)
        about.history = Str(a.T3.HI and a.T3.HI.TX, MAX_ABOUT_TEXT)
    end
    data.about = about

    local ch = player.character or {}
    data.currently = Str(ch.CU, 1500)

    return data
end
