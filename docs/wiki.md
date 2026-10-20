# The wiki

`docs/wiki` is the game's wiki for players: what is in the game and how it
works. Its pages are written by a tool from the game's own code, so the
numbers on them are the numbers in play, and a balance change shows up in
the wiki the next time it is written. Nobody edits a page by hand.

So far it covers the enemies: a page per enemy with its portrait, what it
carries, what it can do and how to beat it, and an index by where you meet
them (`docs/wiki/enemies/README.md`).

## Commands

- `make wiki` writes the pages (`luajit tools/wiki/run.lua`), headless, in
  a second or two. `luajit tools/wiki/run.lua --check` only says which are
  out of date.
- `make wiki-portraits` draws the portraits that are missing, then writes
  the pages. `WIKI_ALL=1` draws them all again; `WIKI_ONLY="city karen"`
  only plays those (the city, and quest ids). It opens a small LÖVE window
  for a few minutes.

The audit (`make audit`, docs/audit.md) flags a page that is out of date
and an enemy met in play with no page, so run `make wiki` (and
`make wiki-portraits` for a new enemy) before a pull request and commit
`docs/wiki` with the change.

## Enemies: `wikiEnemies(add)`

Every feature with enemies answers `wikiEnemies(add)` (docs/features.md)
and calls `add({...})` once per page. The numbers come from the feature's
own constants, formatted into the text (`("%g"):format(...)`), never typed
in as literals: that is what keeps the wiki right. A number that is a
module's `local` either gets its `add` call in that file or becomes a field
of the module. The entry is added by the feature that draws the enemy (its
`drawBelowCars`/`drawAboveCars` draw the portrait). Police
(`src/features/police/init.lua`) is the worked example.

| Field | |
|---|---|
| `kind` | the kind its `serverEnemies` reports: the portrait is drawn from it |
| `id` | the page's name, when two pages share a kind (the kind with `/` as `-` otherwise) |
| `pick(e)` | true for the `serverEnemies` entry to draw (`e.id` is the enemy's own table): which of a shared kind is this page's, or when it looks itself (a droid out of its cloak) |
| `name`, `where`, `about` | what players call it, where and when you meet it, what it is like (required) |
| `quests` | the quest ids it is on, in story order; the first decides its section of the index. None for the city |
| `boss` | true for a boss |
| `scaling` | "boss", "enemy" or "none", when the default (boss for bosses, enemy on a quest) is wrong: the page's footnote on how its numbers grow (src/features/bosses) |
| `stats` | `{ label, value[, unit] }` rows: Health, Shield, Hits, Speed, Sight, how many |
| `weapons` | `{ name, text }`: each gun or attack, its damage, type, rate and range |
| `abilities`, `tips` | sentences: what it does, and how to beat it |
| `drops` | what it leaves |
| `portrait` | false for something the portrait run can't meet (a bot car, the dropship) |
| `portraitLayers` | "all" when its portrait needs what its feature draws under cars too (the portrait is drawn from `drawAboveCars` alone otherwise, so the level under it stays out) |
| `drawImmune` | true to draw it although it is always `immune` (VEX's projection) |

Write it the way CHANGELOG.md is written: for players, plain, short.

## Portraits

`tools/wiki/portraits` is a LÖVE program (`make wiki-portraits` links it
and the game into `build/wiki-love`). It is the audit's headless game
(`tools/audit/harness.lua`) with LÖVE's real graphics put back: the city
first, then every quest toured the way the audit tours them
(`tools/audit/stages.lua`). The first time it meets an enemy that has a
page and no portrait, it walks the player up to it and draws only that
enemy's feature (its `drawAboveCars`, where bodies are, unless the entry
says `portraitLayers = "all"`), centred on it, on a plain ground, without
words or the flat bars over heads, and keeps only the shape the enemy is
(what is joined to it; a neighbour or a speech bubble is wiped):
`docs/wiki/enemies/img/<id>.png`. Enemies the tours never
bring out (city events, an ability's horde, a fight's late waves) get a
scene in `tools/wiki/scenes.lua`.
