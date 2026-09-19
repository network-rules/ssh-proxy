#!/usr/bin/env bash
# Pure Bash SSH SOCKS proxy manager for macOS/Linux.
# Requires only the system ssh and common POSIX utilities.
# Saved passwords and runtime state live in the application directory by default.

set -u
umask 077

APP_NAME='SSH Proxy'
APP_VERSION=1.3.0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_FILE=${SSH_PROXY_CONFIG:-"$SCRIPT_DIR/ssh-proxy-profiles.ini"}
STATE_DIR=${SSH_PROXY_STATE_DIR:-"$SCRIPT_DIR"}
PID_DIR="$STATE_DIR/pids"
LOG_DIR=${SSH_PROXY_LOG_DIR:-"$SCRIPT_DIR/logs"}
STATUS_DIR="$STATE_DIR/status"
CREDENTIAL_DIR="$STATE_DIR/credentials"
RETRY_DELAY=${SSH_PROXY_RETRY_DELAY:-5}
MAX_RETRY_DELAY=${SSH_PROXY_MAX_RETRY_DELAY:-60}
MAC_NOTIFICATION=${SSH_PROXY_MAC_NOTIFICATION:-1}

parse_global_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a path"
        CONFIG_FILE=$2
        shift 2
        ;;
      --state-dir)
        [[ $# -ge 2 ]] || die "--state-dir requires a path"
        STATE_DIR=$2
        PID_DIR="$STATE_DIR/pids"
        LOG_DIR="$STATE_DIR/logs"
        STATUS_DIR="$STATE_DIR/status"
        CREDENTIAL_DIR="$STATE_DIR/credentials"
        shift 2
        ;;
      --no-notify)
        MAC_NOTIFICATION=0
        shift
        ;;
      --help|-h)
        REMAINING_ARGS=(help)
        return 0
        ;;
      --version|-V)
        REMAINING_ARGS=(version)
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done
  REMAINING_ARGS=("$@")
}

