# Docker-First Setup Script Plan

## Goal
Create a new optional script (`multinode_docker.sh`) that sets up Docker as the default entry point, with the full environment (shell, vim, dotfiles, uv, venv) configured inside the container.

## Constraints
- Keep `multinode_claude.sh` **unchanged** (current default)
- New script is an **optional alternative**, not the default

---

## New Script: `multinode_docker.sh`

### Location
`/Users/aghyaddeeb/Documents/coding/onstart/multinode_docker.sh`

### Structure

The script has two phases:

#### Phase 1: Host Setup (runs on bare metal)
Things that **must** run on the host:
- `setup_directories()` - Create /workspace, /data, /data2
- `setup_storage()` - LVM, NFS mounts
- `setup_docker()` - Install Docker via snap
- `setup_firewall()` - UFW rules
- `setup_networking()` - InfiniBand interfaces (multi-node only)
- `setup_verl_container()` - **NEW**: Create the verl container with proper mounts

#### Phase 2: Container Setup (runs inside Docker)
Everything else runs **inside the container**:
- `setup_credentials()` - ~/.env file
- `setup_apt_packages()` - git, tmux, vim, etc.
- `setup_chezmoi()` - Dotfiles
- `setup_git()` - Git config
- `setup_repository()` - Clone reward_seeker
- `setup_uv_and_venv()` - UV, Python, venv, packages
- `setup_ray_cluster()` - Ray head/worker (multi-node only)
- `setup_services()` - tmux sessions for exec/server

#### Phase 3: SSH Auto-Exec
Configure `.bashrc` on host to auto-exec into Docker when SSHing in.

---

## Key Implementation Details

### 1. Container Creation
```bash
sudo docker create \
    --runtime=nvidia --gpus all \
    --net=host \
    --shm-size="10g" \
    --cap-add=SYS_ADMIN \
    --privileged \
    -v /home/ubuntu:/home/ubuntu \
    -v /workspace:/workspace \
    -v /data:/data \
    -v /data2:/data2 \
    -e HOME=/home/ubuntu \
    -w /workspace/reward_seeker \
    --name verl \
    verlai/verl:vemlp-th2.4.0-cu124-vllm0.6.3-ray2.10-te1.7-v0.0.3 \
    sleep infinity
```

### 2. Running Container Setup
After creating container, run Phase 2 inside it:
```bash
sudo docker exec verl bash /tmp/container_setup.sh
```

### 3. SSH Auto-Exec
Add to host's `.bashrc`:
```bash
# Auto-enter Docker container if not already inside
if [ -z "${DOCKER_CONTAINER:-}" ] && [ -t 0 ] && sudo docker ps -q -f name=verl | grep -q .; then
    exec sudo docker exec -it -e DOCKER_CONTAINER=1 verl bash -l
fi
```

---

## Integration: `--docker` Flag

Add flag parsing to `setup_cluster.sh`:
```bash
# At top of script, after SETUP_SCRIPT definition
USE_DOCKER=false
while [[ $# -gt 0 ]] && [[ "$1" == --* ]]; do
    case "$1" in
        --docker) USE_DOCKER=true; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [ "$USE_DOCKER" = true ]; then
    SETUP_SCRIPT="/Users/aghyaddeeb/Documents/coding/onstart/multinode_docker.sh"
fi
```

**Usage:**
```bash
# Default (current behavior)
setup_cluster.sh 147.185.41.18:10.15.22.9

# Docker-first
setup_cluster.sh --docker 147.185.41.18:10.15.22.9
```

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `multinode_docker.sh` | **CREATE** - New Docker-first setup script |
| `multinode_claude.sh` | NO CHANGE |
| `setup_cluster.sh` | **EDIT** - Add `--docker` flag parsing (default unchanged) |

---

## Verification
1. Run setup on a test node: `NID=0 IHN=true SINGLE_NODE=true bash multinode_docker.sh`
2. SSH into the machine - should auto-enter Docker container
3. Inside container, verify:
   - `chezmoi status` - dotfiles applied
   - `which uv` - uv installed
   - `source ~/workspace/reward_seeker/venv/bin/activate` - venv works
   - `vim` - opens with your config
   - `tmux` - opens with your config
