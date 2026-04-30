# llama-cpp-manager

Rootless management script for installing, compiling and running llama.cpp as a systemd user service on Linux.

## Features

- **Isolated installation**: Everything installs to `$HOME/.local/share/llama.cpp` without root privileges
- **CUDA compilation**: Native support for GPU acceleration
- **Background service**: Automatic execution via systemd user
- **Simple management**: Intuitive commands for install, update and manage services
- **Flexible configuration**: YAML-like file for server configuration
- **MCP Proxy Servers**: Built-in support for Model Context Protocol servers (time, fetch, ddg-search included by default, easily extensible to other servers)
- **Multiple services**: Manage both llama.cpp server and MCP proxy services independently
- **Automatic port allocation**: MCP proxy uses port +1 from llama server to avoid conflicts
- **Configurable timezone**: Set timezone for MCP time server
- **Regenerate scripts**: Update launcher scripts without recompiling

## Requirements

- Linux with systemd
- Bash 4.0+
- Git
- CMake
- C/C++ compiler
- For CUDA: NVIDIA drivers and CUDA toolkit
- **Linger enabled for user**: Required for systemd user services to start at login
- **uvx**: For MCP proxy servers (comes with uv/pip)

**Check if Nvidia drivers and CUDA toolkit are properly installed**
- Run `nvidia-smi` to get the driver version and the CUDA version of the driver
- Run `nvcc --version` to get the CUDA toolkit version

The CUDA version of the driver and the version of the CUDA toolkit should match to avoid having issues.

## Installation

**Before running the installation, ensure the following prerequisites are met:**

