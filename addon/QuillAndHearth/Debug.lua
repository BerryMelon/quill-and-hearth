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

QH:Listen("READY", function()
    local c = QH.char
    QH:Print(("v%s loaded. %d moments recorded. Type |cffffd100/quill|r for commands."):format(QH.version, #c.events))
end)
