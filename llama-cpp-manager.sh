#!/usr/bin/env bash
#
# llama-cpp-manager (rootless version)
#

set -euo pipefail

########################################
# Paths
########################################

# Main installation directory
BASE_DIR="$HOME/.local/share/llama.cpp"
BUILD_DIR="$BASE_DIR/build"

# Config and models located inside the base directory
CONFIG_FILE="$BASE_DIR/config"
MODELS_DIR="$BASE_DIR/models"

# Path for the shared libraries (.so files)
LIB_DIR="$BUILD_DIR/bin"

BIN_DIR="$HOME/.local/bin"

# Script to launch the server
SCRIPT_FILE="$BASE_DIR/start-llama-cpp.sh"

LOG_DIR="$HOME/.cache/llama.cpp"
LOG_FILE="$LOG_DIR/llama-cpp.log"

# Systemd user service paths
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_DIR/llama-cpp.service"

TMP_DIR="/tmp/llama.cpp-build.$$"
REPO_URL="https://github.com/ggml-org/llama.cpp.git"

########################################
# Utils
########################################

log() {
    echo "[llama-cpp-manager] $*"
}

ensure_dirs() {
    mkdir -p "$BASE_DIR"
    mkdir -p "$MODELS_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$SYSTEMD_DIR"
}

show_help() {
    cat <<EOF

Llama.cpp Manager (Rootless)
----------------------------
This script manages the installation, compilation, and background execution 
of llama.cpp as a user-level systemd service.

USAGE:
  $(basename "$0") [command]

AVAILABLE COMMANDS:
  install                  Full setup: clones, compiles with CUDA, creates config,
                           models directory, launcher script, and systemd service.
  upgrade                  Fetches the latest version from GitHub, recompiles everything,
                           and restarts the background daemon.
  regenerate-start-script  Updates the launcher script logic (start-llama-cpp.sh) 
                           without recompiling. Use this if you update the manager script.
  restart-daemon           Restarts the llama-cpp systemd user service to apply changes.
  stop-daemon              Stops the llama-cpp systemd user service.
  status                   Shows the current systemd status and recent log output.
  help, -h, --help         Displays this help message with available options.

FILES & DIRECTORIES:
  Installation Dir:  $BASE_DIR
  Configuration:     $CONFIG_FILE
  Models Dir:        $MODELS_DIR
  Logs:              $LOG_FILE

EOF
}

########################################
# Configuration and Models setup
########################################

create_config() {
    mkdir -p "$MODELS_DIR"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
host: 0.0.0.0
port: 8080
EOF
        log "Default config created at: $CONFIG_FILE"
    fi
    log "Models directory ensured at: $MODELS_DIR"
}

########################################
# Server start script generation
########################################

create_start_script() {
cat > "$SCRIPT_FILE" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Fix for "error while loading shared libraries"
export LD_LIBRARY_PATH="$LIB_DIR:\${LD_LIBRARY_PATH:-}"

CONFIG_FILE="$CONFIG_FILE"
BIN="$BUILD_DIR/bin/llama-server"

if [[ ! -x "\$BIN" ]]; then
    echo "Error: llama-server not found at \$BIN"
    exit 1
fi

ARGS=()

# Parse YAML-like config into CLI arguments
while IFS= read -r line || [[ -n "\$line" ]]; do
    line="\$(echo "\$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [[ -z "\$line" ]] && continue
    [[ "\$line" =~ ^# ]] && continue

    if [[ "\$line" == *:* ]]; then
        # Key: Value argument
        key="\${line%%:*}"
        value="\${line#*:}"
        key="\$(echo "\$key" | xargs)"
        value="\$(echo "\$value" | xargs)"
        ARGS+=("--\$key" "\$value")
    else
        # Boolean Flag argument
        key="\$(echo "\$line" | xargs)"
        ARGS+=("--\$key")
    fi
done < "\$CONFIG_FILE"

echo "[launcher] Starting llama-server with LD_LIBRARY_PATH=\$LD_LIBRARY_PATH"
exec "\$BIN" "\${ARGS[@]}"
EOF

chmod +x "$SCRIPT_FILE"
log "Start script updated at: $SCRIPT_FILE"
}

########################################
# PATH Management
########################################

ensure_path() {
    local line='export PATH="$HOME/.local/bin:$PATH"'
    touch "$HOME/.bashrc"
    if ! grep -Fq '.local/bin' "$HOME/.bashrc"; then
        echo "$line" >> "$HOME/.bashrc"
        log "PATH updated in .bashrc"
    fi
}

########################################
# Systemd user service
########################################

create_service() {
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=llama.cpp daemon (user)
After=default.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$SCRIPT_FILE
Restart=always
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable llama-cpp.service >/dev/null
    log "Systemd user service created and enabled"
}

########################################
# Compilation Logic
########################################

build_llama() {
    rm -rf "$TMP_DIR"
    log "Cloning llama.cpp repository..."
    git clone --depth 1 "$REPO_URL" "$TMP_DIR"

    cd "$TMP_DIR"
    log "Building llama.cpp with CUDA support..."
    cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(nproc)"

    rm -rf "$BUILD_DIR"
    mv build "$BUILD_DIR"
    rm -rf "$TMP_DIR"
    log "Build completed and moved to $BUILD_DIR"
}

########################################
# Command Handlers
########################################

install_cmd() {
    ensure_dirs
    log "Starting installation..."
    build_llama
    create_config
    create_start_script
    ensure_path
    create_service
    log "Installation finished successfully"
}

upgrade_cmd() {
    log "Upgrading llama.cpp..."
    build_llama
    create_start_script
    systemctl --user restart llama-cpp.service
    log "Upgrade and restart completed"
}

regenerate_script_cmd() {
    log "Regenerating start script..."
    create_start_script
    log "Start script has been regenerated. Restart the daemon to apply changes."
}

status_cmd() {
    systemctl --user status llama-cpp.service --no-pager
}

restart_cmd() {
    systemctl --user restart llama-cpp.service
    log "Daemon restarted"
}

stop_cmd() {
    systemctl --user stop llama-cpp.service
    log "Daemon stopped"
}

########################################
# Main Entry Point
########################################

case "${1:-}" in
    install)                 install_cmd ;;
    upgrade)                 upgrade_cmd ;;
    regenerate-start-script) regenerate_script_cmd ;;
    restart-daemon)          restart_cmd ;;
    stop-daemon)             stop_cmd ;;
    status)                  status_cmd ;;
    help|--help|-h)          show_help ;;
    *)                       show_help; exit 1 ;;
esac