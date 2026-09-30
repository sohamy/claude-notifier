# claude-notifier

Desktop notifications when Claude Code finishes working.

*[한국어 README](README.ko.md) · [Quickstart](QUICKSTART.md)*

Claude Code runs in a terminal, so long tasks leave you either staring at it or
forgetting about it. This puts a Windows toast on screen the moment Claude stops.
The toast **stays until you click it**, and clicking it **brings that terminal
window to the front** — so you can walk away and come back through the notification.

```
+------------------------------------------+
|  my-project - done                       |
|  fix the broken tests                    |
|  took 2m 14s - D:\work\my-project        |
|  [ Open Claude window ]  [ Dismiss ]     |
+------------------------------------------+
```

The last thing you asked for, how long it took, and which project it was.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (`powershell.exe`) — ships with Windows, nothing to install
- Claude Code

PowerShell 7 (`pwsh`) is fine to have, but the notifier itself runs on 5.1. See
[Notes](#notes) for why.

## Install

Clone anywhere you like, then run the installer from the repo folder:

```powershell
git clone https://github.com/sohamy/claude-notifier.git
cd claude-notifier

# every project (recommended)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# this project only
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Scope Project
```

The installer does two things:

- Adds one `Stop` hook to your Claude Code `settings.json`, pointing at wherever
  you cloned it. Existing hooks and settings are left alone, and the file is
  backed up to `settings.json.bak-<timestamp>` first.
- Registers a `claude-notifier:` URL handler under `HKCU\Software\Classes` so a
  toast click can focus your terminal. User scope, so no admin rights needed.

`-Scope User` writes to `%USERPROFILE%\.claude\settings.json`; `-Scope Project`
writes to `.claude\settings.json` in the current folder.

Running it again is safe — it refreshes the paths instead of adding a duplicate.

## Usage

**There is nothing to run.** Use Claude Code as you normally would and a
notification appears each time it finishes responding.

If you installed mid-session, restart Claude Code once so it picks up the hook.
You can check it registered with `/hooks`.

Clicking the toast (or its **Open Claude window** button) restores and focuses
the terminal Claude was running in. **Dismiss** just closes it.

Everything below is optional tuning. Edit `config.json`, save, and the next
notification uses it — no restart.

### Stop notifying on short turns

The one setting most people want. Quick back-and-forth gets noisy fast:

```json
"minSeconds": 30
```

Only turns that took longer than 30 seconds notify.

### Also notify on turns you interrupted

By default, pressing Esc to stop Claude does **not** notify — you're already at
the keyboard, so a toast would just be noise. If you want one anyway:

```json
"notifyOnInterrupt": true
```

### Let the toast auto-dismiss instead of waiting

```json
"persistUntilClicked": false
```

The toast then behaves like a normal notification: a few seconds on screen, then
into the Action Center.

### Don't focus anything on click

```json
"focusOnClick": false
```

Clicking just closes the toast. Skips the window lookup entirely.

### Silence the sound, keep the banner

```json
"sound": "none"
```

### Use your own sound

```json
"sound": "C:\Windows\Media\Alarm03.wav"
```

Backslashes are doubled because it's JSON. `C:\Windows\Media\` has plenty to
pick from. Avoid the `ms-winsoundevent:Notification.Looping.*` sounds — they're
built for alarms and are far too aggressive for a completion ping.

### Don't notify at night

```json
"quietHoursStart": "23:00",
"quietHoursEnd": "08:00"
```

Ranges that cross midnight work as written.

### Turn it off for a while

```json
"enabled": false
```

Leaves the hook in place and just stops notifying, so you don't have to
reinstall later.

### When nothing shows up

Check the Action Center first (`Win`+`N`). If it's empty there too, notifications
are probably off or Focus Assist is on — **Settings → System → Notifications**.

Then read `logs\notifier.log`. Every fired notification is logged, every skipped
one is logged with the reason, and every toast click is logged with whether the
focus succeeded. An empty log means the hook never ran, so check `/hooks`.

## Configuration

| Key | Default | What it does |
|---|---|---|
| `enabled` | `true` | `false` keeps the hook but stops notifying |
| `sound` | `"default"` | `"none"` for silence, or a path to a `.wav` |
| `minSeconds` | `0` | Skip turns shorter than this many seconds |
| `includePrompt` | `true` | Show what you last asked for in the body |
| `promptMaxLength` | `70` | Truncate that text with `…` past this length |
| `includeProject` | `true` | Put the project folder name in the title |
| `quietHoursStart` | `""` | e.g. `"23:00"`. Empty disables quiet hours |
| `quietHoursEnd` | `""` | e.g. `"08:00"`. May cross midnight |
| `notifyOnInterrupt` | `false` | Also notify on turns you stopped with Esc |
| `persistUntilClicked` | `true` | Keep the toast on screen until clicked or dismissed |
| `focusOnClick` | `true` | Clicking focuses the terminal Claude ran in |

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes only this tool's hook, leaves any other hooks untouched, and unregisters
the `claude-notifier:` handler. Pass `-Scope Project` if that's where you installed it.

## Files

| File | Role |
|---|---|
| `hook.ps1` | The `Stop` hook. Builds the message and launches `notify.ps1` |
| `notify.ps1` | Shows the toast and plays the sound |
| `focus.ps1` | Handles the toast click and focuses the terminal window |
| `install.ps1` / `uninstall.ps1` | Register / remove the hook and URL handler |
| `config.json` | Settings |
| `logs/notifier.log` | Fired, skipped and clicked notifications. Start here when debugging |
| `logs/windows.json` | Cached terminal window per session. Safe to delete |

## How it works

1. When Claude Code finishes responding, its `Stop` hook runs `hook.ps1` and
   passes JSON on stdin containing `cwd`, `session_id`, `transcript_path` and more.
2. `hook.ps1` scans the tail of the transcript (`.jsonl`) for the **last user
   prompt** and its timestamp, and diffs that against now for the duration. An
   interrupted turn is recorded there as `[Request interrupted by user]`, which is
   how it knows to stay quiet.
3. It walks up the process tree to find the terminal window hosting the session,
   and caches that per `session_id` — walking it costs about 0.8s, and the window
   doesn't change while a session runs, so only the first turn pays for it.
4. It launches `notify.ps1` as a **separate process** and returns immediately,
   so Claude Code is never blocked waiting on a toast.
5. The toast carries a `claude-notifier:focus?hwnd=…&pid=…&project=…` URI. Clicking
   it runs `focus.ps1`, which restores and raises that window.
6. The hook always exits `0`. A failed notification never breaks your workflow.

## Notes

- **Runs on Windows PowerShell 5.1, not PowerShell 7.** The WinRT toast APIs
  aren't directly loadable in `pwsh`. The installer registers `powershell`
  for you, so this only matters if you hand-edit the hook command.
- **Windows Terminal shares one process across all its windows.** When you have
  several open, `focus.ps1` picks the one whose title mentions the project, and
  falls back to the main window otherwise — so with multiple windows it can
  occasionally raise the wrong one. Classic console windows are always exact.
- Where WinRT toasts are unavailable, it falls back to a `NotifyIcon` balloon.
  The balloon can't persist or handle clicks, so those two features need WinRT.
- **The `.ps1` files are saved as UTF-8 with BOM.** Strip the BOM and PowerShell
  5.1 reads non-ASCII text as ANSI and fails to parse. Don't let your editor
  re-encode them.
