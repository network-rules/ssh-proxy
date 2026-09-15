# SSH Proxy

Pure Bash application for managing SSH dynamic SOCKS5 tunnels.

- [English](#english)
- [简体中文](#简体中文)

## English

### Requirements

- macOS or Linux
- Bash and OpenSSH client (`ssh`)
- `base64`, `tr`, and `stty`
- `lsof` is optional and used for local port checks

### Usage

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

### Configuration

The default profile file is `ssh-proxy-profiles.ini`.

```ini
[settings]
language = en
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

Set `language = en` or `language = zh-CN` in `[settings]`. The environment
variable `SSH_PROXY_LANG` can temporarily override the configured language.
Status values in the console are localized as well.

### Console controls

| Key | Action |
| --- | --- |
| Up / Down, `j` / `k` | Select a profile |
| Enter, `t` | Start or stop a tunnel |
| `r` | Restart the selected tunnel |
| `l` | View logs |
| `c` | Open an interactive SSH connection; press Enter after success to return |
| `p` | Save a profile password |
| `g` | Save the default password |
| `d` | Delete a profile password |
| `x` | Delete the default password |
| `q` | Quit |

After a successful connection, the console returns to the main screen while
the tunnel continues running in the background. Use `c` for password or MFA
prompts that require interactive input.

### Reconnect behavior

On disconnect, SSH Proxy updates the status, emits a terminal bell, optionally
sends a macOS notification, and retries with exponential backoff. A successful
connection resets the retry counter and delay.

Set `reconnect = no` to disable retrying. Set `max_retries` to a positive
number to stop after that many reconnect attempts.

### Passwords and files

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

## 简体中文

### 环境要求

- macOS 或 Linux
- Bash 和 OpenSSH 客户端（`ssh`）
- `base64`、`tr` 和 `stty`
- `lsof` 可选，用于检查本地端口

### 使用方法

在程序目录中运行：

```bash
./ssh-proxy
```

全局选项：

```text
--config <path>     使用自定义服务器配置文件
--state-dir <path>  使用自定义运行目录
--no-notify         禁用 macOS 通知
--help              显示帮助
--version           显示版本
```

### 配置

默认配置文件为 `ssh-proxy-profiles.ini`。

每台服务器使用独立的 INI 区块，例如 `[gateway]` 和 `[backup]`。
`[settings]` 中的配置是全局默认值，也可以在服务器区块中覆盖。

主要字段：

| 字段 | 说明 |
| --- | --- |
| `host` | 远程 SSH 主机名或 IP 地址 |
| `user` | SSH 用户名 |
| `ssh_port` | 远程 SSH 端口 |
| `local_socks_port` | 本地 SOCKS5 端口，默认使用 `7070` |
| `identity_file` | 私钥路径；使用 `-` 表示 ssh-agent 或默认密钥 |
| `reconnect` | 是否启用自动重连 |
| `max_retries` | 最大重连次数；`0` 表示不限次数 |
| `retry_delay` | 初始重连等待秒数 |
| `max_retry_delay` | 最大重连等待秒数 |

多个配置使用同一个本地端口 `7070` 时，同一时间只能运行其中一个。

在 `[settings]` 中设置 `language = en` 或 `language = zh-CN` 可以切换界面语言。
也可以使用环境变量 `SSH_PROXY_LANG` 临时覆盖配置。控制台中的状态值也会随语言切换。

### 控制台按键

| 按键 | 功能 |
| --- | --- |
| 上 / 下、`j` / `k` | 选择服务器配置 |
| Enter、`t` | 启动或停止隧道 |
| `r` | 重启当前隧道 |
| `l` | 查看日志 |
| `c` | 打开交互式 SSH 连接；连接成功后按 Enter 返回 |
| `p` | 保存服务器密码 |
| `g` | 保存默认密码 |
| `d` | 删除服务器密码 |
| `x` | 删除默认密码 |
| `q` | 退出 |

连接成功后，程序会返回主界面，同时让隧道在后台继续运行。需要输入密码或 MFA
验证码时，请使用 `c` 打开交互式连接。

### 自动重连

连接断开后，SSH Proxy 会更新状态、发出终端提示音，并可选发送 macOS 通知，
随后使用指数退避策略自动重连。连接成功后会重置重连次数和等待时间。

设置 `reconnect = no` 可关闭自动重连；将 `max_retries` 设置为正数可限制重连次数。

### 密码和运行文件

保存的密码位于 `credentials/`，使用三次 Base64 编码保存。这只是混淆，不是加密，
推荐使用 SSH 密钥或 ssh-agent。

运行数据保存在程序目录：

```text
credentials/   保存的密码
logs/          各服务器日志
pids/          后台进程 ID
status/        运行状态文件
```

个人配置、密码、日志、运行状态和私钥文件均已通过 `.gitignore` 排除。
