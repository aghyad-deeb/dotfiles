# Verification Plan: multinode_claude.sh Setup

## Overview
Comprehensive verification of all components configured by the multinode setup script across all 8 nodes.

## Verification Script
Create and run a verification script on each node that checks every component.

---

## 1. Directory Structure
```bash
# Check on all nodes
[ -d /workspace/reward_seeker ] && echo "✓ workspace" || echo "✗ workspace"
[ -d /workspace/reward_seeker/.git ] && echo "✓ git repo" || echo "✗ git repo"
[ -d /workspace/reward_seeker/venv ] && echo "✓ venv" || echo "✗ venv"
[ -d /workspace/reward_seeker/models ] && echo "✓ models dir" || echo "✗ models dir"
[ -d /data ] && echo "✓ /data" || echo "✗ /data"
[ -d /data2 ] && echo "✓ /data2" || echo "✗ /data2"
```

## 2. Credentials (~/.env)
```bash
# Check file exists with correct permissions
[ -f ~/.env ] && [ "$(stat -c %a ~/.env)" = "600" ] && echo "✓ .env" || echo "✗ .env"

# Check all API keys present
grep -q "ANTHROPIC_API_KEY" ~/.env && echo "✓ ANTHROPIC_API_KEY" || echo "✗ ANTHROPIC_API_KEY"
grep -q "AWS_ACCESS_KEY_ID" ~/.env && echo "✓ AWS_ACCESS_KEY_ID" || echo "✗ AWS_ACCESS_KEY_ID"
grep -q "AWS_SECRET_ACCESS_KEY" ~/.env && echo "✓ AWS_SECRET_ACCESS_KEY" || echo "✗ AWS_SECRET_ACCESS_KEY"
grep -q "OPENROUTER_API_KEY" ~/.env && echo "✓ OPENROUTER_API_KEY" || echo "✗ OPENROUTER_API_KEY"
grep -q "OPENAI_API_KEY" ~/.env && echo "✓ OPENAI_API_KEY" || echo "✗ OPENAI_API_KEY"
```

## 3. APT Packages
```bash
dpkg -l | grep -q "^ii  git " && echo "✓ git" || echo "✗ git"
dpkg -l | grep -q "^ii  tmux " && echo "✓ tmux" || echo "✗ tmux"
dpkg -l | grep -q "^ii  python3-venv " && echo "✓ python3-venv" || echo "✗ python3-venv"
dpkg -l | grep -q "^ii  lvm2 " && echo "✓ lvm2" || echo "✗ lvm2"
dpkg -l | grep -q "^ii  netcat-openbsd " && echo "✓ netcat-openbsd" || echo "✗ netcat-openbsd"
```

## 4. Chezmoi & Dotfiles
```bash
# Chezmoi installed
command -v chezmoi && echo "✓ chezmoi" || echo "✗ chezmoi"

# Age encryption tool
command -v age && echo "✓ age" || echo "✗ age"

# Age key file (for decrypting chezmoi secrets)
[ -f ~/key.txt ] && [ "$(stat -c %a ~/key.txt)" = "600" ] && grep -q "AGE-SECRET-KEY" ~/key.txt && echo "✓ age key.txt" || echo "✗ age key.txt"

# Chezmoi config
[ -f ~/.config/chezmoi/chezmoi.toml ] && echo "✓ chezmoi.toml" || echo "✗ chezmoi.toml"

# Dotfiles present
[ -f ~/.bashrc ] && echo "✓ .bashrc" || echo "✗ .bashrc"
[ -f ~/.profile ] && echo "✓ .profile" || echo "✗ .profile"
[ -f ~/.tmux.conf ] && echo "✓ .tmux.conf" || echo "✗ .tmux.conf"
[ -f ~/.vimrc ] && echo "✓ .vimrc" || echo "✗ .vimrc"
[ -f ~/.screenrc ] && echo "✓ .screenrc" || echo "✗ .screenrc"
[ -f ~/.zshrc ] && echo "✓ .zshrc" || echo "✗ .zshrc"
[ -d ~/.vim ] && echo "✓ .vim/" || echo "✗ .vim/"

# SSH keys (check permissions too)
[ -f ~/.ssh/id_ed25519 ] && [ "$(stat -c %a ~/.ssh/id_ed25519)" = "600" ] && echo "✓ id_ed25519" || echo "✗ id_ed25519"
[ -f ~/.ssh/config ] && [ "$(stat -c %a ~/.ssh/config)" = "600" ] && echo "✓ ssh config" || echo "✗ ssh config"

# SSH config has expected hosts
grep -q "^Host " ~/.ssh/config && echo "✓ ssh hosts configured" || echo "✗ ssh hosts"
```

