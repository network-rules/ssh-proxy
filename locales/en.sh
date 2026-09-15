#!/usr/bin/env bash

locale_msg_en() {
  local key=$1
  shift || true
  case "$key" in
    error_prefix) printf 'Error' ;;
    missing_command) printf 'missing command: %s' "$1" ;;
    config_required) printf '%s requires a path' "$1" ;;
    unknown_option) printf 'unknown option: %s' "$1" ;;
    profile_not_found) printf 'profile not found: %s' "$1" ;;
    invalid_profile_name) printf 'profile name may contain only letters, numbers, dots, underscores, and hyphens: %s' "$1" ;;
    profile_file_not_found) printf 'profile file not found: %s' "$1" ;;
    interactive_required) printf 'an interactive terminal is required' ;;
    password_terminal) printf '%s must be run from an interactive terminal' "$1" ;;
    enter_password) printf 'Enter password for %s: ' "$1" ;;
    confirm_password) printf 'Confirm password: ' ;;
    input_cancelled) printf 'password input cancelled' ;;
    passwords_mismatch) printf 'passwords do not match' ;;
    password_empty) printf 'password cannot be empty' ;;
    encode_failed) printf 'failed to encode password' ;;
    write_credential) printf 'cannot write credential file: %s' "$1" ;;
    password_saved) printf 'Password saved for %s (triple Base64; not encryption).' "$1" ;;
    credential_deleted) printf 'Saved password deleted for %s.' "$1" ;;
    no_password) printf 'No saved password for %s.' "$1" ;;
    enter_default) printf 'Enter default password: ' ;;
    confirm_default) printf 'Confirm default password: ' ;;
    default_saved) printf 'Default password saved (triple Base64; not encryption).' ;;
    default_deleted) printf 'Default password deleted.' ;;
    no_default) printf 'No default password saved.' ;;
    delete_credential) printf 'cannot delete credential file: %s' "$1" ;;
    incomplete_profile) printf 'incomplete profile: %s' "$1" ;;
    invalid_name) printf 'invalid profile name on line %s: %s' "$1" "$2" ;;
    invalid_port) printf 'invalid %s port in profile %s: %s' "$1" "$2" "$3" ;;
    identity_unreadable) printf 'identity file is not readable in profile %s: %s' "$1" "$2" ;;
    invalid_reconnect) printf 'reconnect must be yes or no in profile %s' "$1" ;;
    invalid_max_retries) printf 'max_retries must be a non-negative integer in profile %s' "$1" ;;
    invalid_retry_delay) printf '%s must be a positive integer in profile %s' "$1" "$2" ;;
    retry_order) printf 'max_retry_delay must be >= retry_delay in profile %s' "$1" ;;
    duplicate_profile) printf 'duplicate profile name: %s' "$1" ;;
    shared_port_warning) printf 'Warning: local port %s is shared by multiple profiles; run only one at a time.' "$1" ;;
    config_valid) printf 'Configuration valid: %s (%s profiles)' "$1" "$2" ;;
    dependencies) printf 'Dependencies available: ssh, base64, tr, stty%s' "$1" ;;
    already_running) printf '%s is already running (PID %s)' "$1" "$2" ;;
    port_busy) printf 'local port %s is already in use; choose another port or stop the process using it' "$1" ;;
    starting) printf '[%s] Starting %s -> socks5h://127.0.0.1:%s' "$1" "$2" "$3" ;;
    connecting) printf '[%s] Connecting to %s@%s:%s' "$1" "$2" "$3" "$4" ;;
    prompt_password) printf 'Enter a password or MFA code in this terminal if prompted.' ;;
    connected) printf '[%s] Connected; SOCKS proxy ready at socks5h://127.0.0.1:%s' "$1" "$2" ;;
    connection_established) printf 'Connection established. The tunnel is active.' ;;
    return_keep_running) printf 'Press Enter or r to return to the main console and keep it running.' ;;
    return_stop) printf 'Press Ctrl-C to stop the tunnel and return.' ;;
    returning) printf 'Returning to the main console; tunnel remains active.' ;;
    auto_disabled) printf '[%s] Disconnected, exit code %s; automatic reconnect is disabled' "$1" "$2" ;;
    retry_limit) printf '[%s] Disconnected, exit code %s; reconnect limit reached (%s attempts)' "$1" "$2" "$3" ;;
    disconnected) printf '[%s] Disconnected, exit code %s; reconnecting in %ss' "$1" "$2" "$3" ;;
    notify_retry_limit) printf 'SSH SOCKS reconnect limit reached' ;;
    notify_disconnected) printf 'SSH SOCKS disconnected' ;;
    stopped) printf '[%s] Stopped %s' "$1" "$2" ;;
    background_start) printf '%s background start requested; log: %s' "$1" "$2" ;;
    stop_signal) printf 'Stop signal sent: %s (PID %s)' "$1" "$2" ;;
    not_running) printf '%s is not running' "$1" ;;
    no_log) printf 'no log file found: %s' "$1" ;;
    no_profiles) printf 'profile file has no valid entries' ;;
    terminal_settings) printf 'unable to read terminal settings' ;;
    state_directory_error) printf 'unable to create state directory: %s' "$1" ;;
    terminal_console_only) printf 'this application uses the terminal console; use --help for options' ;;
    usage_help) printf 'usage: ssh-proxy.sh --help' ;;
    usage_version) printf 'usage: ssh-proxy.sh --version' ;;
    locale_error) printf 'cannot load %s locale' "$1" ;;
    active_profile) printf '%s is already %s.' "$1" "$2" ;;
    stop_before_interactive) printf 'Stop the current tunnel with Enter/t before opening an interactive connection.' ;;
    interactive_start) printf 'Interactive connection: %s' "$1" ;;
    interactive_prompt) printf 'Enter a password or MFA response when prompted.' ;;
    pause) printf 'Press any key to return...' ;;
    ui_description_1) printf 'A lightweight Bash console for SSH dynamic SOCKS5 tunnels.' ;;
    ui_description_2) printf 'Automatic reconnect, external profiles, and optional password storage.' ;;
    profile_file_label) printf 'Profile file' ;;
    table_name) printf 'NAME' ;;
    table_server) printf 'SERVER' ;;
    table_status) printf 'STATUS' ;;
    table_socks_port) printf 'SOCKS_PORT' ;;
    status_stopped) printf 'STOPPED' ;;
    status_running) printf 'RUNNING' ;;
    status_starting) printf 'STARTING' ;;
    status_connected) printf 'CONNECTED' ;;
    status_reconnecting) printf 'RECONNECTING' ;;
    status_stopping) printf 'STOPPING' ;;
    ui_controls_1) printf 'Up/Down or j/k: select   Enter/t: start/stop   r: restart   l: logs   c: interactive connect' ;;
    ui_controls_2) printf 'p: save profile password   g: save default password   d: delete profile password   x: delete default password   q: quit' ;;
    *) printf '%s' "$key" ;;
  esac
}

