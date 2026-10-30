---
name: verify
description: Format, lint, self-check, build and relaunch ClaudeWatch, then confirm it is running with sane memory. Use after any code change and before committing.
---

Run from the repo root and stop at the first failure, showing the error.

1. `swift format -i ClaudeWatch.swift Tests/ParserCheck.swift`
2. `./check.sh`: must end with `ParserCheck OK`. The `onChange` deprecation warning is expected (macOS 13 support).
3. `./build.sh`: must end with `Installed /Applications/ClaudeWatch.app`.
4. Wait about 60 seconds for the startup read to finish, then run `ps -o rss=,%cpu= -p $(pgrep -x ClaudeWatch)`. Steady state is roughly 100–200 MB and near 0% CPU between refreshes. Report the numbers. If memory keeps climbing across a few samples, flag it.
5. `tail -5 ~/Library/Logs/ClaudeWatch.log`: report any new failures.

If parsing logic changed and `Tests/fixture.jsonl` doesn't cover the new case, add a fixture line and an assert in `Tests/ParserCheck.swift` before saying it's done.
