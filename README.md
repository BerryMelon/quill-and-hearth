# Quill & Hearth

An automatic, first-person roleplay journal for **World of Warcraft: Forever**. Your character writes about their adventures whenever they rest at an inn, in a city, or by a campfire.

- `addon/QuillAndHearth/`: the in-game addon (Lua). It records story moments, builds the story prompt and shows the journal.

**No extra software needed.** When your character rests, the journal shows an *unwritten page*. Click **Copy prompt**, paste it into any AI chat (ChatGPT, Gemini, Claude...), copy the reply back with **Paste entry**, and the entry is written instantly.
- `companion/` (optional): a desktop companion (Node/TypeScript) that writes entries automatically with Gemini, for players who don't want to copy and paste. See [companion/README.md](companion/README.md).

## Development

The addon folder is linked into the game with a directory junction:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\QuillAndHearth" "<repo>\addon\QuillAndHearth"
```

```
npm install
npm run lua:check   # syntax-check all addon Lua files
npm run lua:test    # run the addon's story pipeline (Pipeline.lua) outside WoW
npm run lua:live    # send a real in-game prompt to Gemini and parse the reply (needs companion/.env)
```

The companion overwrites `addon/QuillAndHearth/Generated/Entries.lua`. To keep that out of commits, run once: `git update-index --skip-worktree addon/QuillAndHearth/Generated/Entries.lua`.

### In-game commands
| Command | What it does |
|---|---|
| `/quill` | open your journal (also the minimap book button: left-click opens the journal, right-click opens a menu to rest or set up your character) |
| `/quill minimap` | show or hide the minimap button |
| `/quill help` | list commands |
| `/quill setup` | set up (or redo) your character: Total RP 3 import or the setup wizard |
| `/quill profile` | show what the journal knows about your character |
| `/quill note [text]` | add a personal note to your next entry (no text opens a window; also in the minimap menu) |
| `/quill export` | copy your whole journal as Markdown (also in the minimap menu and the journal window) |
| `/quill rest` | rest and write in your journal (inn, city or campfire; reloads UI) |
| `/quill status` | number of recorded moments |
| `/quill dump [n]` | list the last n events |
| `/quill live` | print events as they are recorded |
| `/quill restcheck` | debug: rest state + your buffs |
| `/quill clear` | debug: delete recorded events |

Recorded data lives in `WTF\Account\<account>\SavedVariables\QuillAndHearth.lua`. It is written on `/reload` or logout.
