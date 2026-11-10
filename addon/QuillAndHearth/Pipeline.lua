-- Quill & Hearth: the story pipeline.
-- Turns recorded events into a story-shaped digest and an LLM prompt, so a journal entry can be
-- written by any AI chat (copy the prompt, paste the reply back).
--
-- Coherence rules:
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
    for _, k in ipairs({ "title", "text", "objectives", "rewardText", "questLine", "instance", "zone", "foe", "killer", "spell" }) do
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
    elseif t == "foe" then
        add((e.kind == "rare" or e.kind == "rare elite" or e.kind == "boss") and 4 or 3, "fought a notable foe")
    elseif t == "spell_learned" then
        add(3, "learned a new ability")
    elseif t == "money" then
        add(e.kind == "milestone" and 4 or 2, "coin and trade")
    elseif t == "level" then
        if (e.level or 0) % 10 == 0 then add(5, "level milestone") else add(2, "grew stronger") end
    elseif t == "bind" then
        add(3, "found a new home")
    elseif t == "note" then
        add(10, "the player's own note")
    elseif t == "loot" then
        if (e.qualityNum or 3) >= 4 then add(5, "a remarkable find") else add(2, "a fine find") end
    elseif t == "reputation" then
        local s = (e.standing or ""):lower()
        if s == "exalted" or s == "revered" then add(5, "a great honour") else add(3, "earned trust") end
    elseif t == "skill" then
        add((e.rank or 0) % 75 == 0 and 3 or 2, "a craft improved")
    elseif t == "achievement" then
        add(3, "an accomplishment")
    elseif t == "camp" then
        add(2, "sat by a campfire")
    elseif t == "hearth" or t == "flight_start" or t == "flight_end" or t == "instance_leave" then
        add(1, "travel")
    end
    if e.first then add(3, "a first") end

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
    local reflections = {} -- milestones that deserve a short "looking back" in the entry
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
                    type = e.type,
                    first = e.first,
                    questID = e.questID,
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
                    m.giver = e.giver or (accept and accept.giver)
                elseif e.type == "quest_accept" then
                    m.kind = "took on a task (NOT finished yet)"
                    m.title = e.title
                    m.story = P.Clean(e.text)
                    m.giver = e.giver
                elseif e.type == "level" then
                    m.kind = "grew stronger"
                    m.title = ("Reached level %d"):format(e.level or 0)
                    if (e.level or 0) % 10 == 0 then reflections["reached level " .. e.level] = true end
                elseif e.type == "zone" then
                    m.kind = "arrived"
                    m.title = e.continentChanged and ("Arrived in " .. (e.continent or "a new land")) or ("First time in " .. (e.zone or "?"))
                elseif e.type == "death" then
                    m.kind = e.first and "was struck down (for the first time ever)" or "was struck down"
                    if e.killer then
                        m.killer = e.killer
                        m.killerKind = e.killerKind
                        m.kind = m.kind .. " by " .. e.killer .. (e.killerKind and (" (" .. e.killerKind .. ")") or "")
                    end
                    if e.first then reflections["the first time they were struck down"] = true end
                elseif e.type == "foe" then
                    m.kind = ("slew a %s foe"):format(e.kind or "formidable")
                    m.title = e.foe
                    m.foeKind = e.kind
                elseif e.type == "spell_learned" then
                    m.kind = "learned a new technique (describe naturally in-world without the literal game skill name)"
                    m.title = e.spell
                elseif e.type == "money" then
                    if e.kind == "milestone" then
                        m.kind = "saved up"
                        m.title = e.milestone or "a pouch of coin"
                        m.moneyKind = "milestone"
                    else
                        m.kind = ("spent %s and was left with %s"):format(e.spent or "most of their coin", e.left or "nearly nothing")
                        m.moneyKind = "spent"
                        m.spent = e.spent
                        m.left = e.left
                    end
                elseif e.type == "note" then
                    m.kind = "personal note (the player's own words)"
                    m.note = P.Clean(e.text, 500)
                elseif e.type == "instance_enter" then
                    m.kind = e.first and "entered a dungeon (their first)" or "entered a dungeon"
                    m.title = e.instance
                    if e.first then reflections["their first dungeon"] = true end
                elseif e.type == "loot" then
                    m.kind = ("found something %s"):format(e.quality == "rare" and "fine" or "remarkable")
                    m.title = e.item
                elseif e.type == "reputation" then
                    m.kind = ("became %s with"):format((e.standing or "friendly"):lower())
                    m.title = e.faction
                elseif e.type == "skill" then
                    m.kind = ("improved their %s to %d"):format(e.skill or "craft", e.rank or 0)
                elseif e.type == "achievement" then
                    m.kind = "accomplished something"
                    m.title = e.achievement
                elseif e.type == "camp" then
                    m.kind = "sat by a campfire and rested"
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

    local reflectionList = {}
    for reason in pairs(reflections) do table.insert(reflectionList, reason) end
    table.sort(reflectionList)

    -- Abilities used, merged over all nights (each rest carries the counts since the previous one).
    local abilityCounts, abilityOrder = {}, {}
    for _, sitting in ipairs(sittings) do
        for _, a in ipairs(sitting.rest.abilities or {}) do
            local name, n = a:match("^(.-) %((%d+)%)$")
            name, n = name or a, tonumber(n) or 1
            if not abilityCounts[name] then table.insert(abilityOrder, name) end
            abilityCounts[name] = (abilityCounts[name] or 0) + n
        end
    end
    table.sort(abilityOrder, function(a, b) return abilityCounts[a] > abilityCounts[b] end)
    local abilities = {}
    for i = 1, math.min(6, #abilityOrder) do
        abilities[i] = ("%s (%d)"):format(abilityOrder[i], abilityCounts[abilityOrder[i]])
    end

    local lastRest = sittings[#sittings].rest
    local digest = {
        startDay = startDay,
        endDay = day,
        nights = #sittings,
        restPlace = PlaceOf(lastRest),
        restKind = lastRest.kind,
        indoors = lastRest.indoors,
        lastRest = lastRest,
        level = lastRest.level,
        abilities = abilities,
        timeOfDay = P.TimeOfDay(lastRest.hour),
        threads = orderedThreads,
        journey = journey,
        collapsed = collapsed,
        reflections = reflectionList,
        isEmpty = #orderedThreads == 0 and #collapsed == 0 and #journey == 0,
    }
    return digest
end

--- In-game hour -> a word for the prompt.
function P.TimeOfDay(hour)
    if type(hour) ~= "number" then return nil end
    if hour < 5 then return "deep in the night" end
    if hour < 8 then return "at dawn" end
    if hour < 12 then return "in the morning" end
    if hour < 17 then return "in the afternoon" end
    if hour < 21 then return "in the evening" end
    return "late at night"
end

---------------------------------------------------------------------------
-- Character description
---------------------------------------------------------------------------
function P.DescribeCharacter(profile, meta)
    local lines = {}
    local function add(label, value, maxLen)
        value = P.Clean(value, maxLen or 600)
        if value then table.insert(lines, label .. ": " .. OneLine(value)) end
    end
    local function addBlock(label, value)
        value = P.Clean(value, 20000)
        if not value then return end
        if value:find("\n", 1, true) then
            table.insert(lines, label .. ":\n" .. value)
        else
            table.insert(lines, label .. ": " .. value)
        end
    end
    local gender = meta and (meta.sex == 3 and "female" or meta.sex == 2 and "male") or nil
    add("Name", profile and profile.name or meta and meta.name)
    local race = profile and profile.trp3 and profile.trp3.race or meta and meta.race
    add("Race", race and (race .. (gender and (" (" .. gender .. ")") or "")))
    add("Class / calling", profile and profile.class or meta and meta.class)
    if meta and meta.class and profile and profile.class and profile.class ~= meta.class then
        add("Fights as (game class)", meta.class)
    end
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
        addBlock("Fears", profile.fear)
        addBlock("Appearance", profile.appearance)
        addBlock("Background / past", profile.past)
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
        for _, m in ipairs(d.misc or {}) do add(m.name, m.value, 1000) end
        for _, p in ipairs(d.personality or {}) do
            local leftPct = math.floor((p.leftStrength or 10) / (p.max or 20) * 100 + 0.5)
            table.insert(lines, ("Personality: %d%% %s / %d%% %s"):format(leftPct, p.left, 100 - leftPct, p.right))
        end
        local a = d.about
        if a then
            addBlock("About", a.text)
            for i, s in ipairs(a.sections or {}) do addBlock("About (part " .. i .. ")", s) end
            addBlock("Appearance", a.physical)
            addBlock("Personality notes", a.personality)
            addBlock("History", a.history)
        end
        addBlock("Currently", d.currently)
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Prompt
---------------------------------------------------------------------------
local RULES = [[You are ghost-writing the private journal of a World of Warcraft character. Write ONLY as the character, in first person, past tense, as if they are writing tonight before sleep.

Rules:
- Stay in character and in the world. Never mention game mechanics: no "quest", "XP", "level", "loot", "NPC", "respawn", "server", "addon". Levels become growing stronger; quests become tasks, contracts, or requests; deaths become being struck down and waking at a spirit healer, or a narrow escape.
- Match the character's voice, temperament, and background.
- NEVER write a quest-by-quest checklist or summarize every task in one or two dry sentences. Instead, build the entry around ONE or TWO centerpiece moments and elaborate on them deeply and imaginatively — bring out the atmosphere, weather, sensory details, tension, dialogue or personality of the people met, and the character's inner thoughts.
- Prioritize [KEY] moments and personal notes for your centerpiece scenes, connecting them to the character's fears, goals, and past. If a day has no major [KEY] events and is mostly [MINOR] tasks or errands, pick the ONE or TWO most interesting or atmospheric minor tasks and elevate them into full, vivid scenes. Fold the remaining minor errands into a brief passing mention, or leave out trivial ones entirely, so the journal reads like an engaging chapter of a novel rather than an errand log.
- Personal notes are the player's own words about their character: always include every one, faithfully and prominently, retold in the character's voice.
- Keep the plot anchored to what actually happened (do not invent major plot twists, bosses, or companions that aren't in the log, and treat any task marked "NOT finished yet" as an open request or plan rather than a completed feat), but use your creativity to dramatize the scenes, surroundings, and encounters around those events.
- Retell quest story text in the character's own words; never copy it verbatim.
- Make the journey believable: when the character moved between distant places, write the travel and WHY they went. Respect the day numbers ("the next morning", "after four days at sea").
- Companions may be named with their class as their calling, but invent nothing about them. People who asked for help ("Asked by") may be named.
- Weave in a few small, unexpected slice-of-life details that fit the zone, class, weather, or resting place (such as a minor travel or camp hiccup, a fleeting observation of locals or wildlife, a small gear or pet moment, or a sensory detail while writing) — as long as they do not contradict recorded events or repeat earlier entries.
- Respect the character's class, weapons, and level, and describe combat and training creatively in natural prose — NEVER parrot exact game ability or spell names like a combat log (do not write literal skill names like "Arcane Shot", "Raptor Strike", "Wing Clip", or "Heroic Strike"). Use the character's class and recorded abilities only as inspiration for how they actually fight in the world (a hunter fights with bow or gun, blades, traps, and their beast — never hurling fireballs; a shaman calls on the elements; a rogue strikes from the shadows). Keep their power grounded in their level: a young adventurer relies on grit and modest fundamentals, never the feats of a seasoned champion.
- If you can browse the web, you may look up the quests (by name or quest id), people, creatures and places on https://warcraft.wiki.gg/ for accurate lore details. Never contradict what is given here; if something isn't on the wiki (new content), rely on the text given.
- %s No date line.]]

P.LENGTH_RULES = {
    short = "Keep it concise: about 150 to 350 words, focusing on the single most memorable scene of the day.",
    normal = "Write a full, immersive entry: about 400 to 1000 words, developing the one or two centerpiece scenes across several rich paragraphs.",
    long = "Write generously and at length: about 700 to 1600 words, with deep scene-building, atmosphere, and reflection.",
}

local FORMAT = [[Reply in EXACTLY this format, with nothing before or after it:
TITLE: <a short evocative title, 2-6 words>
ENTRY:
<the journal entry, paragraphs separated by a blank line>
MEMORY: <the whole story so far including tonight, third person, under 120 words, for continuity next time>]]

local function AppendMoments(out, meta, digest, opts)
    local function line(s) table.insert(out, s or "") end
    if opts.people and #opts.people > 0 then
        line("PEOPLE MET BEFORE (they appear again tonight; the character knows them, so keep continuity with earlier dealings):")
        for _, p in ipairs(opts.people) do
            local parts = { "- " .. p.name }
            if p.zone then table.insert(parts, "first met in " .. p.zone) end
            if p.tasks and #p.tasks > 0 then table.insert(parts, "earlier tasks: " .. table.concat(p.tasks, ", ")) end
            line(table.concat(parts, "; "))
        end
        line()
    end
    line("WHAT HAPPENED SINCE THE LAST ENTRY")
    local whereHow = digest.restKind == "campfire" and "by a campfire"
        or (digest.indoors and "indoors somewhere safe" or "somewhere safe")
    line(("Writing tonight %s at %s%s."):format(whereHow,
        digest.restPlace, digest.timeOfDay and (", " .. digest.timeOfDay) or ""))
    if digest.startDay == digest.endDay then
        line(("Covers day %d."):format(digest.startDay))
    else
        line(("Covers days %d to %d."):format(digest.startDay, digest.endDay))
    end
    if digest.level then
        line(("The character is level %d%s."):format(digest.level,
            meta and meta.class and (" (" .. meta.class .. ")") or ""))
    end
    if digest.abilities and #digest.abilities > 0 then
        line("Combat style context (most-used game abilities — use ONLY as inspiration for natural fight choreography; do NOT write these exact skill names in the entry): " .. table.concat(digest.abilities, ", "))
    end
    if digest.reflections and #digest.reflections > 0 then
        line(("A milestone (%s): end the entry with a short, honest look back at who the character was when the journey began and who they are now."):format(table.concat(digest.reflections, "; ")))
    end
    if #digest.journey > 0 then
        line()
        line("JOURNEY (in order):")
        for _, j in ipairs(digest.journey) do line(("- Day %d: %s"):format(j.day, j.text)) end
    end
    if #digest.threads > 0 then
        line()
        line("STORYLINES (choose 1 or 2 centerpiece moments to dramatize in depth; fold or skip the rest so it never reads like a quest checklist):")
        for _, thread in ipairs(digest.threads) do
            line("* " .. thread.name)
            for _, m in ipairs(thread.moments) do
                line(("  - [%s] Day %d, %s: %s%s%s"):format(m.importance, m.day, m.place, m.kind,
                    m.title and (' "' .. m.title .. '"') or "", m.questID and (" (quest id " .. m.questID .. ")") or ""))
                if m.touched and #m.touched > 0 then line("    TOUCHES THE CHARACTER: " .. table.concat(m.touched, ", ")) end
                if m.giver then line("    Asked by: " .. m.giver) end
                if m.companions then line("    Companions: " .. table.concat(m.companions, ", ")) end
                if m.story then line("    Story: " .. OneLine(m.story)) end
                if m.outcome then line("    Outcome: " .. OneLine(m.outcome)) end
                if m.note then line('    In their words: "' .. OneLine(m.note) .. '"') end
            end
        end
    end
    if #digest.collapsed > 0 then
        line()
        line("OTHER SMALL ERRANDS (skip or fold into a brief passing mention):")
        for _, c in ipairs(digest.collapsed) do line("- " .. c) end
    end
end

--- Standalone prompt to prime or reset an AI chat session with the full character sheet and rules.
function P.BuildSetupPrompt(profile, meta, memory, previousTitles, opts)
    opts = opts or {}
    local name = (profile and profile.name) or (meta and meta.name) or "the character"
    local out = {
        RULES:format(P.LENGTH_RULES[opts.length] or P.LENGTH_RULES.normal),
        "",
        "CHARACTER",
        P.DescribeCharacter(profile, meta),
        "",
        "STORY SO FAR",
        memory and memory ~= "" and memory or "This is the beginning of the journal.",
    }
    if previousTitles and #previousTitles > 0 then
        table.insert(out, "Previous entry titles (avoid repeating): " .. table.concat(previousTitles, " | "))
    end
    table.insert(out, "")
    table.insert(out, "When I send what happened since the last entry, " .. FORMAT:gsub("^Reply", "reply"))
    table.insert(out, "")
    table.insert(out, ('This message sets up our journal session. Do not write a journal entry yet — reply only with: "Ready to write %s\'s journal." and wait for the next night\'s moments.'):format(name))
    return table.concat(out, "\n")
end

--- opts (all optional): { length, people, session = true (short prompt for an active chat) }
function P.BuildPrompt(profile, meta, memory, digest, previousTitles, opts)
    opts = opts or {}
    local out = {}
    local function line(s) table.insert(out, s or "") end
    local lengthRule = P.LENGTH_RULES[opts.length] or P.LENGTH_RULES.normal

    if opts.session then
        local name = (profile and profile.name) or (meta and meta.name) or "the character"
        line(("Write the next journal entry for %s in first person, past tense, using the character sheet and rules from earlier in this chat. Focus on 1 or 2 centerpiece moments and elaborate on them imaginatively (if the log is mostly minor tasks, pick 1 or 2 interesting ones to dramatize into full scenes and fold or skip the rest — never write a quest-by-quest checklist). Describe combat creatively according to their class without using exact game ability names. (%s No date line.)"):format(name, lengthRule))
        line()
    else
        line(RULES:format(lengthRule))
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
    end
    AppendMoments(out, meta, digest, opts)
    line()
    line(FORMAT)
    return table.concat(out, "\n")
end

--- Turn a stored full prompt into a short session-continuation prompt (for rewriting existing entries).
function P.ShortenPrompt(fullPrompt, name)
    if type(fullPrompt) ~= "string" then return fullPrompt end
    local idx = fullPrompt:find("\nPEOPLE MET BEFORE", 1, true)
        or fullPrompt:find("\nWHAT HAPPENED SINCE THE LAST ENTRY", 1, true)
    if not idx then return fullPrompt end
    local header = ("Write this journal entry for %s in first person, past tense, using the character sheet and rules from earlier in this chat. Focus on 1 or 2 centerpiece moments and elaborate on them imaginatively (never write a quest-by-quest checklist), and describe combat creatively without using exact game ability names. (No date line.)\n"):format(name or "the character")
    return header .. fullPrompt:sub(idx)
end

P.MAX_BULK_ENTRIES = 4

local function DayRangeLabel(d)
    if d.endDay and d.endDay ~= d.startDay then
        return ("Days %d - %d"):format(d.startDay or 1, d.endDay)
    end
    return ("Day %d"):format(d.startDay or 1)
end

--- Build a batched prompt covering 2..MAX_BULK_ENTRIES consecutive unwritten days in chronological order.
--- items: array of { digest = ..., people = ... }
function P.BuildBulkPrompt(profile, meta, memory, items, previousTitles, opts)
    opts = opts or {}
    local out = {}
    local function line(s) table.insert(out, s or "") end
    local lengthRule = P.LENGTH_RULES[opts.length] or P.LENGTH_RULES.normal
    local count = #items
    local name = (profile and profile.name) or (meta and meta.name) or "the character"

    if opts.session then
        line(("Write the next %d journal entries for %s in first person, past tense, in chronological order, using the character sheet and rules from earlier in this chat. Give EACH entry its own full depth and length (%s No date line.) — do NOT rush or compress later entries just because you are writing %d in one reply. Focus each entry on 1 or 2 centerpiece moments and elaborate on them imaginatively (never write a quest-by-quest checklist), and describe combat creatively without using exact game ability names."):format(count, name, lengthRule, count))
        line()
    else
        line(RULES:format(lengthRule))
        line(("- You are writing a batch of %d consecutive journal entries in chronological order. Give EACH entry the full depth and word count above — do NOT rush or compress later entries."):format(count))
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
    end

    for i, item in ipairs(items) do
        line(("=== ENTRY %d OF %d (%s) ==="):format(i, count, DayRangeLabel(item.digest)))
        AppendMoments(out, meta, item.digest, { people = item.people })
        line()
    end

    line(("Reply with all %d entries in chronological order in EXACTLY this format, with nothing before or after it:"):format(count))
    for i, item in ipairs(items) do
        line(("=== ENTRY %d (%s) ==="):format(i, DayRangeLabel(item.digest)))
        line(("TITLE: <a short evocative title for %s, 2-6 words>"):format(DayRangeLabel(item.digest)))
        line("ENTRY:")
        line(("<the full journal entry for %s, paragraphs separated by a blank line>"):format(DayRangeLabel(item.digest)))
        line()
    end
    line("MEMORY: <the whole story so far including all entries written above, third person, under 140 words, for continuity next time>")
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

--- Parse a multi-entry AI reply into { entries = { { title, body, memory }, ... }, memory = lastMemory }.
function P.ParseBulkReply(text)
    if type(text) ~= "string" then return nil end
    local cleaned = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
    cleaned = cleaned:gsub("\r\n?", "\n"):gsub("%*%*", ""):gsub("__", "")
    -- Strip section divider lines like "=== ENTRY 1 ===", "--- Day 5 ---", or horizontal rules so they don't leak into entry bodies.
    local lines = {}
    for line in (cleaned .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = strtrim(line):gsub("^#+%s*", "")
        local lower = trimmed:lower()
        local isDivider = trimmed:match("^[=%-_][=%-_][=%-_]+$") ~= nil
            or lower:match("^[=%-_*#]*%s*entry%s+%d+") ~= nil
            or lower:match("^[=%-_*#]+%s*days?%s+%d+") ~= nil
        if not isDivider then
            table.insert(lines, line)
        end
    end
    cleaned = "\n" .. table.concat(lines, "\n")

    local starts = {}
    local pos = 1
    local lower = cleaned:lower()
    while true do
        local matchStart, matchEnd = lower:find("\n[ \t]*#*[ \t]*title%s*:", pos)
        if not matchStart then break end
        table.insert(starts, matchStart + 1)
        pos = matchEnd + 1
    end

    if #starts == 0 then
        local single = P.ParseReply(text)
        if not single then return nil end
        return { entries = { single }, memory = single.memory }
    end

    local entries = {}
    local lastMemory
    for i, startIdx in ipairs(starts) do
        local endIdx = starts[i + 1] and (starts[i + 1] - 1) or #cleaned
        local slice = cleaned:sub(startIdx, endIdx)
        local parsed = P.ParseReply(slice)
        if parsed and parsed.body and parsed.body ~= "" then
            table.insert(entries, parsed)
            if parsed.memory and parsed.memory ~= "" then
                lastMemory = parsed.memory
            end
        end
    end
    if #entries == 0 then return nil end
    return { entries = entries, memory = lastMemory }
end

---------------------------------------------------------------------------
-- Chapter prompt (title + summary of a run of entries)
---------------------------------------------------------------------------
local CHAPTER_RULES = [[You are ghost-writing the private journal of a World of Warcraft character. The character is looking back over a chapter of their journey and writing a chapter title and a short summary, in first person, in their own voice.

Rules:
- Stay in character and in the world. Never mention game mechanics ("quest", "XP", "level", "loot", "NPC").
- Summarise the chapter as the character remembers it: what mattered, what changed in them, who they met. Do not list every entry.
- Only use what the entries below say. Do not invent events.
- About 120-250 words.]]

local CHAPTER_FORMAT = [[Reply in EXACTLY this format, with nothing before or after it:
TITLE: <an evocative chapter title, 2-6 words>
ENTRY:
<the chapter summary, paragraphs separated by a blank line>]]

function P.BuildChapterPrompt(profile, meta, chapter)
    local out = { CHAPTER_RULES, "", "CHARACTER", P.DescribeCharacter(profile, meta), "",
        ("CHAPTER %s (days %d to %d)"):format(chapter.numeral or "?", chapter.firstDay or 0, chapter.lastDay or 0), "" }
    for _, e in ipairs(chapter.entries) do
        if not e.unwritten then
            local body = P.Clean(e.body, 700) or ""
            table.insert(out, ("Day %d - %s:"):format(e.day or 0, e.title or "Untitled"))
            table.insert(out, OneLine(body))
            table.insert(out, "")
        end
    end
    table.insert(out, CHAPTER_FORMAT)
    return table.concat(out, "\n")
end
