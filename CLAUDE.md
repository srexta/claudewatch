# ClaudeWatch

macOS menu bar app (SwiftUI `MenuBarExtra`) that shows live Claude Code sessions, helper agents, time estimates and plan usage limits. Single file: `ClaudeWatch.swift`. No Xcode project, no packages.

## Commands

- `./build.sh` — compile with `swiftc`, install to `/Applications/ClaudeWatch.app`, relaunch
- `./check.sh` — `swift format lint --strict` + parser self-check against `Tests/fixture.jsonl`
- `swift format -i ClaudeWatch.swift Tests/ParserCheck.swift` — auto-format

Run `./check.sh` before every commit. Use the `/verify` skill for the full loop.

## Coding standards

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/); formatting is enforced by `.swift-format` (4-space indent, 140 cols)
- Keep everything in `ClaudeWatch.swift` unless it passes ~1500 lines; `check.sh` strips everything from `@main` down, so keep `@main` last
- Target macOS 13+: no APIs newer than macOS 13 without `#available`
- No third-party dependencies
- No force-try; force-unwrap only on literal URLs
- File/network work goes on `Store.queue` or URLSession, never the main thread; publish to `@Published` on main
- Short `//` comments only where the why isn't obvious; mark deliberate shortcuts with `// ponytail:` and the upgrade path
- Any change to parsing logic needs a matching case in `Tests/fixture.jsonl` + assert in `Tests/ParserCheck.swift`

## Data sources (all undocumented Claude Code internals; may change between versions)

| Data | Location |
|---|---|
| Session transcripts | `~/.claude/projects/<project-dir>/<session-id>.jsonl` |
| Helper agents | `~/.claude/projects/<project-dir>/<session-id>/subagents/agent-*.jsonl` + `.meta.json` (`description`, `finished`) |
| Task lists | `~/.claude/tasks/<session-id>/*.json` (`subject`, `status`) |
| Live command output | `/private/tmp/claude-<uid>/<project-dir>/<session-id>/tasks/*.output` |
| Login token | Keychain service `Claude Code-credentials`, account = macOS username, JSON `claudeAiOauth.accessToken` |
| Usage limits | `GET https://api.anthropic.com/api/oauth/usage`, header `anthropic-beta: oauth-2025-04-20` |
| Service status | `https://status.claude.com/api/v2/status.json` |

## Gotchas

- Transcripts log each assistant message in several chunks: the same `tool_use` id repeats and `usage.output_tokens` grows. Dedupe by id, keep max tokens per message id.
- User prompts starting with `<` are system/command noise, not real prompts.
- There can be two Keychain items named `Claude Code-credentials` (accounts `unknown` = MCP OAuth only, and the username = real login). Read via `/usr/bin/security` with `-a NSUserName()`; `SecItemCopyMatching` fails silently for this item.
- `resets_at` has microseconds (`.499942+00:00`); `ISO8601DateFormatter` can't parse that, so strip the fraction first (`parseDate`).
- `Parser` is incremental: it remembers the byte offset and only reads complete new lines. If a file shrinks it resets.
- `Store.cache` is pruned every refresh to files used that round, which keeps memory flat (~135 MB steady).
- `~/Library/Logs/ClaudeWatch.log` auto-trims at 1 MB and only records failures. Never log tokens or credential contents.
- Notifications go through `osascript` (shows as "Script Editor"), so unsigned builds work without notification entitlements.

## Security

- Never print, log or commit the OAuth token. It is sent only to `api.anthropic.com`.
- External processes (`open`, `osascript`, `security`) are launched with argument arrays, never through a shell.