1. **Copy this script to ~/.local/bin/**:
   ```bash
   cp $(pwd)/llama-cpp-manager.sh ~/.local/bin/llama-cpp-manager
   ```

2. **Make it executable**:
   ```bash
   chmod +x ~/.local/bin/llama-cpp-manager
   ```

3. **Ensure ~/.local/bin is in your PATH**:
   - Add the following line to your `~/.bashrc` or `~/.zshrc`:
     ```bash
     export PATH="$HOME/.local/bin:$PATH"
     ```
   - Apply the changes:
     ```bash
     source ~/.bashrc  # or source ~/.zshrc
     ```

Now you can run the manager script:

```bash
llama-cpp-manager install
```

**IMPORTANT: Before running the installation, enable linger for your user:**

```bash
loginctl enable-linger $USER
```

This command is **required** for systemd user services to start automatically when you log in. Without it, the llama.cpp service will not persist across sessions or start at boot.

This will:
- Clone the llama.cpp repository
- Compile with CUDA support
- Create default configuration
- Set up models directory
- Create launcher script
- Configure systemd user service

## MCP Server Installation

To install the MCP proxy servers (time, fetch, ddg-search included by default), run:

```bash
llama-cpp-manager install-mcp-proxy
```

This will:
- Create MCP configuration files
- Set up MCP proxy launcher script
- Configure systemd service for MCP proxy
- Enable the service

**Note**: The MCP proxy servers require `uvx` to be available in your PATH. You can extend this to support other MCP servers by modifying the `mcp.json` configuration file.

## Available Commands

| Command | Description |
|---------|-------------|
| `install [--overwrite]` | Full installation from scratch. Clones, builds and installs llama.cpp with systemd service |
| `install-mcp-proxy [--overwrite]` | Install MCP proxy servers (time, fetch, ddg-search). Requires llama.cpp to be installed first |
| `upgrade` | Updates llama.cpp to latest version and restarts service |
| `regenerate-start-script` | Regenerates all launch scripts without changing configs or recompiling |
| `restart-daemon` | Restarts both llama-cpp and mcp services |
| `stop-daemon` | Stops all llama-cpp services |
| `status` | Shows status of all llama-cpp services |
| `help` | Shows this help message |

## Directory Structure

```
~/.local/share/llama.cpp/
├── config-llama-cpp              # Llama.cpp server configuration (YAML-like)
├── config-mcp                    # MCP proxy configuration (key=value format)
├── mcp.json                      # MCP servers JSON configuration
├── models/                       # Directory for models
├── build/
│   └── bin/                      # Compiled binaries
├── start-llama-cpp.sh            # Llama.cpp server launcher script
└── start-mcp-server.sh           # MCP proxy launcher script

~/.local/bin/                     # Scripts added to PATH
~/.config/systemd/user/           # Systemd service files
├── llama-cpp.service             # Llama.cpp systemd service
└── llama-cpp-mcp.service         # MCP proxy systemd service

~/.cache/llama.cpp/               # Logs
└── llama-cpp.log                 # Combined log file for all services
```

## Configuration

### Llama.cpp Configuration (`~/.local/share/llama.cpp/config-llama-cpp`)

YAML-like configuration file for llama.cpp server:

```yaml
host: 0.0.0.0   # Server address (0.0.0.0 = all interfaces)
port: 8080      # Listening port
webui-mcp-proxy # Enable MCP proxy integration
```

**Important**: Only use arguments that llama-server accepts with `--` (double dash). Arguments with single dash (`-`) are NOT supported in the config file.

For example:
- ✅ `--port 8080` - Valid
- ❌ `-p 8080` - Invalid (will be ignored)

Supported options are the same as llama-server accepts with `--`.

### MCP Configuration (`~/.local/share/llama.cpp/config-mcp`)

Key-value configuration for MCP proxy servers:

```ini
PORT: 8081          # Port for MCP proxy (default: llama port + 1)
TIMEZONE: Europe/Madrid  # Timezone for time server
```

**Important**: Update the TIMEZONE to match your actual timezone.

## Server Usage

Once installed and running, you can access the server:

```bash
# Access the API
curl http://localhost:8080

# View logs
cat ~/.cache/llama.cpp/llama-cpp.log
```

## Updating

To update to the latest version:

```bash
llama-cpp-manager upgrade
```

This will:
1. Clone the latest repository commit
2. Recompile everything
3. Restart the daemon automatically

## Systemd Service

**IMPORTANT: Before using systemd user services, enable linger for your user:**

```bash
loginctl enable-linger $USER
```

This command is **required** for the llama.cpp service to:
- Start automatically when you log in
- Persist across sessions
- Run as a background service without user interaction

**Check if linger is enabled:**
```bash
loginctl show-user $USER | grep Linger
# Should show: Linger=yes
```

The service is configured automatically during installation. You can manage it manually with:

```bash
# List services
systemctl --user list-units

# Restart llama-cpp service
systemctl --user restart llama-cpp.service

# Restart MCP service
systemctl --user restart llama-cpp-mcp.service

# Stop llama-cpp service
systemctl --user stop llama-cpp.service

# Stop MCP service
systemctl --user stop llama-cpp-mcp.service

# Check status
systemctl --user status llama-cpp.service
systemctl --user status llama-cpp-mcp.service

# View logs
journalctl --user -u llama-cpp.service -f
journalctl --user -u llama-cpp-mcp.service -f
```

## Uninstallation

To uninstall:

```bash
# Stop the services
systemctl --user stop llama-cpp.service
systemctl --user stop llama-cpp-mcp.service

# Disable
systemctl --user disable llama-cpp.service
systemctl --user disable llama-cpp-mcp.service

# Remove installation
rm -rf ~/.local/share/llama.cpp
```

## Configuration Examples

### Local server (recommended)
```yaml
host: 127.0.0.1
port: 8080
webui-mcp-proxy
```

### Server with authentication
```yaml
host: 127.0.0.1
port: 8080
server: true
webui-mcp-proxy
```

### Server with CORS
```yaml
host: 0.0.0.0
port: 8080
cng: true
webui-mcp-proxy
```

### MCP with custom timezone
```ini
PORT: 8081
TIMEZONE: America/New_York
```

## Troubleshooting

### Shared library errors
If you have issues with shared libraries, regenerate the launch scripts:
```bash
llama-cpp-manager regenerate-start-script
```

### Service won't start
Check the logs:
```bash
cat ~/.cache/llama.cpp/llama-cpp.log
```

### Update without recompiling
If you only change configuration:
```bash
systemctl --user restart llama-cpp.service
```

### MCP proxy not working
Verify that `uvx` is available:
```bash
which uvx
```

If not installed, install uv first:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Notes

- Script runs in rootless mode, no sudo required
- Models must be placed manually in `~/.local/share/llama.cpp/models/`
- Service restarts automatically if it fails
- **Linger must be enabled for user**: Run `loginctl enable-linger $USER` for systemd user services to work
- MCP proxy servers are installed separately and require `uvx` to be available
- MCP proxy uses port +1 from llama server by default to avoid conflicts
- For more information about llama.cpp, visit: https://github.com/ggml-org/llama.cpp
