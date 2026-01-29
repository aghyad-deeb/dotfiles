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

## Post-Setup Verification (REQUIRED)

After setup completes, **always run comprehensive verification** on all nodes. Run this verification script on each node:

```bash
# Run on each node (rental0, rental1, etc.)
ssh rentalN 'bash -s' << 'VERIFY'
echo "=== Verification for $(hostname) ==="

# 1. Directory Structure
echo "--- Directories ---"
[ -d /workspace/reward_seeker ] && echo "✓ workspace" || echo "✗ workspace"
[ -d /workspace/reward_seeker/.git ] && echo "✓ git repo" || echo "✗ git repo"
[ -d /workspace/reward_seeker/venv ] && echo "✓ venv" || echo "✗ venv"

# 2. Credentials
echo "--- Credentials ---"
[ -f ~/.env ] && [ "$(stat -c %a ~/.env)" = "600" ] && echo "✓ .env" || echo "✗ .env"
grep -q "ANTHROPIC_API_KEY" ~/.env 2>/dev/null && echo "✓ ANTHROPIC_API_KEY" || echo "✗ ANTHROPIC_API_KEY"

# 3. Chezmoi & Age Encryption (CRITICAL)
echo "--- Chezmoi & Age ---"
command -v chezmoi >/dev/null && echo "✓ chezmoi" || echo "✗ chezmoi"
command -v age >/dev/null && echo "✓ age" || echo "✗ age"
[ -f ~/key.txt ] && [ "$(stat -c %a ~/key.txt)" = "600" ] && echo "✓ key.txt" || echo "✗ key.txt"
[ -f ~/.config/chezmoi/chezmoi.toml ] && echo "✓ chezmoi.toml" || echo "✗ chezmoi.toml"

# CRITICAL: Verify age key matches chezmoi recipient
KEY_PUBLIC=$(grep "# public key:" ~/key.txt 2>/dev/null | awk '{print $4}')
TOML_RECIPIENT=$(grep "recipient" ~/.config/chezmoi/chezmoi.toml 2>/dev/null | cut -d'"' -f2)
if [ "$KEY_PUBLIC" = "$TOML_RECIPIENT" ]; then
    echo "✓ age key matches recipient"
else
    echo "✗ KEY MISMATCH: key=$KEY_PUBLIC recipient=$TOML_RECIPIENT"
fi

# CRITICAL: Test decryption actually works
if [ -d ~/.local/share/chezmoi ]; then
    TEST_FILE=$(find ~/.local/share/chezmoi -name "*.age" -type f 2>/dev/null | head -1)
    if [ -n "$TEST_FILE" ]; then
        age -d -i ~/key.txt "$TEST_FILE" >/dev/null 2>&1 && echo "✓ age decryption works" || echo "✗ DECRYPTION FAILED"
    fi
fi

# 4. Dotfiles
echo "--- Dotfiles ---"
[ -f ~/.bashrc ] && echo "✓ .bashrc" || echo "✗ .bashrc"
[ -f ~/.tmux.conf ] && echo "✓ .tmux.conf" || echo "✗ .tmux.conf"
[ -f ~/.vimrc ] && echo "✓ .vimrc" || echo "✗ .vimrc"
[ -d ~/.vim ] && echo "✓ .vim/" || echo "✗ .vim/"

# 5. SSH Keys
echo "--- SSH ---"
[ -f ~/.ssh/id_ed25519 ] && [ "$(stat -c %a ~/.ssh/id_ed25519)" = "600" ] && echo "✓ id_ed25519" || echo "✗ id_ed25519"
[ -f ~/.ssh/config ] && echo "✓ ssh config" || echo "✗ ssh config"

# 6. Git
echo "--- Git ---"
[ "$(git config --global user.email)" = "th3elctronicag@gmail.com" ] && echo "✓ git email" || echo "✗ git email"

# 7. Python/UV
echo "--- Python/UV ---"
[ -f ~/.local/bin/uv ] && echo "✓ uv" || echo "✗ uv"
[ -f /workspace/reward_seeker/venv/bin/python ] && echo "✓ venv python" || echo "✗ venv python"

# 8. External Auth
echo "--- External Auth ---"
[ -f ~/.netrc ] && grep -q "api.wandb.ai" ~/.netrc && echo "✓ wandb" || echo "✗ wandb"
[ -f ~/.cache/huggingface/token ] && echo "✓ huggingface" || echo "✗ huggingface"

# 9. Docker
echo "--- Docker ---"
command -v docker >/dev/null && echo "✓ docker installed" || echo "✗ docker"
groups | grep -q docker && echo "✓ in docker group" || echo "✗ not in docker group"

# 10. Networking (multi-node)
echo "--- Networking ---"
! grep -q "127.0.1.1" /etc/hosts && echo "✓ /etc/hosts fixed" || echo "✗ /etc/hosts has 127.0.1.1"
grep -q "NCCL_IB_HCA" ~/.bashrc && echo "✓ NCCL vars" || echo "✗ NCCL vars missing"

# 11. Services
echo "--- Services ---"
tmux has-session -t exec 2>/dev/null && echo "✓ exec session" || echo "✗ exec session"
tmux has-session -t ray 2>/dev/null && echo "✓ ray session" || echo "✗ ray session"

# 12. Claude Code
echo "--- Claude Code ---"
(command -v claude >/dev/null || [ -f ~/.local/bin/claude ]) && echo "✓ claude installed" || echo "✗ claude"

echo "=== Done ==="
VERIFY
```

Run verification in parallel on all nodes:
```bash
for i in $(seq 0 $((NUM_NODES-1))); do
    ssh rental$i 'bash -s' < verify.sh &
done
wait
```

**If any check fails, fix it before considering setup complete.**

## Post-Setup Notification

After setup AND verification complete, send a notification:

```bash
~/.claude/skills/notify/scripts/notify.sh "Cluster Ready" "N node(s) setup and verified"
```

Replace N with the actual number of nodes configured.
