## What

<!-- One or two sentences on what this changes. -->

## Why

<!-- Link the issue or describe the problem. -->

## Checklist

- [ ] Target branch is `staging` (only @FlexoZA opens `staging` -> `main` release PRs)
- [ ] `luacheck .` passes
- [ ] `make audit` passes (7.0 or better, no blocker; the Audit check reruns it here)
- [ ] `love .` starts and the change was played
- [ ] No build output or editor files committed
