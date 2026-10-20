# Quill & Hearth: Progress (paused 2026-10-19)

**Repo:** https://github.com/BerryMelon/quill-and-hearth (public, `main`, first commit `f98e5ab`)
**Local:** `C:\Users\chund\.gemini\antigravity\scratch\quill-and-hearth`, linked into `_classic_beta_\Interface\AddOns\QuillAndHearth`

## Docs
- [PLAN.md](PLAN.md): approved v1 implementation plan (architecture, data flow, phases)
- [IDEATION.md](IDEATION.md): original brainstorm (scoring, threads, in-world calendar, chapters)
- [FOREVER_ADDON_DEV.md](FOREVER_ADDON_DEV.md): WoW: Forever addon dev notes (TOC 16001, game type camelot/forever, secret values)

## Key decisions
- An addon can't call an LLM (no network) → **companion app** (Node/TS command-line program that watches the save files, Gemini, key in `.env`). It reads `SavedVariables/QuillAndHearth.lua` and writes `addon/QuillAndHearth/Generated/Entries.lua`. It never writes to SavedVariables.
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
- ✅ Addon loads; quests are recorded with their full quest and turn-in text (verified in SavedVariables).
- ✅ `/quill rest` in an inn records `kind = rested` and reloads.
- 🐞→🔧 Campfire rest was allowed far from the fire (the buff lasts a long time). **Fixed:** the addon now remembers where you were when you got or refreshed the camp buff, and only allows campfire rest within 20 yards of that spot. **Not yet retested in game.**

## Next time
1. Retest the campfire fix and paste the `/quill restcheck` buff list (exact camp buff name and spell ID → `CAMP_AURA_SPELLS`).
2. Phase 2: onboarding (TRP3 import prompt + manual wizard: name, class/RP class, characteristics).
3. Check whether TRP3 runs on the Forever beta.
4. Phase 3: companion app (Node/TS, Gemini). Phase 4: journal UI with stock Blizzard templates.
