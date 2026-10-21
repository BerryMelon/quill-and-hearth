-- Quill & Hearth: rest detection. A REST marker means "the next entry covers everything up to here".
--
-- A rest happens when the player:
--   * logs out (Logout/Quit, incl. /camp) while in a rested area or near a campfire, or
--   * uses "/quill rest" (or the minimap menu) while resting (writes the marker, opens the journal).
-- Plain /reload does NOT count as resting.
local _, QH = ...

local Safe = QH.Safe

-- Campfire detection.
-- The camp buff lasts long after you walk away, so the buff alone is not enough.
-- When the buff is gained/refreshed (you are sitting at the fire), we remember that spot
-- as the "camp anchor". Campfire rest requires the buff AND being near the anchor.
QH.CAMP_AURA_SPELLS = {}
QH.CAMP_AURA_PATTERNS = { "cozy fire", "campfire", "camp benefits" }
QH.CAMP_RADIUS_YARDS = 20
QH.CAMP_ANCHOR_MAX_AGE = 2 * 60 * 60 -- seconds

local function FindCampAura()
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local spellId = Safe(aura.spellId)
        local name = Safe(aura.name)
        if spellId and QH.CAMP_AURA_SPELLS[spellId] then
            return aura
        end
        if type(name) == "string" then
            local lower = name:lower()
            for _, pattern in ipairs(QH.CAMP_AURA_PATTERNS) do
                if lower:find(pattern, 1, true) then
                    return aura
                end
            end
        end
    end
    return nil
end

--- Player world position in yards: x, y, instanceID (nil if unavailable/restricted).
local function GetWorldPos()
    local y, x, _, instanceID = UnitPosition("player")
    y, x, instanceID = Safe(y), Safe(x), Safe(instanceID)
    if x and y then return x, y, instanceID end

    -- Fallback: map position -> world position.
    local mapID = C_Map.GetBestMapForUnit("player")
    local mapPos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if mapPos then
        local continentID, worldPos = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
        if worldPos then
            local wx, wy = worldPos:GetXY()
            return wx, wy, continentID
        end
    end
    return nil
end

local lastCampExpiration

local function UpdateCampAnchor()
    if not QH.char then return end
    local aura = FindCampAura()
    if not aura then
        lastCampExpiration = nil
        return
    end
    local expiration = Safe(aura.expirationTime) or 0
    -- New buff, or the buff was refreshed (expiration moved forward): we are at a fire now.
    if lastCampExpiration == nil or expiration > lastCampExpiration + 1 then
        local x, y, instanceID = GetWorldPos()
        if x then
            QH.char.state.campAnchor = { x = x, y = y, instanceID = instanceID, t = GetServerTime() }
        end
    end
    lastCampExpiration = expiration
end

QH:On("UNIT_AURA", function(_, unit)
    if unit == "player" then UpdateCampAnchor() end
end)

QH:Listen("READY", function()
    -- Baseline only: don't move an existing anchor just because we logged in with the buff.
    local aura = FindCampAura()
    lastCampExpiration = aura and (Safe(aura.expirationTime) or 0) or nil
end)

--- Distance in yards to the camp anchor, or nil if there is no valid anchor.
function QH:GetCampDistance()
    local anchor = self.char and self.char.state.campAnchor
    if not anchor then return nil end
    if GetServerTime() - (anchor.t or 0) > self.CAMP_ANCHOR_MAX_AGE then return nil end
    local x, y, instanceID = GetWorldPos()
    if not x or (anchor.instanceID and instanceID and anchor.instanceID ~= instanceID) then
        return nil
    end
    local dx, dy = x - anchor.x, y - anchor.y
    return math.sqrt(dx * dx + dy * dy)
end

local function IsAtCampfire()
    if not FindCampAura() then return false end
    local dist = QH:GetCampDistance()
    return dist ~= nil and dist <= QH.CAMP_RADIUS_YARDS
end

--- Returns "rested" (inn/city), "campfire", or nil.
function QH:GetRestKind()
    if IsResting() then return "rested" end
    if IsAtCampfire() then return "campfire" end
    return nil
end

function QH:PushRest(kind, how)
    local last = self:LastEvent()
    if last and last.type == "rest" then
        return -- nothing new happened since the last rest
    end
    self:Push("rest", { kind = kind, how = how, home = GetBindLocation() })
end

---------------------------------------------------------------------------
-- Logout detection (distinguish a real logout from /reload)
---------------------------------------------------------------------------
local loggingOut = false

if type(Logout) == "function" then
    hooksecurefunc("Logout", function() loggingOut = true end)
end
if type(Quit) == "function" then
    hooksecurefunc("Quit", function() loggingOut = true end)
end

QH:On("LOGOUT_CANCEL", function() loggingOut = false end)

QH:On("PLAYER_LOGOUT", function()
    if not loggingOut or not QH.char then return end
    local kind = QH:GetRestKind()
    if kind then
        QH:PushRest(kind, "logout")
    end
end)

---------------------------------------------------------------------------
-- Manual rest: /quill rest
---------------------------------------------------------------------------
StaticPopupDialogs["QUILLANDHEARTH_REST"] = {
    text = "Rest a while and write in your journal?",
    button1 = "Write",
    button2 = CANCEL,
    OnAccept = function()
        local kind = QH:GetRestKind()
        if kind then
            QH:PushRest(kind, "manual")
            QH.Journal:Open() -- the unwritten page is ready to write
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
}

--- Ask to rest and write (used by /quill rest and the minimap menu).
function QH:RequestRest()
    if InCombatLockdown() then
        QH:Print("You can't rest while in combat.")
        return
    end
    if not QH:GetRestKind() then
        QH:Print("You need a safe place to rest before you can write: an inn, a city, or a campfire.")
        return
    end
    StaticPopup_Show("QUILLANDHEARTH_REST")
end

QH:RegisterCommand("rest", "rest and write in your journal (inn, city or campfire)", function()
    QH:RequestRest()
end)

QH:RegisterCommand("restcheck", "debug: show rest state and your current buffs", function()
    QH:Print("IsResting() = " .. tostring(IsResting()) .. ", rest kind = " .. tostring(QH:GetRestKind()))
    local campAura = FindCampAura()
    local dist = QH:GetCampDistance()
    print(("  camp buff: %s | camp spot: %s | distance: %s (max %d)"):format(
        campAura and tostring(Safe(campAura.name)) or "none",
        QH.char and QH.char.state.campAnchor and "remembered" or "none",
        dist and ("%.1f yd"):format(dist) or "n/a",
        QH.CAMP_RADIUS_YARDS))
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        print(("  [%s] %s"):format(tostring(Safe(aura.spellId) or "secret"), tostring(Safe(aura.name) or "secret")))
    end
end)
