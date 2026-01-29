#!/bin/bash
# Multi-Node Cluster Setup Script
# Usage: ./setup_cluster.sh PUBLIC_IP1:PRIVATE_IP1[:PORT1] PUBLIC_IP2:PRIVATE_IP2[:PORT2] ...
# First node is the head node (rental0), rest are workers (rental1, rental2, ...)
# PORT is optional (default: 22)

set -euo pipefail

SETUP_SCRIPT="/Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh"
DOCKER_SETUP_SCRIPT="/Users/aghyaddeeb/Documents/coding/onstart/multinode_docker.sh"
SSH_CONFIG="$HOME/.ssh/config"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -i $HOME/.ssh/id_ed25519"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "[$(date '+%H:%M:%S')] $*"; }
log_success() { echo -e "[$(date '+%H:%M:%S')] ${GREEN}✓${NC} $*"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}✗${NC} $*" >&2; }
log_warn() { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}!${NC} $*"; }

# Send macOS notification
notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

# Check if old machine with same name prefix is still alive
check_old_machine_alive() {
    local host_entry="${NAME_PREFIX}0"

    # Check if entry exists in SSH config
    if ! grep -q "^Host ${host_entry}$" "$SSH_CONFIG" 2>/dev/null; then
        log "No existing SSH config for ${host_entry}, proceeding..."
        return 0
    fi

    # Extract HostName and Port from SSH config
    local old_ip old_port old_user
    old_ip=$(awk "/^Host ${host_entry}$/,/^Host / {if (/HostName/) print \$2}" "$SSH_CONFIG" | head -1)
    old_port=$(awk "/^Host ${host_entry}$/,/^Host / {if (/Port/) print \$2}" "$SSH_CONFIG" | head -1)
    old_user=$(awk "/^Host ${host_entry}$/,/^Host / {if (/User/) print \$2}" "$SSH_CONFIG" | head -1)
    old_port="${old_port:-22}"
    old_user="${old_user:-ubuntu}"

    if [ -z "$old_ip" ]; then
        log "Could not extract IP for ${host_entry}, proceeding..."
        return 0
    fi

    log "Checking if old ${host_entry} (${old_ip}:${old_port}) is still alive..."

    # Quick SSH connection test (5 second timeout)
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
           -p "$old_port" -i ~/.ssh/id_ed25519 "${old_user}@${old_ip}" "true" 2>/dev/null; then
        # Old machine is still alive!
        local msg="${host_entry} is still alive at ${old_ip}"
        log_error "$msg"
        log_error "Aborting setup to prevent overwriting active machine config"
        notify "⚠️ Setup Aborted" "$msg - not overwriting config"
        exit 1
    fi

    log_success "Old ${host_entry} is not reachable, safe to proceed"
    return 0
}

# Arrays to store node info
declare -a PUBLIC_IPS
declare -a PRIVATE_IPS
declare -a PORTS
declare -a USERS

# Default name prefix for SSH aliases
NAME_PREFIX="rental"

# Loopback IP for LocalForward (set based on NAME_PREFIX)
LOOPBACK_IP="127.0.0.1"

# Usernames to try (in order)
TRY_USERS=("ubuntu" "user")

# Parse arguments
parse_args() {
    # Parse flags first
    while [[ $# -gt 0 ]] && [[ "$1" == --* ]]; do
        case "$1" in
            --docker)
                SETUP_SCRIPT="$DOCKER_SETUP_SCRIPT"
                log "Using Docker-first setup script"
                shift
                ;;
            --name-prefix)
                NAME_PREFIX="$2"
                # Set loopback IP based on name prefix
                case "$NAME_PREFIX" in
                    rental) LOOPBACK_IP="127.0.0.1" ;;
                    eval)   LOOPBACK_IP="127.0.0.2" ;;
                    *)      LOOPBACK_IP="127.0.0.3" ;;
                esac
                log "Using name prefix: $NAME_PREFIX (loopback: $LOOPBACK_IP)"
                shift 2
                ;;
            *)
                log_error "Unknown flag: $1"
                exit 1
                ;;
        esac
    done

    if [ $# -eq 0 ]; then
        echo "Usage: $0 [--docker] [--name-prefix PREFIX] PUBLIC_IP1:PRIVATE_IP1[:PORT1] [PUBLIC_IP2:PRIVATE_IP2[:PORT2] ...]"
        echo "Example: $0 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17:20000"
        echo "Example: $0 --docker 147.185.41.18:10.15.22.9  # Use Docker-first setup"
        echo "Example: $0 --name-prefix eval 147.185.41.18:10.15.22.9  # Use 'eval0' instead of 'rental0'"
        exit 1
    fi

    for arg in "$@"; do
        IFS=':' read -r pub priv port <<< "$arg"
        if [ -z "$pub" ] || [ -z "$priv" ]; then
            log_error "Invalid format: $arg (expected PUBLIC:PRIVATE[:PORT])"
            exit 1
        fi
        PUBLIC_IPS+=("$pub")
        PRIVATE_IPS+=("$priv")
        PORTS+=("${port:-22}")
    done

    log "Parsed ${#PUBLIC_IPS[@]} node(s)"
    log "Head node: ${PUBLIC_IPS[0]} (private: ${PRIVATE_IPS[0]}, port: ${PORTS[0]})"
}

