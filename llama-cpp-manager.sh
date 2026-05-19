#!/usr/bin/env bash
#
# llama-cpp-manager
#

set -euo pipefail

########################################
# Paths
########################################

BASE_DIR="$HOME/.local/share/llama.cpp"
BUILD_DIR="$BASE_DIR/build"

CONFIG_LLAMA="$BASE_DIR/config-llama-cpp"
CONFIG_MCP="$BASE_DIR/config-mcp"
MCP_JSON="$BASE_DIR/mcp.json"

MODELS_DIR="$BASE_DIR/models"
LIB_DIR="$BUILD_DIR/bin"

SCRIPT_FILE="$BASE_DIR/start-llama-cpp.sh"
MCP_SCRIPT="$BASE_DIR/start-mcp-server.sh"

SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_DIR/llama-cpp.service"
MCP_SERVICE_FILE="$SYSTEMD_DIR/llama-cpp-mcp.service"

TMP_DIR="/tmp/llama.cpp-build.$$"
REPO_URL="https://github.com/ggml-org/llama.cpp.git"

########################################
# Utils
########################################

log() { echo "[llama-cpp-manager] $*"; }

ensure_dirs() {
    mkdir -p \
        "$BASE_DIR" \
        "$MODELS_DIR" \
        "$SYSTEMD_DIR"
}

show_help() {
cat <<EOF
USAGE:
   $(basename "$0") <command> [--overwrite]

COMMANDS:
   install [--overwrite]              Clone, build and install llama.cpp with systemd service
   install-mcp-proxy [--overwrite]    Install MCP proxy servers
   upgrade                            Update llama.cpp to latest version and restart service
   regenerate-start-script            Regenerate start scripts without changing configs
   restart-daemon                     Restart llama-cpp and mcp services
   stop-daemon                        Stop all llama-cpp services
   logs                               Show llama.cpp logs
   status                             Show status + health checks
EOF
}

has_flag() {
    [[ "${2:-}" == "--overwrite" ]]
}

require_llama_installed() {
    if [[ ! -x "$BUILD_DIR/bin/llama-server" ]]; then
        echo "Error: llama.cpp is not installed."
        echo
        echo "Run:"
        echo "  $(basename "$0") install"
        exit 1
    fi
}

reload_systemd() {
    systemctl --user daemon-reload
}

get_llama_port() {
    local port="8080"

    if [[ -f "$CONFIG_LLAMA" ]]; then
        port="$(grep -i '^port:' "$CONFIG_LLAMA" | head -n1 | cut -d: -f2- | xargs || true)"
    fi

    [[ "$port" =~ ^[0-9]+$ ]] || port="8080"

    echo "$port"
}

get_default_mcp_port() {
    local p
    p="$(get_llama_port)"
    echo $((p + 1))
}

########################################
# Build llama.cpp
########################################

build_llama() {
    rm -rf "$TMP_DIR"

    git clone --depth 1 "$REPO_URL" "$TMP_DIR"

    cd "$TMP_DIR"

    cmake \
        -B build \
        -DGGML_CUDA=ON \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DCMAKE_BUILD_TYPE=Release

    cmake --build build -j"$(nproc)"

    rm -rf "$BUILD_DIR"
    mv build "$BUILD_DIR"

    cd /

    rm -rf "$TMP_DIR"
}

########################################
# Config llama.cpp
########################################

create_llama_config() {
    local overwrite="$1"

    if [[ -f "$CONFIG_LLAMA" && "$overwrite" != "yes" ]]; then
        log "Keeping existing $CONFIG_LLAMA"
        return
    fi

cat > "$CONFIG_LLAMA" <<EOF
host: 0.0.0.0
port: 8080
EOF

    log "Created $CONFIG_LLAMA"
}

ensure_webui_mcp_proxy_flag() {
    [[ -f "$CONFIG_LLAMA" ]] || return

    if ! grep -Fxq "webui-mcp-proxy" "$CONFIG_LLAMA"; then
        echo "webui-mcp-proxy" >> "$CONFIG_LLAMA"
        log "Added webui-mcp-proxy to $CONFIG_LLAMA"
    fi
}

