# Quill & Hearth

An automatic, first-person roleplay journal for **World of Warcraft: Forever**. Your character writes about their adventures whenever they rest at an inn, in a city, or by a campfire.

- `addon/QuillAndHearth/`: the in-game addon (Lua). It records story moments and shows the journal.
- `companion/`: desktop companion (Node/TypeScript, coming in phase 3). It turns the recorded moments into journal entries using an LLM.

## Development

The addon folder is linked into the game with a directory junction:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\QuillAndHearth" "<repo>\addon\QuillAndHearth"
```

```
npm install
npm run lua:check   # syntax-check all addon Lua files
```

### In-game commands
| Command | What it does |
|---|---|
| `/quill` | help |
| `/quill setup` | set up (or redo) your character: Total RP 3 import or the setup wizard |
| `/quill profile` | show what the journal knows about your character |
| `/quill rest` | rest and write in your journal (inn, city or campfire; reloads UI) |
| `/quill status` | number of recorded moments |
| `/quill dump [n]` | list the last n events |
| `/quill live` | print events as they are recorded |
| `/quill restcheck` | debug: rest state + your buffs |
| `/quill clear` | debug: delete recorded events |

Recorded data lives in `WTF\Account\<account>\SavedVariables\QuillAndHearth.lua`. It is written on `/reload` or logout.
