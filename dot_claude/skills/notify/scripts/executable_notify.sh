#!/bin/bash
# Send macOS notification
# Usage: ./notify.sh "Title" "Message" [sound]

set -euo pipefail

TITLE="${1:-Notification}"
MESSAGE="${2:-}"
SOUND="${3:-default}"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"Title\" \"Message\" [sound]"
    echo "Example: $0 \"Build Complete\" \"All tests passed\" default"
    exit 1
fi

terminal-notifier -title "$TITLE" -message "$MESSAGE" -sound "$SOUND"

echo "Notification sent: $TITLE - $MESSAGE"
