-- Tests for addon/QuillAndHearth/Pipeline.lua, run by tools/lua-test.mjs (fengari).

-- Minimal WoW API stubs used by Pipeline.lua.
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local QH = {}
assert(load(PIPELINE_SRC, "=Pipeline.lua"))("QuillAndHearth", QH)
assert(load(FIXTURE_SRC, "=fixture"))()
local P = QH.Pipeline

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print("ok    " .. name)
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local flonsus = QuillAndHearthDB.characters["Flonsus-ClassicBetaPvE"]

test("FindSittings splits at rests", function()
    local s = P.FindSittings(flonsus.events, 0)
    eq(#s, 2)
    eq(s[1].rest.seq, 2)
    eq(#s[2].events, 2)
    eq(#P.FindSittings(flonsus.events, 5), 0)
end)

test("BuildDigest merges several nights into one entry", function()
    local d = P.BuildDigest(P.FindSittings(flonsus.events, 0), 3, {})
    eq(d.startDay, 3)
    eq(d.endDay, 4, "second sitting is the next day")
    eq(d.nights, 2)
    eq(d.lastRest.seq, 5)
    eq(d.restPlace, "Gallows' End Tavern, Tirisfal Glades")
    assert(not d.isEmpty)
end)

test("Unfinished quests are marked NOT finished", function()
    local d = P.BuildDigest(P.FindSittings(flonsus.events, 0), 1, {})
    local found
    for _, t in ipairs(d.threads) do
        for _, m in ipairs(t.moments) do
            if m.title == "Graverobbers" then found = m end
        end
    end
    assert(found, "Graverobbers moment missing")
    eq(found.kind, "took on a task (NOT finished yet)")
    assert(found.story:find("Mass Graves"))
end)

test("Hooks from fears make a key moment", function()
    local hooks = P.DeriveHooks({ fear = "Gnolls, and deep water" })
    local hasGnoll
    for _, h in ipairs(hooks) do if h == "gnoll" then hasGnoll = true end end
    assert(hasGnoll, "gnoll hook missing: " .. table.concat(hooks, ","))
    local d = P.BuildDigest(P.FindSittings(flonsus.events, 0), 1, hooks)
    local m = d.threads[1].moments[1]
    eq(m.importance, "KEY")
    eq(m.touched[1], "gnoll")
end)

test("BuildPrompt contains the rules, character, story and reply format", function()
    local d = P.BuildDigest(P.FindSittings(flonsus.events, 0), 1, {})
    local prompt = P.BuildPrompt({ name = "Flonsus Vire", class = "Plague Doctor", traits = { voice = "Terse" } },
        flonsus.meta, "", d, {})
    assert(prompt:find("first person"))
    assert(prompt:find("Name: Flonsus Vire"))
    assert(prompt:find("Class / calling: Plague Doctor"))
    assert(prompt:find("Way with words: Terse"))
    assert(prompt:find('"Graverobbers"'))
    assert(prompt:find("This is the first entry"))
    assert(prompt:find("TITLE:"))
    assert(prompt:find("MEMORY:"))
end)

test("ParseReply reads the requested format", function()
    local r = P.ParseReply("TITLE: Ichor and Ash\nENTRY:\nFirst paragraph.\n\nSecond paragraph.\nMEMORY: Flonsus took a task in Brill.")
    eq(r.title, "Ichor and Ash")
    eq(r.body, "First paragraph.\n\nSecond paragraph.")
    eq(r.memory, "Flonsus took a task in Brill.")
end)

test("ParseReply tolerates markdown and chatter", function()
    local r = P.ParseReply("**TITLE:** \"The Mass Graves\"\n\n**ENTRY:**\nThe night is cold.\n\n**MEMORY:** Things happened.")
    eq(r.title, "The Mass Graves")
    eq(r.body, "The night is cold.")
    eq(r.memory, "Things happened.")
end)

test("ParseReply without markers uses the first short line as the title", function()
    local r = P.ParseReply("A Cold Night\n\nI wrote nothing of note today.")
    eq(r.title, "A Cold Night")
    eq(r.body, "I wrote nothing of note today.")
    eq(r.memory, nil)
end)

test("ParseReply ignores a title containing the word Entry", function()
    local r = P.ParseReply("TITLE: Journal Entry: Brill\nENTRY:\nBody text.\nMEMORY: m")
    eq(r.title, "Journal Entry: Brill")
    eq(r.body, "Body text.")
end)

test("ParseReply strips WoW escape pipes and rejects empty pastes", function()
    local r = P.ParseReply("TITLE: X\nENTRY:\n|cffff0000Red|r text || done")
    eq(r.body, "Red text  done")
    eq(P.ParseReply("   "), nil)
end)

print(("%d Lua tests passed"):format(passed))

---------------------------------------------------------------------------
-- Notes + digest
---------------------------------------------------------------------------
-- A richer, scripted log: notes, a voyage, a death, a fear-touching quest, small errands.
local function Log()
    local seq, t = 0, 1800000000
    local events = {}
    local function ev(e)
        seq, t = seq + 1, t + 300
        e.seq, e.t = seq, t
        e.zone = e.zone or "Westfall"
        e.continent = e.continent or "Eastern Kingdoms"
        events[#events + 1] = e
    end
    ev({ type = "quest_accept", questID = 1, title = "Boar Trouble", text = "The Rockhide boars are tearing up the fields. Thin their numbers. Farmers are scared." })
    ev({ type = "quest_done", questID = 1, title = "Boar Trouble", rewardText = "You did it! The fields are safe again, and the Saldeans thank you from the bottom of their hearts for this." })
    for i = 1, 6 do ev({ type = "quest_done", questID = 10 + i, title = "Errand " .. i }) end
    ev({ type = "note", text = "I keep the letter from my sister in my coat. I haven't opened it." })
    ev({ type = "death" })
    ev({ type = "zone", from = "Wetlands", zone = "Darkshore", continent = "Kalimdor", fromContinent = "Eastern Kingdoms", continentChanged = true })
    ev({ type = "rest", kind = "rested", zone = "Darkshore", subzone = "Auberdine" })
    return events
end

test("Notes are always KEY moments and appear in the prompt", function()
    local events = Log()
    local d = P.BuildDigest(P.FindSittings(events, 0), 1, {})
    local note
    for _, th in ipairs(d.threads) do
        for _, m in ipairs(th.moments) do if m.note then note = m end end
    end
    assert(note, "note moment missing")
    eq(note.importance, "KEY")
    local prompt = P.BuildPrompt(nil, { name = "Ari", race = "Human", class = "Warrior" }, "", d, {})
    assert(prompt:find('In their words: "I keep the letter from my sister'), "note not in prompt")
    assert(prompt:find("leave out MINOR moments"), "length rule missing")
end)

print(("%d Lua tests passed in total"):format(passed))

---------------------------------------------------------------------------
-- Writer: stored prompts, rewriting entries
---------------------------------------------------------------------------
do
    GetServerTime = function() return 2000000000 end
    local W = { Pipeline = QH.Pipeline }
    assert(load(WRITER_SRC, "=Writer.lua"))("QuillAndHearth", W)
    W.charKey = "Ari-Test"
    W.char = { events = Log(), meta = { name = "Ari" }, state = {}, journal = { entries = {
        { id = "Ari-Test:old", t = 1, day = 1, title = "Old Title", body = "Old text", prompt = "OLD PROMPT", source = "paste" },
    } } }
    W.Send = function() end
    W.GetProfile = function() return { name = "Ari", traits = { voice = "Plain" } } end
    W.GetSetting = function(_, key) return ({ moodPrompt = true, length = "normal" })[key] end

    test("AI entries keep their full prompt", function()
        local pending = W:GetPendingWrite()
        assert(pending and pending.prompt:find("TITLE:"), "no pending prompt")
        local entry = W:SaveWrittenEntry(pending, "TITLE: Across the Water\nENTRY:\nWe reached Auberdine.\nMEMORY: Ari reached Auberdine.")
        eq(entry.source, "paste")
        eq(entry.prompt, pending.fullPrompt)
        eq(W:GetPendingWrite(), nil, "nothing left to write")
    end)

    test("Rewriting the newest entry replaces it and updates the story memory", function()
        local entries = W:GetEntries()
        local newest = entries[#entries]
        local updated = W:RewriteEntry(newest.id, "TITLE: A Better Night\nENTRY:\nRicher words.\nMEMORY: Ari crossed the sea.")
        eq(updated.title, "A Better Night")
        eq(updated.body, "Richer words.")
        eq(updated.source, "paste")
        eq(W:GetJournal().memory, "Ari crossed the sea.")
        eq(updated.prompt ~= nil, true, "prompt kept for further rewrites")
    end)

    test("Rewriting an older entry replaces it in place and leaves the memory alone", function()
        local updated = W:RewriteEntry("Ari-Test:old", "TITLE: Overridden\nENTRY:\nNew text.\nMEMORY: should be ignored")
        eq(updated.title, "Overridden")
        eq(updated.source, "paste")
        eq(W:GetJournal().memory, "Ari crossed the sea.", "older rewrite must not rewind the story")
        eq(W:FindEntry("Ari-Test:old").body, "New text.")
        eq(#W:GetEntries(), 2)
    end)

    test("A bad paste is rejected", function()
        local ok, err = W:RewriteEntry("Ari-Test:old", "   ")
        eq(ok, nil)
        assert(err:find("Paste the AI"))
    end)
end
print(("%d Lua tests passed in total (with Writer)"):format(passed))

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
do
    local X = { RegisterCommand = function() end }
    assert(load(EXPORT_SRC, "=Export.lua"))("QuillAndHearth", X)
    local E = X.Export

    test("Markdown export has a header and one section per entry, oldest first", function()
        local md = E.ToMarkdown({
            { day = 1, title = "Ichor and Ash", body = "First.\n\nSecond.", zone = "Tirisfal Glades", subzone = "Brill", restKind = "campfire", level = 6 },
            { day = 2, dayEnd = 5, title = "Across the Sea", body = "Salt and rope.", zone = "Darkshore", level = 12 },
        }, { name = "Flonsus Vire", race = "Undead", class = "Priest", realm = "Stormrage", exportedOn = "2026-10-21" })
        assert(md:find("^# Flonsus Vire's Journal\n"), "title")
        assert(md:find("%*Undead Priest of Stormrage%*"), "subtitle")
        assert(md:find("2 entries · exported 2026%-10%-21"), "count/date")
        local a = md:find("## Day 1: Ichor and Ash", 1, true)
        local b = md:find("## Days 2-5: Across the Sea", 1, true)
        assert(a and b and a < b, "sections in order")
        assert(md:find("*By a campfire near Brill, Tirisfal Glades · level 6*", 1, true), "place line")
        assert(md:find("First.\n\nSecond.", 1, true), "paragraphs kept")
        print("\n--- sample export ---\n" .. md)
    end)

    test("Markdown export of an empty journal", function()
        local md = E.ToMarkdown({}, { name = "Ari" })
        assert(md:find("0 entries", 1, true))
        assert(md:find("still blank", 1, true))
    end)
end
print(("%d Lua tests passed in total (with Export)"):format(passed))

---------------------------------------------------------------------------
-- v0.10: mood, time of day, givers, reflections, new moments, chapters, edit/hide/favourite
---------------------------------------------------------------------------
local function RichLog()
    local seq, t = 0, 1900000000
    local events = {}
    local function ev(e)
        seq, t = seq + 1, t + 300
        e.seq, e.t = seq, t
        e.zone = e.zone or "Eversong Woods"
        e.continent = e.continent or "Eastern Kingdoms"
        e.level = e.level or 9
        events[#events + 1] = e
    end
    ev({ type = "quest_accept", questID = 7, title = "Lynx Trouble", giver = "Magister Landra", text = "Feral lynxes stalk the village." })
    ev({ type = "quest_done", questID = 7, title = "Lynx Trouble", giver = "Magister Landra", rewardText = "You have my thanks. The village can breathe again, and the children may play in the glade once more." })
    ev({ type = "loot", item = "Sunstrider Blade", quality = "epic", qualityNum = 4 })
    ev({ type = "reputation", faction = "Silvermoon City", standing = "Honored" })
    ev({ type = "skill", skill = "Tailoring", rank = 75 })
    ev({ type = "achievement", achievement = "Explore Eversong Woods" })
    ev({ type = "camp" })
    ev({ type = "death", first = true })
    ev({ type = "level", level = 10 })
    ev({ type = "rest", kind = "campfire", zone = "Eversong Woods", subzone = "Fairbreeze Village", hour = 23, level = 10,
        abilities = { "Lightning Bolt (42)", "Earth Shock (18)", "Healing Wave (5)" } })
    return events
end

test("Prompt carries mood, time of day, reflections, givers and the length setting", function()
    local d = P.BuildDigest(P.FindSittings(RichLog(), 0), 1, {})
    eq(d.timeOfDay, "late at night")
    assert(#d.reflections >= 2, "level 10 and first death are milestones")
    local prompt = P.BuildPrompt(nil, { name = "Fistnal" }, "", d, {}, { mood = "Weary", length = "short" })
    assert(prompt:find("Fairbreeze Village, Eversong Woods, late at night", 1, true), "time of day")
    assert(prompt:find("mood tonight: Weary", 1, true), "mood")
    assert(prompt:find("A milestone", 1, true), "reflection")
    assert(prompt:find("Asked by: Magister Landra", 1, true), "quest giver")
    assert(prompt:find("Keep it brief", 1, true), "short length rule")
    assert(not prompt:find("%%s"), "no leftover format markers")
    assert(prompt:find("Respect the character's class and level", 1, true), "class/level rule")
    assert(prompt:find("warcraft.wiki.gg", 1, true), "wiki hint")
    assert(prompt:find("The character is level 10", 1, true), "level line")
    assert(prompt:find("Abilities used most since the last entry (times used): Lightning Bolt (42), Earth Shock (18), Healing Wave (5)", 1, true), "abilities")
    assert(prompt:find("(quest id 7)", 1, true), "quest id")
    for _, needle in ipairs({ '"Sunstrider Blade"', '"Silvermoon City"', "Tailoring to 75", '"Explore Eversong Woods"', "campfire" }) do
        assert(prompt:find(needle, 1, true), "missing " .. needle)
    end
    local long = P.BuildPrompt(nil, { name = "Fistnal" }, "", d, {}, { length = "long" })
    assert(long:find("Write generously", 1, true))
end)

test("Chat patterns built from Blizzard format strings", function()
    LOOT_ITEM_SELF = "You receive loot: %s."
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    FACTION_STANDING_CHANGED = "You are now %s with %s."
    SKILL_RANK_UP = "Your skill in %s has increased to %d."
    local C = { On = function() end, Listen = function() end, Safe = function(v) return v end, Truncate = function(s) return s end }
    hooksecurefunc = function() end
    assert(load(CAPTURE_SRC, "=Capture.lua"))("QuillAndHearth", C)
    local loot = C.PatternFrom(LOOT_ITEM_SELF)
    local link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
    eq(("You receive loot: " .. link .. "."):match(loot), link)
    local standing, faction = ("You are now Honored with Silvermoon City."):match(C.PatternFrom(FACTION_STANDING_CHANGED))
    eq(standing, "Honored")
    eq(faction, "Silvermoon City")
    local skill, rank = ("Your skill in Tailoring has increased to 75."):match(C.PatternFrom(SKILL_RANK_UP))
    eq(skill, "Tailoring")
    eq(rank, "75")
    eq(C.FormatCoins(45), "45 copper")
    eq(C.FormatCoins(350), "3 silver")
    eq(C.FormatCoins(12500), "1 gold and 25 silver")
    eq(C.FormatCoins(20000), "2 gold")
    eq(C.IsAbilityCast("Smite"), true)
    eq(C.IsAbilityCast("LOGINEFFECT"), false)
    eq(C.IsAbilityCast("Opening - No Text"), false)
    eq(C.IsAbilityCast("Drink"), false)
    eq(C.IsAbilityCast("Herbalism Skill"), false)
    eq(C.IsAbilityCast("Find Herbs"), false)
end)

do
    GetServerTime = function() return 2000000000 end
    local W = { Pipeline = QH.Pipeline, Templates = QH.Templates }
    assert(load(WRITER_SRC, "=Writer.lua"))("QuillAndHearth", W)
    W.charKey = "Fist-Test"
    W.char = { events = {}, meta = { name = "Fistnal" }, state = {}, journal = { entries = {
        { id = "a", t = 1, day = 1, level = 8, continent = "Eastern Kingdoms", zone = "Silvermoon City", title = "Arrival", body = "One." },
        { id = "b", t = 2, day = 2, level = 9, continent = "Eastern Kingdoms", zone = "Eversong Woods", title = "Lynxes", body = "Two." },
        { id = "c", t = 3, day = 3, level = 10, continent = "Eastern Kingdoms", zone = "Eversong Woods", title = "Stronger", body = "Three." },
        { id = "d", t = 4, day = 7, level = 11, continent = "Kalimdor", zone = "Darkshore", title = "Across the Sea", body = "Four." },
    } } }
    W.Send = function() end
    W.GetProfile = function() return { name = "Fistnal", traits = { voice = "Formal" } } end
    W.GetSetting = function(_, key) return ({ moodPrompt = true, length = "normal" })[key] end

    test("Chapters split on level bands and continents", function()
        local chapters = W:GetChapters()
        eq(#chapters, 3)
        eq(chapters[1].numeral, "I")
        eq(#chapters[1].entries, 2)
        eq(chapters[1].mainZone, "Silvermoon City")
        eq(chapters[2].key, "c")
        eq(chapters[3].key, "d")
        eq(chapters[3].isOpen, true)
        eq(chapters[1].title, "The Days in Silvermoon City")
    end)

    test("Chapter summaries: AI prompt and pasted reply", function()
        local ch = W:GetChapters()[1]
        local prompt = W:GetChapterPrompt(ch)
        assert(prompt:find("Day 2 - Lynxes:", 1, true), "entries in prompt")
        assert(prompt:find("TITLE:", 1, true))
        local saved = W:SaveChapterSummary(ch.key, "TITLE: Ashes of Quel'Thalas\nENTRY:\nA chapter of beginnings.")
        eq(saved.title, "Ashes of Quel'Thalas")
        eq(saved.summary, "A chapter of beginnings.")
    end)

    test("Edit and favourite entries", function()
        local e = W:EditEntry("b", "  The Lynx Hunt ", "New words.\r\nSecond line.")
        eq(e.title, "The Lynx Hunt")
        eq(e.body, "New words.\nSecond line.")
        local bad, err = W:EditEntry("b", "x", "   ")
        eq(bad, nil)
        assert(err)
        W:SetEntryFavorite("c", true)
        eq(W:FindEntry("c").favorite, true)
    end)

    test("Mood is stored on the entry and cleared afterwards", function()
        W.char.events = RichLog()
        W:SetPendingMood("Hopeful")
        local pending = W:GetPendingWrite()
        assert(pending.prompt:find("mood tonight: Hopeful", 1, true))
        local entry = W:SaveWrittenEntry(pending, "TITLE: Eversong\nENTRY:\nWords.\nMEMORY: m")
        eq(entry.mood, "Hopeful")
        eq(entry.continent, "Eastern Kingdoms")
        eq(W.char.state.pendingMood, nil)
    end)

    test("Markdown export with chapters, summaries and favourites", function()
        local X = { RegisterCommand = function() end }
        assert(load(EXPORT_SRC, "=Export.lua"))("QuillAndHearth", X)
        W.Export = X.Export
        W.BuildJournalMarkdown = X.BuildJournalMarkdown
        UnitName = function() return "Fistnal" end
        W.Print = function() end
        assert(W:DeleteEntry("a"), "delete")
        eq(W:FindEntry("a"), nil, "entry gone")
        eq(W:GetChapters()[1].key, "b", "chapter now starts at the next entry")
        eq(W:GetChapters()[1].title, "Ashes of Quel'Thalas", "chapter summary moved to the next entry")
        eq(W:DeleteEntry("nope"), false)
        local md, count = W:BuildJournalMarkdown(false)
        assert(md:find("## Chapter I: Ashes of Quel'Thalas", 1, true), "chapter heading")
        assert(md:find("> A chapter of beginnings.", 1, true), "chapter summary")
        assert(md:find("### Day 2: The Lynx Hunt", 1, true), "entry under chapter")
        assert(not md:find("Arrival", 1, true), "deleted entries are gone from the export")
        local favMd, favCount = W:BuildJournalMarkdown(true)
        eq(favCount, 1)
        assert(favMd:find("Stronger", 1, true) and not favMd:find("Lynx Hunt", 1, true))
        eq(count, 4, "b, c, d and the mood test's entry")
    end)
end
print(("%d Lua tests passed in total (v0.10)"):format(passed))

do
    local W = { Pipeline = QH.Pipeline, Templates = QH.Templates }
    assert(load(WRITER_SRC, "=Writer.lua"))("QuillAndHearth", W)
    W.charKey = "People-Test"
    W.Send = function() end
    W.GetProfile = function() return { name = "Grok", traits = { voice = "Plain" } } end
    W.GetSetting = function(_, key) return ({ moodPrompt = true, length = "normal" })[key] end
    W.char = { events = RichLog(), meta = { name = "Grok", class = "Shaman" }, state = {}, people = {
        ["Magister Landra"] = { first = 1, zone = "Silvermoon City", tasks = { "An Old Favour", "Lynx Trouble" } },
        ["Someone New"] = { first = 9999999999, tasks = {} },
    } }

    test("People met before are remembered in the prompt (not shown in the UI)", function()
        local pending = W:GetPendingWrite()
        local prompt = pending.prompt
        assert(prompt:find("PEOPLE MET BEFORE", 1, true), "section missing")
        assert(prompt:find("- Magister Landra; first met in Silvermoon City; earlier tasks: An Old Favour", 1, true), "earlier dealings")
        assert(not prompt:find("earlier tasks: An Old Favour, Lynx Trouble", 1, true), "tonight's task is not 'earlier'")
        assert(not prompt:find("Someone New", 1, true), "only people met before")
    end)

    test("v0.11: killer on death, notable foes, new spells learned, coin milestones/spends, and indoors", function()
        local events = {
            { seq = 1, t = 100, type = "foe", foe = "Hogger", kind = "elite", zone = "Elwynn Forest", level = 10 },
            { seq = 2, t = 120, type = "death", killer = "Defias Pillager", killerKind = "normal", zone = "Westfall", level = 10 },
            { seq = 3, t = 140, type = "spell_learned", spell = "Ghost Wolf", zone = "Orgrimmar", level = 10 },
            { seq = 4, t = 160, type = "money", kind = "milestone", milestone = "their first gold piece", zone = "Orgrimmar", level = 10 },
            { seq = 5, t = 180, type = "money", kind = "spent", spent = "90 silver", left = "4 silver", zone = "Orgrimmar", level = 10 },
            { seq = 6, t = 200, type = "rest", kind = "rested", indoors = true, zone = "Orgrimmar", subzone = "The Broken Tusk", hour = 20, level = 10 },
        }
        W.char.events = events
        W.char.journal = nil
        W:SetPendingMood("Weary")
        local pending = W:GetPendingWrite()
        local prompt = pending.prompt
        assert(prompt:find("indoors somewhere safe at The Broken Tusk, Orgrimmar, in the evening", 1, true), "indoors + evening")
        assert(prompt:find('slew a elite foe "Hogger"', 1, true), "notable foe in prompt")
        assert(prompt:find("was struck down by Defias Pillager (normal)", 1, true), "killer in prompt")
        assert(prompt:find('learned a new ability "Ghost Wolf"', 1, true), "learned spell in prompt")
        assert(prompt:find('saved up "their first gold piece"', 1, true), "coin milestone in prompt")
        assert(prompt:find("spent 90 silver and was left with 4 silver", 1, true), "coin spend in prompt")
    end)

    test("Save for later & chronological day ordering (Day 2 waits for Day 1's story so far)", function()
        local events = {
            { seq = 1, t = 100, type = "quest_done", questID = 101, title = "Day One Task", questLine = "Crown of the Earth", zone = "Teldrassil", level = 5 },
            { seq = 2, t = 200, type = "rest", kind = "rested", indoors = true, zone = "Teldrassil", subzone = "Dolanaar", hour = 21, level = 5 },
        }
        W.char.events = events
        W.char.journal = nil
        W:SetAISessionStarted(false)
        W:SetPendingMood("Hopeful")

        -- 1. Save Day 1 for later (no AI reply pasted yet).
        local pendingDay1 = W:GetPendingWrite()
        assert(pendingDay1 and pendingDay1.prompt, "Day 1 prompt is ready initially")
        local day1 = W:SavePendingForLater(pendingDay1)
        assert(day1 and day1.unwritten == true, "Day 1 saved as unwritten")
        eq(day1.day, 1)
        eq(day1.mood, "Hopeful")
        eq(W:GetPendingWrite(), nil, "live pending cleared after saving Day 1 for later")
        eq(W:GetFirstUnwrittenEntry().id, day1.id)

        -- 2. Player plays Day 2 and rests while Day 1 is still unwritten.
        table.insert(W.char.events, { seq = 3, t = 500, type = "quest_done", questID = 102, title = "Day Two Task", questLine = "Crown of the Earth", zone = "Teldrassil", level = 6 })
        table.insert(W.char.events, { seq = 4, t = 600, type = "rest", kind = "campfire", zone = "Teldrassil", subzone = "Starbreeze Village", hour = 22, level = 6 })

        local pendingDay2 = W:GetPendingWrite()
        assert(pendingDay2, "Day 2 has pending digest")
        eq(pendingDay2.digest.startDay, 2)
        eq(pendingDay2.blockedBy and pendingDay2.blockedBy.id, day1.id, "Day 2 is blocked by unwritten Day 1")
        eq(pendingDay2.prompt, nil, "Day 2 has no prompt while Day 1 is unwritten")

        -- Trying to write Day 2 before Day 1 is rejected.
        local badSave, badErr = W:SaveWrittenEntry(pendingDay2, "TITLE: Jumping Ahead\nENTRY:\nNope.\nMEMORY: m")
        eq(badSave, nil)
        assert(badErr:find("Write Day 1 first", 1, true), "error should tell user to write Day 1 first: " .. tostring(badErr))

        -- 3. Player saves Day 2 for later as well.
        local day2 = W:SavePendingForLater(pendingDay2)
        assert(day2 and day2.unwritten == true, "Day 2 also saved for later")
        eq(day2.day, 2)

        -- Day 2's prompt is still locked because Day 1 is unwritten.
        local p2Locked, p2Err, blocker = W:GetUnwrittenEntryPrompts(day2.id)
        eq(p2Locked, nil)
        eq(blocker.id, day1.id)
        assert(p2Err:find("Write Day 1 first", 1, true))

        -- Day 1's prompt IS available because it is the oldest unwritten entry.
        W:SetEntryMood(day1.id, "Weary")
        local p1Prompts = W:GetUnwrittenEntryPrompts(day1.id)
        assert(p1Prompts and p1Prompts.fullPrompt:find("Day One Task", 1, true), "Day 1 prompt has Day 1 task")
        assert(p1Prompts.fullPrompt:find("mood tonight: Weary", 1, true), "Day 1 prompt reflects updated mood")

        -- 4. Writing Day 1 with AI saves its title, body, and MEMORY, and unlocks Day 2!
        local writtenDay1 = W:SaveUnwrittenEntry(day1.id, "TITLE: The Boughs of Teldrassil\nENTRY:\nI rested in Dolanaar.\nMEMORY: Eminai completed her first task in Teldrassil and rested in Dolanaar.")
        assert(writtenDay1 and not writtenDay1.unwritten, "Day 1 is now written")
        eq(writtenDay1.title, "The Boughs of Teldrassil")
        eq(W:GetFirstUnwrittenEntry().id, day2.id, "Day 2 is now the first unwritten entry")

        -- 5. Day 2's prompt is now unlocked and contains Day 1's STORY SO FAR and title!
        local p2Unlocked = W:GetUnwrittenEntryPrompts(day2.id)
        assert(p2Unlocked, "Day 2 prompt is now unlocked")
        assert(p2Unlocked.fullPrompt:find("Eminai completed her first task in Teldrassil", 1, true), "Day 2 fullPrompt includes Day 1's STORY SO FAR")
        assert(p2Unlocked.fullPrompt:find("The Boughs of Teldrassil", 1, true), "Day 2 fullPrompt includes Day 1's title")
        assert(p2Unlocked.prompt:find("Day Two Task", 1, true), "Day 2 prompt has Day 2 task")

        local writtenDay2 = W:SaveUnwrittenEntry(day2.id, "TITLE: Embers at Starbreeze\nENTRY:\nCamped by the village.\nMEMORY: Eminai camped near Starbreeze Village on Day 2.")
        assert(writtenDay2 and not writtenDay2.unwritten, "Day 2 is now written")
        eq(W:GetFirstUnwrittenEntry(), nil, "no unwritten entries left")
    end)

    test("Session-based prompts and uncut TRP3 descriptions", function()
        local longBio = ("Born in the hills of Alterac, Grok walked the old elemental paths. "):rep(20) .. "\n\nEND_OF_LONG_TRP3_BIO"
        assert(#longBio > 1200, "bio exceeds old 400-char limit")
        W.GetProfile = function()
            return {
                name = "Grok",
                class = "Shaman",
                trp3 = { about = { text = longBio } },
            }
        end
        W.char.events = RichLog()
        W.char.journal = nil
        W:SetAISessionStarted(false)

        -- 1. Standalone setup prompt has the full uncut TRP3 bio, rules, and "Ready to write" instruction.
        local setup = W:GetSetupPrompt()
        assert(setup:find("END_OF_LONG_TRP3_BIO", 1, true), "full uncut TRP3 bio in setup prompt")
        assert(setup:find('Ready to write Grok\'s journal.', 1, true), "ready instruction in setup prompt")

        -- 2. Before session is started, pending.prompt defaults to fullPrompt.
        local pending1 = W:GetPendingWrite()
        eq(pending1.prompt, pending1.fullPrompt)
        assert(pending1.fullPrompt:find("END_OF_LONG_TRP3_BIO", 1, true), "fullPrompt includes uncut bio")
        assert(not pending1.sessionPrompt:find("CHARACTER", 1, true), "sessionPrompt omits repeated CHARACTER block")
        assert(pending1.sessionPrompt:find("WHAT HAPPENED SINCE THE LAST ENTRY", 1, true), "sessionPrompt has tonight's moments")
        assert(pending1.sessionPrompt:find("PEOPLE MET BEFORE", 1, true), "sessionPrompt keeps people met before")
        assert(#pending1.sessionPrompt < #pending1.fullPrompt * 0.55, "sessionPrompt is much shorter than fullPrompt")

        -- 3. Saving an AI entry automatically marks the session as started, and still stores fullPrompt on the entry.
        local saved = W:SaveWrittenEntry(pending1, "TITLE: Sparks in the Dark\nENTRY:\nThe fire crackled.\nMEMORY: Grok rested.")
        assert(saved, "entry saved")
        eq(W:IsAISessionStarted(), true, "session marked started after AI save")
        eq(saved.prompt, pending1.fullPrompt, "entry keeps fullPrompt for future standalone rewrites")

        -- 4. Next night's pending.prompt now defaults to the short sessionPrompt.
        table.insert(W.char.events, { seq = 99, t = 9999, type = "rest", kind = "campfire", zone = "Durotar", hour = 21, level = 11 })
        local pending2 = W:GetPendingWrite()
        eq(pending2.prompt, pending2.sessionPrompt, "active session uses short sessionPrompt by default")

        -- 5. ShortenPrompt turns any stored entry's full prompt into a short session prompt for rewrites.
        local shortRewrite = P.ShortenPrompt(saved.prompt, "Grok")
        assert(not shortRewrite:find("CHARACTER", 1, true))
        assert(shortRewrite:find("WHAT HAPPENED SINCE THE LAST ENTRY", 1, true))
    end)

    test("Standing slice-of-life rule in setup and full prompts (no pre-scripted cue lists)", function()
        local setup = P.BuildSetupPrompt({ name = "Eminai", class = "Priest" }, { name = "Eminai", class = "Priest" }, "", {})
        assert(setup:find("slice-of-life moments", 1, true), "setup prompt should contain the standing slice-of-life rule")

        local quietSitting = {
            {
                events = {},
                rest = { seq = 201, t = 1950000100, type = "rest", kind = "rested", indoors = true, zone = "Teldrassil", subzone = "Dolanaar" },
            },
        }
        local qd = P.BuildDigest(quietSitting, 1, {})
        local fullPrompt = P.BuildPrompt(nil, { name = "Eminai" }, "", qd, {})
        assert(fullPrompt:find("slice-of-life moments", 1, true), "full prompt should contain the standing slice-of-life rule")
        assert(not fullPrompt:find("SMALL SLICE-OF-LIFE MOMENTS", 1, true), "prompt should not inject pre-scripted slice-of-life cues")

        local sessionPrompt = P.BuildPrompt(nil, { name = "Eminai" }, "", qd, {}, { session = true })
        assert(not sessionPrompt:find("SMALL SLICE-OF-LIFE MOMENTS", 1, true), "session prompt should stay lean without pre-scripted cues")
    end)
end
print(("%d Lua tests passed in total (v0.11)"):format(passed))

-- The live check uses the richer log (note, voyage, death, fear, errands).
do
    local d = P.BuildDigest(P.FindSittings(Log(), 0), 1, P.DeriveHooks({ fear = "boars" }))
    SAMPLE_PROMPT = P.BuildPrompt({ name = "Ari Thorne", class = "Warrior", traits = { temperament = "Brooding", voice = "Plain" }, fear = "boars" },
        { name = "Ari", race = "Human", sex = 3, faction = "Alliance" }, "", d, {})
end

PARSE = P.ParseReply

-- Live check uses the v0.10 rich night (mood, time of day, milestone, quest giver).
do
    local d = P.BuildDigest(P.FindSittings(RichLog(), 0), 1, {})
    SAMPLE_PROMPT = P.BuildPrompt({ name = "Grok Stormcaller", class = "Shaman", traits = { temperament = "Stoic", voice = "Plain" } },
        { name = "Grok", race = "Orc", class = "Shaman", sex = 2, faction = "Horde" }, "", d, {}, { mood = "Weary", length = "short" })
end
