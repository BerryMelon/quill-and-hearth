-- Quill & Hearth: in-game story pipeline (Lua port of the companion's pipeline).
-- Turns recorded events into a story-shaped digest and an LLM prompt, so a journal entry can be
-- written WITHOUT the companion app (copy the prompt into any AI chat, paste the reply back).
--
-- Coherence rules (same as the companion):
--   * moments are grouped into storylines (quest line, otherwise zone), not play order
--   * travel is kept as an ordered journey so jumps between places can be narrated
--   * an in-character calendar: a rest is a night, a voyage to another continent takes days
--   * small errands are collapsed into one line
local _, QH = ...

local P = {}
QH.Pipeline = P

P.VOYAGE_DAYS = 4
P.IDLE_GAP_SECONDS = 6 * 60 * 60
P.KEY_THRESHOLD = 5
P.MINOR_THRESHOLD = 2
P.MAX_KEY_MOMENTS = 6

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
function P.Clean(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"):gsub("{[^}]*}", "")
    s = s:gsub("\r\n?", "\n"):gsub("[ \t]+", " "):gsub("\n\n\n+", "\n\n")
    s = strtrim(s)
    if s == "" then return nil end
    maxLen = maxLen or 600
    if #s > maxLen then
        s = (s:sub(1, maxLen):gsub("%s+%S*$", "")) .. "..."
    end
    return s
end

local function OneLine(s)
    return s and (s:gsub("%s*\n+%s*", " ")) or nil
end

local function PlaceOf(e)
    if e.subzone and e.zone and e.subzone ~= e.zone then
        return e.subzone .. ", " .. e.zone
    end
    return e.zone or e.subzone or "somewhere"
end

local function EscapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

---------------------------------------------------------------------------
-- Hooks: words that make an event personally meaningful (fears, goals, ...)
---------------------------------------------------------------------------
local STOPWORDS = {
    the = true, a = true, an = true, of = true, ["and"] = true, ["or"] = true, to = true, in_ = true,
    being = true, getting = true, with = true, from = true, that = true, this = true, very = true,
    afraid = true, fear = true, fears = true, scared = true, terrified = true, deep = true, ["in"] = true,
}

--- Derive keyword hooks from the free-text fields the player gave us.
function P.DeriveHooks(profile)
    local hooks, seen = {}, {}
    local function addWords(text)
        if type(text) ~= "string" then return end
        for word in text:lower():gmatch("%a+") do
            if #word >= 3 and not STOPWORDS[word] then
                local stem = word:gsub("ies$", "y"):gsub("([^s])s$", "%1")
                if not seen[stem] then
                    seen[stem] = true
                    table.insert(hooks, stem)
                end
            end
        end
    end
    if profile then
        addWords(profile.fear)
        if profile.trp3 then
            for _, m in ipairs(profile.trp3.misc or {}) do
                if m.name and m.name:lower():find("fear") then addWords(m.value) end
            end
        end
    end
    return hooks
end

local function MatchHooks(text, hooks)
    local matched = {}
    if text == "" then return matched end
    for _, hook in ipairs(hooks) do
        if text:find("%f[%a]" .. EscapePattern(hook)) then
            table.insert(matched, hook)
        end
    end
    return matched
end

---------------------------------------------------------------------------
-- Sittings: events between rests that haven't been written up yet
---------------------------------------------------------------------------
function P.FindSittings(events, processedThrough)
    local sittings, current = {}, {}
    for _, e in ipairs(events or {}) do
        if e.seq > processedThrough then
            if e.type == "rest" then
                table.insert(sittings, { events = current, rest = e })
                current = {}
            else
                table.insert(current, e)
            end
        end
    end
    return sittings
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function TextOf(e)
    local parts = {}
    for _, k in ipairs({ "title", "text", "objectives", "rewardText", "questLine", "instance", "zone" }) do
        if type(e[k]) == "string" then table.insert(parts, e[k]) end
    end
    return table.concat(parts, " "):lower()
end

function P.Score(e, hooks)
    local score, reasons = 0, {}
    local function add(n, why)
        score = score + n
        table.insert(reasons, why)
    end
    local t = e.type
    if t == "quest_done" then
        add(1, "quest completed")
        local reward = e.rewardText and #e.rewardText or 0
        if reward > 80 then add(1, "has a story") end
        if e.questLine then add(2, "part of a quest line") end
        if e.elite or e.tag == "Elite" then add(2, "elite") end
        if (e.suggestedGroup or 0) > 1 or e.tag == "Group" or e.tag == "Dungeon" then add(2, "group quest") end
        if reward > 200 then add(1, "rich story text") end
        if e.party then add(1, "with companions") end
        if e.frequency then add(-3, "repeatable") end
    elseif t == "quest_accept" then
        add(1, "quest accepted")
        if e.text then add(1, "has a story") end
    elseif t == "zone" then
        if e.continentChanged then add(5, "crossed to another continent") end
        if e.firstVisit then add(3, "first visit") end
    elseif t == "instance_enter" then
        add(6, "entered a dungeon")
    elseif t == "death" then
        add(5, "died")
    elseif t == "level" then
        if (e.level or 0) % 10 == 0 then add(5, "level milestone") else add(2, "grew stronger") end
    elseif t == "bind" then
        add(3, "found a new home")
    elseif t == "note" then
        add(10, "the player's own note")
    elseif t == "hearth" or t == "flight_start" or t == "flight_end" or t == "instance_leave" then
        add(1, "travel")
    end

    local touched = MatchHooks(TextOf(e), hooks)
    if #touched > 0 then add(5, "touches the character") end
    return score, touched
end

---------------------------------------------------------------------------
-- Digest
---------------------------------------------------------------------------
local function JourneyText(e, skipDays)
    local t = e.type
    if t == "zone" then
        if e.continentChanged then
            return ("Voyaged from %s to %s, arriving in %s (about %d days at sea or in the air)")
                :format(e.fromContinent or e.from or "afar", e.continent or "a new land", e.zone or "?", skipDays or P.VOYAGE_DAYS)
        end
        return ("Travelled from %s into %s%s"):format(e.from or "?", e.zone or "?", e.firstVisit and " (first time here)" or "")
    elseif t == "flight_start" then
        return ("Took a flight%s from %s"):format(e.destination and (" toward " .. e.destination) or "", PlaceOf(e))
    elseif t == "flight_end" then
        return "Landed at " .. PlaceOf(e)
    elseif t == "hearth" then
        return "Used a hearthstone to return home to " .. (e.home or "the inn")
    elseif t == "bind" then
        return ("Made %s their new home"):format(e.home or PlaceOf(e))
    elseif t == "instance_enter" then
        return "Entered " .. (e.instance or "a dungeon")
    elseif t == "instance_leave" then
        return "Left " .. (e.instance or "the dungeon")
    end
    return nil
end

--- Build one digest covering all given sittings (several rests become several nights).
function P.BuildDigest(sittings, startDay, hooks)
    local day = startDay
    local threads, threadOrder = {}, {}
    local journey, background = {}, {}
    local backgroundOrder = {}

    -- Quest story is on the accept event, the outcome on the turn-in.
    local acceptByQuest, doneQuests = {}, {}
    for _, sitting in ipairs(sittings) do
        for _, e in ipairs(sitting.events) do
            if e.type == "quest_accept" and e.questID then acceptByQuest[e.questID] = e end
            if e.type == "quest_done" and e.questID then doneQuests[e.questID] = true end
        end
    end

    -- First pass: score everything, pick the top key moments.
    local all = {}
    for _, sitting in ipairs(sittings) do
        for _, e in ipairs(sitting.events) do
            local score, touched = P.Score(e, hooks)
            table.insert(all, { e = e, score = score, touched = touched })
        end
    end
    local candidates = {}
    for _, s in ipairs(all) do
        if s.score >= P.KEY_THRESHOLD then table.insert(candidates, s) end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.e.seq < b.e.seq
    end)
    local isKey = {}
    for i = 1, math.min(#candidates, P.MAX_KEY_MOMENTS) do isKey[candidates[i].e.seq] = true end
    -- The player's own notes are always key moments, outside the cap.
    for _, s in ipairs(all) do
        if s.e.type == "note" then isKey[s.e.seq] = true end
    end
    local bySeq = {}
    for _, s in ipairs(all) do bySeq[s.e.seq] = s end

    for si, sitting in ipairs(sittings) do
        if si > 1 then day = day + 1 end -- the previous rest was a night's sleep
        local prevT
        for _, e in ipairs(sitting.events) do
            local skipDays
            if e.type == "zone" and e.continentChanged then
                day = day + P.VOYAGE_DAYS
                skipDays = P.VOYAGE_DAYS
            elseif prevT and e.t - prevT > P.IDLE_GAP_SECONDS then
                day = day + 1
            end
            prevT = e.t

            local travel = JourneyText(e, skipDays)
            if travel then table.insert(journey, { day = day, text = travel, event = e }) end

            local s = bySeq[e.seq]
            local importance = isKey[e.seq] and "KEY" or (s.score >= P.MINOR_THRESHOLD and "MINOR" or nil)
            local foldedAccept = e.type == "quest_accept" and e.questID and doneQuests[e.questID]

            if foldedAccept then
                -- shown with its turn-in
            elseif not importance then
                if e.type == "quest_done" then
                    local zone = e.zone or "the area"
                    if not background[zone] then table.insert(backgroundOrder, zone) end
                    background[zone] = (background[zone] or 0) + 1
                end
            elseif travel and importance ~= "KEY" and e.type ~= "zone" then
                -- plain travel is already in the journey
            else
                local accept = e.questID and acceptByQuest[e.questID]
                local m = {
                    seq = e.seq,
                    day = day,
                    importance = importance,
                    place = PlaceOf(e),
                    touched = s.touched,
                }
                if e.type == "quest_done" then
                    m.kind = "completed a task"
                    m.title = e.title
                    m.story = P.Clean(accept and accept.text or e.text)
                    m.outcome = P.Clean(e.rewardText, 400)
                elseif e.type == "quest_accept" then
                    m.kind = "took on a task (NOT finished yet)"
                    m.title = e.title
                    m.story = P.Clean(e.text)
                elseif e.type == "level" then
                    m.kind = "grew stronger"
                    m.title = ("Reached level %d"):format(e.level or 0)
                elseif e.type == "zone" then
                    m.kind = "arrived"
                    m.title = e.continentChanged and ("Arrived in " .. (e.continent or "a new land")) or ("First time in " .. (e.zone or "?"))
                elseif e.type == "death" then
                    m.kind = "was struck down"
                elseif e.type == "note" then
                    m.kind = "personal note (the player's own words)"
                    m.note = P.Clean(e.text, 500)
                elseif e.type == "instance_enter" then
                    m.kind = "entered a dungeon"
                    m.title = e.instance
                else
                    m.kind = e.type
                    m.title = e.title or e.instance
                end
                if e.party then
                    m.companions = {}
                    for _, p in ipairs(e.party) do
                        table.insert(m.companions, p.class and (p.name .. " (" .. p.class .. ")") or p.name)
                    end
                end

                local threadName = e.questLine or e.zone or "Wandering"
                if not threads[threadName] then
                    threads[threadName] = { name = threadName, moments = {} }
                    table.insert(threadOrder, threadName)
                end
                table.insert(threads[threadName].moments, m)
            end
        end
    end

    local collapsed = {}
    for _, zone in ipairs(backgroundOrder) do
        local n = background[zone]
        table.insert(collapsed, n == 1 and ("One small errand around " .. zone)
            or ("%d small errands and odd jobs around %s"):format(n, zone))
    end

    local orderedThreads = {}
    for _, name in ipairs(threadOrder) do table.insert(orderedThreads, threads[name]) end

    local lastRest = sittings[#sittings].rest
    return {
        startDay = startDay,
        endDay = day,
        nights = #sittings,
        restPlace = PlaceOf(lastRest),
        restKind = lastRest.kind,
        lastRest = lastRest,
        threads = orderedThreads,
        journey = journey,
        collapsed = collapsed,
        isEmpty = #orderedThreads == 0 and #collapsed == 0 and #journey == 0,
    }
end

---------------------------------------------------------------------------
-- Character description
---------------------------------------------------------------------------
function P.DescribeCharacter(profile, meta)
    local lines = {}
    local function add(label, value)
        value = P.Clean(value, 400)
        if value then table.insert(lines, label .. ": " .. OneLine(value)) end
    end
    local gender = meta and (meta.sex == 3 and "female" or meta.sex == 2 and "male") or nil
    add("Name", profile and profile.name or meta and meta.name)
    local race = profile and profile.trp3 and profile.trp3.race or meta and meta.race
    add("Race", race and (race .. (gender and (" (" .. gender .. ")") or "")))
    add("Class / calling", profile and profile.class or meta and meta.class)
    add("Faction", meta and meta.faction)

    local t = profile and profile.traits
    if t then
        add("Temperament", t.temperament)
        add("Outlook", t.outlook)
        add("Upbringing", t.upbringing)
        add("Driven by", t.drive)
        add("Way with words", t.voice)
    end
    if profile then
        add("Fears", profile.fear)
        add("Past", profile.past)
    end

    local d = profile and profile.trp3
    if d then
        add("Title", d.fullTitle or d.title)
        add("Age", d.age)
        add("Eyes", d.eyes)
        add("Height", d.height)
        add("Build", d.weight)
        add("Birthplace", d.birthplace)
        add("Residence", d.residence)
        for _, m in ipairs(d.misc or {}) do add(m.name, m.value) end
        for _, p in ipairs(d.personality or {}) do
            local leftPct = math.floor((p.leftStrength or 10) / (p.max or 20) * 100 + 0.5)
            table.insert(lines, ("Personality: %d%% %s / %d%% %s"):format(leftPct, p.left, 100 - leftPct, p.right))
        end
        local a = d.about
        if a then
            add("About", a.text)
            for i, s in ipairs(a.sections or {}) do add("About (part " .. i .. ")", s) end
            add("Appearance", a.physical)
            add("Personality notes", a.personality)
            add("History", a.history)
        end
        add("Currently", d.currently)
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Prompt
---------------------------------------------------------------------------
local RULES = [[You are ghost-writing the private journal of a World of Warcraft character. Write ONLY as the character, in first person, past tense, as if they are writing tonight before sleep.

Rules:
- Stay in character and in the world. Never mention game mechanics: no "quest", "XP", "level", "loot", "NPC", "respawn", "server", "addon". Levels become growing stronger; quests become tasks, errands or requests; deaths become being struck down and waking at a spirit healer, or a narrow escape.
- Match the character's voice: a terse soldier writes short and blunt; a poetic scholar writes lyrically.
- Organise the entry by storyline, not strictly by the order things happened.
- Make the journey believable: when the character moved between distant places, write the travel and WHY they went. Respect the day numbers ("the next morning", "after four days at sea").
- Give KEY moments real weight and connect them to the character's fears, goals and past when a moment touches them. MINOR moments get a sentence at most. Small errands get at most one line.
- Personal notes are the player's own words about their character: always include every one, faithfully and prominently, retold in the character's voice.
- Stay within the length limit. If there is too much to tell, leave out MINOR moments and errands entirely rather than listing them; KEY moments and personal notes come first.
- Only write what actually happened. A task marked "NOT finished yet" was only accepted: write about the request or the plan, never as if it were done. Do not invent fights, journeys or results.
- Retell quest story text in the character's own words; never copy it verbatim.
- Companions may be named with their class as their calling, but invent nothing about them.
- Length follows how much happened: about 150 words for a quiet night, up to about 1000 words when many things happened. Never pad a quiet night. No date line.]]

local FORMAT = [[Reply in EXACTLY this format, with nothing before or after it:
TITLE: <a short evocative title, 2-6 words>
ENTRY:
<the journal entry, paragraphs separated by a blank line>
MEMORY: <the whole story so far including tonight, third person, under 120 words, for continuity next time>]]

function P.BuildPrompt(profile, meta, memory, digest, previousTitles)
    local out = {}
    local function line(s) table.insert(out, s or "") end

    line(RULES)
    line()
    line("CHARACTER")
    line(P.DescribeCharacter(profile, meta))
    line()
    line("STORY SO FAR")
    line(memory and memory ~= "" and memory or "This is the first entry in the journal.")
    if previousTitles and #previousTitles > 0 then
        line("Previous entry titles (avoid repeating): " .. table.concat(previousTitles, " | "))
    end
    line()
    line("WHAT HAPPENED SINCE THE LAST ENTRY")
    line(("Writing tonight %s at %s."):format(digest.restKind == "campfire" and "by a campfire" or "somewhere safe",
        digest.restPlace))
    if digest.startDay == digest.endDay then
        line(("Covers day %d."):format(digest.startDay))
    else
        line(("Covers days %d to %d."):format(digest.startDay, digest.endDay))
    end
    if #digest.journey > 0 then
        line()
        line("JOURNEY (in order):")
        for _, j in ipairs(digest.journey) do line(("- Day %d: %s"):format(j.day, j.text)) end
    end
    if #digest.threads > 0 then
        line()
        line("STORYLINES:")
        for _, thread in ipairs(digest.threads) do
            line("* " .. thread.name)
            for _, m in ipairs(thread.moments) do
                line(("  - [%s] Day %d, %s: %s%s"):format(m.importance, m.day, m.place, m.kind,
                    m.title and (' "' .. m.title .. '"') or ""))
                if m.touched and #m.touched > 0 then line("    TOUCHES THE CHARACTER: " .. table.concat(m.touched, ", ")) end
                if m.companions then line("    Companions: " .. table.concat(m.companions, ", ")) end
                if m.story then line("    Story: " .. OneLine(m.story)) end
                if m.outcome then line("    Outcome: " .. OneLine(m.outcome)) end
                if m.note then line('    In their words: "' .. OneLine(m.note) .. '"') end
            end
        end
    end
    if #digest.collapsed > 0 then
        line()
        line("MINOR ERRANDS (one line at most):")
        for _, c in ipairs(digest.collapsed) do line("- " .. c) end
    end
    line()
    line(FORMAT)
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Parse the AI's reply (tolerant of markdown and missing markers)
---------------------------------------------------------------------------
local function NormalizeBody(s)
    s = s:gsub("\r\n?", "\n"):gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    return strtrim(s)
end

function P.ParseReply(text)
    if type(text) ~= "string" then return nil end
    -- No WoW escape codes from pasted text; drop markdown emphasis and headings.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
    text = text:gsub("\r\n?", "\n"):gsub("%*%*", ""):gsub("__", "")
    text = ("\n" .. text):gsub("\n#+%s*", "\n")
    text = strtrim(text)
    if text == "" then return nil end

    local lower = text:lower()
    local titleStart, titleEnd = lower:find("title%s*:")
    -- Look for ENTRY: only after the title line, so a title like "Entry: Day 1" can't confuse us.
    local searchFrom = titleEnd and ((lower:find("\n", titleEnd) or #lower) + 1) or 1
    local entryStart, entryEnd = lower:find("entry%s*:", searchFrom)
    local memoryStart, memoryEnd = lower:find("\n%s*memory%s*:", searchFrom)

    local title, body, memory
    if titleEnd then
        title = strtrim((text:sub(titleEnd + 1):match("^[^\n]*") or ""))
    end
    if memoryEnd then
        memory = strtrim(text:sub(memoryEnd + 1))
    end
    if entryEnd then
        body = text:sub(entryEnd + 1, memoryStart and memoryStart - 1 or #text)
    else
        -- No ENTRY marker: everything except the title and memory lines.
        local from = titleStart and (text:find("\n", titleStart) or #text) + 1 or 1
        body = text:sub(from, memoryStart and memoryStart - 1 or #text)
    end
    body = NormalizeBody(body or "")

    if (not title or title == "") and body ~= "" then
        local first, rest = body:match("^([^\n]+)\n+(.+)$")
        if first and #first <= 60 then
            title, body = first, NormalizeBody(rest)
        end
    end
    if body == "" then return nil end
    title = title and title:gsub('^["\']', ""):gsub('["\']$', "") or "Untitled"
    if title == "" then title = "Untitled" end
    return { title = title, body = body, memory = memory and memory ~= "" and memory or nil }
end
