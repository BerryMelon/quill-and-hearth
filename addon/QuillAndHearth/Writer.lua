-- Quill & Hearth: journal entries written in game (copy-paste bridge), and what's still unwritten.
local _, QH = ...

local P = QH.Pipeline

--- In-game journal state for this character (SavedVariables).
function QH:GetJournal()
    local c = self.char
    c.journal = c.journal or {}
    local j = c.journal
    j.entries = j.entries or {}
    j.processedThrough = j.processedThrough or 0
    j.memory = j.memory or ""
    return j
end

local function GeneratedChar()
    local gen = QuillAndHearth_Generated
    return gen and gen.characters and gen.characters[QH.charKey]
end

--- Highest event seq already turned into an entry (by the companion OR in game).
function QH:GetProcessedThrough()
    local gc = GeneratedChar()
    local fromCompanion = gc and gc.processedThrough or 0
    local fromGame = self.char and self:GetJournal().processedThrough or 0
    return math.max(fromCompanion, fromGame)
end

--- All entries (companion-written and in-game), oldest first.
function QH:GetEntries()
    local list = {}
    local gc = GeneratedChar()
    if gc and type(gc.entries) == "table" then
        for _, e in ipairs(gc.entries) do table.insert(list, e) end
    end
    if self.char then
        for _, e in ipairs(self:GetJournal().entries) do table.insert(list, e) end
    end
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return list
end

local function NextDay()
    local day = QH:GetJournal().nextDay or 1
    for _, e in ipairs(QH:GetEntries()) do
        day = math.max(day, (e.dayEnd or e.day or 0) + 1)
    end
    return day
end

--- The unwritten nights: a digest + prompt for every rest not yet written up, or nil.
function QH:GetPendingWrite()
    if not self.char then return nil end
    local sittings = P.FindSittings(self.char.events, self:GetProcessedThrough())
    if #sittings == 0 then return nil end

    local profile = self:GetProfile()
    local digest = P.BuildDigest(sittings, NextDay(), P.DeriveHooks(profile))
    local titles = {}
    local entries = self:GetEntries()
    for i = math.max(1, #entries - 7), #entries do table.insert(titles, entries[i].title) end
    local prompt = P.BuildPrompt(profile, self.char.meta, self:GetJournal().memory, digest, titles)
    return { digest = digest, prompt = prompt, sittings = sittings }
end

--- Save an AI reply (pasted by the player) as the entry for `pending`.
function QH:SaveWrittenEntry(pending, reply)
    local parsed = P.ParseReply(reply)
    if not parsed then return nil, "That doesn't look like a journal entry. Paste the AI's whole reply." end

    local d = pending.digest
    local rest = d.lastRest
    local j = self:GetJournal()
    if rest.seq <= self:GetProcessedThrough() then
        return nil, "Those nights were already written."
    end

    local entry = {
        id = self.charKey .. ":" .. rest.seq,
        restSeq = rest.seq,
        day = d.startDay,
        dayEnd = d.endDay ~= d.startDay and d.endDay or nil,
        title = parsed.title,
        body = parsed.body,
        zone = rest.zone,
        subzone = rest.subzone,
        restKind = rest.kind,
        level = rest.level,
        t = rest.t,
        source = "paste",
    }
    table.insert(j.entries, entry)
    j.processedThrough = rest.seq
    j.nextDay = d.endDay + 1
    if parsed.memory then j.memory = parsed.memory end
    self:Send("ENTRY_WRITTEN", entry)
    return entry
end
