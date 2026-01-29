#!/bin/bash
# Multinode tmux session manager - runs on HEAD NODE
# Creates a tmux session on rental0 (head node) with:
#   - Window 0: Head node shell (local)
#   - Window 1+: All nodes - head is local, workers via SSH to private IPs
#
# This allows the session to persist even when your laptop disconnects.
# Just SSH back to rental0 and `tmux attach -t multinode`.

set -eo pipefail

SESSION_NAME="${SESSION_NAME:-multinode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SCRIPT="$SCRIPT_DIR/tmux_remote.sh"

# Usage check
if [ $# -lt 1 ]; then
    echo "Usage: $0 <num_nodes>"
    echo ""
    echo "Examples:"
    echo "  $0 4    # 4 nodes: head + 3 workers"
    echo "  $0 1    # Single node (head only)"
    echo ""
    echo "Requires: setup_cluster.sh must have been run first"
    echo "          (creates rental0 alias and worker1,2,... on head node)"
    exit 1
fi

NUM_NODES=$1

if [ "$NUM_NODES" -lt 1 ]; then
    echo "Error: Need at least 1 node"
    exit 1
fi

echo "Setting up tmux session '$SESSION_NAME' with $NUM_NODES nodes on HEAD NODE"
echo "Session will persist even if you disconnect!"
echo ""

# Copy remote script to head node and execute
scp -q "$REMOTE_SCRIPT" rental0:/tmp/tmux_remote.sh
ssh rental0 "chmod +x /tmp/tmux_remote.sh && /tmp/tmux_remote.sh '$SESSION_NAME' '$NUM_NODES'"

echo ""
echo "tmux session '$SESSION_NAME' created on HEAD NODE (rental0)!"
echo ""
echo "  Window 'head': Head node shell (local)"
if [ "$NUM_NODES" -gt 1 ]; then
    echo "  Window 'all-nodes': All $NUM_NODES nodes (head + workers)"
fi
echo ""
echo "To attach:"
echo "  ssh -t rental0 'tmux attach -t $SESSION_NAME'"
echo ""
echo "Or if already on head node:"
echo "  tmux attach -t $SESSION_NAME"
