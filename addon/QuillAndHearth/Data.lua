-- Quill & Hearth: per-character storage, event log, pruning
local _, QH = ...

local MAX_EVENTS = 3000 -- safety cap so SavedVariables never grows unbounded

---------------------------------------------------------------------------
-- Character record
---------------------------------------------------------------------------
function QH:InitCharacter()
    local chars = self.db.characters
    local c = chars[self.charKey]
    if not c then
        c = {}
        chars[self.charKey] = c
    end
    c.events = c.events or {}
    c.nextSeq = c.nextSeq or 1
    c.firstVisits = c.firstVisits or {} -- [mapID] = true
    c.state = c.state or {}             -- persistent tracking (lastZone, instance, ...)

    -- Static facts used in the prompt.
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    c.meta = {
        name = UnitName("player"),
        realm = GetNormalizedRealmName(),
        class = (UnitClass("player")),
        classFile = classFile,
        race = (UnitRace("player")),
        raceFile = raceFile,
        sex = UnitSex("player"),
        faction = (UnitFactionGroup("player")),
        level = UnitLevel("player"),
        projectID = WOW_PROJECT_ID,
        build = select(2, GetBuildInfo()),
    }

    self.char = c
    self:PruneProcessed()
end

---------------------------------------------------------------------------
-- Location
---------------------------------------------------------------------------
local function FindContinent(mapID)
    local guard = 0
    while mapID and guard < 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == Enum.UIMapType.Continent then
            return info.mapID, info.name
        end
        mapID = info.parentMapID
        guard = guard + 1
    end
    return nil
end

function QH:GetLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    local continentID, continentName
    if mapID then
        continentID, continentName = FindContinent(mapID)
    end
    local subzone = GetSubZoneText()
    return {
        zone = GetZoneText(),
        subzone = (subzone ~= "" and subzone) or nil,
        mapID = mapID,
        continentID = continentID,
        continent = continentName,
    }
end

---------------------------------------------------------------------------
-- Event log
---------------------------------------------------------------------------
--- Append a story event. `data` fields are copied onto the event.
function QH:Push(eventType, data)
    local c = self.char
    if not c then return end

    local e = data or {}
    e.seq = c.nextSeq
    e.t = GetServerTime()
    e.type = eventType
    e.level = e.level or UnitLevel("player")

    local loc = self:GetLocation()
    e.zone = e.zone or loc.zone
    e.subzone = e.subzone or loc.subzone
    e.mapID = e.mapID or loc.mapID
    e.continent = e.continent or loc.continent

    c.nextSeq = c.nextSeq + 1
    table.insert(c.events, e)

    if #c.events > MAX_EVENTS then
        table.remove(c.events, 1)
    end

    if self.debugLive then
        self:Print(("#%d %s @ %s"):format(e.seq, eventType, e.zone or "?"))
    end
    return e
end

function QH:LastEvent()
    local ev = self.char and self.char.events
    return ev and ev[#ev]
end

--- Remove events that have already been turned into journal entries.
function QH:PruneProcessed()
    local processed = self:GetProcessedThrough()
    if processed <= 0 then return end

    local kept = {}
    for _, e in ipairs(self.char.events) do
        if e.seq > processed then
            table.insert(kept, e)
        end
    end
    local removed = #self.char.events - #kept
    self.char.events = kept
    if removed > 0 then
        self.prunedOnLoad = removed
    end
end
