-- Quill & Hearth: AI-driven journal entries (copy-paste bridge), saved-for-later unwritten days,
-- rewrites of existing entries, and sequential day-by-day story continuity.
local _, QH = ...

local P = QH.Pipeline

--- The journal for this character (SavedVariables).
---   entries          written entries ({ id, title, body, prompt, source, ... })
---   processedThrough highest event seq covered by an entry
---   memory           the AI's rolling "story so far"
function QH:GetJournal()
    local c = self.char
    c.journal = c.journal or {}
    local j = c.journal
    j.entries = j.entries or {}
    j.processedThrough = j.processedThrough or 0
    j.memory = j.memory or ""
    if not j.unhidden then
        -- "Hide" was replaced by delete (v0.10.3): bring back anything hidden earlier.
        for _, e in ipairs(j.entries) do e.hidden = nil end
        j.unhidden = true
    end
    return j
end

--- Highest event seq already turned into an entry.
function QH:GetProcessedThrough()
    return self.char and self:GetJournal().processedThrough or 0
end

--- All entries, oldest first.
function QH:GetEntries()
    local list = {}
    if self.char then
        for _, e in ipairs(self:GetJournal().entries) do table.insert(list, e) end
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

--- Oldest saved-for-later entry that hasn't been written with AI yet, or nil.
--- Because each day's prompt needs the STORY SO FAR from the previous day, unwritten entries
--- must be written in chronological order (Day 1 before Day 2).
function QH:GetFirstUnwrittenEntry()
    for _, e in ipairs(self:GetEntries()) do
        if e.unwritten then return e end
    end
    return nil
end

local function FormatDayRange(day, dayEnd)
    if dayEnd and dayEnd ~= day then
        return ("Days %d - %d"):format(day or 1, dayEnd)
    end
    return ("Day %d"):format(day or 1)
end

local function NextDay()
    local day = QH:GetJournal().nextDay or 1
    for _, e in ipairs(QH:GetEntries()) do
        day = math.max(day, (e.dayEnd or e.day or 0) + 1)
    end
    return day
end

--- Options for tonight's writing: the mood picked on the unwritten page, and the length setting.
function QH:GetWriteOptions()
    local ask = self:GetSetting("moodPrompt")
    return {
        mood = ask and self.char.state.pendingMood or nil,
        length = self:GetSetting("length"),
    }
end

function QH:SetPendingMood(mood)
    self.char.state.pendingMood = mood
end

function QH:SetEntryMood(id, mood)
    local target = self:FindEntry(id)
    if not target or not target.unwritten then return end
    target.mood = mood
    if target.opts then target.opts.mood = mood end
end

function QH:IsAISessionStarted()
    return self.char and self.char.state and self.char.state.aiSessionStarted == true or false
end

function QH:SetAISessionStarted(started)
    if not self.char then return end
    self.char.state.aiSessionStarted = started and true or nil
end

