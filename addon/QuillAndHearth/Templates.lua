-- Quill & Hearth: the in-game template writer. Writes a journal entry with no AI at all, in the
-- character's voice (from onboarding), from the same digest the AI prompt uses.
-- Variants are picked with a seed from the rest, so the same night always reads the same.
local _, QH = ...

local T = {}
QH.Templates = T

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Rng(seed)
    local state = (seed or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 16807) % 2147483647
        return (state % n) + 1
    end
end

local function Fill(template, vars)
    return (template:gsub("{(%w+)}", function(key) return vars[key] or "" end))
end

local function Join(list)
    if #list == 0 then return "" end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function Capitalize(s)
    return (s:gsub("^%l", string.upper))
end

local VOICES = { Plain = true, Formal = true, Poetic = true, Terse = true }

local function VoiceOf(profile)
    local v = profile and profile.traits and profile.traits.voice
    return VOICES[v] and v or "Plain"
end

---------------------------------------------------------------------------
-- Phrase banks: [voice] = { variants... }. {placeholders} are filled per moment.
---------------------------------------------------------------------------
local B = {}

B.openRested = {
    Plain = { "I'm writing this at {place}, glad of a roof and a bed.", "A quiet corner at {place} and a little ink. Time to set down what happened." },
    Formal = { "I set down these lines at {place}, where I have taken lodging for the night.", "From {place}, I record the events of recent days." },
    Poetic = { "Lamplight flickers across the page here at {place}, and the day's dust is finally settling.", "The common room at {place} hums softly around me as I write." },
    Terse = { "{place}. A bed. Ink.", "Resting at {place}." },
}
B.openCampfire = {
    Plain = { "I've made camp near {place} and the fire is warm enough to write by.", "Sitting by a campfire near {place}, I finally have a moment to write." },
    Formal = { "I write by the light of a campfire near {place}.", "Encamped near {place}, I take the opportunity to record the day." },
    Poetic = { "Sparks climb into the dark above my little fire near {place}, and the page glows orange.", "The fire near {place} crackles like an old friend telling stories." },
    Terse = { "Camp near {place}. Fire's lit.", "Campfire. {place}. Writing." },
}
B.nextDay = {
    Plain = { "The next day, ", "The following morning, " },
    Formal = { "On the following day, ", "When the next day dawned, " },
    Poetic = { "When dawn came again, ", "With the new morning, " },
    Terse = { "Next day: ", "Morning. " },
}
B.daysLater = {
    Plain = { "Some days later, ", "A few days on, " },
    Formal = { "Several days thereafter, ", "Some days later, " },
    Poetic = { "Days slipped past, and then ", "Many sunrises later, " },
    Terse = { "Days later: ", "Later. " },
}
B.voyage = {
    Plain = { "I left {from} behind and spent {days} days travelling to {continent}, landing in {zone}.", "The crossing to {continent} took {days} long days before I reached {zone}." },
    Formal = { "I departed {from} and, after a passage of some {days} days, arrived upon the shores of {continent} at {zone}.", "A voyage of {days} days carried me from {from} to {zone}, in {continent}." },
    Poetic = { "For {days} days the sea rocked me from {from} toward {continent}, until {zone} rose out of the haze.", "{continent} was only a rumour on the horizon for {days} days; then {zone} welcomed me ashore." },
    Terse = { "{days} days of travel. {from} to {zone}, {continent}.", "Crossed to {continent}. {days} days. Landed in {zone}." },
}
B.firstVisit = {
    Plain = { "I set foot in {zone} for the first time.", "{zone} was new to me." },
    Formal = { "I entered {zone}, a land I had not visited before.", "For the first time, my road led into {zone}." },
    Poetic = { "{zone} opened before me, strange and new.", "I walked into {zone} for the first time, every path unfamiliar." },
    Terse = { "First time in {zone}.", "New ground: {zone}." },
}
B.flight = {
    Plain = { "I caught a flight to {dest}.", "A ride on the wind took me to {dest}." },
    Formal = { "I took passage by air to {dest}.", "A flight carried me swiftly to {dest}." },
    Poetic = { "I flew to {dest}, the land unrolling beneath me like a map.", "The wind bore me to {dest}, high above the treetops." },
    Terse = { "Flew to {dest}.", "Flight to {dest}." },
}
B.hearth = {
    Plain = { "When the work was done, I used my hearthstone to return to {home}.", "I headed home to {home} by hearthstone." },
    Formal = { "I returned by hearthstone to {home}.", "My hearthstone carried me back to {home}." },
    Poetic = { "The hearthstone's glow pulled me home to {home} in a heartbeat.", "A flash of light, and {home} was around me again." },
    Terse = { "Hearthed to {home}.", "Back to {home}." },
}
B.bind = {
    Plain = { "I've decided to call {home} home for now.", "{home} is where I'll lay my head from now on." },
    Formal = { "I have made {home} my place of residence.", "I have taken up lodging at {home} for the foreseeable future." },
    Poetic = { "{home} will be my hearth now, for as long as the road allows.", "I've tied my heart, for a while, to {home}." },
    Terse = { "New home: {home}.", "Staying at {home} now." },
}
B.taskDone = {
    Plain = { "I finished the matter of {title}.", "I saw {title} through to the end.", "{title} is done." },
    Formal = { "I brought the matter of {title} to its conclusion.", "I completed the task known as {title}.", "The affair of {title} is concluded." },
    Poetic = { "{title}: that thread is woven to its end.", "I closed the chapter of {title}.", "{title} lies behind me now." },
    Terse = { "{title}. Done.", "Finished {title}.", "{title}: handled." },
}
B.taskAccepted = {
    Plain = { "I agreed to help with {title}. It still lies ahead of me.", "Someone asked for my help with {title}; I said yes." },
    Formal = { "I have accepted responsibility for {title}, though it remains unfinished.", "I pledged my aid in the matter of {title}." },
    Poetic = { "A new burden: {title}. I carry it into tomorrow.", "{title} waits for me, like a road not yet walked." },
    Terse = { "Took on {title}. Not done yet.", "New task: {title}." },
}
B.taskStory = {
    Plain = { "It started with this: {story}", "The gist of it: {story}" },
    Formal = { "The circumstances were these: {story}", "As it was explained to me: {story}" },
    Poetic = { "The tale, as it was told to me: {story}", "Its story stays with me: {story}" },
    Terse = { "{story}", "Short version: {story}" },
}
B.fear = {
    Plain = { "Of all things, it had to involve {hook}. I did it anyway.", "{Hook}. Of course it was {hook}. My hands shook, but I didn't turn back." },
    Formal = { "I confess the involvement of {hook} tested my composure, yet I did not falter.", "That {hook} should be involved was a trial I had not wished for, but I endured it." },
    Poetic = { "{Hook}, the very shape of my nightmares, and still I walked toward it.", "Fear of {hook} gnawed at me with every step, and I stepped anyway." },
    Terse = { "{Hook}. Hate them. Did it anyway.", "{Hook} again. Didn't run." },
}
B.death = {
    Plain = { "I was struck down near {place} and woke at a spirit healer's side. I'm still shaken.", "I nearly didn't make it out of {place}; I came to at a spirit healer, bruised in more than body." },
    Formal = { "I fell near {place}, and only the grace of a spirit healer returned me to the world.", "I was overcome near {place}; I awoke in the care of a spirit healer." },
    Poetic = { "Darkness took me near {place}, and for a moment there was nothing. Then the spirit healer's light.", "I fell near {place}, and the world went grey and silent before it let me back." },
    Terse = { "Died near {place}. Spirit healer. Back on my feet.", "Struck down at {place}. Woke at a spirit healer." },
}
B.level = {
    Plain = { "I feel stronger than I did a few days ago.", "Something has changed in me. I'm more capable than before." },
    Formal = { "I find my abilities much improved of late.", "My skills have grown considerably." },
    Poetic = { "There is a new strength in my arms and a new certainty in my step.", "I am not who I was when this road began." },
    Terse = { "Stronger now.", "Getting better at this." },
}
B.dungeon = {
    Plain = { "We went into {instance}{with}.", "{Instance} was dark and dangerous, and we went in anyway{with}." },
    Formal = { "We ventured into {instance}{with}.", "I entered {instance}{with}." },
    Poetic = { "{Instance} swallowed us whole{with}, and somehow spat us back out.", "Into the depths of {instance} we went{with}." },
    Terse = { "{Instance}{with}. Went in.", "Entered {instance}{with}." },
}
B.minor = {
    Plain = { "I also saw to {list}.", "Besides that, there was {list}." },
    Formal = { "I further attended to {list}.", "Other matters included {list}." },
    Poetic = { "Smaller threads ran through the days as well: {list}.", "Between it all: {list}." },
    Terse = { "Also: {list}.", "Plus {list}." },
}
B.errands = {
    Plain = { "The rest of the time went to small jobs around {zones}.", "Plenty of odd jobs around {zones} filled the gaps." },
    Formal = { "The remainder of my time was spent on minor errands about {zones}.", "Various small duties around {zones} occupied the rest." },
    Poetic = { "The rest dissolved into small errands around {zones}, the kind no one sings about.", "Little tasks around {zones} filled the hours between." },
    Terse = { "Odd jobs around {zones}.", "Errands. {zones}." },
}
B.noteIntro = {
    Plain = { "One more thing I want to remember: ", "Something I keep thinking about: " },
    Formal = { "I wish to record the following: ", "A private reflection: " },
    Poetic = { "And this, before the ink dries: ", "A thought I cannot shake: " },
    Terse = { "Note: ", "Remember: " },
}
B.quiet = {
    Plain = { "Not much happened, honestly. A quiet stretch.", "A quiet few days, and I'm grateful for it." },
    Formal = { "These days passed without remarkable incident.", "Little of consequence occurred." },
    Poetic = { "The days slipped by like water, leaving little behind.", "A stillness lay over these days." },
    Terse = { "Quiet. Nothing much.", "Uneventful." },
}
B.time = {
    Plain = { "It's {time} as I write.", "Writing this {time}." },
    Formal = { "I write {time}.", "The hour: {time}." },
    Poetic = { "It is {time}, and the world has gone soft and quiet.", "I write {time}, while the world holds its breath." },
    Terse = { "{Time}.", "{Time}. Tired." },
}
B.giver = {
    Plain = { "{giver} had asked for my help with it.", "It was {giver} who asked." },
    Formal = { "I undertook it at the request of {giver}.", "{giver} had entrusted it to me." },
    Poetic = { "{giver} had pressed the matter into my hands.", "It began with {giver}'s request." },
    Terse = { "For {giver}.", "{giver} asked." },
}
B.giverAgain = {
    Plain = { "{giver} again. We're getting to know each other.", "Once more it was {giver} who asked; I'm becoming a familiar face to them." },
    Formal = { "Once again, {giver} sought my assistance.", "{giver}, whom I have aided before, called upon me again." },
    Poetic = { "{giver} again, a familiar face on an unfamiliar road.", "Our paths crossed once more, {giver} and I." },
    Terse = { "{giver} again.", "For {giver}. Again." },
}
B.loot = {
    Plain = { "I came away with something special: {item}.", "Among the day's spoils was {item}. I keep looking at it." },
    Formal = { "I acquired a notable item: {item}.", "Fortune granted me {item}." },
    Poetic = { "{item} came into my keeping, and it feels like a promise.", "I found {item}, and for a moment the road felt kinder." },
    Terse = { "Found {item}. Good.", "New gear: {item}." },
}
B.reputation = {
    Plain = { "{faction} seem to trust me more now. I'm {standing} with them, they say.", "I've earned some standing with {faction}: {standing}, no less." },
    Formal = { "My standing with {faction} has risen to {standing}.", "{faction} now regard me as {standing}." },
    Poetic = { "{faction} look at me differently now; I am {standing} in their eyes.", "Doors open a little wider among {faction}. {Standing}, they call me." },
    Terse = { "{faction}: {standing} now.", "{Standing} with {faction}." },
}
B.skill = {
    Plain = { "My {skill} keeps getting better; I'd put myself at {rank} now.", "Practice is paying off. My {skill} has come a long way." },
    Formal = { "My proficiency in {skill} has reached {rank}.", "I have made steady progress in {skill}." },
    Poetic = { "My hands are learning {skill}, one patient lesson at a time.", "{Skill} comes easier to me now, like a song I almost know." },
    Terse = { "{Skill}: {rank}.", "Better at {skill}." },
}
B.achievement = {
    Plain = { "I managed something I'm proud of: {achievement}.", "A small triumph worth writing down: {achievement}." },
    Formal = { "I count among my accomplishments: {achievement}.", "An accomplishment worth recording: {achievement}." },
    Poetic = { "{achievement}. Something to tell the fire about one day.", "I did it: {achievement}." },
    Terse = { "Done: {achievement}.", "{achievement}. Proud." },
}
B.camp = {
    Plain = { "I stopped by a campfire for a while and just sat.", "There was a campfire on the road, and I let myself rest by it." },
    Formal = { "I paused at a campfire to rest and gather my thoughts.", "A campfire offered a brief respite." },
    Poetic = { "I sat by a campfire and watched the sparks climb, and for once I thought of nothing.", "A fire on the roadside, a little warmth, a little peace." },
    Terse = { "Sat by a fire. Rested.", "Campfire. Short rest." },
}
B.reflection = {
    Plain = { "Looking back, I'm not who I was when I set out. I've grown, and I can feel it.", "Some days I barely recognize the person who started this journey." },
    Formal = { "In reflection, I am much changed since my journey began.", "I am not the same person who first set out, and I find I do not regret it." },
    Poetic = { "When I think of who I was at the start, it feels like a stranger's story, and yet it's mine.", "The road has carved me into someone new." },
    Terse = { "I've changed. Good.", "Not who I was. Stronger." },
}
-- Closings by the mood chosen when resting (take priority over temperament).
B.moodClose = {
    Weary = { "I'm so tired. Sleep, now.", "Every bone aches. Tomorrow can wait." },
    Triumphant = { "What a day. I'll sleep well tonight.", "I did well. I'll let myself be proud of that." },
    Troubled = { "Something about all this sits wrong with me.", "I can't shake this unease." },
    Grieving = { "It hurts more than I'll admit to anyone but this page.", "Some losses don't fit into words." },
    Hopeful = { "Tomorrow feels full of promise.", "For the first time in a while, I'm looking forward." },
    Content = { "A good day. I'm content.", "Warm, fed, and at peace. That's enough." },
}
-- Closings by temperament.
B.close = {
    Stoic = { "Tomorrow there will be more to do. I'll do it.", "Rest now. The road waits." },
    Cheerful = { "Tomorrow is bound to bring something good. It usually does!", "All in all, not a bad few days at all." },
    Brooding = { "Sleep won't come easily tonight.", "I wonder what all of this is leading to." },
    ["Hot-headed"] = { "Let tomorrow bring whatever it likes. I'll be ready.", "If trouble comes looking, it'll find me waiting." },
    Gentle = { "I hope everyone I met today sleeps safe tonight.", "May tomorrow be kinder to us all." },
    default = { "Enough for tonight.", "The candle's burning low. Enough for now." },
}
B.title = {
    task = { "{title}", "On {title}", "The Matter of {title}" },
    voyage = { "Across to {continent}", "A New Shore", "The Long Crossing" },
    death = { "A Close Call", "Back from the Brink", "Struck Down" },
    dungeon = { "Into {instance}", "The Depths of {instance}" },
    note = { "Thoughts by Firelight", "Things Worth Remembering" },
    quiet = { "Quiet Days in {zone}", "Day {day}", "A Few Days in {zone}" },
}

