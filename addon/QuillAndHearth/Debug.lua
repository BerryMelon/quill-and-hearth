-- Quill & Hearth: debug commands
local _, QH = ...

local function Describe(e)
    local t = e.type
    if t == "quest_accept" or t == "quest_done" then
        local extra = {}
        if e.questLine then table.insert(extra, "line: " .. e.questLine) end
        if e.elite then table.insert(extra, "elite") end
        if e.tag then table.insert(extra, e.tag) end
        if e.text or e.rewardText then table.insert(extra, "has text") end
        local suffix = #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or ""
        return ("%s \"%s\"%s"):format(t, tostring(e.title), suffix)
    elseif t == "zone" then
        local s = ("zone %s -> %s"):format(tostring(e.from), tostring(e.zone))
        if e.firstVisit then s = s .. " (first visit)" end
        if e.continentChanged then s = s .. (" (from %s)"):format(tostring(e.fromContinent)) end
        return s
    elseif t == "rest" then
        return ("REST (%s, %s)"):format(tostring(e.kind), tostring(e.how))
    elseif t == "note" then
        return ('note "%s"'):format(tostring(e.text))
    elseif t == "loot" then
        return ("loot %s (%s)"):format(tostring(e.item), tostring(e.quality))
    elseif t == "reputation" then
        return ("reputation %s: %s"):format(tostring(e.faction), tostring(e.standing))
    elseif t == "skill" then
        return ("skill %s -> %s"):format(tostring(e.skill), tostring(e.rank))
    elseif t == "achievement" then
        return ("achievement %s"):format(tostring(e.achievement))
    elseif t == "foe" then
        return ("foe %s (%s)"):format(tostring(e.foe), tostring(e.kind or "foe"))
    elseif t == "death" then
        return e.killer and ("death (by %s)"):format(tostring(e.killer)) or "death"
    elseif t == "spell_learned" then
        return ("spell_learned %s"):format(tostring(e.spell))
    elseif t == "money" then
        return e.kind == "milestone" and ("money milestone (%s)"):format(tostring(e.milestone))
            or ("money spent (%s, left %s)"):format(tostring(e.spent), tostring(e.left))
    elseif t == "level" then
        return "level up -> " .. tostring(e.level)
    elseif t == "flight_start" or t == "flight_end" then
        return ("%s -> %s"):format(t, tostring(e.destination))
    elseif t == "hearth" or t == "bind" then
        return ("%s (%s)"):format(t, tostring(e.home))
    elseif t == "instance_enter" or t == "instance_leave" then
        local n = e.party and #e.party or 0
        return ("%s %s (party: %d)"):format(t, tostring(e.instance), n)
    end
    return t
end

QH:RegisterCommand("status", "show how many moments are recorded", function()
    local c = QH.char
    if not c then return end
    local sinceRest = 0
    for i = #c.events, 1, -1 do
        if c.events[i].type == "rest" then break end
        sinceRest = sinceRest + 1
    end
    QH:Print(("%d events stored, %d since the last rest. Next seq: %d."):format(#c.events, sinceRest, c.nextSeq))
    if QH.prunedOnLoad then
        QH:Print(("%d already-journaled events were cleaned up on load."):format(QH.prunedOnLoad))
    end
end)

QH:RegisterCommand("dump", "list the last N recorded events (default 15)", function(arg)
    local c = QH.char
    if not c then return end
    local n = tonumber(arg) or 15
    local first = math.max(1, #c.events - n + 1)
    QH:Print(("Last %d of %d events:"):format(#c.events - first + 1, #c.events))
    for i = first, #c.events do
        local e = c.events[i]
        print(("  #%d [L%s] %s |cff999999@ %s|r"):format(e.seq, tostring(e.level), Describe(e), tostring(e.zone)))
    end
end)

QH:RegisterCommand("live", "toggle printing each event as it is recorded", function()
    QH.debugLive = not QH.debugLive
    QH:Print("Live event printing " .. (QH.debugLive and "ON" or "OFF"))
end)

StaticPopupDialogs["QUILLANDHEARTH_CLEAR"] = {
    text = "Delete ALL recorded Quill & Hearth events for this character?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if QH.char then
            QH.char.events = {}
            QH:Print("Events cleared.")
        end
    end,
    timeout = 0,
    hideOnEscape = true,
}

QH:RegisterCommand("clear", "debug: delete all recorded events for this character", function()
    StaticPopup_Show("QUILLANDHEARTH_CLEAR")
end)

local SIM_SCENARIOS = {
    {
        questID = 90001,
        title = "Patrol the Old Road",
        giver = "Captain Grayson",
        text = "Bandits have been bold along the milestones since the rains began. Walk the road before dusk and see the way cleared.",
        rewardText = "The road is quieter already. Take this and get yourself something warm by the fire.",
        foe = "Garrick the Cutthroat",
        foeKind = "rare",
    },
    {
        questID = 90002,
        title = "Supplies for the Watchtower",
        giver = "Quartermaster Lewis",
        text = "The north watch has been rationed to hardtack and rain-water. Carry this crate up the ridge before nightfall.",
        rewardText = "You made good time up that mud slope. The watch will sleep better tonight.",
        foe = "Ridgetop Stalker",
        foeKind = "elite",
    },
    {
        questID = 90003,
        title = "Whispers in the Cellar",
        giver = "Innkeeper Farley",
        text = "Something scratched through the old stonework beneath the taproom last night. Take a lantern and see what got in.",
        rewardText = "So that was what kept the hounds barking. First mug tonight is on the house.",
        foe = "Broodmother Skitter",
        foeKind = "rare",
    },
    {
        questID = 90004,
        title = "Lost Courier's Satchel",
        giver = "Marshal Dughan",
        text = "Our rider's mare came back without him from the eastern ford. Find the satchel before the river takes it.",
        rewardText = "Seals unbroken, thank the Light. You've saved us a week of blind marching.",
        foe = "Mirescale Snapper",
        foeKind = "elite",
    },
}

QH:RegisterCommand("sim", "debug: simulate a day of moments + rest and open the journal", function()
    local c = QH.char
    if not c then return end
    c.state.simIndex = ((c.state.simIndex or 0) % #SIM_SCENARIOS) + 1
    local sc = SIM_SCENARIOS[c.state.simIndex]
    local level = (UnitLevel and QH.Safe(UnitLevel("player"))) or 1

    QH:MeetPerson(sc.giver, sc.title)
    QH:Push("quest_accept", {
        questID = sc.questID,
        title = sc.title,
        giver = sc.giver,
        text = sc.text,
        questLevel = level,
    })
    QH:Push("foe", {
        foe = sc.foe,
        kind = sc.foeKind,
        foeLevel = level + 1,
    })
    QH:Push("quest_done", {
        questID = sc.questID,
        title = sc.title,
        giver = sc.giver,
        rewardText = sc.rewardText,
        questLevel = level,
    })

    local rest = QH:Push("rest", {
        kind = "inn",
        how = "sim",
        abilities = QH.TakeAbilitySummary and QH:TakeAbilitySummary() or { "Strike (6)", "Guard (2)" },
        timeOfDay = QH.GetTimeOfDay and QH:GetTimeOfDay() or "night",
        indoors = true,
    })
    QH:Print(('Simulated "%s" (with %s) and rested. Opening journal...'):format(sc.title, sc.giver))
    QH:Send("RESTED", rest)
    if QH.OpenJournal then QH:OpenJournal() end
end)

QH:Listen("READY", function()
    local c = QH.char
    QH:Print(("v%s loaded. %d moments recorded. Type |cffffd100/quill|r for commands."):format(QH.version, #c.events))
end)