local function RecentTitles(entries, beforeId)
    local written = {}
    for _, e in ipairs(entries) do
        if beforeId and e.id == beforeId then break end
        if not e.unwritten and e.title then table.insert(written, e.title) end
    end
    local titles = {}
    for i = math.max(1, #written - 7), #written do table.insert(titles, written[i]) end
    return titles
end

--- Standalone prompt to start or reset an AI chat session with the full character sheet and story so far.
function QH:GetSetupPrompt()
    if not self.char then return "" end
    local titles = RecentTitles(self:GetEntries())
    return P.BuildSetupPrompt(self:GetProfile(), self.char.meta, self:GetJournal().memory, titles, self:GetWriteOptions())
end

--- People in tonight's moments whom the character had already met before these nights.
--- Marks those moments (m.metBefore) and returns a short list for the prompt, or nil.
local function PeopleMetBefore(people, digest, sittings)
    if not people then return nil end
    local firstEvent = sittings[1].events[1]
    local startT = firstEvent and firstEvent.t or digest.lastRest.t
    local current = {}
    for _, thread in ipairs(digest.threads) do
        for _, m in ipairs(thread.moments) do
            if m.title then current[m.title] = true end
        end
    end
    local list, seen = {}, {}
    for _, thread in ipairs(digest.threads) do
        for _, m in ipairs(thread.moments) do
            local p = m.giver and people[m.giver]
            if p and (p.first or 0) < startT then
                m.metBefore = true
                if not seen[m.giver] then
                    seen[m.giver] = true
                    local earlier = {}
                    for _, title in ipairs(p.tasks or {}) do
                        if not current[title] then table.insert(earlier, title) end
                    end
                    table.insert(list, { name = m.giver, zone = p.zone, tasks = earlier })
                end
            end
        end
    end
    return #list > 0 and list or nil
end

--- The unwritten nights: a digest + prompts (full and session-short) for every rest not yet written up, or nil.
--- If an earlier saved-for-later entry is still unwritten (`blockedBy`), prompts are withheld until that earlier
--- day is written so `STORY SO FAR` stays in chronological order.
function QH:GetPendingWrite()
    if not self.char then return nil end
    local sittings = P.FindSittings(self.char.events, self:GetProcessedThrough())
    if #sittings == 0 then return nil end

    local profile = self:GetProfile()
    local digest = P.BuildDigest(sittings, NextDay(), P.DeriveHooks(profile))
    local opts = self:GetWriteOptions()
    opts.people = PeopleMetBefore(self.char.people, digest, sittings)

    local blockedBy = self:GetFirstUnwrittenEntry()
    if blockedBy then
        return {
            digest = digest,
            blockedBy = blockedBy,
            sittings = sittings,
            opts = opts,
        }
    end

    local titles = RecentTitles(self:GetEntries())
    local memory = self:GetJournal().memory
    local fullPrompt = P.BuildPrompt(profile, self.char.meta, memory, digest, titles, opts)
    local sessionOpts = {}
    for k, v in pairs(opts) do sessionOpts[k] = v end
    sessionOpts.session = true
    local sessionPrompt = P.BuildPrompt(profile, self.char.meta, memory, digest, titles, sessionOpts)
    local prompt = self:IsAISessionStarted() and sessionPrompt or fullPrompt
    return {
        digest = digest,
        prompt = prompt,
        fullPrompt = fullPrompt,
        sessionPrompt = sessionPrompt,
        sittings = sittings,
        opts = opts,
    }
end

--- Store a finished entry for `pending` (from a pasted AI reply).
--- The full prompt is kept with the entry so it can be rewritten later (events get pruned).
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
        continent = rest.continent,
        restKind = rest.kind,
        level = rest.level,
        mood = pending.opts and pending.opts.mood or nil,
        t = rest.t,
        source = source,
        prompt = pending.fullPrompt or pending.prompt,
    }
    table.insert(j.entries, entry)
    j.processedThrough = rest.seq
    j.nextDay = d.endDay + 1
    if memory then j.memory = memory end
    QH.char.state.pendingMood = nil
    QH:Send("ENTRY_WRITTEN", entry)
    return entry
end

--- Seal `pending` into the journal as an unwritten ("saved for later") entry so the player can
--- end the day and keep playing without needing an AI chat right now.
function QH:SavePendingForLater(pending)
    if not pending or not pending.digest then return nil, "Nothing is waiting to be saved." end
    local d = pending.digest
    local rest = d.lastRest
    local j = self:GetJournal()
    if rest.seq <= self:GetProcessedThrough() then
        return nil, "Those nights were already saved."
    end

    local dayLabel = FormatDayRange(d.startDay, d.endDay ~= d.startDay and d.endDay or nil)
    local entry = {
        id = self.charKey .. ":" .. rest.seq,
        restSeq = rest.seq,
        day = d.startDay,
        dayEnd = d.endDay ~= d.startDay and d.endDay or nil,
        title = dayLabel .. " (unwritten)",
        unwritten = true,
        digest = d,
        people = pending.opts and pending.opts.people or nil,
        zone = rest.zone,
        subzone = rest.subzone,
        continent = rest.continent,
        restKind = rest.kind,
        level = rest.level,
        mood = pending.opts and pending.opts.mood or nil,
        t = rest.t,
    }
    table.insert(j.entries, entry)
    j.processedThrough = rest.seq
    j.nextDay = d.endDay + 1
    self.char.state.pendingMood = nil
    self:Send("ENTRY_WRITTEN", entry)
    return entry
end

