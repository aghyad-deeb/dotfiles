#!/bin/bash
# Remote tmux setup script - runs on head node
# Usage: tmux_remote.sh <session_name> <num_nodes>

set -eo pipefail

SESSION_NAME="${1:-multinode}"
NUM_NODES="${2:-1}"

# Kill existing session
tmux kill-session -t "$SESSION_NAME" >/dev/null 2>&1 || true

# Create session with docker group if available
if getent group docker >/dev/null 2>&1; then
    sg docker -c "tmux new-session -d -s '$SESSION_NAME' -n 'head'"
else
    tmux new-session -d -s "$SESSION_NAME" -n "head"
fi

# Single node - done
if [ "$NUM_NODES" -eq 1 ]; then
    echo "tmux session '$SESSION_NAME' created (single node)"
    exit 0
fi

# Multi-node: create all-nodes window with panes
win_name="all-nodes"
tmux new-window -t "$SESSION_NAME" -n "$win_name"

# Create panes for all nodes (max 4 per window)
panes=$NUM_NODES
[ $panes -gt 4 ] && panes=4

# First pane is head (already exists), rest are workers
for ((i=1; i<panes; i++)); do
    case $i in
        1) tmux split-window -t "$SESSION_NAME:$win_name" -h ;;
        2) tmux split-window -t "$SESSION_NAME:$win_name.0" -v ;;
        3) tmux split-window -t "$SESSION_NAME:$win_name.1" -v ;;
    esac
    tmux send-keys -t "$SESSION_NAME:$win_name" "ssh worker$i" Enter
done

tmux select-layout -t "$SESSION_NAME:$win_name" tiled
tmux select-window -t "$SESSION_NAME:head"

echo "tmux session '$SESSION_NAME' created on head node!"
