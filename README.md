# llama-cpp-manager

Rootless management script for installing, compiling and running llama.cpp as a systemd user service on Linux.

## Features

- **Isolated installation**: Everything installs to `$HOME/.local/share/llama.cpp` without root privileges
- **CUDA compilation**: Native support for GPU acceleration
- **Background service**: Automatic execution via systemd user
- **Simple management**: Intuitive commands for install, update and admin the service
- **Flexible configuration**: YAML-like file for server configuration

## Requirements

- Linux with systemd
- Bash 4.0+
- Git
- CMake
- C/C++ compiler
- For CUDA: NVIDIA drivers and CUDA toolkit
- **Linger enabled for user**: Required for systemd user services to start at login

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

## Available Commands

| Command | Description |
|---------|-------------|
| `install` | Full installation from scratch |
| `upgrade` | Updates to latest commit and recompiles |
| `regenerate-start-script` | Regenerates launch script without recompiling |
| `restart-daemon` | Restarts the daemon service |
| `stop-daemon` | Stops the service |
| `status` | Shows service status and recent logs |
| `help` | Shows this help message |

## Directory Structure

```
~/.local/share/llama.cpp/
├── config              # Server configuration
├── models/             # Directory for models
└── build/
    └── bin/            # Compiled binaries

~/.local/bin/           # Scripts added to PATH
~/.config/systemd/user/ # Systemd service
~/.cache/llama.cpp/     # Logs
```

## Configuration

Configuration file is located at `~/.local/share/llama.cpp/config`:

```yaml
host: 0.0.0.0   # Server address (0.0.0.0 = all interfaces)
port: 8080      # Listening port
```

**Important**: Only use arguments that llama-server accepts with `--` (double dash). Arguments with single dash (`-`) are NOT supported in the config file.

For example:
- ✅ `--port 8080` - Valid
- ❌ `-p 8080` - Invalid (will be ignored)

Supported options are the same as llama-server accepts with `--`.

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

# Restart
systemctl --user restart llama-cpp.service

# Stop
systemctl --user stop llama-cpp.service

# Check status
systemctl --user status llama-cpp.service

# View logs
journalctl --user -u llama-cpp.service -f
```

## Uninstallation

To uninstall:

```bash
# Stop the service
systemctl --user stop llama-cpp.service

# Disable
systemctl --user disable llama-cpp.service

# Remove installation
rm -rf ~/.local/share/llama.cpp
rm -f ~/.local/bin/llama-server
```

## Configuration Examples

### Local server (recommended)
```yaml
host: 127.0.0.1
port: 8080
```

### Server with authentication
```yaml
host: 127.0.0.1
port: 8080
server: true
```

### Server with CORS
```yaml
host: 0.0.0.0
port: 8080
cng: true
```

## Troubleshooting

### Shared library errors
If you have issues with shared libraries, regenerate the launch script:
```bash
llama-cpp-manager.sh regenerate-start-script
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

## Notes

- Script runs in rootless mode, no sudo required
- Models must be placed manually in `~/.local/share/llama.cpp/models/`
- Service restarts automatically if it fails
- **Linger must be enabled for user**: Run `loginctl enable-linger $USER` for systemd user services to work
- For more information about llama.cpp, visit: https://github.com/ggml-org/llama.cpp
