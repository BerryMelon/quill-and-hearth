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

--- Name of the NPC (or object) the quest dialog belongs to, if it's a usable value.
local function QuestGiver()
    local name = Safe(UnitName("questnpc")) or Safe(UnitName("npc"))
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

--- Remember people the character dealt with (for the prompt's story memory and the People page).
function QH:MeetPerson(name, questTitle)
    if not (name and self.char) then return end
    local people = self.char.people or {}
    self.char.people = people
    local p = people[name]
    if not p then
        local loc = self:GetLocation()
        p = { first = GetServerTime(), zone = loc.subzone and (loc.subzone .. ", " .. (loc.zone or "")) or loc.zone, tasks = {}, count = 0 }
        people[name] = p
    end
    p.count = p.count + 1
    p.last = GetServerTime()
    if questTitle then
        for _, t in ipairs(p.tasks) do if t == questTitle then return end end
        table.insert(p.tasks, questTitle)
        if #p.tasks > 6 then table.remove(p.tasks, 1) end
    end
end

QH:On("QUEST_DETAIL", function()
    pendingDetail = {
        questID = GetQuestID(),
        title = Safe(GetTitleText()),
        text = Truncate(GetQuestText(), QUEST_TEXT_MAX),
        objectives = Truncate(GetObjectiveText(), 400),
        giver = QuestGiver(),
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
        e.giver = pendingDetail.giver
    end
    pendingDetail = nil

    Merge(e, GetQuestFacts(questID))
    QH:MeetPerson(e.giver, e.title)
    QH:Push("quest_accept", e)
end)

QH:On("QUEST_COMPLETE", function()
    local questID = GetQuestID()
    pendingComplete = {
        questID = questID,
        title = Safe(GetTitleText()),
        rewardText = Truncate(GetRewardText(), QUEST_TEXT_MAX),
        facts = questID and GetQuestFacts(questID) or {},
        giver = QuestGiver(),
    }
end)

QH:On("QUEST_TURNED_IN", function(_, questID)
    local e = { questID = questID, title = C_QuestLog.GetTitleForQuestID(questID) }
    if pendingComplete and pendingComplete.questID == questID then
        e.title = e.title or pendingComplete.title
        e.rewardText = pendingComplete.rewardText
        e.giver = pendingComplete.giver
        Merge(e, pendingComplete.facts)
    end
    pendingComplete = nil
    e.party = GetParty()
    QH:MeetPerson(e.giver, e.title)
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
        QH:Push("instance_enter", { instance = name, instanceType = instanceType, party = GetParty(),
            first = QH:MarkFirst("dungeon") or nil })
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
    QH:Push("death", { first = QH:MarkFirst("death") or nil })
end)

--- True the first time this kind of thing ever happens to the character (for reflections).
function QH:MarkFirst(kind)
    local s = self.char and self.char.state
    if not s then return false end
    s.firsts = s.firsts or {}
    if s.firsts[kind] then return false end
    s.firsts[kind] = true
    return true
end

---------------------------------------------------------------------------
-- More moments: notable loot, reputation, profession milestones, achievements
---------------------------------------------------------------------------
--- Turn a Blizzard format string ("You receive loot: %s.") into a Lua pattern.
local function PatternFrom(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

QH.PatternFrom = PatternFrom -- exposed for tests

local LOOT_PATTERNS = {}
for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF" }) do
    local p = PatternFrom(_G[key])
    if p then table.insert(LOOT_PATTERNS, p) end
end
local QUALITY_NAMES = { [3] = "rare", [4] = "epic", [5] = "legendary", [6] = "artifact" }

QH:On("CHAT_MSG_LOOT", function(_, msg)
    msg = Safe(msg)
    if type(msg) ~= "string" then return end
    for _, pattern in ipairs(LOOT_PATTERNS) do
        local link = msg:match(pattern)
        if link then
            local itemString = link:match("|H(item:[^|]+)|h")
            local name = link:match("|h%[(.-)%]|h")
            local quality = itemString and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemString)
            if name and quality and quality >= 3 then
                QH:Push("loot", { item = name, quality = QUALITY_NAMES[quality] or "rare", qualityNum = quality })
            end
            return
        end
    end
end)

local STANDING_PATTERN = PatternFrom(_G.FACTION_STANDING_CHANGED) -- "You are now %s with %s."
QH:On("CHAT_MSG_SYSTEM", function(_, msg)
    msg = Safe(msg)
    if type(msg) ~= "string" or not STANDING_PATTERN then return end
    local standing, faction = msg:match(STANDING_PATTERN)
    if standing and faction then
        QH:Push("reputation", { standing = standing, faction = faction })
    end
end)

local SKILL_PATTERN = PatternFrom(_G.SKILL_RANK_UP) -- "Your skill in %s has increased to %d."
QH:On("CHAT_MSG_SKILL", function(_, msg)
    msg = Safe(msg)
    if type(msg) ~= "string" or not SKILL_PATTERN then return end
    local skill, rank = msg:match(SKILL_PATTERN)
    rank = tonumber(rank)
    if skill and rank and rank % 25 == 0 then
        QH:Push("skill", { skill = skill, rank = rank })
    end
end)

QH:On("ACHIEVEMENT_EARNED", function(_, achievementID)
    if not GetAchievementInfo then return end
    local _, name = GetAchievementInfo(achievementID)
    name = Safe(name)
    if name then QH:Push("achievement", { achievement = name }) end
end)