# Clear known_hosts entries for all nodes (handles changed host keys)
clear_known_hosts() {
    log "Clearing old SSH host keys..."

    for i in "${!PUBLIC_IPS[@]}"; do
        local ip="${PUBLIC_IPS[$i]}"
        local port="${PORTS[$i]}"

        # Remove by IP
        ssh-keygen -R "$ip" 2>/dev/null || true

        # Remove by [IP]:port format (for non-standard ports)
        if [ "$port" != "22" ]; then
            ssh-keygen -R "[$ip]:$port" 2>/dev/null || true
        fi
    done

    log_success "Old host keys cleared"
}

# Detect working username for a node
detect_user() {
    local ip=$1
    local port=$2

    for try_user in "${TRY_USERS[@]}"; do
        if ssh $SSH_OPTS -p "$port" -o BatchMode=yes -o ConnectTimeout=5 "$try_user@$ip" "true" 2>/dev/null; then
            echo "$try_user"
            return 0
        fi
    done

    # Return first user as fallback (will fail later with proper error)
    echo "${TRY_USERS[0]}"
    return 1
}

# Detect users for all nodes
detect_all_users() {
    log "Detecting SSH users for all nodes..."

    local failed=0
    for i in "${!PUBLIC_IPS[@]}"; do
        local detected_user
        if detected_user=$(detect_user "${PUBLIC_IPS[$i]}" "${PORTS[$i]}"); then
            USERS+=("$detected_user")
            log_success "${NAME_PREFIX}$i: user '$detected_user'"
        else
            USERS+=("$detected_user")
            log_error "${NAME_PREFIX}$i: could not connect with any user (tried: ${TRY_USERS[*]})"
            ((failed++))
        fi
    done

    if [ $failed -gt 0 ]; then
        log_error "Failed to detect user for $failed node(s)"
        exit 1
    fi
}

# Update SSH config with rental aliases
update_ssh_config() {
    log "Updating SSH config..."

    # Backup existing config
    if [ -f "$SSH_CONFIG" ]; then
        cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
    fi

    # Remove existing entries with this prefix
    if [ -f "$SSH_CONFIG" ]; then
        # Create temp file without matching entries
        awk -v prefix="$NAME_PREFIX" '
            $0 ~ "^Host " prefix "[0-9]+$" { skip=1; next }
            /^Host / { skip=0 }
            !skip { print }
        ' "$SSH_CONFIG" > "$SSH_CONFIG.tmp"
        mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
    fi

    # Add new entries
    for i in "${!PUBLIC_IPS[@]}"; do
        cat >> "$SSH_CONFIG" << EOF

Host ${NAME_PREFIX}$i
    HostName ${PUBLIC_IPS[$i]}
    User ${USERS[$i]}
    Port ${PORTS[$i]}
    IdentityFile ~/.ssh/id_ed25519
    LocalForward ${LOOPBACK_IP}:3000 localhost:3000
    LocalForward ${LOOPBACK_IP}:5173 localhost:5173
    LocalForward ${LOOPBACK_IP}:8001 localhost:8001
EOF
    done

    log_success "SSH config updated with ${#PUBLIC_IPS[@]} ${NAME_PREFIX} entries"
}

