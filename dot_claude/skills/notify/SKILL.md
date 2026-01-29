---
name: notify
description: Send macOS notifications to alert the user. Use this when completing long-running tasks, when user attention is needed, or when explicitly requested.
---

# macOS Notification Skill

Send notifications to the user's macOS notification center.

## Usage

```bash
~/.claude/skills/notify/scripts/notify.sh "Title" "Message" [sound]
```

## Examples

```bash
# Basic notification
~/.claude/skills/notify/scripts/notify.sh "Task Complete" "Build finished successfully"

# With sound (default: Glass)
~/.claude/skills/notify/scripts/notify.sh "Error" "Tests failed" "Basso"

# Cluster setup done
~/.claude/skills/notify/scripts/notify.sh "Cluster Ready" "All 4 nodes configured"
```

## Available Sounds

- `default` (default) - system default sound
- `Ping` - soft ping
- `Pop` - pop sound
- `Basso` - deep tone (good for errors)
- `Hero` - achievement sound
- `Glass` - subtle chime

## When to Use

Use this skill proactively when:
- Long-running tasks complete (builds, deployments, cluster setup)
- Errors occur that need user attention
- User explicitly asks to be notified
- Background processes finish

## Notes

- Notifications appear in macOS Notification Center
- Works even if Terminal is not in focus
- User must have notifications enabled for Terminal/iTerm
