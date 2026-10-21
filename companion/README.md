# Quill & Hearth companion

Writes your character's journal with Gemini whenever they **rest** in game: logging out at an inn, in a city, or by a campfire, or using `/quill rest`.

## Setup
1. `npm install`
2. Copy `.env.example` to `.env` and set `GEMINI_API_KEY` (get one at https://aistudio.google.com/apikey). `WOW_DIR` defaults to the Forever beta folder.
3. `npm start`, then leave it running while you play.

## Running it
The companion only runs when you start it yourself (`npm start`). It never starts with Windows on its own. It runs in its console window; close it or press Ctrl+C to stop, or use `npm run stop` from another terminal. Only one companion runs at a time (`data/companion.pid`); logs go to `data/companion.log`.

While running, it rewrites `Entries.lua` every minute as a heartbeat. When the game loads, the addon uses it to tell whether the companion is running, and shows a warning if it isn't.

## How it works
1. The addon records story events and a REST marker into `WTF/Account/<acct>/SavedVariables/QuillAndHearth.lua`. The game writes that file on logout or `/reload`.
2. The companion notices the change and splits the log into **sittings** (the events between two rests).
3. For each sitting it:
   - scores events (story text, quest lines, deaths, first visits, and anything that touches the character's fears or goals)
   - groups them into storylines
   - dates them on an in-character calendar (a rest is a night; a sea voyage takes days)
   - collapses small errands into one line
4. Gemini writes one first-person entry per sitting, guided by a **character brief** (from the TRP3 sheet or the onboarding answers) and a rolling **story memory**.
5. Entries are saved in `data/<character>.json` (the source of truth) and written to the addon's `Generated/Entries.lua`. They show up in game after your next login or `/reload`. The addon then deletes the events that have already been written up.

## Commands
| Command | |
|---|---|
| `npm start` | watch and write entries as you rest |
| `npm run once` | process once and exit |
| `npm run stop` | stop a background companion |
| `npm run once -- --mock-llm --dry-run` | offline test: fake writer, prints entries, writes nothing |
| `npm test` | unit + end-to-end tests (mock LLM) |
| `npm run typecheck` | TypeScript check |
