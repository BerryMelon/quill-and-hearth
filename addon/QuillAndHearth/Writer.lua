-- Quill & Hearth: journal entries written in game (copy-paste bridge or template writer),
-- rewrites of existing entries, and what's still unwritten.
local _, QH = ...

local P = QH.Pipeline

--- In-game journal state for this character (SavedVariables).
---   entries          entries written in game ({ id, title, body, prompt, source, ... })
---   overrides[id]    pasted rewrites of companion-written entries ({ title, body, t })
---   processedThrough highest event seq covered by an in-game entry
---   memory           the AI's rolling "story so far"
function QH:GetJournal()
    local c = self.char
    c.journal = c.journal or {}
    local j = c.journal
    j.entries = j.entries or {}
    j.overrides = j.overrides or {}
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

--- All entries (companion-written and in-game), oldest first. Companion entries are copied
--- with any in-game rewrite applied, so the generated data itself is never modified.
function QH:GetEntries()
    local list = {}
    local j = self.char and self:GetJournal()
    local gc = GeneratedChar()
    if gc and type(gc.entries) == "table" then
        for _, e in ipairs(gc.entries) do
            local override = j and e.id and j.overrides[e.id]
            if override then
                local copy = {}
                for k, v in pairs(e) do copy[k] = v end
                copy.title, copy.body, copy.rewritten = override.title, override.body, true
                table.insert(list, copy)
            else
                table.insert(list, e)
            end
        end
    end
    if j then
        for _, e in ipairs(j.entries) do table.insert(list, e) end
    end
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return list
end

function QH:FindEntry(id)
    for i, e in ipairs(self:GetEntries()) do
        if e.id == id then return e, i end
    end
    return nil
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

--- Store a finished entry for `pending` (from a pasted AI reply or the template writer).
--- The prompt is kept with the entry so it can be rewritten later (events get pruned).
local function StoreEntry(pending, title, body, memory, source)
    local d = pending.digest
    local rest = d.lastRest
    local j = QH:GetJournal()
    if rest.seq <= QH:GetProcessedThrough() then
        return nil, "Those nights were already written."
    end

    local entry = {
        id = QH.charKey .. ":" .. rest.seq,
        restSeq = rest.seq,
        day = d.startDay,
        dayEnd = d.endDay ~= d.startDay and d.endDay or nil,
        title = title,
        body = body,
        zone = rest.zone,
        subzone = rest.subzone,
        restKind = rest.kind,
        level = rest.level,
        t = rest.t,
        source = source,
        prompt = pending.prompt,
    }
    table.insert(j.entries, entry)
    j.processedThrough = rest.seq
    j.nextDay = d.endDay + 1
    if memory then j.memory = memory end
    QH:Send("ENTRY_WRITTEN", entry)
    return entry
end

local BAD_PASTE = "That doesn't look like a journal entry. Paste the AI's whole reply."

--- Save an AI reply (pasted by the player) as the entry for `pending`.
function QH:SaveWrittenEntry(pending, reply)
    local parsed = P.ParseReply(reply)
    if not parsed then return nil, BAD_PASTE end
    return StoreEntry(pending, parsed.title, parsed.body, parsed.memory, "paste")
end

--- Write the entry for `pending` with the in-game template writer (no AI).
function QH:WriteTemplateEntry(pending)
    local written = QH.Templates.Write(pending.digest, self:GetProfile())
    -- Keep the AI's "story so far" roughly current, so a later AI entry knows these days happened.
    local d = pending.digest
    local memory = strtrim((self:GetJournal().memory or "") .. (" Days %d-%d near %s: %s."):format(
        d.startDay, d.endDay, d.lastRest.zone or "the road", written.title))
    if #memory > 900 then memory = "..." .. memory:sub(-900) end
    return StoreEntry(pending, written.title, written.body, memory, "template")
end

--- Replace an existing entry with a newly pasted AI version (from the entry's stored prompt).
--- The story memory is only updated when rewriting the newest entry, so older rewrites
--- can't rewind the story.
function QH:RewriteEntry(id, reply)
    local parsed = P.ParseReply(reply)
    if not parsed then return nil, BAD_PASTE end

    local j = self:GetJournal()
    local entries = self:GetEntries()
    local isNewest = entries[#entries] and entries[#entries].id == id

    local target
    for _, e in ipairs(j.entries) do
        if e.id == id then target = e end
    end
    if target then
        target.title, target.body = parsed.title, parsed.body
        target.source = "paste"
        target.rewrittenAt = GetServerTime()
    else
        if not self:FindEntry(id) then return nil, "That entry no longer exists." end
        j.overrides[id] = { title = parsed.title, body = parsed.body, t = GetServerTime() }
    end
    if isNewest and parsed.memory then j.memory = parsed.memory end

    local entry = self:FindEntry(id)
    self:Send("ENTRY_WRITTEN", entry)
    return entry
end
