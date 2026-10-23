# Quill & Hearth: Progress

> **2026-10-21: the companion app was removed (v0.9.0).** Copy-paste with any AI chat plus the in-game template writer cover everything, with no installs, no API keys and no privacy concerns. Flonsus's 2 companion-written entries were migrated into his saved journal (backup: `SavedVariables\QuillAndHearth.lua.before-companion-removal.bak`; the companion's data was copied to `scratch\quill-and-hearth-companion-backup`). The companion code is still in git history (last commit with it: `2509049`). Sections below that mention the companion are historical.

## v0.11.0 (G1, G3, G4, G5, I4, K1 + Session-Based AI Prompts & Uncut TRP3)
- **Session-based AI prompts & uncut TRP3 (`TRP3.lua`, `Pipeline.lua`, `Writer.lua`, `Onboarding.lua`, `UI/Bridge.lua`):**
  - Removed the 400-character truncation in `Pipeline.DescribeCharacter` and raised `TRP3.lua` `MAX_ABOUT_TEXT` to `20000` (existing characters with truncated TRP3 snapshots auto-upgrade silently on login).
  - After character setup / TRP3 import (or via `/quill session` / minimap menu **"AI chat session setup..."**), `Bridge:ShowSessionSetup()` provides a standalone **AI Chat Session Setup** prompt (`P.BuildSetupPrompt`) with the full rules, uncut character sheet, and `STORY SO FAR`, telling the AI to reply *"Ready to write <Name>'s journal."*
  - Once an AI session is active (`char.state.aiSessionStarted`), nightly prompts (`sessionPrompt`) omit the repeated rules, character sheet, and story-so-far block, sending only tonight's moments + format reminder.
  - Inside `Write with AI` (`Bridge.lua`), a **"New AI chat / reset session (include full character & rules)"** checkbox sits next to `Select all` so players can toggle between the short session prompt and the full prompt anytime they start a new chat thread. Every saved entry still stores `fullPrompt` for future rewrites, and `P.ShortenPrompt` lets rewrites use the short format too.
