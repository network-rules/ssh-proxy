# SSH Proxy

A pure Bash application for managing SSH dynamic SOCKS5 tunnels.

## Requirements

- macOS or Linux
- Bash and OpenSSH client (`ssh`)
- `base64`, `tr`, and `stty`
- `lsof` is optional and used for local port checks

## Usage

Run from the application directory:

```bash
./ssh-proxy
```

Global options:

```text
--config <path>     Use a custom profile file
--state-dir <path>  Use a custom runtime directory
--no-notify         Disable macOS notifications
--help              Show help
--version           Show version
```

## Configuration

The default profile file is `ssh-proxy-profiles.ini`.

```ini
[settings]
reconnect = yes
max_retries = 0
retry_delay = 5
max_retry_delay = 60

[gateway]
host = gateway.example.com
user = user
ssh_port = 22
local_socks_port = 7070
identity_file = ~/.ssh/id_ed25519

[backup]
host = backup.example.com
user = user
ssh_port = 22
local_socks_port = 7070
identity_file = -
reconnect = no
max_retries = 3
```

Each server uses its own INI section. Values in `[settings]` apply globally
and can be overridden in an individual server section.

| Field | Description |
| --- | --- |
| `host` | Remote SSH hostname or IP address |
| `user` | SSH username |
| `ssh_port` | Remote SSH port |
| `local_socks_port` | Local SOCKS5 port; default profiles use `7070` |
| `identity_file` | Private key path, or `-` for ssh-agent/default keys |
| `reconnect` | Enable or disable automatic reconnect |
| `max_retries` | Maximum reconnect attempts; `0` means unlimited |
| `retry_delay` | Initial reconnect delay in seconds |
| `max_retry_delay` | Maximum reconnect delay in seconds |

Only one profile can run at a time when profiles share local port `7070`.

## Console controls

| Key | Action |
| --- | --- |
| Up / Down, `j` / `k` | Select a profile |
| Enter, `t` | Start or stop a tunnel |
| `r` | Restart the selected tunnel |
| `l` | View logs |
| `c` | Open an interactive SSH connection |
| `p` | Save a profile password |
| `g` | Save the default password |
| `d` | Delete a profile password |
| `x` | Delete the default password |
| `q` | Quit |

After a successful connection, the console returns to the main screen while
the tunnel continues running in the background. Use `c` for password or MFA
prompts that require interactive input.

## Reconnect behavior

On disconnect, SSH Proxy updates the status, emits a terminal bell, optionally
sends a macOS notification, and retries with exponential backoff. A successful
connection resets the retry counter and delay.

Set `reconnect = no` to disable retrying. Set `max_retries` to a positive
number to stop after that many reconnect attempts.

## Passwords and files

Saved passwords are kept in `credentials/` using triple Base64 encoding.
This is obfuscation, not encryption. SSH keys or an SSH agent are recommended.

Runtime data is stored in the application directory:

```text
credentials/   Saved passwords
logs/          Per-profile logs
pids/          Background process IDs
status/        Runtime status files
```

Personal configuration, credentials, logs, runtime state, and private-key
files are excluded by `.gitignore`.