########################################
# Config MCP
########################################

create_mcp_config() {
    local overwrite="$1"
    local port

    port="$(get_default_mcp_port)"

    if [[ -f "$CONFIG_MCP" && "$overwrite" != "yes" ]]; then
        log "Keeping existing $CONFIG_MCP"
        return
    fi

cat > "$CONFIG_MCP" <<EOF
PORT: $port
TIMEZONE: Europe/Madrid
EOF

    log "Created $CONFIG_MCP"
}

create_mcp_json() {
    local overwrite="$1"
    local timezone="Europe/Madrid"

    if [[ -f "$CONFIG_MCP" ]]; then
        timezone="$(grep -i '^TIMEZONE:' "$CONFIG_MCP" | head -n1 | cut -d: -f2- | xargs || true)"
        [[ -n "$timezone" ]] || timezone="Europe/Madrid"
    fi

    if [[ -f "$MCP_JSON" && "$overwrite" != "yes" ]]; then
        log "Keeping existing $MCP_JSON"
        return
    fi

cat > "$MCP_JSON" <<EOF
{
  "mcpServers": {
    "time": {
      "command": "uvx",
      "args": ["mcp-server-time", "--local-timezone=$timezone"]
    },
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "ddg-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"]
    }
  }
}
EOF

    log "Created $MCP_JSON"
}

########################################
# Start scripts
########################################

create_start_script() {
cat > "$SCRIPT_FILE" <<EOF
#!/usr/bin/env bash

set -euo pipefail

BUILD_DIR="$BUILD_DIR"
LIB_DIR="$LIB_DIR"
CONFIG_FILE="$CONFIG_LLAMA"

export LD_LIBRARY_PATH="\$LIB_DIR:\${LD_LIBRARY_PATH:-}"

BIN="\$BUILD_DIR/bin/llama-server"

[[ -x "\$BIN" ]] || {
    echo "llama-server not found"
    exit 1
}

[[ -f "\$CONFIG_FILE" ]] || {
    echo "config missing"
    exit 1
}

ARGS=()

while IFS= read -r line || [[ -n "\$line" ]]; do
    line="\$(echo "\$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [[ -z "\$line" ]] && continue
    [[ "\$line" =~ ^# ]] && continue

    if [[ "\$line" == *:* ]]; then
        key="\${line%%:*}"
        value="\${line#*:}"

        key="\$(echo "\$key" | xargs)"
        value="\$(echo "\$value" | xargs)"

        ARGS+=("--\$key" "\$value")
    else
        key="\$(echo "\$line" | xargs)"
        ARGS+=("--\$key")
    fi
done < "\$CONFIG_FILE"

exec "\$BIN" "\${ARGS[@]}"
EOF

    chmod +x "$SCRIPT_FILE"
}

create_mcp_start_script() {
cat > "$MCP_SCRIPT" <<EOF
#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="$CONFIG_MCP"
JSON_FILE="$MCP_JSON"

UVX_BIN="\$HOME/.local/bin/uvx"

[[ -x "\$UVX_BIN" ]] || UVX_BIN="\$(command -v uvx || true)"

[[ -x "\$UVX_BIN" ]] || {
    echo "uvx not found"
    exit 1
}

[[ -f "\$CONFIG_FILE" ]] || {
    echo "config-mcp missing"
    exit 1
}

PORT="\$(grep -i '^PORT:' "\$CONFIG_FILE" | head -n1 | cut -d: -f2- | xargs || true)"
TIMEZONE="\$(grep -i '^TIMEZONE:' "\$CONFIG_FILE" | head -n1 | cut -d: -f2- | xargs || true)"

[[ "\$PORT" =~ ^[0-9]+$ ]] || {
    echo "Invalid PORT"
    exit 1
}

[[ -n "\$TIMEZONE" ]] || {
    echo "TIMEZONE missing"
    exit 1
}

[[ -f "/usr/share/zoneinfo/\$TIMEZONE" ]] || {
    echo "Invalid TIMEZONE"
    exit 1
}

cat > "\$JSON_FILE" <<JSON
{
  "mcpServers": {
    "time": {
      "command": "uvx",
      "args": ["mcp-server-time", "--local-timezone=\$TIMEZONE"]
    },
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "ddg-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"]
    }
  }
}
JSON

exec "\$UVX_BIN" mcp-proxy \
  --named-server-config "\$JSON_FILE" \
  --allow-origin "*" \
  --port "\$PORT" \
  --stateless
EOF

    chmod +x "$MCP_SCRIPT"
}