locale_msg() {
  locale_msg_en "$@"
}

locale_usage_en() {
  cat <<'EOF'
Usage:
  bash ssh-proxy.sh            Open the unified terminal console

Global options:
  --config <path>              Use a custom profile file
  --state-dir <path>           Use a custom runtime directory
  --no-notify                  Disable macOS notifications (keep terminal bell)

Language:
  Set language = en or language = zh-CN in [settings], or use SSH_PROXY_LANG.

Profile file format (INI; one block per server):
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

Reconnect settings:
  reconnect                     yes or no; default: yes
  max_retries                   Maximum reconnect attempts; 0 means unlimited
  retry_delay                   Initial delay between reconnect attempts in seconds
  max_retry_delay               Maximum exponential-backoff delay in seconds

The legacy space-separated format is still accepted:
  gateway gateway.example.com user 22 7070 ~/.ssh/id_ed25519

Notes:
  - Use socks5h://127.0.0.1:<local_socks_port> as the browser/tool proxy address.
  - The console prompts for passwords or MFA and reconnects automatically after disconnects.
  - Authentication uses a saved profile password, then the saved default password, then ssh-agent/private keys.
  - Disconnect alerts include a terminal bell; macOS notifications are enabled by default.
  - Triple Base64 is obfuscation, not encryption. Anyone who can read the file can recover the password.

Controls:
  Up/Down or j/k                Select a profile
  Enter/t                       Start or stop a tunnel
  r                             Restart the selected tunnel
  l                             View logs
  c                             Open an interactive connection; press Enter after connecting to return
  p                             Save a profile password
  g                             Save the default password
  d                             Delete a profile password
  x                             Delete the default password
  q                             Quit
EOF
}

locale_usage() {
  locale_usage_en
}