## 5. Git Configuration
```bash
[ "$(git config --global user.email)" = "th3elctronicag@gmail.com" ] && echo "✓ git email" || echo "✗ git email"
[ "$(git config --global user.name)" = "aghyad-deeb" ] && echo "✓ git name" || echo "✗ git name"
```

## 6. Python/UV Environment
```bash
# UV installed
[ -f ~/.local/bin/uv ] && echo "✓ uv" || echo "✗ uv"

# Python 3.10 in venv
[ -f /workspace/reward_seeker/venv/bin/python ] && echo "✓ venv python" || echo "✗ venv python"

# Key packages installed
/workspace/reward_seeker/venv/bin/pip show numpy &>/dev/null && echo "✓ numpy" || echo "✗ numpy"
/workspace/reward_seeker/venv/bin/pip show torch &>/dev/null && echo "✓ torch" || echo "✗ torch"
/workspace/reward_seeker/venv/bin/pip show flash-attn &>/dev/null && echo "✓ flash-attn" || echo "✗ flash-attn"
/workspace/reward_seeker/venv/bin/pip show wandb &>/dev/null && echo "✓ wandb pkg" || echo "✗ wandb pkg"
```

## 7. External Service Auth
```bash
# Wandb logged in
[ -f ~/.netrc ] && grep -q "api.wandb.ai" ~/.netrc && echo "✓ wandb auth" || echo "✗ wandb auth"

# HuggingFace logged in
[ -f ~/.cache/huggingface/token ] && echo "✓ hf auth" || echo "✗ hf auth"
```

## 8. Storage (LVM & NFS)
```bash
# LVM volume exists
sudo lvs vg0/lv_scratch &>/dev/null && echo "✓ LVM volume" || echo "✗ LVM volume"

# Mounts in fstab
grep -q "10.15.69.82:/data" /etc/fstab && echo "✓ NFS in fstab" || echo "✗ NFS in fstab"
grep -q "/dev/mapper/vg0-lv_scratch" /etc/fstab && echo "✓ LVM in fstab" || echo "✗ LVM in fstab"

# Actually mounted
mountpoint -q /data && echo "✓ /data mounted" || echo "✗ /data mounted"
mountpoint -q /data2 && echo "✓ /data2 mounted" || echo "✗ /data2 mounted"
```

## 9. Networking (Multi-node only)
```bash
# /etc/hosts fixed (no 127.0.1.1)
! grep -q "127.0.1.1" /etc/hosts && echo "✓ hosts fixed" || echo "✗ hosts has 127.0.1.1"

# InfiniBand module loaded
lsmod | grep -q ib_ipoib && echo "✓ ib_ipoib module" || echo "✗ ib_ipoib module"

# InfiniBand interfaces up with IPs (check at least one)
ip addr show ibp26s0 2>/dev/null | grep -q "10.10.1" && echo "✓ IB interfaces" || echo "✗ IB interfaces"

# NCCL variables in bashrc
grep -q "NCCL_IB_HCA" ~/.bashrc && echo "✓ NCCL vars" || echo "✗ NCCL vars"
grep -q "GLOO_SOCKET_IFNAME" ~/.bashrc && echo "✓ GLOO vars" || echo "✗ GLOO vars"
```

