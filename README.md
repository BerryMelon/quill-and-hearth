# Quill & Hearth

An automatic, first-person roleplay journal for **World of Warcraft: Forever**. Your character writes about their adventures whenever they rest at an inn, in a city, or by a campfire.

**No extra software needed.** When your character rests, the journal shows an *unwritten page*:
- **Write it plainly**: your character writes a simple entry instantly, in their own voice, with no AI.
- **Copy prompt / Paste entry**: paste the prompt into any AI chat (ChatGPT, Gemini, Claude...) and paste the reply back for a rich, personal entry.

Every entry keeps its prompt, so you can turn a plain entry into an AI one later (**Copy prompt / Paste new version**). Total RP 3 profiles can be imported; otherwise a short setup wizard asks about your character.

## Layout
- `addon/QuillAndHearth/`: the addon (Lua). It records story moments, builds the story prompt, writes plain entries and shows the journal.
- `tools/`: dev tooling (Lua syntax check, Lua tests via fengari).
- `docs/`: plan, progress notes, research.

## Development

The addon folder is linked into the game with a directory junction (Forever beta, and retail for testing):

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\QuillAndHearth" "<repo>\addon\QuillAndHearth"
mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\QuillAndHearth" "<repo>\addon\QuillAndHearth"
```

```
npm install
npm run lua:check   # syntax-check all addon Lua files
npm run lua:test    # run the addon's pure-Lua logic (pipeline, template writer, writer, export) outside WoW
npm run lua:live    # dev only: send a real prompt to Gemini and parse the reply (needs GEMINI_API_KEY in a git-ignored .env)
```

### In-game commands
| Command | What it does |
|---|---|
| `/quill` | open your journal (also the minimap book button: left-click opens the journal, right-click opens a menu) |
| `/quill rest` | rest and write in your journal (inn, city or campfire) |
| `/quill note [text]` | add a personal note to your next entry (no text opens a window; also in the minimap menu) |
| `/quill export` | copy your whole journal as Markdown (also in the minimap menu and the journal window) |
| `/quill setup` | set up (or redo) your character: Total RP 3 import or the setup wizard |
| `/quill profile` | show what the journal knows about your character |
| `/quill options` | open the options (text size, entry length, mood prompt, auto-open, writing ritual, minimap button); also in Options > AddOns |
| `/quill minimap` | show or hide the minimap button |
| `/quill help` | list commands |
| `/quill status` | number of recorded moments |
| `/quill dump [n]` | debug: list the last n events |
| `/quill live` | debug: print events as they are recorded |
| `/quill restcheck` | debug: rest state + your buffs |
| `/quill clear` | debug: delete recorded events |

Everything is saved in `WTF\Account\<account>\SavedVariables\QuillAndHearth.lua` (written on `/reload` or logout).
