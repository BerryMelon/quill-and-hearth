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
-- Notes + template writer
---------------------------------------------------------------------------
assert(load(TEMPLATES_SRC, "=Templates.lua"))("QuillAndHearth", QH)
local T = QH.Templates

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

test("Template writer covers voyage, fear, death, errands and notes", function()
    local events = Log()
    local d = P.BuildDigest(P.FindSittings(events, 0), 5, P.DeriveHooks({ fear = "boars" }))
    local w = T.Write(d, { name = "Ari", traits = { voice = "Plain", temperament = "Brooding" } })
    assert(w.title and w.title ~= "", "no title")
    local body = w.body
    assert(body:find("Auberdine"), "opening should name the rest place")
    assert(body:find("Kalimdor"), "voyage missing")
    assert(body:find("Boar Trouble"), "key task missing")
    assert(body:lower():find("boar"), "fear line missing")
    assert(body:find("spirit healer"), "death missing")
    assert(body:find("Westfall"), "errands line missing")
    assert(body:find("letter from my sister"), "note missing")
    assert(not body:find("{"), "unfilled placeholder: " .. body)
    print("\n--- sample template entry (Plain, Brooding) ---\nTITLE: " .. w.title .. "\n\n" .. body .. "\n")
end)

test("Template writer is deterministic and voice-aware", function()
    local d = P.BuildDigest(P.FindSittings(Log(), 0), 1, {})
    local a = T.Write(d, { traits = { voice = "Terse" } })
    local b = T.Write(d, { traits = { voice = "Terse" } })
    eq(a.body, b.body, "same night, same text")
    local poetic = T.Write(d, { traits = { voice = "Poetic", temperament = "Cheerful" } })
    assert(poetic.body ~= a.body, "voices should differ")
    print("--- sample template entry (Terse) ---\nTITLE: " .. a.title .. "\n\n" .. a.body .. "\n")
end)

test("Template writer handles a quiet night and no profile", function()
    local d = P.BuildDigest({ { events = {}, rest = { seq = 3, t = 1, type = "rest", kind = "campfire", zone = "Durotar" } } }, 2, {})
    local w = T.Write(d, nil)
    assert(w.body:find("Durotar"), "rest place missing")
    assert(not w.body:find("{"), "unfilled placeholder")
end)

print(("%d Lua tests passed in total"):format(passed))

---------------------------------------------------------------------------
-- Writer: stored prompts, rewriting entries
---------------------------------------------------------------------------
do
    GetServerTime = function() return 2000000000 end
    local W = { Pipeline = QH.Pipeline, Templates = QH.Templates }
    assert(load(WRITER_SRC, "=Writer.lua"))("QuillAndHearth", W)
    W.charKey = "Ari-Test"
    -- An older entry already in the journal (e.g. migrated from the old companion).
    W.char = { events = Log(), meta = { name = "Ari" }, state = {}, journal = { entries = {
        { id = "Ari-Test:old", t = 1, day = 1, title = "Old Title", body = "Old text", prompt = "OLD PROMPT", source = "companion" },
    } } }
    W.Send = function() end
    W.GetProfile = function() return { name = "Ari", traits = { voice = "Plain" } } end

    test("Template entries keep their prompt", function()
        local pending = W:GetPendingWrite()
        assert(pending and pending.prompt:find("TITLE:"), "no pending prompt")
        local entry = W:WriteTemplateEntry(pending)
        eq(entry.source, "template")
        eq(entry.prompt, pending.prompt)
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

-- The live check uses the richer log (note, voyage, death, fear, errands).
do
    local d = P.BuildDigest(P.FindSittings(Log(), 0), 1, P.DeriveHooks({ fear = "boars" }))
    SAMPLE_PROMPT = P.BuildPrompt({ name = "Ari Thorne", class = "Warrior", traits = { temperament = "Brooding", voice = "Plain" }, fear = "boars" },
        { name = "Ari", race = "Human", sex = 3, faction = "Alliance" }, "", d, {})
end

PARSE = P.ParseReply