--- Build the AI prompts for a saved-for-later unwritten entry.
--- Only the oldest unwritten entry can generate a prompt, because later days depend on its STORY SO FAR.
function QH:GetUnwrittenEntryPrompts(id)
    local target = self:FindEntry(id)
    if not target or not target.unwritten or not target.digest then
        return nil, "That entry was already written."
    end
    local first = self:GetFirstUnwrittenEntry()
    if first and first.id ~= target.id then
        local firstLabel = FormatDayRange(first.day, first.dayEnd)
        return nil, ("Write %s first so the story so far is ready for this entry."):format(firstLabel), first
    end

    local profile = self:GetProfile()
    local titles = RecentTitles(self:GetEntries(), target.id)
    local askMood = self:GetSetting("moodPrompt")
    local opts = {
        mood = askMood and target.mood or nil,
        length = self:GetSetting("length"),
        people = target.people,
    }
    local memory = self:GetJournal().memory
    local fullPrompt = P.BuildPrompt(profile, self.char.meta, memory, target.digest, titles, opts)
    local sessionOpts = {}
    for k, v in pairs(opts) do sessionOpts[k] = v end
    sessionOpts.session = true
    local sessionPrompt = P.BuildPrompt(profile, self.char.meta, memory, target.digest, titles, sessionOpts)
    local prompt = self:IsAISessionStarted() and sessionPrompt or fullPrompt
    return {
        prompt = prompt,
        fullPrompt = fullPrompt,
        sessionPrompt = sessionPrompt,
    }
end

local BAD_PASTE = "That doesn't look like a journal entry. Paste the AI's whole reply."

--- Save an AI reply (pasted by the player) as the entry for `pending`.
function QH:SaveWrittenEntry(pending, reply)
    local first = self:GetFirstUnwrittenEntry()
    if first then
        return nil, ("Write %s first so the story so far stays in order."):format(FormatDayRange(first.day, first.dayEnd))
    end
    local parsed = P.ParseReply(reply)
    if not parsed then return nil, BAD_PASTE end
    local entry, err = StoreEntry(pending, parsed.title, parsed.body, parsed.memory, "paste")
    if entry then self:SetAISessionStarted(true) end
    return entry, err
end

--- Save an AI reply into a saved-for-later (`unwritten`) entry, unlocking the next unwritten day.
function QH:SaveUnwrittenEntry(id, reply)
    local target = self:FindEntry(id)
    if not target or not target.unwritten then
        return nil, "That entry was already written."
    end
    local prompts, lockErr = self:GetUnwrittenEntryPrompts(id)
    if not prompts then return nil, lockErr end

    local parsed = P.ParseReply(reply)
    if not parsed then return nil, BAD_PASTE end

    target.title = parsed.title
    target.body = parsed.body
    target.source = "paste"
    target.prompt = prompts.fullPrompt
    target.unwritten = nil
    target.digest = nil
    target.people = nil

    if parsed.memory then
        self:GetJournal().memory = parsed.memory
    end
    self:SetAISessionStarted(true)
    self:Send("ENTRY_WRITTEN", target)
    return target
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

    local target = self:FindEntry(id)
    if not target then return nil, "That entry no longer exists." end
    target.title, target.body = parsed.title, parsed.body
    target.source = "paste"
    target.rewrittenAt = GetServerTime()
    if isNewest and parsed.memory then j.memory = parsed.memory end
    self:SetAISessionStarted(true)

    self:Send("ENTRY_WRITTEN", target)
    return target
end

---------------------------------------------------------------------------
-- Your journal, your control: edit, hide, favourite
---------------------------------------------------------------------------
function QH:EditEntry(id, title, body)
    local target = self:FindEntry(id)
    if not target then return nil, "That entry no longer exists." end
    title = strtrim(title or "")
    body = strtrim((body or ""):gsub("\r\n?", "\n") or "")
    if body == "" then return nil, "An entry needs some words." end
    target.title = title ~= "" and title or "Untitled"
    target.body = body
    target.editedAt = GetServerTime()
    self:Send("ENTRY_WRITTEN", target)
    return target
end

function QH:SetEntryFavorite(id, favorite)
    local target = self:FindEntry(id)
    if not target then return end
    target.favorite = favorite or nil
    self:Send("ENTRY_WRITTEN", target)
