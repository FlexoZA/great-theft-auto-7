# The audit

Every pull request into `staging` is audited and rated out of 10 before it
may be merged. The audit reads the change, then plays the game headless (no
window, no LÖVE: plain LuaJIT with a stand-in for LÖVE) and looks at what
happens. It runs on GitHub for every pull request into `staging` and the
merge button stays grey until it passes; run it yourself first:

```bash
make audit
```

That is `luajit tools/audit/run.lua`: this branch against `origin/staging`
(`git fetch` first). It prints the score and every finding; `--md
report.md` writes the report the pull request gets. `/audit` in Claude Code
runs it and adds a code review on top (below).

## The score

Five categories, each starting at 10 and losing points for every finding
**this branch brings in**:

| Category | Weight | What it checks |
| --- | --- | --- |
| Stability | 25% | the game loads; every quest starts and plays without an error; every message handler survives rubbish from a client; the world and players save and load back |
| Arsenal coverage | 20% | every gun, damaging ability and grenade hurts every kind of enemy; equipment has tiers that resolve and a shop blurb |
| Map completeness | 15% | every quest map has a backdrop past its edge, a soundtrack, ammo crates, a star home (unless its city-map spec says `noHome`); no enemy, crate or spawn point inside a wall |
| Code quality | 20% | luacheck on added lines; prints, debug switches, TODOs, swallowed errors, commented-out code; assets made per frame; movement not scaled by `dt`; very long functions |
| Structure | 20% | the feature rules of `CLAUDE.md`: gameplay in its feature folder, core files untouched or minimal, no reaching into another feature's files, raw keys, damage without a type, data fields named like hooks, copy-paste, a branch scattered over many features, the changelog, enemies the audit can't see, undocumented hooks |

A **blocker** (the game doesn't load, a quest crashes, a Lua syntax error)
zeroes its category and fails the audit on its own. A **major** finding
costs 2 points, a **minor** one half a point. The overall score is the
weighted mean; **7.0 and no blocker passes**.

### What the branch inherited is not its fault

The game checks are run twice, in parallel: on this branch and on the
base (where the branch left `origin/staging`, checked out into a worktree
and judged by this branch's audit). A finding the base has too is listed
as debt, folded away in the report, and costs nothing. The line checks
only ever look at added lines. So a pull request is rated on what it does:
fix some debt and it disappears from the list; add a gun that can't hurt
the Baron and it shows up.

## How the game checks work

- **Headless game** (`tools/audit/harness.lua`, `stub.lua`): the real
  `main.lua`, server and client joined by an in-process loopback instead
  of sockets, the real game screen updating and drawing. Sounds are
  silent but recorded, draw calls are counted.
- **Quests**: every quest in `Quests.list` is taken the way the job board
  does it (`quests:serverBegin`), played for a few seconds, toured to its
  fight, then the blue star home is taken. Anything that errors is a
  blocker.
- **Tours** (`tools/audit/stages.lua`): bosses come out late (the Major at
  the flag, Bigfoot at the end of the trail). The audit's player can't die
  and is put on the spots a map marks (`bossX/bossY`, the flag, a finale),
  and a quest whose fight needs more gets a script there. The report notes
  every kind of enemy that was seen but never hittable; a new quest whose
  enemies never show up wants a script.
- **Enemies**: every feature that owns enemies lists them on the host with
  `serverEnemies(server, add)` (docs/features.md). The audit flags a feature
  that answers `serverShotAt` but not this, since it can't aim at what it
  can't see.
- **Arsenal matrix** (`tools/audit/checks/arsenal.lua`): for each kind of
  enemy met, the player stands on foot in clear sight of one and uses each
  gun (trigger held, re-aimed), each ability with damage of its own or a
  gun (cast the way the game does), and each grenade. Hurt means its health
  dropped or it went down, and a round or blast of the player's reached
  some target (so Cyber Feud's two sides shooting each other don't count).
  Five tries from different sides before a pair is a finding; bosses are
  healed back between tries. Only the pairs a branch touches are tested
  (a changed gun against every enemy, a changed enemy against every gun;
  a change to weapons, damage or tiers tests everything). `--full` tests
  every pair (slow).
- **Soundtrack**: a looping sound of 15 s or more made or played after the
  quest started. **Backdrop**: surroundings is asked to draw with the
  camera on the map's corner; nothing drawn means the bare grid.
- **Rubbish**: every server message handler gets empty, wrong, huge,
  negative, infinite and NaN fields (LuaJIT's `tonumber("nan")` is NaN). A
  handler that errors would let any client crash the host.

## The review (`/audit` in Claude Code)

The script catches what a machine can be sure of. `/audit` runs it, then
reads the diff as a reviewer would for what it can't: logic bugs, a
shortcut that only works for one case, a fix in the wrong place, a client
trusted with something the server should decide, duplicated ideas that a
pattern match misses, a boss without a brain module or stamina, a new
enemy that ignores a damage type. It verifies each finding against the
code, scores the review out of 10 on the same categories and writes both
into `build/audit/review.md`, ready to paste into the pull request.

## Options

```
luajit tools/audit/run.lua [--base <ref>] [--full] [--quest <id>]... [--no-base] [--no-game]
                           [--md <file>] [--json <file>] [--pass <score>]
```

`--quest` limits the game checks to those quests (quick when you are
working on one). `--no-base` skips the base run (everything counts as new);
`--no-game` runs only the line checks.

## The rules on GitHub

Two rulesets (Settings -> Rules -> Rulesets) hold the branches to this:

- **staging-audit** on `staging`: the `audit` check must pass before a pull
  request merges; no force-pushes, no deleting the branch.
- **main-release** on `main`: only a repository admin (Christiaan, @FlexoZA)
  may change it, at a release; no force-pushes, no deleting it. A pull
  request into `main` must come from `staging`: the `from-staging` check
  (`.github/workflows/release-source.yml`) fails for any other branch.

A pull request into `staging` must name `staging` as its base: GitHub
offers `main`, the default branch, and a pull request into `main` is never
audited.

## Changing the rules

Thresholds, core paths and the list of features that answer `serverShotAt`
without being enemies are in `tools/audit/config.lua`. Penalties and the
pass mark are at the top of `tools/audit/report.lua`. A change there is a
change to the rules everyone is held to: say why in the pull request. Mark
a line the line checks should leave alone with a trailing
`-- audit: allow` comment, and say why next to it.
