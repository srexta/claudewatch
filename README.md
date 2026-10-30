# ClaudeWatch

A macOS menu bar app that shows what your Claude Code sessions are doing, while they do it.

- Every session from the last 24 hours: title, project, what it's doing now, running time
- Helper agents: their task and each step they take
- Estimated time to finish, based on how long similar prompts and commands took in the last 7 days
- Task-list progress, live command output, tokens used per step
- Your 5-hour session and weekly usage limits, plus Claude's service status
- Search, a notification when a session finishes, and an alert when a command runs too long

ClaudeWatch only reads files Claude Code already writes on your Mac. Nothing is uploaded anywhere, except one request to Anthropic to fetch your usage limits.

---

## Before you start

You need:

| What | How to check |
|---|---|
| A Mac running **macOS 13 (Ventura) or newer** | Apple menu → About This Mac |
| **Claude Code** installed, and used at least once | Run `claude --version` in Terminal |
| **Xcode Command Line Tools** (Apple's free tools that turn code into an app) | Run `swiftc --version` in Terminal |

If `swiftc --version` says "command not found", install the tools:

```sh
xcode-select --install
```

A window appears. Click **Install** and wait for it to finish, usually 5–15 minutes.

To see your usage limits, you must be logged in to Claude Code with a **claude.ai account** (Pro or Max). If you use Claude Code with an API key instead, everything else still works and the usage cards stay empty.

---

## Install, step by step

### Step 1: Open Terminal

Terminal is the Mac app where you type commands.

1. Press **⌘ + Space** to open Spotlight.
2. Type **Terminal** and press **Enter**.

A window with a blinking cursor opens. Paste each command below into this window and press **Enter** after each one.

### Step 2: Check your Mac is ready

```sh
sw_vers -productVersion
```
You should see `13` or higher (for example `14.5` or `15.1`). If it's lower, update macOS first.

```sh
claude --version
```
You should see a version number. If you see `command not found`, install Claude Code first from https://claude.com/claude-code, run `claude` once, and log in.

```sh
swiftc --version
```
You should see a line starting with `Apple Swift version`. If you see `command not found`, run `xcode-select --install`, click **Install** in the window that appears, wait for it to finish, then run `swiftc --version` again.

### Step 3: Download the code

```sh
git clone https://github.com/srexta/claudewatch.git ~/ClaudeWatch
```
This copies the project into a folder called `ClaudeWatch` in your home folder. You should see `Cloning into '/Users/<you>/ClaudeWatch'...` followed by a few lines ending in `done.`

If you get an error saying `git` is not found, the command from Step 2 (`xcode-select --install`) installs it too.

### Step 4: Go into the folder

```sh
cd ~/ClaudeWatch
```
This moves Terminal into the project folder. Nothing is printed; that's normal.

### Step 5: Build and install the app

```sh
./build.sh
```
This does four things:
1. Turns the code into a Mac app (`ClaudeWatch.app`).
2. Copies it into your **Applications** folder.
3. Registers it with Spotlight so you can search for it.
4. Starts it.

It takes about a minute. When it's done, the last two lines should be:

```
Built /Users/<you>/ClaudeWatch/ClaudeWatch.app
Installed /Applications/ClaudeWatch.app
```

### Step 6: Find it in the menu bar

Look at the **top-right of your screen**, near the clock and Wi-Fi icons. You should see a **✳︎** icon, and next to it a small bar labeled **Session**.

Click the ✳︎ to open the panel.

### Step 7: Check it's working

In the panel you should see:
- a green dot with **All Systems Operational** at the top
- **Session Usage** and **Weekly** cards with percentages. These may take a few seconds and need the Keychain approval described below.
- a card for each Claude Code session you used in the last 24 hours

To test it live, open a new Terminal window, run `claude`, and ask it something. Within a few seconds a new card appears with a green dot and a running timer.

---

## First run: three permission pop-ups

macOS may ask you to approve a few things. All of them are expected.

1. **Keychain access**: "security wants to access … Claude Code-credentials".
   Click **Always Allow**. This lets ClaudeWatch reuse your existing Claude Code login to fetch your usage limits. The login is only sent to Anthropic.

2. **Notifications**: the first time a session finishes or runs long, macOS may ask about notifications from **Script Editor**, which ClaudeWatch uses to show alerts.
   Click **Allow**. If you missed it, go to System Settings → Notifications → Script Editor and turn it on.

3. **Start at login (optional)**: turn on the **Start at login** switch at the bottom of the panel. macOS may show a notice that ClaudeWatch was added to login items.

---

## Using it

- **Menu bar icon**: the number next to ✳︎ is how many sessions are working right now. The small bar under "Session" is your 5-hour usage. The thin tick shows how far through that 5-hour window you are.
- **Session cards**: click a project name to open it in VS Code. Click file names to open those files.
- **Helper agents**: click an agent to see its task and each of its steps.
- **Estimated time to finish**: appears once you have at least 3 finished prompts in the last 7 days. It's a guess based on your history, not a promise.
- **Alert threshold**: use the +/− control at the bottom to choose after how many minutes a long-running command triggers an alert.

You can also open ClaudeWatch from Spotlight (⌘Space → "ClaudeWatch"), Launchpad, or Finder → Applications.

---

## Update to a new version

```sh
cd ~/ClaudeWatch
git pull
./build.sh
```

The build script replaces the old app and restarts it.

---

## Uninstall

```sh
pkill -x ClaudeWatch
rm -rf /Applications/ClaudeWatch.app ~/ClaudeWatch ~/Library/Logs/ClaudeWatch.log
defaults delete local.claudewatch
```

If you turned on "Start at login", also remove it from System Settings → General → Login Items.

---

## Troubleshooting

**I don't see the ✳︎ icon.**
Your menu bar may be full. On MacBooks with a notch, extra icons hide behind it. Quit a few menu bar apps, or hold ⌘ and drag icons to make room. Then run `open /Applications/ClaudeWatch.app`.

**"No Claude Code login found in Keychain"**
Open Terminal, run `claude`, and type `/login` to sign in with your claude.ai account. Then click the refresh arrow in the panel. If you clicked "Deny" on the Keychain pop-up, quit and reopen ClaudeWatch to get the pop-up again.

**"Couldn't load usage (HTTP 401)"**
Your Claude Code login has expired. Use Claude Code once (or run `/login`) and click refresh.

**No sessions appear.**
ClaudeWatch only shows sessions active in the last 24 hours. Start a Claude Code session and it should appear within a few seconds.

**`./build.sh: Permission denied`**
Run `chmod +x build.sh`, then `./build.sh` again.

**"cp: /Applications/ClaudeWatch.app: Permission denied"**
Your Mac user isn't an administrator. Ask an admin to run `./build.sh`, or open the app straight from the folder: `open ~/ClaudeWatch/ClaudeWatch.app`.

**Spotlight can't find ClaudeWatch.**
Spotlight indexing may be turned off. Check with `mdutil -s /System/Volumes/Data`. To turn it on: `sudo mdutil -i on /System/Volumes/Data`.

**Something else is wrong.**
Check the log at `~/Library/Logs/ClaudeWatch.log`. It records what the app tried and why it failed. It never contains your password or login token.

---

## For contributors

- `./check.sh` runs the formatter check and a self-test of the session-log reader
- `./build.sh` builds and installs the app
- Code style is enforced by `swift format` (config in `.swift-format`)
- `CLAUDE.md` has project notes for Claude Code; `/verify` runs the full check-build-run loop

---

## How it works

| Information | Where it comes from |
|---|---|
| Sessions, steps, tokens | `~/.claude/projects/*/*.jsonl` (Claude Code's session logs) |
| Helper agents | `~/.claude/projects/*/<session>/subagents/` |
| Task-list progress | `~/.claude/tasks/<session>/` |
| Live command output | `/private/tmp/claude-<your user id>/…/tasks/*.output` |
| Usage limits | `api.anthropic.com/api/oauth/usage`, using your Claude Code login |
| Service status | `status.claude.com` |

The panel refreshes every 3 seconds. Usage limits refresh every minute.
