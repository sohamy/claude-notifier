# Quickstart

*[한국어](QUICKSTART.ko.md) · [full README](README.md)*

## From scratch

```powershell
git clone https://github.com/sohamy/claude-notifier.git
cd claude-notifier
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

That's it. Clone it anywhere — the installer records wherever you put it.

If Claude Code was already running, **restart it once** so it picks up the hook.
Check with `/hooks`.

## Then what

Nothing. Use Claude Code as usual.

| When | What happens |
|---|---|
| Claude finishes responding | A toast appears and **stays until you click it** |
| You click the toast | That Claude terminal window comes to the front |
| You stop it with Esc | No notification — you're already at the keyboard |

The toast shows what you last asked for, how long it took, and the project name.

## Too noisy?

Change one line in `config.json`. Saved changes apply to the next notification —
no restart.

```json
"minSeconds": 30
```

Only notifies for work that took over 30 seconds. Short exchanges stay quiet.

| You want | Setting |
|---|---|
| Sound off, banner on | `"sound": "none"` |
| Toast auto-dismisses | `"persistUntilClicked": false` |
| Quiet at night | `"quietHoursStart": "23:00"`, `"quietHoursEnd": "08:00"` |
| Off for a while | `"enabled": false` |

## Nothing shows up?

1. Action Center (`Win`+`N`). Empty there too? Check **Settings → System → Notifications**
   for notifications being off or Focus Assist being on.
2. `logs\notifier.log` — says whether a notification fired, or why it was skipped.
3. Log completely empty? The hook never ran. Check `/hooks`.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes only this tool's hook and its click handler. Other settings stay put.