# Copy setup script to all nodes in parallel
copy_scripts() {
    log "Copying setup script to all nodes..."

    local pids=()
    for i in "${!PUBLIC_IPS[@]}"; do
        scp $SSH_OPTS -P "${PORTS[$i]}" "$SETUP_SCRIPT" "${USERS[$i]}@${PUBLIC_IPS[$i]}:/tmp/setup.sh" &
        pids+=($!)
    done

    # Wait for all copies to complete
    local failed=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Failed to copy to ${NAME_PREFIX}$i (${PUBLIC_IPS[$i]})"
            ((failed++))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "Script copied to all ${#PUBLIC_IPS[@]} nodes"
    else
        log_error "Failed to copy to $failed node(s)"
        exit 1
    fi
}

# Run setup on all nodes
run_setup() {
    local head_private="${PRIVATE_IPS[0]}"

    log "Starting setup on all nodes (RAY_HEAD_IP=$head_private)..."

    # Start all nodes in parallel - workers will wait for head's Ray port
    local pids=()
    local logfiles=()

    for i in "${!PUBLIC_IPS[@]}"; do
        local nid=$i
        local ihn="false"
        [ $i -eq 0 ] && ihn="true"

        local logfile="/tmp/setup_${NAME_PREFIX}${i}.log"
        logfiles+=("$logfile")

        # Single-node mode skips Ray and InfiniBand
        local single_node="false"
        [ ${#PUBLIC_IPS[@]} -eq 1 ] && single_node="true"

        log "Starting ${NAME_PREFIX}$i (NID=$nid, IHN=$ihn, SINGLE_NODE=$single_node)..."
        ssh $SSH_OPTS -p "${PORTS[$i]}" "${USERS[$i]}@${PUBLIC_IPS[$i]}" \
            "NID=$nid IHN=$ihn RAY_HEAD_IP=$head_private SINGLE_NODE=$single_node bash /tmp/setup.sh" \
            > "$logfile" 2>&1 &
        pids+=($!)
    done

    # Monitor progress
    log "Setup running on ${#pids[@]} nodes. Monitoring..."

    local completed=0
    local failed=0
    declare -a done_nodes=()

    while [ $((completed + failed)) -lt ${#pids[@]} ]; do
        for i in "${!pids[@]}"; do
            # Skip already processed
            [[ " ${done_nodes[*]:-} " =~ " $i " ]] && continue

            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                # Process finished
                if wait "${pids[$i]}"; then
                    log_success "${NAME_PREFIX}$i completed"
                    ((completed++))
                else
                    log_error "${NAME_PREFIX}$i failed (check ${logfiles[$i]})"
                    ((failed++))
                fi
                done_nodes+=($i)
            fi
        done
        sleep 5
    done

    if [ $failed -gt 0 ]; then
        log_warn "$failed node(s) failed setup"
        # Print logs for failed nodes
        print_setup_logs "${logfiles[@]}"
        return 1
    fi

    log_success "All ${#pids[@]} nodes completed setup"
    # Always print logs so Claude can see what happened
    print_setup_logs "${logfiles[@]}"
}

# Print setup logs (last 100 lines of each)
print_setup_logs() {
    local logfiles=("$@")

    echo ""
    log "Setup logs from all nodes:"
    echo "=============================================="

    for logfile in "${logfiles[@]}"; do
        local node_name=$(basename "$logfile" .log | sed 's/setup_//')
        echo ""
        echo "--- ${node_name} (last 100 lines) ---"
        tail -100 "$logfile" 2>/dev/null || echo "(no log available)"
        echo "--- end ${node_name} ---"
    done

    echo ""
    echo "=============================================="
    echo "Full logs available at: ${logfiles[*]}"
}

# Verify Docker is running on all nodes
verify_docker() {
    log "Verifying Docker on all nodes..."

    local failed=0
    for i in "${!PUBLIC_IPS[@]}"; do
        if ssh $SSH_OPTS -p "${PORTS[$i]}" "${USERS[$i]}@${PUBLIC_IPS[$i]}" "sudo docker ps | grep -q sandbox-fusion" 2>/dev/null; then
            log_success "${NAME_PREFIX}$i: Docker sandbox-fusion running"
        else
            log_error "${NAME_PREFIX}$i: Docker sandbox-fusion NOT running"
            ((failed++))
        fi
    done

    return $failed
}

# Verify Ray cluster status
verify_ray() {
    # Skip Ray verification for single-node setups
    if [ ${#PUBLIC_IPS[@]} -eq 1 ]; then
        log "Skipping Ray verification (single-node mode)"
        return 0
    fi

    log "Verifying Ray cluster on head node..."

    local ray_status
    ray_status=$(ssh $SSH_OPTS -p "${PORTS[0]}" "${USERS[0]}@${PUBLIC_IPS[0]}" "ray status 2>/dev/null" || true)

    if [ -z "$ray_status" ]; then
        log_error "Could not get Ray status"
        return 1
    fi

    echo "$ray_status"

    # Check node count
    local node_count
    node_count=$(echo "$ray_status" | grep -oP '\d+ node' | grep -oP '\d+' | head -1 || echo "0")

    if [ "$node_count" -eq "${#PUBLIC_IPS[@]}" ]; then
        log_success "Ray cluster has all $node_count nodes"
    else
        log_warn "Ray cluster has $node_count nodes (expected ${#PUBLIC_IPS[@]})"
    fi
}

# Configure SSH on head node to access workers via private IPs
setup_head_node_ssh() {
    # Skip for single-node setups
    if [ ${#PUBLIC_IPS[@]} -eq 1 ]; then
        log "Skipping head node SSH setup (single-node mode)"
        return 0
    fi

    log "Configuring SSH on head node for worker access..."

    # Build SSH config content for workers
    local ssh_config_content=""
    for i in "${!PRIVATE_IPS[@]}"; do
        if [ $i -eq 0 ]; then
            continue  # Skip head node itself
        fi
        ssh_config_content+="
Host worker$i
    HostName ${PRIVATE_IPS[$i]}
    User ${USERS[$i]}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"
    done

    # Apply SSH config on head node
    ssh $SSH_OPTS -p "${PORTS[0]}" "${USERS[0]}@${PUBLIC_IPS[0]}" bash -s << EOF
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Remove existing worker entries
if [ -f ~/.ssh/config ]; then
    awk '
        /^Host worker[0-9]+/ { skip=1; next }
        /^Host / { skip=0 }
        !skip { print }
    ' ~/.ssh/config > ~/.ssh/config.tmp
    mv ~/.ssh/config.tmp ~/.ssh/config
fi

# Add worker entries
cat >> ~/.ssh/config << 'SSHEOF'
$ssh_config_content
SSHEOF

chmod 600 ~/.ssh/config
EOF

    log_success "Head node SSH config updated for ${#PRIVATE_IPS[@]} workers"
}

# Print final report
print_report() {
    echo ""
    echo "=============================================="
    echo "           CLUSTER SETUP COMPLETE"
    echo "=============================================="
    echo ""
    echo "Node Configuration:"
    echo "-------------------"
    printf "%-10s %-18s %-15s %-6s %-5s %-8s\n" "Node" "Public IP" "Private IP" "Port" "NID" "Role"
    printf "%-10s %-18s %-15s %-6s %-5s %-8s\n" "----" "---------" "----------" "----" "---" "----"

    for i in "${!PUBLIC_IPS[@]}"; do
        local role="Worker"
        [ $i -eq 0 ] && role="Head"
        printf "%-10s %-18s %-15s %-6s %-5s %-8s\n" "${NAME_PREFIX}$i" "${PUBLIC_IPS[$i]}" "${PRIVATE_IPS[$i]}" "${PORTS[$i]}" "$i" "$role"
    done

    echo ""
    echo "Quick Access:"
    echo "-------------"
    for i in "${!PUBLIC_IPS[@]}"; do
        local role="worker"
        [ $i -eq 0 ] && role="head"
        echo "  ssh ${NAME_PREFIX}$i  # $role node"
    done

    echo ""
    echo "Useful Commands:"
    echo "----------------"
    echo "  ssh ${NAME_PREFIX}0 'ray status'              # Check Ray cluster"
    echo "  ssh ${NAME_PREFIX}0 'sudo docker ps'          # Check Docker"
    echo "  ssh ${NAME_PREFIX}0 'tail -50 /workspace/onstart.log'  # View setup log"
    echo ""
}

# Main
main() {
    parse_args "$@"

    # Check if old machine with same name is still alive
    check_old_machine_alive

    echo ""
    log "Starting multi-node cluster setup..."
    echo ""

    clear_known_hosts
    detect_all_users
    update_ssh_config
    copy_scripts
    run_setup

    echo ""
    log "Running verifications..."
    verify_docker || true
    echo ""
    verify_ray || true

    # Configure SSH on head node for inter-node access
    echo ""
    setup_head_node_ssh

    print_report
}

main "$@"