- **G1 (Foes & deaths):** Tracks the hostile target (`PLAYER_TARGET_CHANGED` / `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`) so `PLAYER_DEAD` records what killed you (`killer`, `killerKind`), and defeating a notable foe (`elite`, `rare`, `rare elite`, `boss`) records a `foe` moment (once per foe per sitting).
- **G3 (Spells learned):** `LEARNED_SPELL_IN_TAB` captures newly learned abilities (skipping Rank > 1 upgrades and deduplicating per character) as `spell_learned` moments; `UNIT_SPELLCAST_SUCCEEDED` filters out system/consumable/gathering casts (`LOGINEFFECT`, `Opening*`, `Food`, `Drink`, `Herbalism*`, `Find *`, etc.) so `Abilities used most` stays focused on real class abilities.
- **G4 (Indoors detection):** `PushRest` records `indoors = IsIndoors()` for the prompt and ritual emotes (the manual weather selector buttons on the unwritten page were removed after in-game testing).
- **G5 (Coin milestones & heavy spends):** `PLAYER_MONEY` captures first-time coin milestones (`first silver coin` at <= L10, `first gold piece`, `10g`, `100g`, `1000g`, pre-marked on `READY` so existing characters don't false-trigger) and heavy trainer/repair/mount expenses that leave your pouch nearly empty.
- **I4 (Dynamic writing ritual emotes & taint-free right-click menu):** Replaced `/read` with `/sit` + context-aware local chat emotes (`QH:PickRitualEmote` varies by campfire, indoors/tavern, and mood, printed via `DEFAULT_CHAT_FRAME:AddMessage` instead of `SendChatMessage("EMOTE")` which is blocked by the C++ engine outdoors), and replaced `MenuUtil.CreateContextMenu` on the minimap button with a custom zero-taint dropdown (`QuillAndHearthMenu`) to prevent `ADDON_ACTION_FORBIDDEN` popups.
- **AI-Only Journaling + "Save for later" & Chronological Ordering (`Writer.lua`, `UI/JournalFrame.lua`, `UI/Bridge.lua`):**
  - Removed `Templates.lua` and all *"Write it plainly"* buttons (entries and chapters) so Quill & Hearth is focused 100% on AI-driven roleplay journaling.
  - Added **Save for later** (`QH:SavePendingForLater`): when resting without an AI chat open, players can seal that day's digest into the journal (`unwritten = true`, tagged `LATER` in the list) and keep playing the next day cleanly.
  - Enforced **chronological day ordering** (`QH:GetFirstUnwrittenEntry`, `QH:GetUnwrittenEntryPrompts`, `QH:SaveUnwrittenEntry`): if Day 1 was saved for later and hasn't been written with AI yet, Day 2's prompt is locked until Day 1 is written (with a **Go to Day 1** button), because Day 2's prompt needs Day 1's `STORY SO FAR` (`j.memory`) and title. Writing Day 1 immediately unlocks Day 2 with the updated story so far.
- **Randomized slice-of-life flavor cues (`P.RollFlavors` in `Pipeline.lua`):** Seeded per rest (`rest.seq`, `rest.t`, `startDay`) and kept hidden from the unwritten page UI so they remain a surprise when the entry is written. Busy nights roll `0..3` cues; quiet nights roll `1..4` generalized creative cues across context-aware slots (`road`, `combat` using actual abilities from `digest.abilities`, `town`, and `hearth` matched to `campfire` / `indoors` / `outdoors`) so the AI invents original slice-of-life moments each night.
- **K1 (Custom icon & release packager):** `tools/pack.mjs` (`npm run pack`) generates the 64x64 32-bit uncompressed `addon/QuillAndHearth/Media/Icon.tga` (used in `QuillAndHearth.toc`, journal portrait, and minimap button) and builds `dist/QuillAndHearth-v0.11.0.zip`. 29 Lua tests.

## v0.10.3
- Entry tools are now **Edit**, a **star** (favourite; raid-marker star icon, gold/faded) and a **delete** button (red X) with a confirmation ("the entry and its prompt will be lost for good"). Hide and the Show-hidden filter were removed; previously hidden entries are unhidden once. Deleting a chapter's first entry moves its saved chapter summary to the next entry. The nights a deleted entry covered stay written (no new unwritten page).

## v0.10.2
- The People page and button were removed (too bland). People are still tracked (`char.people`: first met, zone, tasks). When a quest giver met before these nights appears again, the prompt gets a **PEOPLE MET BEFORE** section (where first met, earlier tasks), and the plain writer says "… again". 29 Lua tests.

## v0.10.1 (testing feedback on the Forever stress test, 2026-10-21)
- Text boxes: clicking anywhere in an empty box now focuses it (the scroll frame takes the click; the old click catcher sat behind it).
- Read aloud removed (TTS voices don't fit characters).
- Prompt: respect class and level (class-true abilities, level-appropriate power); the character's level and game class in the prompt; **abilities used most** since the last rest (player's own casts, counted via UNIT_SPELLCAST_SUCCEEDED, stored on the rest event); quest ids; and an optional lookup hint for https://warcraft.wiki.gg/ (rely on the given text for new Forever content).
- Live check (level 10 orc shaman): Earth Shock, lightning and Healing Wave used, nothing beyond level.

## Built: v0.10.0 (improvement batch), being tested on the Forever stress test
- **Reading:** text size setting (small/medium/large; larger defaults, more padding and line spacing), a soft divider under the header, a resizable journal window (size remembered), and Read aloud (`C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)`, the 12.x signature, checked in Blizzard's API docs). A drop cap isn't possible: WoW text can't flow around a big letter.
- **Story:** quest-giver names (`questnpc`/`npc`) in the prompt and template, plus a People page (`char.people`); mood buttons on the unwritten page (stored on the entry); time of day at rest; milestone reflections (level x0, first death, first dungeon); length setting (short/normal/long); new moments: rare/epic loot, reputation standing, profession ranks (every 25), achievements, sitting by a campfire. Chat-message patterns are built from Blizzard's own format strings (works in any client language).
- **Chapters:** derived from entries (new level band or new continent), shown as headers in the left list; a chapter page with Summary with AI / Write it plainly; summaries are included in the export.
- **Writing flow:** one window for AI (copy the prompt at the top, paste the reply below), auto-save when a TITLE:/ENTRY: reply is pasted; auto-open on the unwritten page after rest/login (setting).
- **Control:** edit an entry by hand, hide/unhide (never deleted; Show hidden filter), favourites (filter + export option), an options panel (Settings canvas category, `/quill options`).
- **Ritual:** book sound and the /read emote when the journal opens after a rest (setting).
- Tests: 28 Lua tests.

## Current state (v0.9.0)
- The addon only: event capture, rest markers (inn/city/campfire), onboarding (TRP3 import or wizard), the journal (unwritten page: Write it plainly / Copy prompt / Paste entry; written entries: Copy prompt / Paste new version), personal notes, Markdown export, and a minimap button + menu.
- Data lives only in SavedVariables (`char.journal`: entries with stored prompts, processedThrough, nextDay, memory). No `Generated/Entries.lua` anymore.
- Tests: `npm run lua:check`, `npm run lua:test` (20 Lua tests). `npm run lua:live` (dev only) reads `GEMINI_API_KEY` from the root `.env`.
- Next: polish (chapters, hide entries, UI tweaks from screenshots), the campfire retest when the Forever beta is back, and then publishing (to be discussed).


**Repo:** https://github.com/BerryMelon/quill-and-hearth (public, `main`, first commit `f98e5ab`)
**Local:** `C:\Users\chund\.gemini\antigravity\scratch\quill-and-hearth`, linked into `_classic_beta_\Interface\AddOns\QuillAndHearth`

## Docs
- [PLAN.md](PLAN.md): approved v1 implementation plan (architecture, data flow, phases)
- [IDEATION.md](IDEATION.md): original brainstorm (scoring, threads, in-world calendar, chapters)
- [FOREVER_ADDON_DEV.md](FOREVER_ADDON_DEV.md): WoW: Forever addon dev notes (TOC 16001, game type camelot/forever, secret values)

## Key decisions
- An addon can't call an LLM (no network) ??**companion app** (Node/TS command-line program that watches the save files, Gemini, key in `.env`). It reads `SavedVariables/QuillAndHearth.lua` and writes `addon/QuillAndHearth/Generated/Entries.lua`. It never writes to SavedVariables.
- **First-person** journal, **English only**, entries are written **only on rest**: a real logout (not `/reload`) or `/quill rest` in a rested area (inn/city) or at a campfire (camp buff + within 20 yards of where the buff was gained).
- **TRP3 is optional:** if it's detected, ask to import; otherwise run onboarding (full name or in-game name, in-game class or RP class, short characteristics questions that set the tone).
- No social/RP chat capture in v1. Party members: names and class only, for group moments.
- v1 UI uses only **Blizzard's stock templates and textures**; redesign after testing.
- Forever client: `C:\Program Files (x86)\World of Warcraft\_classic_beta_` (build 1.60.1.70450). Test character: Flonsus-ClassicBetaPvE (Undead Priest). Git author: Doheny <berrymelon@me.com>.

## Done: Phase 1 (addon foundation)
- Event capture: quests with story text, zones, first visits, continent changes, dungeons with party names/classes, flights, hearthstone, new home, level-ups, deaths.
- Rest markers: real logout (not `/reload`) or `/quill rest` while in a rested area, or at a campfire.
- Debug commands: `/quill status | dump | live | restcheck | clear`.
- `npm run lua:check` syntax-checks the addon.

## Tested in game
- ??Addon loads; quests are recorded with their full quest and turn-in text (verified in SavedVariables).
- ??`/quill rest` in an inn records `kind = rested` and reloads.
- ?筌?沃???Campfire rest was allowed far from the fire (the buff lasts a long time). **Fixed:** the addon now remembers where you were when you got or refreshed the camp buff, and only allows campfire rest within 20 yards of that spot. **Not yet retested in game.**

## Next time
1. Journal UI was checked in game on 2026-10-20 and looks good (bring screenshots next time for tuning). Still to test: the full loop (`npm start` in companion/, then `/quill rest` at an inn, the ink-drying status, Reload UI, and reading the new entry).
2. Pending in-game tests: the TRP3 import, and the campfire fix (paste the `/quill restcheck` buff list).
3. Phase 5 polish: chapters, entry rewrite/hide, UI redesign after v1 feedback.

## Built: v0.8.0 (export), not yet tested in game
- `Export.lua`: the whole journal as Markdown (an addon can't write files or PDFs), shown pre-selected in a read-only box for Ctrl+C. Header (name, race/class, realm, entry count, date), one `## Day N: Title` section per entry with the place/level line. Opened from the journal footer's **Export** button, the minimap menu's **Export journal...**, or `/quill export`. `Export.ToMarkdown` is pure and tested (20 Lua tests).

## Done: v0.7.0 (rewrite any entry). The user tested everything fully: looking good. The user checked it in game: looking good
- Length rule (in game + companion): about 150 words for a quiet night, up to about 1000 words when many things happened, never padded (was 120-350).
- Every new entry stores the prompt it was written from (`entry.prompt`): in-game entries (plain or pasted) and companion entries (the companion stores a copy-paste-ready prompt with the TITLE/ENTRY/MEMORY format). Entries written before v0.7.0 have no prompt, so they show no buttons.
- Written entries with a prompt show **Copy prompt** / **Paste new version**. In-game entries are replaced in place (`source` becomes `paste`, `rewrittenAt`); companion entries get `journal.overrides[id]` (the generated file is never modified). The page shows (written plainly) / (rewritten).
- Story memory is only replaced when rewriting the newest entry.
- Bridge refactored to jobs (`PendingJob` / `RewriteJob`); journal selection is by entry id.
- Tests: 18 Lua tests (incl. Writer with WoW stubs), 14 companion tests.

## Done: v0.6.0 (template writer + notes). The user tested Write it plainly: simple but usable.
- `Templates.lua`: in-game template writer (no AI). Voice banks for Plain/Formal/Poetic/Terse, closings by temperament, told in chronological order with day transitions (next day / days later), voyages, first visits, flights, hearthstone, deaths, dungeons with companions, fear lines (hooks), minor list (max 3), errands, notes; deterministic per rest (seeded). The journal's unwritten page has a third button: **Write it plainly**. Template entries add a short line to the AI story memory.
- `Notes.lua`: `/quill note [text]` or the minimap menu's **Add a note...** (multi-line dialog, 500 chars). Notes are `note` events, always KEY (outside the cap), shown in the prompt as `In their words: ...`, used by the companion too.
- Prompt (in game + companion): MINOR moments get a sentence at most and may be left out entirely to stay within the length; notes always included.
- Tests: 14 Lua tests (incl. template samples), 14 companion tests; live Gemini check with a note, voyage, death and fear passed.

## Done: v0.5.0 (no companion needed: copy-paste bridge). Tested on retail 2026-10-21: the copy-paste flow works well and the UI looks good
- The addon also loads on retail (Interface `120105, 16001`), linked into `_retail_\Interface\AddOns` for testing while the Forever beta is down.
- Decision (2026-10-21): tiered approach (see NO_COMPANION_OPTIONS.md). 1) The copy-paste bridge is now the default (done). 2) Next: an in-game template writer (C1) so entries work with no AI at all, later grown into a pre-written snippet library (C2). 3) The companion is optional.
- `Pipeline.lua`: Lua port of sittings/calendar/scoring/digest/prompt plus ParseReply (tolerant of markdown, missing markers, WoW pipes). Several unwritten nights merge into one entry. Hooks come from the profile's fear text.
- `Writer.lua`: in-game entries in `char.journal` (entries, processedThrough, nextDay, memory); GetEntries merges companion and in-game entries; pruning uses the max of both processedThrough values.
- `UI/Bridge.lua`: Copy prompt dialog (read-only, pre-selected, Ctrl+C) and Paste reply dialog (Ctrl+V, Save to journal).
- Journal: an *unwritten page* row/page with a summary of moments, the steps, and Copy/Paste buttons. `/quill rest` no longer reloads unless the companion is running. The companion skips nights already written in game.
- Tests: `npm run lua:test` (10 Lua tests via fengari), `npm run lua:live` (real Gemini reply parsed by the addon's parser: passed, and the fear hook showed up in the writing), companion 13 tests.

## Built: v0.4.0 (minimap button + companion heartbeat), not yet tested in game
- `UI/MinimapButton.lua`: a draggable round book button on the minimap (left-click: journal; right-click: a MenuUtil menu with Open journal / Rest and write (disabled unless resting) / Set up character / Show profile / Hide button). `/quill minimap` toggles it. The addon compartment supports the same left/right clicks.
- Companion: `npm run stop`, single instance (`data/companion.pid`), log file (`data/companion.log`), heartbeat (rewrites Entries.lua every 60 s; the addon compares `generatedAt` with its load time and warns if the companion isn't running).
- **Decision (2026-10-21): no autostart with Windows** (privacy, since the addon will be published to other users). The user starts the companion manually; an addon can't launch programs anyway.

## Built: Phase 4 (journal UI, v0.3.0)
- `UI/JournalFrame.lua`: stock `ButtonFrameTemplate`; entry list on the left (newest first, NEW tags), a parchment reading page on the right (`QuestTitleFont`/`QuestFont`), footer status (moments since last rest / ink drying + Reload UI button), an empty-state page that explains the companion.
- `/quill` opens the journal; `/quill help` lists commands; addon compartment (minimap addon menu) entry with a tooltip; login notice for new entries.
- Companion: gemini-3.5-flash (2.5 is retired, 3.7/3.8/flash-latest hang on this key) with fallback gemini-3-flash-preview, retries/backoff, a 120 s timeout; unfinished quests are never narrated as done; double-escaped newlines are fixed.
- First real run done: Flonsus has 2 entries in `Generated/Entries.lua`.

## Built: Phase 3 (companion app, `companion/`)
- Node + TypeScript (tsx, vitest, zod 4, @google/genai 2.x, chokidar, luaparse).
- `savedvars/`: Lua ??JSON (UTF-8 safe; atomic writes).
- `pipeline/`:
  - `segment` splits the log into sittings between rests
  - `calendar` assigns in-character days (+4 days for a voyage to another continent, +1 day after more than 6 hours idle, a rest = next day)
  - `score` picks key/minor/background moments (capped at 6 key moments; +5 for touching the brief's hooks)
  - `digest` builds storylines, the journey, and collapsed errands
- `llm/`:
  - `brief` turns the TRP3 sheet or onboarding answers into a character brief + hooks (cached by profile hash)
  - `write` writes one first-person entry per sitting and updates the story memory (strict in-world rules: no game terms, explained travel)
  - `mock` is the offline writer
- `state/`: `data/<char>.json` is the source of truth; `Generated/Entries.lua` is rendered from it with `processedThrough` per character (the addon prunes on load).
- 11 tests passing (incl. end-to-end on the real SavedVariables fixture); `tsc` clean; dry run against the live install works.

## Done (tested in game): Phase 2 setup wizard
- Wizard tested by the user and works. The TRP3 import is still untested (TRP3 not installed yet).

## Built, not yet tested in game: Phase 2 (onboarding, v0.2.0)
- First login without a profile: if TRP3 is ready, a popup offers **Import / Set up manually / Later**. Otherwise an intro popup leads to the wizard.
- `TRP3.lua`: snapshots the TRP3 profile (name, title, race/class, age, eyes, height, weight, birthplace, residence, misc fields, personality traits with strength 0-20, About in all 3 templates, Currently) into `profile.trp3`. Field names verified against the TRP3 source. **TRP3 officially supports Forever** (its TOC lists `16001`).
- When the TRP3 characteristics/About change (detected via the profile ID plus TRP3's `v` counters), the addon asks whether to re-import.
- `UI/OnboardingWizard.lua` (stock `ButtonFrameTemplate`), 4 steps: name (or in-game name) ??in-game class or RP class ??temperament/outlook/upbringing ??drive/voice + optional fear and past.
- Saved as `QuillAndHearthDB.characters[key].profile` with `source = "trp3" | "manual"`.
- Commands: `/quill setup`, `/quill profile`.
