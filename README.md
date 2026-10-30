# ClaudeWatch

A macOS menu bar app that shows what your Claude Code sessions are doing.

- Live sessions with title, project link, current step and running time
- Helper agents with their task and step-by-step activity
- Estimated time to finish, based on how long similar prompts/commands took in the last 7 days
- Task-list progress, live command output, tokens per step
- Session (5-hour) and weekly usage limits, plus Claude status
- Search, "done" and "running too long" notifications, start at login

It reads Claude Code's local logs in `~/.claude/projects` and `~/.claude/tasks`. Usage limits use your existing Claude Code login from the macOS Keychain; nothing is stored or sent anywhere except Anthropic's usage endpoint.

## Build

Requires macOS 13+ and Xcode Command Line Tools.

```sh
./build.sh
```

This compiles the app, installs it to `/Applications/ClaudeWatch.app`, and launches it.