end

--- Delete an entry for good (its text and its stored prompt). The nights it covered stay written,
--- so they won't come back as an unwritten page. A chapter summary saved on this entry moves to
--- the next entry of the same chapter.
function QH:DeleteEntry(id)
    local j = self:GetJournal()
    local index
    for i, e in ipairs(j.entries) do
        if e.id == id then index = i end
    end
    if not index then return false end

    if j.chapters and j.chapters[id] then
        for _, ch in ipairs(self:GetChapters()) do
            if ch.key == id and ch.entries[2] then
                j.chapters[ch.entries[2].id] = j.chapters[id]
            end
        end
        j.chapters[id] = nil
    end

    local removed = table.remove(j.entries, index)
    QH:Print(('"%s" was deleted.'):format(removed.title or "Untitled"))
    self:Send("ENTRY_WRITTEN")
    return true
end

---------------------------------------------------------------------------
-- Chapters: derived from the entries. A new chapter starts at every new level band
-- (1-9, 10-19, ...) or when the character reaches another continent.
---------------------------------------------------------------------------
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV",
    "XVI", "XVII", "XVIII", "XIX", "XX" }

local function Band(level)
    return level and math.floor(level / 10) or nil
end

--- entries: oldest first. Returns chapters oldest first: { key, number, numeral, entries, title,
--- summary, firstDay, lastDay, zones, minLevel, maxLevel, custom }
function QH:BuildChapters(entries)
    local chapters, current = {}, nil
    for _, e in ipairs(entries) do
        local startNew = current == nil
        if current and not startNew then
            local band = Band(e.level)
            if band and current.band and band > current.band then startNew = true end
            if e.continent and current.continent and e.continent ~= current.continent then startNew = true end
        end
        if startNew then
            current = { key = e.id, entries = {}, band = Band(e.level), continent = e.continent, zones = {}, zoneOrder = {} }
            table.insert(chapters, current)
        end
        table.insert(current.entries, e)
        current.band = current.band or Band(e.level)
        current.continent = current.continent or e.continent
        if e.zone and not current.zones[e.zone] then
            current.zones[e.zone] = 0
            table.insert(current.zoneOrder, e.zone)
        end
        if e.zone then current.zones[e.zone] = current.zones[e.zone] + 1 end
    end

    local saved = self.char and self:GetJournal().chapters or {}
    for i, ch in ipairs(chapters) do
        ch.number = i
        ch.numeral = ROMAN[i] or tostring(i)
        local first, last = ch.entries[1], ch.entries[#ch.entries]
        ch.firstDay = first.day
        ch.lastDay = last.dayEnd or last.day
        for _, e in ipairs(ch.entries) do
            if e.level then
                ch.minLevel = math.min(ch.minLevel or e.level, e.level)
                ch.maxLevel = math.max(ch.maxLevel or e.level, e.level)
            end
        end
        local mainZone, best = nil, -1
        for _, zone in ipairs(ch.zoneOrder) do
            if ch.zones[zone] > best then mainZone, best = zone, ch.zones[zone] end
        end
        ch.mainZone = mainZone
        local custom = saved[ch.key]
        ch.custom = custom
        ch.title = custom and custom.title or (mainZone and ("The Days in " .. mainZone) or "The Road")
        ch.summary = custom and custom.summary or nil
        ch.isOpen = i == #chapters
    end
    return chapters
end

function QH:GetChapters()
    return self:BuildChapters(self:GetEntries())
end

function QH:FindChapter(key)
    for _, ch in ipairs(self:GetChapters()) do
        if ch.key == key then return ch end
    end
    return nil
end

--- The AI prompt to write a chapter's title and summary.
function QH:GetChapterPrompt(chapter)
    return P.BuildChapterPrompt(self:GetProfile(), self.char.meta, chapter)
end

function QH:SaveChapterSummary(key, reply)
    local parsed = P.ParseReply(reply)
    if not parsed then return nil, BAD_PASTE end
    local j = self:GetJournal()
    j.chapters = j.chapters or {}
    j.chapters[key] = { title = parsed.title, summary = parsed.body, t = GetServerTime() }
    self:Send("ENTRY_WRITTEN")
    return self:FindChapter(key)
end
