-- Quill & Hearth: core (namespace, event dispatch, slash commands, init)
local ADDON_NAME, QH = ...

QH.name = ADDON_NAME
QH.title = "Quill & Hearth"
QH.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
QH.ICON = "Interface\\AddOns\\QuillAndHearth\\Media\\Icon"
QH.DB_VERSION = 1

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function QH:Print(...)
    print("|cffd8b26aQuill & Hearth|r:", ...)
end

--- True if the value is a Midnight/Forever "secret value" we must not inspect.
function QH.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

--- Returns v if it is a usable (non-secret) value, else nil.
function QH.Safe(v)
    if QH.IsSecret(v) then return nil end
    return v
end

function QH.Truncate(s, maxLen)
    if type(s) ~= "string" or QH.IsSecret(s) then return nil end
    if s == "" then return nil end
    if #s > maxLen then
        return s:sub(1, maxLen) .. "..."
    end
    return s
end

---------------------------------------------------------------------------
-- Event dispatch (WoW events + internal messages)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

function QH:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

--- Internal messages, e.g. "READY" once the character's data is available.
function QH:Listen(message, fn)
    messageHandlers[message] = messageHandlers[message] or {}
    table.insert(messageHandlers[message], fn)
end

function QH:Send(message, ...)
    local list = messageHandlers[message]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
QH.commands = {}
QH.commandHelp = {}

function QH:RegisterCommand(name, help, fn)
    self.commands[name] = fn
    table.insert(self.commandHelp, { name = name, help = help })
end

local function ShowHelp()
    QH:Print("v" .. QH.version .. " commands:")
    for _, c in ipairs(QH.commandHelp) do
        print(("  |cffffd100/quill %s|r - %s"):format(c.name, c.help))
    end
end

SLASH_QUILLANDHEARTH1 = "/quill"
SLASH_QUILLANDHEARTH2 = "/qh"
SlashCmdList.QUILLANDHEARTH = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local fn = QH.commands[cmd]
    if fn then
        fn(rest)
    elseif cmd == "" and QH.commands.journal then
        QH.commands.journal("")
    else
        ShowHelp()
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
QH:On("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= ADDON_NAME then return end
    QuillAndHearthDB = QuillAndHearthDB or {}
    local db = QuillAndHearthDB
    db.version = db.version or QH.DB_VERSION
    db.characters = db.characters or {}
    QH.db = db
end)

QH:On("PLAYER_LOGIN", function()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    QH.charKey = name .. "-" .. realm
    QH:InitCharacter()
    QH:Send("READY")
end)
