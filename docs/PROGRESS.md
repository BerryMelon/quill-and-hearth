# Quill & Hearth: Progress (paused 2026-10-19)

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

## Built: v0.4.0 (minimap button + companion autostart), not yet tested in game
- `UI/MinimapButton.lua`: a draggable round book button on the minimap (left-click: journal; right-click: a MenuUtil menu with Open journal / Rest and write (disabled unless resting) / Set up character / Show profile / Hide button). `/quill minimap` toggles it. The addon compartment supports the same left/right clicks.
- Companion: `npm run autostart:on` / `autostart:off` (Windows Startup folder VBS launcher, hidden), `npm run stop`, single instance (`data/companion.pid`), log file (`data/companion.log`), heartbeat (rewrites Entries.lua every 60 s; the addon compares `generatedAt` with its load time and warns if the companion isn't running).
- An addon can't launch programs, which is why autostart happens at Windows sign-in.

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