---------------------------------------------------------------------------
-- Writer
---------------------------------------------------------------------------
--- Write { title, body } for a digest. Told in the order things happened, which reads most
--- naturally for short template prose (the AI prompt groups by storyline instead).
function T.Write(digest, profile, opts)
    opts = opts or {}
    local voice = VoiceOf(profile)
    local temperament = profile and profile.traits and profile.traits.temperament
    local pick = Rng(digest.lastRest.seq * 7919 + digest.startDay)
    local function say(bank, vars)
        local variants = bank[voice] or bank.Plain
        return Fill(variants[pick(#variants)], vars or {})
    end

    local paragraphs, current = {}, {}
    local currentDay = digest.startDay
    local function flush()
        if #current > 0 then
            table.insert(paragraphs, table.concat(current, " "))
            current = {}
        end
    end
    --- Add a sentence; a new day starts a new paragraph with a time transition.
    local function sentence(s, day, transitionIncluded)
        if day and day > currentDay then
            flush()
            if not transitionIncluded then
                local bank = (day - currentDay > 1) and B.daysLater or B.nextDay
                s = say(bank) .. (s:gsub("^%u", string.lower))
            end
            currentDay = day
        elseif #current >= 4 then
            flush()
        end
        table.insert(current, s)
    end
    local function plural(word)
        return word:find("s$") and word or (word:find("y$") and word:gsub("y$", "ies") or word .. "s")
    end

    -- Opening
    local restPlace = digest.lastRest.subzone or digest.lastRest.zone or "the road"
    local opening = say(digest.restKind == "campfire" and B.openCampfire or B.openRested, { place = restPlace })
    if digest.timeOfDay then
        opening = opening .. " " .. say(B.time, { time = digest.timeOfDay, Time = Capitalize(digest.timeOfDay) })
    end
    table.insert(paragraphs, opening)

    -- One timeline of journey beats and story moments, in the order they happened.
    local timeline = {}
    for _, j in ipairs(digest.journey) do
        if j.event then table.insert(timeline, { seq = j.event.seq, day = j.day, journey = j.event }) end
    end
    local SPECIFIC = { loot = true, reputation = true, skill = true, achievement = true, camp = true }
    local notes, minors = {}, {}
    local titleKind, titleVars
    for _, thread in ipairs(digest.threads) do
        for _, m in ipairs(thread.moments) do
            if m.note then
                table.insert(notes, m)
            elseif m.importance == "KEY" or SPECIFIC[m.type] then
                table.insert(timeline, { seq = m.seq or 0, day = m.day, moment = m })
            elseif m.title then
                table.insert(minors, m.giver and (m.title .. " for " .. m.giver .. (m.metBefore and " again" or "")) or m.title)
            end
        end
    end
    table.sort(timeline, function(a, b) return a.seq < b.seq end)

    local told = 0
    for _, item in ipairs(timeline) do
        local e, m = item.journey, item.moment
        if e then
            if e.type == "zone" and e.continentChanged then
                sentence(say(B.voyage, { from = e.fromContinent or e.from or "home", continent = e.continent or "a new land",
                    zone = e.zone or "?", days = tostring(QH.Pipeline.VOYAGE_DAYS) }), item.day, true)
                told = told + 1
            elseif e.type == "zone" and e.firstVisit then
                sentence(say(B.firstVisit, { zone = e.zone or "?" }), item.day)
                told = told + 1
            elseif e.type == "flight_start" and e.destination then
                sentence(say(B.flight, { dest = e.destination }), item.day)
                told = told + 1
            elseif e.type == "hearth" then
                sentence(say(B.hearth, { home = e.home or "the inn" }), item.day)
                told = told + 1
            elseif e.type == "bind" then
                sentence(say(B.bind, { home = e.home or e.zone or "here" }), item.day)
                told = told + 1
            end
        elseif m then
            local vars = { title = m.title or "the task", place = m.place, instance = m.title or "the depths" }
            vars.Instance = Capitalize(vars.instance)
            told = told + 1
            local t = m.type
            if t == "quest_done" then
                sentence(say(B.taskDone, vars), m.day)
                if m.giver then sentence(say(m.metBefore and B.giverAgain or B.giver, { giver = m.giver })) end
                if m.story then
                    local first = m.story:match("^(.-[%.!?])%s") or m.story
                    if #first < 220 then sentence(say(B.taskStory, { story = first })) end
                end
                titleKind, titleVars = titleKind or "task", titleVars or vars
            elseif t == "quest_accept" then
                sentence(say(B.taskAccepted, vars), m.day)
                if m.giver then sentence(say(m.metBefore and B.giverAgain or B.giver, { giver = m.giver })) end
            elseif t == "death" then
                sentence(say(B.death, vars), m.day)
                titleKind, titleVars = "death", vars
            elseif t == "level" then
                sentence(say(B.level, vars), m.day)
            elseif t == "instance_enter" then
                vars.with = m.companions and (" with " .. Join(m.companions)) or ""
                sentence(say(B.dungeon, vars), m.day)
                titleKind, titleVars = titleKind or "dungeon", titleVars or vars
            elseif t == "loot" then
                sentence(say(B.loot, { item = m.title or "something fine" }), m.day)
            elseif t == "reputation" then
                local standing = (m.kind:match("^became (%S+) with") or "friendly")
                sentence(say(B.reputation, { faction = m.title or "the locals", standing = standing, Standing = Capitalize(standing) }), m.day)
            elseif t == "skill" then
                local skill, rank = m.kind:match("^improved their (.+) to (%d+)$")
                skill = skill or "craft"
                sentence(say(B.skill, { skill = skill, Skill = Capitalize(skill), rank = rank or "?" }), m.day)
            elseif t == "achievement" then
                sentence(say(B.achievement, { achievement = m.title or "something" }), m.day)
            elseif t == "camp" then
                sentence(say(B.camp), m.day)
            else
                told = told - 1 -- arrivals are already told by the journey
            end
            if m.touched and #m.touched > 0 then
                local hook = plural(m.touched[1])
                sentence(say(B.fear, { hook = hook, Hook = Capitalize(hook) }))
            end
        end
    end

    if #minors > 0 then
        local list = {}
        for i = 1, math.min(3, #minors) do list[i] = minors[i] end
        sentence(say(B.minor, { list = Join(list) }))
        told = told + 1
    end
    flush()

    if #digest.collapsed > 0 then
        local zones = {}
        for _, c in ipairs(digest.collapsed) do
            local zone = c:match("around (.+)$")
            if zone then table.insert(zones, zone) end
        end
        if #zones > 0 then
            table.insert(paragraphs, say(B.errands, { zones = Join(zones) }))
            told = told + 1
        end
    end

    if told == 0 and #notes == 0 then
        table.insert(paragraphs, say(B.quiet))
    end

    -- The player's own notes, in their words.
    for _, m in ipairs(notes) do
        table.insert(paragraphs, say(B.noteIntro) .. (m.note or ""))
        titleKind = titleKind or "note"
    end

    -- Milestones: a short look back.
    if digest.reflections and #digest.reflections > 0 then
        table.insert(paragraphs, say(B.reflection))
    end

    -- Closing: the chosen mood first, otherwise the character's temperament.
    local closings = (opts.mood and B.moodClose[opts.mood]) or B.close[temperament] or B.close.default
    table.insert(paragraphs, closings[pick(#closings)])

    -- Title
    local voyage
    for _, j in ipairs(digest.journey) do
        if j.event and j.event.type == "zone" and j.event.continentChanged then voyage = j.event end
    end
    local titleBank, vars
    if titleKind == "death" then
        titleBank, vars = B.title.death, titleVars
    elseif voyage then
        titleBank, vars = B.title.voyage, { continent = voyage.continent or "a New Land" }
    elseif titleKind == "task" or titleKind == "dungeon" then
        titleBank, vars = B.title[titleKind], titleVars
    elseif titleKind == "note" then
        titleBank, vars = B.title.note, {}
    else
        titleBank, vars = B.title.quiet, { zone = digest.lastRest.zone or "the Wilds", day = tostring(digest.startDay) }
    end
    local title = Fill(titleBank[pick(#titleBank)], vars or {})

    return { title = title, body = table.concat(paragraphs, "\n\n") }
end

---------------------------------------------------------------------------
-- Chapter summary (no AI)
---------------------------------------------------------------------------
B.chapterOpen = {
    Plain = { "Looking back over these days, from {from} to {to}:", "A few words to remember these days by, from {from} to {to}:" },
    Formal = { "A summary of the days spent between {from} and {to}:", "In review, the period from {from} to {to}:" },
    Poetic = { "From {from} to {to}, the road unrolled like this:", "These are the days between {from} and {to}, as I remember them:" },
    Terse = { "{from} to {to}. Summary:", "Recap. {from}, then {to}." },
}
B.chapterList = {
    Plain = { "I wrote about {list}.", "There was {list}." },
    Formal = { "I recorded {list}.", "Those pages tell of {list}." },
    Poetic = { "The pages remember {list}.", "There was {list}, each a stone on the path." },
    Terse = { "{list}.", "Covered: {list}." },
}
B.chapterClose = {
    Plain = { "On to whatever comes next.", "It feels like a chapter, now that I look at it." },
    Formal = { "So concludes this chapter of my account.", "Thus ends this part of the record." },
    Poetic = { "One chapter closes; the ink is already wet for the next.", "The page turns." },
    Terse = { "Chapter done.", "Next." },
}

function T.ChapterSummary(chapter, profile)
    local voice = VoiceOf(profile)
    local pick = Rng((chapter.number or 1) * 104729)
    local function say(bank, vars)
        local variants = bank[voice] or bank.Plain
        return Fill(variants[pick(#variants)], vars or {})
    end
    local titles = {}
    for _, e in ipairs(chapter.entries) do
        if not e.hidden and e.title then table.insert(titles, '"' .. e.title .. '"') end
    end
    while #titles > 6 do table.remove(titles, 1) end
    local zones = chapter.zoneOrder or {}
    local from = zones[1] or "the road"
    local to = zones[#zones] or from
    local body = table.concat({
        say(B.chapterOpen, { from = from, to = to }),
        say(B.chapterList, { list = Join(titles) }),
        say(B.chapterClose),
    }, "\n\n")
    return { title = chapter.mainZone and ("The Days in " .. chapter.mainZone) or "The Road", body = body }
end
