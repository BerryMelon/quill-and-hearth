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

-- Expose a real prompt for the live check (tools/live-prompt-check).
local d = P.BuildDigest(P.FindSittings(flonsus.events, 0), 1, P.DeriveHooks({ fear = "gnolls" }))
SAMPLE_PROMPT = P.BuildPrompt({ name = "Flonsus Vire", class = "Priest", traits = { temperament = "Brooding", voice = "Formal" }, fear = "gnolls" },
    flonsus.meta, "", d, {})
PARSE = P.ParseReply