########################################
# Services
########################################

create_llama_service() {
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=llama.cpp daemon
After=graphical-session.target network-online.target
Wants=graphical-session.target network-online.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/llama.cpp
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStartPre=/usr/bin/sleep 10
ExecStartPre=/usr/bin/bash -c 'until nvidia-smi >/dev/null 2>&1; do sleep 2; done'
ExecStart=%h/.local/share/llama.cpp/start-llama-cpp.sh
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
}

create_mcp_service() {
cat > "$MCP_SERVICE_FILE" <<EOF
[Unit]
Description=llama.cpp MCP proxy
After=llama-cpp.service
Requires=llama-cpp.service

[Service]
Type=simple
WorkingDirectory=%h/.local/share/llama.cpp
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/.local/share/llama.cpp/start-mcp-server.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
}

########################################
# Commands
########################################

install_cmd() {
    local overwrite="no"

    has_flag "$@" && overwrite="yes"

    ensure_dirs

    build_llama

    create_llama_config "$overwrite"

    create_start_script
    create_llama_service

    reload_systemd

    systemctl --user enable llama-cpp.service

    log "Install complete"
}

install_mcp_cmd() {
    local overwrite="no"

    has_flag "$@" && overwrite="yes"

    require_llama_installed

    ensure_dirs

    ensure_webui_mcp_proxy_flag

    create_mcp_config "$overwrite"
    create_mcp_json "$overwrite"

    create_mcp_start_script
    create_mcp_service

    reload_systemd

    systemctl --user enable llama-cpp-mcp.service

    echo
    echo "IMPORTANT:"
    echo "Check:"
    echo "  $CONFIG_MCP"
    echo
    echo "Set TIMEZONE correctly."
}

upgrade_cmd() {
    require_llama_installed

    build_llama

    create_start_script

    reload_systemd

    systemctl --user restart llama-cpp.service
}

regenerate_cmd() {
    require_llama_installed

    create_start_script

    if [[ -f "$MCP_SCRIPT" ]]; then
        create_mcp_start_script
    fi

    reload_systemd
}

restart_cmd() {
    systemctl --user restart llama-cpp.service

    if [[ -f "$MCP_SERVICE_FILE" ]]; then
        systemctl --user restart llama-cpp-mcp.service
    fi
}

stop_cmd() {
    systemctl --user stop llama-cpp.service || true
    systemctl --user stop llama-cpp-mcp.service || true
}

logs_cmd() {
    journalctl --user -u llama-cpp.service -f
}

status_cmd() {
    local port

    port="$(get_llama_port)"

    echo "=== llama-cpp.service ==="
    systemctl --user status llama-cpp.service --no-pager

    echo
    echo "=== llama.cpp API ==="

    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
        echo "API OK"
    else
        echo "API DOWN"
    fi

    echo
    echo "=== llama-cpp-mcp.service ==="

    systemctl --user status llama-cpp-mcp.service --no-pager || true
}

########################################
# Main
########################################

case "${1:-}" in
    install)
        install_cmd "$@"
        ;;

    install-mcp-proxy)
        install_mcp_cmd "$@"
        ;;

    upgrade)
        upgrade_cmd
        ;;

    regenerate-start-script)
        regenerate_cmd
        ;;

    restart-daemon)
        restart_cmd
        ;;

    stop-daemon)
        stop_cmd
        ;;

    logs)
        logs_cmd
        ;;

    status)
        status_cmd
        ;;

    help|--help|-h|"")
        show_help
        ;;

    *)
        show_help
        exit 1
        ;;
esac