## 10. Docker
```bash
# Docker installed (not snap)
command -v docker && ! snap list docker &>/dev/null && echo "✓ docker (apt)" || echo "✗ docker"

# Docker version
docker --version && echo "✓ docker works" || echo "✗ docker broken"

# Docker socket permissions
[ "$(stat -c %a /var/run/docker.sock)" = "660" ] && echo "✓ socket perms" || echo "✗ socket perms"

# User in docker group
groups | grep -q docker && echo "✓ in docker group" || echo "✗ not in docker group"

# Docker Compose available
docker compose version &>/dev/null && echo "✓ docker compose" || echo "✗ docker compose"
```

## 11. Firewall (UFW)
```bash
sudo ufw status | grep -q "Status: active" && echo "✓ UFW active" || echo "✗ UFW inactive"
sudo ufw status | grep -q "22/tcp" && echo "✓ SSH allowed" || echo "✗ SSH not allowed"
sudo ufw status | grep -q "10.0.0.0/8" && echo "✓ internal net allowed" || echo "✗ internal net"
```

## 12. Ray Cluster
```bash
# Ray tmux session exists
tmux has-session -t ray 2>/dev/null && echo "✓ ray session" || echo "✗ ray session"

# Ray processes running
pgrep -f "ray" && echo "✓ ray processes" || echo "✗ ray processes"

# Ray status (head node only)
ray status 2>/dev/null | head -3
```

## 13. Services (tmux sessions)
```bash
# All expected sessions
tmux has-session -t exec 2>/dev/null && echo "✓ exec session" || echo "✗ exec session"
tmux has-session -t server 2>/dev/null && echo "✓ server session" || echo "✗ server session"
tmux has-session -t ray 2>/dev/null && echo "✓ ray session" || echo "✗ ray session"

# Docker container running
sudo docker ps | grep -q sandbox-fusion && echo "✓ sandbox-fusion container" || echo "✗ container not running"
```

## 14. Timezone
```bash
[ "$(readlink /etc/localtime)" = "/usr/share/zoneinfo/America/Los_Angeles" ] && echo "✓ timezone" || echo "✗ timezone"
```

## 15. Claude Code
```bash
# Installed
(command -v claude || [ -f ~/.local/bin/claude ]) && echo "✓ claude installed" || echo "✗ claude not installed"

# Version check
~/.local/bin/claude --version 2>/dev/null && echo "✓ claude works" || echo "✗ claude broken"

# API key sourcing in bashrc
grep -q "ANTHROPIC_API_KEY" ~/.bashrc && echo "✓ API key in bashrc" || echo "✗ API key not in bashrc"
```

## 16. Head Node Specific (rental0)
```bash
# Worker SSH aliases configured
grep -q "Host worker1" ~/.ssh/config && echo "✓ worker aliases" || echo "✗ worker aliases"

# Can SSH to workers
ssh -o ConnectTimeout=5 worker1 "echo ok" && echo "✓ worker1 reachable" || echo "✗ worker1 unreachable"
```

## 17. Multinode tmux Session
```bash
# Session exists with correct structure
tmux list-windows -t multinode 2>/dev/null | grep -q "head" && echo "✓ head window" || echo "✗ head window"
tmux list-windows -t multinode 2>/dev/null | grep -q "nodes-1" && echo "✓ nodes-1 window" || echo "✗ nodes-1"
tmux list-windows -t multinode 2>/dev/null | grep -q "nodes-2" && echo "✓ nodes-2 window" || echo "✗ nodes-2"
```

---

## Execution Plan

1. **Create verification script** combining all checks above
2. **Run on head node (rental0)** with all checks including head-specific
3. **Run on all worker nodes** (rental1-7) with worker-appropriate checks
4. **Collect and summarize results** showing any failures
5. **Fix any identified issues**

## Files to Modify
- None - this is a read-only verification plan

## Verification Method
Run the consolidated script and ensure all checks pass with "✓"
