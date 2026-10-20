-- Quill & Hearth: story event capture (non-combat only; Forever restricts combat data)
local _, QH = ...

local Safe, Truncate = QH.Safe, QH.Truncate

local QUEST_TEXT_MAX = 1200
local HEARTHSTONE_SPELLS = { [8690] = true }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function GetParty()
    if not IsInGroup() then return nil end
    local members = {}
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, count do
        local unit = prefix .. i
        if not UnitIsUnit(unit, "player") then
            local name = Safe(UnitName(unit))
            local className = Safe((UnitClass(unit)))
            if name then
                table.insert(members, { name = name, class = className })
            end
        end
    end
    return #members > 0 and members or nil
end

--- Extra quest facts from the quest log (only while the quest is still in the log).
local function GetQuestFacts(questID)
    local facts = {}
    local mapID = C_Map.GetBestMapForUnit("player")

    if C_QuestLine and C_QuestLine.GetQuestLineInfo and mapID then
        local ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID, mapID)
        if ok and type(info) == "table" then
            facts.questLineID = info.questLineID
            facts.questLine = info.questLineName
        end
    end

    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if index then
        local info = C_QuestLog.GetInfo(index)
        if info then
            facts.questLevel = info.level
            facts.suggestedGroup = (info.suggestedGroup or 0) > 0 and info.suggestedGroup or nil
            facts.frequency = (info.frequency or 0) > 0 and info.frequency or nil -- 1 daily, 2 weekly
        end
    end

    if C_QuestLog.GetQuestTagInfo then
        local tag = C_QuestLog.GetQuestTagInfo(questID)
        if tag and tag.tagName then facts.tag = tag.tagName end
    end

    if C_QuestLog.IsEliteQuest then -- Forever-specific API
        local ok, elite = pcall(C_QuestLog.IsEliteQuest, questID)
        if ok and elite then facts.elite = true end
    end

    return facts
end

local function Merge(into, from)
    for k, v in pairs(from) do into[k] = v end
    return into
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local pendingDetail   -- text seen in the quest-giver dialog (QUEST_DETAIL)
local pendingComplete -- text seen in the turn-in dialog (QUEST_COMPLETE)

QH:On("QUEST_DETAIL", function()
    pendingDetail = {
        questID = GetQuestID(),
        title = Safe(GetTitleText()),
        text = Truncate(GetQuestText(), QUEST_TEXT_MAX),
        objectives = Truncate(GetObjectiveText(), 400),
    }
end)

QH:On("QUEST_ACCEPTED", function(_, ...)
    local questID = select(select("#", ...), ...) -- last arg is questID across API versions
    if type(questID) ~= "number" then return end

    local e = {
        questID = questID,
        title = C_QuestLog.GetTitleForQuestID(questID),
    }
    if pendingDetail and pendingDetail.questID == questID then
        e.title = e.title or pendingDetail.title
        e.text = pendingDetail.text
        e.objectives = pendingDetail.objectives
    end
    pendingDetail = nil

    Merge(e, GetQuestFacts(questID))
    QH:Push("quest_accept", e)
end)

QH:On("QUEST_COMPLETE", function()
    local questID = GetQuestID()
    pendingComplete = {
        questID = questID,
        title = Safe(GetTitleText()),
        rewardText = Truncate(GetRewardText(), QUEST_TEXT_MAX),
        facts = questID and GetQuestFacts(questID) or {},
    }
end)

QH:On("QUEST_TURNED_IN", function(_, questID)
    local e = { questID = questID, title = C_QuestLog.GetTitleForQuestID(questID) }
    if pendingComplete and pendingComplete.questID == questID then
        e.title = e.title or pendingComplete.title
        e.rewardText = pendingComplete.rewardText
        Merge(e, pendingComplete.facts)
    end
    pendingComplete = nil
    e.party = GetParty()
    QH:Push("quest_done", e)
end)

---------------------------------------------------------------------------
-- Zones, continents, instances
---------------------------------------------------------------------------
local function CheckZone()
    local c = QH.char
    if not c then return end
    local loc = QH:GetLocation()
    if not loc.zone or loc.zone == "" then return end

    local s = c.state
    if s.lastZone ~= loc.zone then
        local firstVisit = loc.mapID and not c.firstVisits[loc.mapID] or false
        local continentChanged = s.lastContinent ~= nil and loc.continent ~= nil
            and s.lastContinent ~= loc.continent
        if s.lastZone then -- skip the very first baseline
            QH:Push("zone", {
                from = s.lastZone,
                fromContinent = continentChanged and s.lastContinent or nil,
                firstVisit = firstVisit or nil,
                continentChanged = continentChanged or nil,
            })
        end
        if loc.mapID then c.firstVisits[loc.mapID] = true end
        s.lastZone = loc.zone
        s.lastContinent = loc.continent or s.lastContinent
    end
end

local function CheckInstance()
    local c = QH.char
    if not c then return end
    local inInstance, instanceType = IsInInstance()
    local dungeonLike = inInstance and (instanceType == "party" or instanceType == "raid")
    local s = c.state

    if dungeonLike and not s.instance then
        local name = GetInstanceInfo()
        s.instance = name
        QH:Push("instance_enter", { instance = name, instanceType = instanceType, party = GetParty() })
    elseif not dungeonLike and s.instance then
        QH:Push("instance_leave", { instance = s.instance })
        s.instance = nil
    end
end

QH:On("ZONE_CHANGED_NEW_AREA", function()
    C_Timer.After(1, CheckZone)
end)

QH:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(1.5, function()
        CheckZone()
        CheckInstance()
    end)
end)

---------------------------------------------------------------------------
-- Travel: flight paths, hearthstone, new home
---------------------------------------------------------------------------
local onTaxi = false
local taxiDestination

if type(TakeTaxiNode) == "function" then
    hooksecurefunc("TakeTaxiNode", function(index)
        taxiDestination = TaxiNodeName and TaxiNodeName(index) or nil
    end)
end

QH:On("PLAYER_CONTROL_LOST", function()
    C_Timer.After(0.5, function()
        if UnitOnTaxi("player") and not onTaxi then
            onTaxi = true
            QH:Push("flight_start", { destination = taxiDestination })
        end
    end)
end)

QH:On("PLAYER_CONTROL_GAINED", function()
    if onTaxi then
        onTaxi = false
        QH:Push("flight_end", { destination = taxiDestination })
        taxiDestination = nil
    end
end)

QH:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit ~= "player" then return end
    spellID = Safe(spellID)
    if spellID and HEARTHSTONE_SPELLS[spellID] then
        QH:Push("hearth", { home = GetBindLocation() })
    end
end)

QH:On("HEARTHSTONE_BOUND", function()
    QH:Push("bind", { home = GetBindLocation() })
end)

---------------------------------------------------------------------------
-- Growth & hardship
---------------------------------------------------------------------------
QH:On("PLAYER_LEVEL_UP", function(_, newLevel)
    QH:Push("level", { level = newLevel })
end)

QH:On("PLAYER_DEAD", function()
    QH:Push("death", {})
end)
