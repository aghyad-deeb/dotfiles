---
name: multinode-setup
description: Automates setup of remote GPU rental machines (single or multi-node). Triggered when user provides a mapping of public IPs to private IPs for nodes to set up, or asks to configure remote machines for distributed training.
---

# Multi-Node Remote Machine Setup

This skill automates the setup of rented GPU machines using a single setup script.

## Quick Start

When user provides a node mapping, run:

```bash
~/.claude/skills/multinode-setup/scripts/setup_cluster.sh PUBLIC1:PRIVATE1 PUBLIC2:PRIVATE2 ...
```

Example:
```bash
~/.claude/skills/multinode-setup/scripts/setup_cluster.sh 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17
```

The first node is always the head node (rental0).

## What the Script Does

1. **Clears old SSH host keys** - Removes stale entries from `~/.ssh/known_hosts` (handles reinstalled/new machines with same IP)
2. **Detects SSH user** - Tries `ubuntu` first, then `user` (auto-detection per node)
3. **Updates local `~/.ssh/config`** - Creates rental0, rental1, ... aliases with correct user (public IPs)
4. **Copies setup script** - SCPs `multinode_claude.sh` to all nodes in parallel
5. **Runs setup on all nodes** - Executes with correct `NID`, `IHN`, `RAY_HEAD_IP`, and `SINGLE_NODE` vars
6. **Displays setup logs** - Shows stdout/stderr from all nodes (last 100 lines) so Claude can diagnose issues
7. **Verifies setup** - Checks Docker and Ray cluster status (Ray skipped for single-node)
8. **Configures head node SSH** - Sets up worker1, worker2, ... aliases on head node (private IPs) for inter-node access
9. **Prints final report** - Node table and quick access commands

## Single-Node vs Multi-Node

- **Single node**: Skips Ray cluster and InfiniBand setup (not needed for single-GPU work)
- **Multi-node**: Full setup including Ray head/worker configuration and InfiniBand networking

## Input Format

User provides mapping in various formats. Parse into `PUBLIC:PRIVATE` pairs:

```
Public IP       Private IP
147.185.40.110  10.15.17.105
147.185.40.111  10.15.17.106
```

Becomes:
```bash
./setup_cluster.sh 147.185.40.110:10.15.17.105 147.185.40.111:10.15.17.106
```

## Script Variables

The underlying `multinode_claude.sh` uses:
- `RAY_HEAD_IP`: Private IP of the head node (auto-set to first node's private IP)
- `NID`: Node ID (0 for head, 1, 2, ... for workers)
- `IHN`: "Is Head Node" - `true` only for node 0
- `SINGLE_NODE`: `true` when only one node is provided (skips Ray/InfiniBand)

## After Setup

Quick access commands:
```bash
ssh rental0  # Head node
ssh rental1  # Worker node
ssh rental0 "ray status"  # Check Ray cluster
```

## SSH Configuration

The script uses `~/.ssh/id_ed25519` as the identity file. It auto-detects the SSH username by trying:
1. `ubuntu` (common on cloud providers)
2. `user` (common on GPU rental platforms like Vast.ai)

Each node can have a different user - the script detects per-node.

## Troubleshooting

The script automatically displays the last 100 lines of each node's setup log when complete. For full logs:
```bash
cat /tmp/setup_rental0.log  # Local log for head node
cat /tmp/setup_rental1.log  # Local log for worker node
ssh rental0 "cat /workspace/onstart.log"  # Remote log
```

**Host key errors**: Handled automatically. The script clears old host keys from `~/.ssh/known_hosts` before connecting.

The setup script is idempotent - safe to re-run.

## Post-Setup: Create tmux Session

After setup completes successfully, create a tmux session **on the head node** for persistent access:

```bash
~/.claude/skills/multinode-setup/scripts/tmux_multinode.sh <num_nodes>
```

Example (4 nodes):
```bash
~/.claude/skills/multinode-setup/scripts/tmux_multinode.sh 4
```

**Key feature**: The tmux session lives on the head node, not your laptop. This means:
- Close your laptop → session persists
- SSH back to rental0 → reattach to same session
- All inter-node SSH connections remain active

The session structure:
- **Window "head"**: Local shell on head node (no SSH needed)
- **Window "all-nodes"** (or "nodes-1", "nodes-2", ... for 5+ nodes): All nodes with max 4 panes per window
  - Head node pane: local shell
  - Worker panes: SSH via private IPs (worker1, worker2, ...)

Layout example for 4 nodes:
```
Window "head":     Window "all-nodes":
┌───────────┐      ┌─────────┬─────────┐
│   local   │      │  local  │ worker1 │
└───────────┘      ├─────────┼─────────┤
                   │ worker2 │ worker3 │
                   └─────────┴─────────┘
```

To attach from your laptop:
```bash
ssh -t rental0 'tmux attach -t multinode'
```

Or if already on head node:
```bash
tmux attach -t multinode
```

## Post-Setup Notification

After setup completes, send a notification to alert the user:

```bash
~/.claude/skills/notify/scripts/notify.sh "Cluster Ready" "N node(s) setup complete"
```

Replace N with the actual number of nodes configured.
