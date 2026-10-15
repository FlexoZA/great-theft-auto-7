---
name: audit
description: In-depth audit of this branch before it goes into staging - runs tools/audit (headless game checks, arsenal matrix, map checks, line checks, rated out of 10) and adds a verified code review for scatter, shortcuts, sloppiness and bugs, with a final rating out of 10. Use when asked to audit, rate or review a branch or pull request for staging.
---

# Audit this branch

Two halves: the machine audit (`tools/audit`, docs/audit.md), which plays
the game headless and is the same check GitHub runs on every pull request
into `staging`, and your review of the diff for what a machine can't judge.
Both end in one report with a rating out of 10.

## 1. Run the machine audit

```bash
git fetch origin -q
mkdir -p build/audit
luajit tools/audit/run.lua --md build/audit/report.md --json build/audit/report.json
```

It takes a few minutes (it runs the base too, in a worktree, to tell new
findings from inherited ones). Add `--full` when the branch touches weapons,
abilities or enemies broadly and you want every gun against every enemy.
Read `build/audit/report.json`: `score` (overall, per category, pass) and
`findings` (`new` true are this branch's). If it errored rather than
rating, say so and stop: the audit is the gate and must work.

## 2. Review the diff

```bash
git diff $(git merge-base HEAD origin/staging) --stat
git diff $(git merge-base HEAD origin/staging)
```

Read every changed hunk, and enough of the surrounding file to judge it.
Read `CLAUDE.md` and the parts of `docs/features.md` the change touches.
Look for what the script can't see; for each kind, the questions to ask:

**Bugs**
- Logic: wrong condition, off-by-one, a nil that can reach arithmetic or an
  index, a list changed while iterating it, state never reset between quests
  or games (`exitGame`, `serverQuestEnded`, `mapChanged`), a timer not scaled
  by `dt`.
- Multiplayer: does it work for 2-8 players and for someone joining mid-game
  (`serverPlayerJoined` sends what was only sent on change)? Does a bot
  (`player.bot`) or a player who left (`car.owner` not in `server.players`)
  break it? Messages: right side, right fields, `tonumber` on receipt.
- Authority: anything that changes the world happens on the host; a client
  only sends intent. Is a client trusted with an amount, a position, an item,
  a price, a target it could forge? Is a client message's field used
  unchecked (nil, NaN from `tonumber("nan")`, huge, negative)?
- Saving: does new state that should survive a restart go through
  `serverSaveWorld`/`serverSavePlayer` with a `version`?

**Shortcuts**
- A fix in the wrong place (patching a symptom in feature B for a bug in A).
- Hard-coded names, ids, map names or coordinates where the data exists.
- A special case for one quest/enemy/gun where the general path should
  have been fixed (e.g. damage that skips `serverShotAt`, an enemy that
  ignores `damage`/`type`, a weapon that only hurts players).
- Copying another feature's code instead of a hook or a shared helper.
- Features coupled directly (`require` of another feature's internals,
  reaching into its `sv`) where docs/features.md has a hook for it.

**Scatter**
- One idea spread over many files or features, or a feature's code living
  outside its folder (`src/features/<name>/`), assets outside it.
- Core files (`main.lua`, `src/net/`, `src/states/`, `src/audio/`,
  `src/art/`, `src/state.lua`, `src/ui.lua`, `src/car.lua`, `src/body.lua`)
  changed for anything but a minimal new hook.
- Unrelated changes riding along (formatting churn, drive-by edits).

**Sloppiness**
- Names that don't say what they hold; comments that don't match the code
  or are missing where the surrounding code has them (match its density and
  voice); dead code; leftover debugging; magic numbers that belong in the
  tuning block at the top of the file.
- Missing project standards: equipment without `tierStats`/`blurb`
  (CLAUDE.md "Tiers"); damage without a type; an enemy character or boss
  without its own brain module; a boss that doesn't tire through
  `src/features/bosses` or seek health drops; a quest map without a
  backdrop, soundtrack or ammo; keys tested raw instead of `Controls`;
  sounds not on an `Audio` channel; a `CHANGELOG.md` line missing or
  written for developers instead of players.

**Verify every finding before you keep it.** Open the code and confirm it:
quote the line, trace the value, and when it is about behaviour, prove it
with a small headless run (see `tools/audit/harness.lua`: `Harness.boot()`,
`game:quest(id)`, `game:run(s)`, `game:enemies()`). Drop anything you can't
confirm; say "plausible" only for what you could not run. Don't repeat what
the machine audit already reported.

## 3. Rate it

Score your review out of 10 on the audit's categories (stability, arsenal,
maps, quality, structure) the same way the script does: start at 10, a
blocker zeroes the category, a major finding costs 2, a minor one 0.5.
Overall review score = the same weights (25/20/15/20/20).

**Final rating = the lower of the machine score and the mean of the
machine score and your review score**, to one decimal. It passes at 7.0
with no blocker in either half and the machine audit passing (that one is
the gate GitHub enforces).

## 4. Report

Write `build/audit/review.md`:

```markdown
# Audit: <final>/10 <PASS|FAIL>

Machine audit <score>/10, review <score>/10. <one sentence verdict>

## Must fix before staging
<blockers and majors, each: what, where (file:line), why it matters, the fix>

## Should fix
<minors>

## Machine audit
<paste build/audit/report.md's findings table and category scores>
```

Then tell the user the final rating, pass or fail, and the must-fix list in
a few lines, with a link to `build/audit/review.md`. Offer to fix the
findings; don't change code before they say so.