usage() {
  cat <<'EOF'
Usage:
  bash ssh-proxy.sh            Open the unified terminal console

Global options:
  --config <path>              Use a custom profile file
  --state-dir <path>           Use a custom PID/log directory
  --no-notify                  Disable macOS notifications (keep terminal bell)

Profile file format (INI; one block per server):
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

version() {
  printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

pid_file() { printf '%s/%s.pid' "$PID_DIR" "$1"; }
log_file() { printf '%s/%s.log' "$LOG_DIR" "$1"; }
status_file() { printf '%s/%s.status' "$STATUS_DIR" "$1"; }
credential_file() { printf '%s/%s.b64' "$CREDENTIAL_DIR" "$1"; }
default_credential_file() { printf '%s/default.b64' "$CREDENTIAL_DIR"; }

b64_encode() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

b64_decode() {
  if base64 -D </dev/null >/dev/null 2>&1; then
    base64 -D
  else
    base64 -d
  fi
}

triple_b64_encode() {
  local value=$1
  value=$(b64_encode "$value")
  value=$(b64_encode "$value")
  b64_encode "$value"
}

triple_b64_decode() {
  local value=$1
  value=$(printf '%s' "$value" | b64_decode) || return 1
  value=$(printf '%s' "$value" | b64_decode) || return 1
  printf '%s' "$value" | b64_decode
}

has_saved_password() {
  [[ -s "$(credential_file "$1")" ]]
}

has_default_password() {
  [[ -s "$(default_credential_file)" ]]
}

has_effective_password() {
  has_saved_password "$1" || has_default_password
}

askpass_password() {
  local name=${SSH_PROXY_PROFILE:-}
  local file
  [[ -n "$name" ]] || exit 1
  if has_saved_password "$name"; then
    file=$(credential_file "$name")
  else
    file=$(default_credential_file)
  fi
  [[ -r "$file" ]] || exit 1
  triple_b64_decode "$(<"$file")"
}

save_password() {
  local name=$1 password confirm encoded file
  find_profile "$name" || die "profile not found: $name"
  [[ -t 0 ]] || die 'save-password must be run from an interactive terminal'
  printf 'Enter password for %s: ' "$name"
  IFS= read -r -s password || { printf '\n'; die 'password input cancelled'; }
  printf '\nConfirm password: '
  IFS= read -r -s confirm || { printf '\n'; die 'password input cancelled'; }
  printf '\n'
  [[ "$password" = "$confirm" ]] || die 'passwords do not match'
  [[ -n "$password" ]] || die 'password cannot be empty'
  encoded=$(triple_b64_encode "$password") || die 'failed to encode password'
  file=$(credential_file "$name")
  printf '%s\n' "$encoded" > "$file" || die "cannot write credential file: $file"
  chmod 600 "$file" 2>/dev/null || true
  unset password confirm encoded
  printf 'Password saved for %s (triple Base64; not encryption).\n' "$name"
}

clear_password() {
  local name=$1 file
  find_profile "$name" || die "profile not found: $name"
  file=$(credential_file "$name")
  if [[ -e "$file" ]]; then
    rm -f "$file" || die "cannot delete credential file: $file"
    printf 'Saved password deleted for %s.\n' "$name"
  else
    printf 'No saved password for %s.\n' "$name"
  fi
}

save_default_password() {
  local password confirm encoded file
  [[ -t 0 ]] || die 'save-default-password must be run from an interactive terminal'
  printf 'Enter default password: '
  IFS= read -r -s password || { printf '\n'; die 'password input cancelled'; }
  printf '\nConfirm default password: '
  IFS= read -r -s confirm || { printf '\n'; die 'password input cancelled'; }
  printf '\n'
  [[ "$password" = "$confirm" ]] || die 'passwords do not match'
  [[ -n "$password" ]] || die 'password cannot be empty'
  encoded=$(triple_b64_encode "$password") || die 'failed to encode password'
  file=$(default_credential_file)
  printf '%s\n' "$encoded" > "$file" || die "cannot write credential file: $file"
  chmod 600 "$file" 2>/dev/null || true
  unset password confirm encoded
  printf 'Default password saved (triple Base64; not encryption).\n'
}

clear_default_password() {
  local file
  file=$(default_credential_file)
  if [[ -e "$file" ]]; then
    rm -f "$file" || die "cannot delete credential file: $file"
    printf 'Default password deleted.\n'
  else
    printf 'No default password saved.\n'
  fi
}

password_status() {
  local name
  if [[ $# -eq 1 ]]; then
    find_profile "$1" || die "profile not found: $1"
    if has_saved_password "$1"; then
      printf '%s: PROFILE_PASSWORD\n' "$1"
    elif has_default_password; then
      printf '%s: DEFAULT_PASSWORD\n' "$1"
    else
      printf '%s: NOT_SAVED\n' "$1"
    fi
    return 0
  fi
  if has_default_password; then printf '%-16s SAVED\n' DEFAULT; else printf '%-16s NOT_SAVED\n' DEFAULT; fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if has_effective_password "$name"; then
      printf '%-16s PROFILE_PASSWORD\n' "$name"
    elif has_default_password; then
      printf '%-16s DEFAULT_PASSWORD\n' "$name"
    else
      printf '%-16s NOT_SAVED\n' "$name"
    fi
  done < <(profile_names)
}

set_profile_status() {
  printf '%s\n' "$2" > "$(status_file "$1")"
}

profile_status() {
  local name=$1 file
  file=$(status_file "$name")
  if ! ui_is_running "$name" 2>/dev/null; then
    printf 'STOPPED'
  elif [[ -r "$file" ]]; then
    tr -d '\r\n' < "$file"
  else
    printf 'RUNNING'
  fi
}

notify() {
  local title=$1
  local message=$2
  printf '\a\a' >&2
  printf '[%s] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$title" "$message" >&2

  # Optional built-in macOS notification. No third-party package is used.
  if [[ "$MAC_NOTIFICATION" = 1 && "$OSTYPE" = darwin* && -x /usr/bin/osascript ]]; then
    /usr/bin/osascript - "$title" "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
  fi
}

expand_path() {
  local value=$1
  case "$value" in
    -|'') printf '%s' '-' ;;
    "~"/*) printf '%s/%s' "$HOME" "${value#\~/}" ;;
    *) printf '%s' "$value" ;;
  esac
}

trim_whitespace() {
  local value=$1
  value="${value#"${value%%[!$' \t\r\n']*}"}"
  value="${value%"${value##*[!$' \t\r\n']}"}"
  printf '%s' "$value"
}

strip_quotes() {
  local value=$1
  if [[ "$value" = \"*\" && "$value" = *\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ "$value" = \'*\' && "$value" = *\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

config_format() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim_whitespace "$line")
    [[ -z "$line" || "$line" = \#* || "$line" = \;* ]] && continue
    [[ "$line" =~ ^\[[A-Za-z0-9_.-]+\]$ ]] && { printf 'ini'; return 0; }
    printf 'legacy'
    return 0
  done < "$CONFIG_FILE"
  printf 'legacy'
}

load_ini_profile() {
  local wanted=$1 line section= key value found=0
  local default_reconnect=yes default_max_retries=0
  local default_retry_delay=$RETRY_DELAY default_max_retry_delay=$MAX_RETRY_DELAY
  local profile_reconnect= profile_max_retries= profile_retry_delay= profile_max_retry_delay=

  PROFILE_NAME=$wanted
  PROFILE_HOST=
  PROFILE_USER=
  PROFILE_SSH_PORT=
  PROFILE_LOCAL_PORT=
  PROFILE_IDENTITY=-

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim_whitespace "$line")
    [[ -z "$line" || "$line" = \#* || "$line" = \;* ]] && continue
    if [[ "$line" =~ ^\[([A-Za-z0-9_.-]+)\]$ ]]; then
      section=${BASH_REMATCH[1]}
      [[ "$section" = "$wanted" ]] && found=1
      continue
    fi
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=$(strip_quotes "$(trim_whitespace "${BASH_REMATCH[2]}")")

    case "$section:$key" in
      settings:reconnect|defaults:reconnect) default_reconnect=$value ;;
      settings:max_retries|defaults:max_retries) default_max_retries=$value ;;
      settings:retry_delay|defaults:retry_delay) default_retry_delay=$value ;;
      settings:max_retry_delay|defaults:max_retry_delay) default_max_retry_delay=$value ;;
      "$wanted":host) PROFILE_HOST=$value ;;
      "$wanted":user) PROFILE_USER=$value ;;
      "$wanted":ssh_port) PROFILE_SSH_PORT=$value ;;
      "$wanted":local_socks_port|"$wanted":local_port) PROFILE_LOCAL_PORT=$value ;;
      "$wanted":identity_file|"$wanted":identity) PROFILE_IDENTITY=$(expand_path "$value") ;;
      "$wanted":reconnect) profile_reconnect=$value ;;
      "$wanted":max_retries) profile_max_retries=$value ;;
      "$wanted":retry_delay) profile_retry_delay=$value ;;
      "$wanted":max_retry_delay) profile_max_retry_delay=$value ;;
    esac
  done < "$CONFIG_FILE"

  [[ "$found" = 1 ]] || return 1
  PROFILE_RECONNECT=${profile_reconnect:-$default_reconnect}
  PROFILE_MAX_RETRIES=${profile_max_retries:-$default_max_retries}
  PROFILE_RETRY_DELAY=${profile_retry_delay:-$default_retry_delay}
  PROFILE_MAX_RETRY_DELAY=${profile_max_retry_delay:-$default_max_retry_delay}
  return 0
}

profile_names() {
  local line section= name host user ssh_port local_port identity extra
  [[ -r "$CONFIG_FILE" ]] || die "profile file not found: $CONFIG_FILE"
  if [[ "$(config_format)" = ini ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(trim_whitespace "$line")
      if [[ "$line" =~ ^\[([A-Za-z0-9_.-]+)\]$ ]]; then
        section=${BASH_REMATCH[1]}
        case "$section" in
          settings|defaults) ;;
          *) printf '%s\n' "$section" ;;
        esac
      fi
    done < "$CONFIG_FILE"
  else
    while IFS=' ' read -r name host user ssh_port local_port identity extra; do
      [[ -z "${name:-}" || "$name" = \#* || -n "${extra:-}" ]] && continue
      printf '%s\n' "$name"
    done < "$CONFIG_FILE"
  fi
}

find_profile() {
  local wanted=$1
  local name host user ssh_port local_port identity extra
  [[ -r "$CONFIG_FILE" ]] || die "profile file not found: $CONFIG_FILE"

  if [[ "$(config_format)" = ini ]]; then
    load_ini_profile "$wanted"
    return $?
  fi

  while IFS=' ' read -r name host user ssh_port local_port identity extra; do
    [[ -z "${name:-}" || "$name" = \#* ]] && continue
    [[ -n "${extra:-}" ]] && continue
    if [[ "$name" = "$wanted" ]]; then
      [[ -n "${host:-}" && -n "${user:-}" && -n "${ssh_port:-}" && -n "${local_port:-}" ]] || die "incomplete profile: $name"
      PROFILE_NAME=$name
      PROFILE_HOST=$host
      PROFILE_USER=$user
      PROFILE_SSH_PORT=$ssh_port
      PROFILE_LOCAL_PORT=$local_port
      PROFILE_IDENTITY=$(expand_path "${identity:--}")
      PROFILE_RECONNECT=yes
      PROFILE_MAX_RETRIES=0
      PROFILE_RETRY_DELAY=$RETRY_DELAY
      PROFILE_MAX_RETRY_DELAY=$MAX_RETRY_DELAY
      return 0
    fi
  done < "$CONFIG_FILE"
  return 1
}

list_profiles() {
  local name
  [[ -r "$CONFIG_FILE" ]] || die "profile file not found: $CONFIG_FILE"
  printf '%-16s %-34s %-16s %s\n' NAME SERVER USER SOCKS_PORT
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    find_profile "$name" || continue
    printf '%-16s %-34s %-16s %s\n' "$name" "$PROFILE_HOST:$PROFILE_SSH_PORT" "$PROFILE_USER" "$PROFILE_LOCAL_PORT"
  done < <(profile_names)
}

check_config() {
  local name line_no=0 warned_ports= reconnect_value
  local -a names ports
  local found=0
  require_command ssh
  require_command base64
  require_command tr
  require_command stty
  [[ -r "$CONFIG_FILE" ]] || die "profile file not found: $CONFIG_FILE"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    line_no=$((line_no + 1))
    found=1
    valid_name "$name" || die "invalid profile name on line $line_no: $name"
    find_profile "$name" || die "unable to read profile: $name"
    [[ -n "$PROFILE_HOST" && -n "$PROFILE_USER" && -n "$PROFILE_SSH_PORT" && -n "$PROFILE_LOCAL_PORT" ]] || die "incomplete profile: $name"
    valid_port "$PROFILE_SSH_PORT" || die "invalid SSH port in profile $name: $PROFILE_SSH_PORT"
    valid_port "$PROFILE_LOCAL_PORT" || die "invalid local port in profile $name: $PROFILE_LOCAL_PORT"
    if [[ "$PROFILE_IDENTITY" != '-' ]]; then
      [[ -r "$PROFILE_IDENTITY" ]] || die "identity file is not readable in profile $name: $PROFILE_IDENTITY"
    fi
    reconnect_value=$(printf '%s' "$PROFILE_RECONNECT" | tr '[:upper:]' '[:lower:]')
    [[ "$reconnect_value" = yes || "$reconnect_value" = no || "$reconnect_value" = true || "$reconnect_value" = false ]] || die "reconnect must be yes or no in profile $name"
    [[ "$PROFILE_MAX_RETRIES" =~ ^[0-9]+$ ]] || die "max_retries must be a non-negative integer in profile $name"
    [[ "$PROFILE_RETRY_DELAY" =~ ^[1-9][0-9]*$ ]] || die "retry_delay must be a positive integer in profile $name"
    [[ "$PROFILE_MAX_RETRY_DELAY" =~ ^[1-9][0-9]*$ ]] || die "max_retry_delay must be a positive integer in profile $name"
    (( PROFILE_MAX_RETRY_DELAY >= PROFILE_RETRY_DELAY )) || die "max_retry_delay must be >= retry_delay in profile $name"

    local old
    for old in "${names[@]:-}"; do
      [[ "$old" != "$name" ]] || die "duplicate profile name: $name"
    done
    for old in "${ports[@]:-}"; do
      if [[ "$old" = "$PROFILE_LOCAL_PORT" && ":$warned_ports:" != *":$PROFILE_LOCAL_PORT:"* ]]; then
        printf 'Warning: local port %s is shared by multiple profiles; run only one at a time.\n' "$PROFILE_LOCAL_PORT" >&2
        warned_ports="$warned_ports$PROFILE_LOCAL_PORT:"
        break
      fi
    done
    names+=("$name")
    ports+=("$PROFILE_LOCAL_PORT")
  done < <(profile_names)

  [[ "$found" = 1 ]] || die "profile file has no valid entries"
  printf 'Configuration valid: %s (%s profiles)\n' "$CONFIG_FILE" "${#names[@]}"
  printf 'Dependencies available: ssh, base64, tr, stty%s\n' "$(command -v lsof >/dev/null 2>&1 && printf ', lsof' || true)"
}

show_config() {
  printf 'Profile file: %s\n' "$CONFIG_FILE"
  printf 'State directory: %s\n' "$STATE_DIR"
  printf 'PID directory: %s\n' "$PID_DIR"
  printf 'Log directory: %s\n' "$LOG_DIR"
  printf 'Status directory: %s\n' "$STATUS_DIR"
  printf 'Credential directory: %s\n' "$CREDENTIAL_DIR"
}

port_owner() {
  local port=$1
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  fi
}

port_is_busy() {
  [[ -n "$(port_owner "$1")" ]]
}

cleanup() {
  local pid_file_path=$1
  local child_pid=${2:-}
  if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  rm -f "$pid_file_path"
}

run_tunnel() {
  local name=$1
  local pid_path log_path child_pid rc stopping=0
  local delay retry_count=0 reconnect_enabled max_retries max_retry_delay
  local interactive_mode=${SSH_PROXY_INTERACTIVE:-0} interactive_key
  find_profile "$name" || die "profile not found: $name"
  valid_name "$name" || die "profile name may contain only letters, numbers, dots, underscores, and hyphens"
  reconnect_enabled=$(printf '%s' "$PROFILE_RECONNECT" | tr '[:upper:]' '[:lower:]')
  delay=$PROFILE_RETRY_DELAY
  max_retries=$PROFILE_MAX_RETRIES
  max_retry_delay=$PROFILE_MAX_RETRY_DELAY

  pid_path=$(pid_file "$name")
  log_path=$(log_file "$name")

  if [[ -f "$pid_path" ]]; then
    local old_pid
    old_pid=$(<"$pid_path")
    if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
      die "$name is already running (PID $old_pid)"
    fi
    rm -f "$pid_path"
  fi

  if port_is_busy "$PROFILE_LOCAL_PORT"; then
    port_owner "$PROFILE_LOCAL_PORT" >&2
    die "local port $PROFILE_LOCAL_PORT is already in use; choose another port or stop the process using it"
  fi

  printf '%s\n' "$$" > "$pid_path"
  set_profile_status "$name" STARTING
  trap 'stopping=1; set_profile_status "$name" STOPPING; cleanup "$pid_path" "${child_pid:-}"; set_profile_status "$name" STOPPED' INT TERM EXIT

  printf '[%s] Starting %s -> socks5h://127.0.0.1:%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$name" "$PROFILE_LOCAL_PORT" | tee -a "$log_path"

  while [[ "$stopping" = 0 ]]; do
    local -a ssh_args
    ssh_args=(
      -N -T
      -D "127.0.0.1:$PROFILE_LOCAL_PORT"
      -p "$PROFILE_SSH_PORT"
      -o ExitOnForwardFailure=yes
      -o ServerAliveInterval=30
      -o ServerAliveCountMax=3
      -o ConnectTimeout=15
      -o TCPKeepAlive=yes
    )
    if [[ "$interactive_mode" = 1 ]]; then
      ssh_args+=( -o StrictHostKeyChecking=ask )
    else
      # Background connections cannot answer SSH's host-key prompt. Accept a
      # new host key automatically, but still reject changed known-host keys.
      ssh_args+=( -o StrictHostKeyChecking=accept-new )
    fi
    if [[ "$PROFILE_IDENTITY" != '-' ]]; then
      ssh_args+=( -i "$PROFILE_IDENTITY" )
    fi

    printf '[%s] Connecting to %s@%s:%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$PROFILE_USER" "$PROFILE_HOST" "$PROFILE_SSH_PORT" | tee -a "$log_path"
    printf 'Enter a password or MFA code in this terminal if prompted.\n' >&2

    # Do not use ssh -f: keeping ssh as a child lets us detect disconnects.
    if has_effective_password "$name"; then
      SSH_ASKPASS="$0" \
      SSH_ASKPASS_REQUIRE=force \
      SSH_PROXY_ASKPASS=1 \
      SSH_PROXY_PROFILE="$name" \
      SSH_PROXY_STATE_DIR="$STATE_DIR" \
      DISPLAY="${DISPLAY:-1}" \
      ssh "${ssh_args[@]}" "$PROFILE_USER@$PROFILE_HOST" 2>>"$log_path" &
    else
      ssh "${ssh_args[@]}" "$PROFILE_USER@$PROFILE_HOST" 2>>"$log_path" &
    fi
    child_pid=$!

    # The dynamic forward starts listening only after SSH authentication succeeds.
    local connect_wait=0
    while (( connect_wait < 150 )); do
      if ! kill -0 "$child_pid" 2>/dev/null; then break; fi
      if [[ -n "$(port_owner "$PROFILE_LOCAL_PORT")" ]]; then
        set_profile_status "$name" CONNECTED
        printf '[%s] Connected; SOCKS proxy ready at socks5h://127.0.0.1:%s\n' \
          "$(date '+%Y-%m-%d %H:%M:%S')" "$PROFILE_LOCAL_PORT" | tee -a "$log_path"
        retry_count=0
        delay=$PROFILE_RETRY_DELAY
        break
      fi
      sleep 0.2
      connect_wait=$((connect_wait + 1))
    done

    if [[ "$interactive_mode" = 1 && "$(profile_status "$name")" = CONNECTED ]]; then
      printf '\nConnection established. The tunnel is active.\n'
      printf 'Press Enter or r to return to the main console and keep it running.\n'
      printf 'Press Ctrl-C to stop the tunnel and return.\n\n'
      while kill -0 "$child_pid" 2>/dev/null; do
        interactive_key=
        if IFS= read -rsn1 -t 1 interactive_key; then
          case "$interactive_key" in
            ''|$'\n'|$'\r'|r|R)
              printf 'Returning to the main console; tunnel remains active.\n'
              printf '%s\n' "$child_pid" > "$pid_path"
              trap - INT TERM EXIT
              INTERACTIVE_DETACHED=1
              child_pid=
              return 0
              ;;
          esac
        fi
      done
    fi

    wait "$child_pid"
    rc=$?
    child_pid=

    [[ "$stopping" = 1 ]] && break
    if [[ "$reconnect_enabled" != yes && "$reconnect_enabled" != true ]]; then
      set_profile_status "$name" STOPPED
      printf '[%s] Disconnected, exit code %s; automatic reconnect is disabled\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$rc" | tee -a "$log_path"
      break
    fi
    retry_count=$((retry_count + 1))
    if (( max_retries > 0 && retry_count > max_retries )); then
      set_profile_status "$name" STOPPED
      notify "SSH SOCKS reconnect limit reached" "$name (maximum retries: $max_retries)"
      printf '[%s] Disconnected, exit code %s; reconnect limit reached (%s attempts)\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$rc" "$max_retries" | tee -a "$log_path"
      break
    fi
    set_profile_status "$name" RECONNECTING
    notify "SSH SOCKS disconnected" "$name (exit code $rc); reconnecting in ${delay}s"
    printf '[%s] Disconnected, exit code %s; reconnecting in %ss\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$rc" "$delay" >> "$log_path"
    sleep "$delay"
    (( delay < max_retry_delay )) && delay=$((delay * 2))
    (( delay > max_retry_delay )) && delay=$max_retry_delay
  done

  printf '[%s] Stopped %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$name" | tee -a "$log_path"
}

start_tunnel() {
  local name=$1
  find_profile "$name" || die "profile not found: $name"
  valid_name "$name" || die "profile name may contain only letters, numbers, dots, underscores, and hyphens"
  SSH_PROXY_CONFIG="$CONFIG_FILE" \
  SSH_PROXY_STATE_DIR="$STATE_DIR" \
  SSH_PROXY_LOG_DIR="$LOG_DIR" \
  SSH_PROXY_INTERNAL_RUN=1 \
  nohup "$0" "$name" >>"$(log_file "$name")" 2>&1 </dev/null &
  printf '%s background start requested; log: %s\n' "$name" "$(log_file "$name")"
}

restart_tunnel() {
  local name=$1
  stop_tunnel "$name"
  sleep 1
  start_tunnel "$name"
}

stop_tunnel() {
  local name=$1 pid_path pid
  valid_name "$name" || die "profile name may contain only letters, numbers, dots, underscores, and hyphens"
  pid_path=$(pid_file "$name")
  set_profile_status "$name" STOPPING
  [[ -r "$pid_path" ]] || { set_profile_status "$name" STOPPED; printf '%s is not running\n' "$name"; return 0; }
  pid=$(<"$pid_path")
  [[ "$pid" =~ ^[0-9]+$ ]] || { rm -f "$pid_path"; set_profile_status "$name" STOPPED; printf '%s is not running\n' "$name"; return 0; }
  if kill -0 "$pid" 2>/dev/null; then
    kill TERM "$pid" 2>/dev/null || true
    printf 'Stop signal sent: %s (PID %s)\n' "$name" "$pid"
  else
    rm -f "$pid_path"
    set_profile_status "$name" STOPPED
    printf '%s is not running\n' "$name"
  fi
}

status_one() {
  local name=$1 pid_path pid state
  pid_path=$(pid_file "$name")
  if [[ -r "$pid_path" ]]; then
    pid=$(<"$pid_path")
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      state=$(profile_status "$name")
      printf '%-16s %-12s PID=%s\n' "$name" "$state" "$pid"
      return 0
    fi
  fi
  printf '%-16s STOPPED\n' "$name"
}

status_all() {
  local name
  [[ -r "$CONFIG_FILE" ]] || die "profile file not found: $CONFIG_FILE"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    status_one "$name"
  done < <(profile_names)
}

logs() {
  local name=$1 file
  file=$(log_file "$name")
  [[ -f "$file" ]] || die "no log file found: $file"
  tail -n 80 "$file"
}

load_ui_profiles() {
  UI_NAMES=()
  UI_HOSTS=()
  UI_USERS=()
  UI_SSH_PORTS=()
  UI_LOCAL_PORTS=()
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    find_profile "$name" || continue
    UI_NAMES+=("$name")
    UI_HOSTS+=("$PROFILE_HOST")
    UI_USERS+=("$PROFILE_USER")
    UI_SSH_PORTS+=("$PROFILE_SSH_PORT")
    UI_LOCAL_PORTS+=("$PROFILE_LOCAL_PORT")
  done < <(profile_names)
  if (( ${#UI_NAMES[@]} == 0 )); then
    [[ "${1:-}" = allow-empty ]] && return 1
    die "profile file has no valid entries"
  fi
}

ui_config_snapshot() {
  cksum "$CONFIG_FILE" 2>/dev/null || printf 'missing'
}

ui_reload_profiles() {
  local current_profile=$1 i=0
  local -a old_names=("${UI_NAMES[@]}")
  local -a old_hosts=("${UI_HOSTS[@]}")
  local -a old_users=("${UI_USERS[@]}")
  local -a old_ssh_ports=("${UI_SSH_PORTS[@]}")
  local -a old_local_ports=("${UI_LOCAL_PORTS[@]}")
  [[ -r "$CONFIG_FILE" ]] || return 1
  if ! load_ui_profiles allow-empty; then
    UI_NAMES=("${old_names[@]}")
    UI_HOSTS=("${old_hosts[@]}")
    UI_USERS=("${old_users[@]}")
    UI_SSH_PORTS=("${old_ssh_ports[@]}")
    UI_LOCAL_PORTS=("${old_local_ports[@]}")
    return 1
  fi
  while (( i < ${#UI_NAMES[@]} )); do
    if [[ "${UI_NAMES[$i]}" = "$current_profile" ]]; then
      selected=$i
      return 0
    fi
    i=$((i + 1))
  done
  (( selected >= ${#UI_NAMES[@]} )) && selected=$((${#UI_NAMES[@]} - 1))
}

ui_refresh_config() {
  local profile=${UI_NAMES[$selected]}
  ui_reload_profiles "$profile" || true
  last_config_snapshot=$(ui_config_snapshot)
  last_config_check=$SECONDS
  redraw=1
}

ui_is_running() {
  local name=$1 pid_path pid
  pid_path=$(pid_file "$name")
  [[ -r "$pid_path" ]] || return 1
  pid=$(<"$pid_path")
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

ui_status_snapshot() {
  local i snapshot=
  i=0
  while (( i < ${#UI_NAMES[@]} )); do
    snapshot="$snapshot${UI_NAMES[$i]}=$(profile_status "${UI_NAMES[$i]}");"
    i=$((i + 1))
  done
  printf '%s' "$snapshot"
}

ui_wait_for_connected() {
  local name=$1 state i=0
  while (( i < 75 )); do
    state=$(profile_status "$name")
    case "$state" in
      CONNECTED) return 0 ;;
      STOPPED|RECONNECTING) return 1 ;;
    esac
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

ui_clear() {
  printf '\033[2J\033[H'
}

ui_pause() {
  local key
  printf '\nPress any key to return...' >&2
  IFS= read -rsn1 key || true
}

UI_SAVED_STTY=

ui_restore_terminal() {
  if [[ -n "${UI_SAVED_STTY:-}" ]]; then
    stty "$UI_SAVED_STTY" 2>/dev/null || true
  fi
  printf '\033[?25h\033[0m\n'
}

ui_install_trap() {
  trap ui_restore_terminal INT TERM EXIT
}

ui_draw() {
  local selected=$1 i marker state
  ui_clear
  printf '\033[1;36m'
  cat <<'EOF'
+------------------------------------------------------------+
|                         SSH PROXY                          |
|              Dynamic SOCKS5 Tunnel Manager                 |
+------------------------------------------------------------+
EOF
  printf '\033[0m\n'
  printf 'A lightweight Bash console for SSH dynamic SOCKS5 tunnels.\n'
  printf 'Automatic reconnect, external profiles, and optional password storage.\n\n'
  printf 'Profile file: %s\n\n' "$CONFIG_FILE"
  printf '  %-18s %-34s %-12s %-12s\n' NAME SERVER STATUS SOCKS_PORT
  printf '  %-18s %-34s %-12s %-12s\n' '------------------' '----------------------------------' '------------' '------------'
  i=0
  while (( i < ${#UI_NAMES[@]} )); do
    marker=' '
    [[ "$i" = "$selected" ]] && marker='>'
    state=$(profile_status "${UI_NAMES[$i]}")
    printf '%s %-18s %-34s %-12s %-12s\n' \
      "$marker" "${UI_NAMES[$i]}" "${UI_USERS[$i]}@${UI_HOSTS[$i]}:${UI_SSH_PORTS[$i]}" \
      "$state" "127.0.0.1:${UI_LOCAL_PORTS[$i]}"
    i=$((i + 1))
  done
  printf '\n\033[2mUp/Down or j/k: select   Enter/t: start/stop   r: restart   l: logs   c: interactive connect   f: reload config\033[0m\n'
  printf '\033[2m p: save profile password   g: save default password   d: delete profile password   x: delete default password   q: quit\033[0m\n'
}

ui_run() {
  local selected=0 key escape_key profile redraw=1 last_snapshot current_snapshot
  local last_config_snapshot current_config_snapshot last_config_check
  load_ui_profiles
  require_command stty
  require_command cksum
  UI_SAVED_STTY=$(stty -g) || die 'unable to read terminal settings'
  stty -echo -icanon min 1 time 0
  ui_install_trap
  printf '\033[?25l'
  last_config_snapshot=$(ui_config_snapshot)
  last_config_check=$SECONDS

  while :; do
    if (( redraw )); then
      ui_draw "$selected"
      last_snapshot=$(ui_status_snapshot)
      redraw=0
    fi
    key=
    # Check status every 10 seconds, but check the INI file only once per
    # minute to avoid unnecessary file reads and redraws.
    if ! IFS= read -rsn1 -t 10 key; then
      if (( SECONDS - last_config_check >= 60 )); then
        current_config_snapshot=$(ui_config_snapshot)
        if [[ "$current_config_snapshot" != "$last_config_snapshot" ]]; then
          ui_refresh_config
        else
          last_config_check=$SECONDS
        fi
      fi
      current_snapshot=$(ui_status_snapshot)
      if [[ "$current_snapshot" != "$last_snapshot" ]]; then
        redraw=1
      fi
      continue
    fi
    case "$key" in
      q|Q) break ;;
      j|J) selected=$(( (selected + 1) % ${#UI_NAMES[@]} )) ;;
      k|K) selected=$(( (selected - 1 + ${#UI_NAMES[@]}) % ${#UI_NAMES[@]} )) ;;
      $'\033')
        IFS= read -rsn2 escape_key || true
        case "$escape_key" in
          '[A') selected=$(( (selected - 1 + ${#UI_NAMES[@]}) % ${#UI_NAMES[@]} )) ;;
          '[B') selected=$(( (selected + 1) % ${#UI_NAMES[@]} )) ;;
        esac
        ;;
      ''|$'\n'|$'\r'|t|T)
        profile=${UI_NAMES[$selected]}
        if ui_is_running "$profile"; then
          stop_tunnel "$profile"
        else
          start_tunnel "$profile"
          ui_wait_for_connected "$profile" || true
        fi
        sleep 0.3
        ;;
      r|R)
        profile=${UI_NAMES[$selected]}
        restart_tunnel "$profile"
        sleep 1
        ;;
      f|F)
        ui_refresh_config
        ;;
      l|L)
        profile=${UI_NAMES[$selected]}
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        logs "$profile" || true
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      p|P)
        profile=${UI_NAMES[$selected]}
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        save_password "$profile" || true
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      d|D)
        profile=${UI_NAMES[$selected]}
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        clear_password "$profile" || true
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      g|G)
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        save_default_password || true
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      x|X)
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        clear_default_password || true
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      c|C)
        profile=${UI_NAMES[$selected]}
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        if ui_is_running "$profile"; then
          printf '%s is already %s.\n\n' "$profile" "$(profile_status "$profile")"
          printf 'Stop the current tunnel with Enter/t before opening an interactive connection.\n'
          ui_pause
        else
          printf 'Interactive connection: %s\nEnter a password or MFA response when prompted.\n\n' "$profile"
          INTERACTIVE_DETACHED=0
          SSH_PROXY_INTERACTIVE=1
          run_tunnel "$profile" || true
          unset SSH_PROXY_INTERACTIVE
          [[ "${INTERACTIVE_DETACHED:-0}" = 1 ]] || ui_pause
        fi
        ui_install_trap
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
      h|H|\?)
        stty "$UI_SAVED_STTY"
        printf '\033[?25h'
        ui_clear
        usage
        ui_pause
        stty -echo -icanon min 1 time 0
        printf '\033[?25l'
        ;;
    esac
    redraw=1
  done
}

if [[ "${SSH_PROXY_ASKPASS:-0}" = 1 ]]; then
  askpass_password
  exit $?
fi

# Private supervisor entry point used by the terminal console. This is intentionally not a public command.
if [[ "${SSH_PROXY_INTERNAL_RUN:-0}" = 1 ]]; then
  [[ $# -eq 1 ]] || exit 2
  mkdir -p "$PID_DIR" "$LOG_DIR" "$STATUS_DIR" "$CREDENTIAL_DIR" || exit 1
  run_tunnel "$1"
  exit $?
fi

parse_global_options "$@"
if (( ${#REMAINING_ARGS[@]:-0} > 0 )); then
  set -- "${REMAINING_ARGS[@]}"
else
  set --
fi
mkdir -p "$PID_DIR" "$LOG_DIR" "$STATUS_DIR" "$CREDENTIAL_DIR" || die "unable to create state directory: $STATE_DIR"

if [[ "${1:-}" = help ]]; then
  [[ $# -eq 1 ]] || die 'usage: ssh-proxy.sh --help'
  usage
  exit 0
fi
if [[ "${1:-}" = version ]]; then
  [[ $# -eq 1 ]] || die 'usage: ssh-proxy.sh --version'
  version
  exit 0
fi
[[ $# -eq 0 ]] || die 'this application uses the terminal console; use --help for options'
[[ -t 0 && -t 1 ]] || die 'an interactive terminal is required'
ui_run
