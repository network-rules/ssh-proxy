#!/usr/bin/env bash

locale_msg() {
  local key=$1
  shift || true
  case "$key" in
    error_prefix) printf '错误' ;;
    missing_command) printf '缺少命令：%s' "$1" ;;
    config_required) printf '%s 需要路径参数' "$1" ;;
    unknown_option) printf '未知选项：%s' "$1" ;;
    profile_not_found) printf '找不到服务器配置：%s' "$1" ;;
    invalid_profile_name) printf '服务器名称只能包含字母、数字、点、下划线和连字符：%s' "$1" ;;
    profile_file_not_found) printf '找不到配置文件：%s' "$1" ;;
    interactive_required) printf '需要交互式终端' ;;
    password_terminal) printf '%s 必须在交互式终端中运行' "$1" ;;
    enter_password) printf '请输入 %s 的密码： ' "$1" ;;
    confirm_password) printf '请确认密码： ' ;;
    input_cancelled) printf '密码输入已取消' ;;
    passwords_mismatch) printf '两次输入的密码不一致' ;;
    password_empty) printf '密码不能为空' ;;
    encode_failed) printf '密码编码失败' ;;
    write_credential) printf '无法写入凭据文件：%s' "$1" ;;
    password_saved) printf '已保存 %s 的密码（三次 Base64 编码，不是加密）。' "$1" ;;
    credential_deleted) printf '已删除 %s 的保存密码。' "$1" ;;
    no_password) printf '%s 没有保存的密码。' "$1" ;;
    enter_default) printf '请输入默认密码： ' ;;
    confirm_default) printf '请确认默认密码： ' ;;
    default_saved) printf '已保存默认密码（三次 Base64 编码，不是加密）。' ;;
    default_deleted) printf '已删除默认密码。' ;;
    no_default) printf '没有保存默认密码。' ;;
    delete_credential) printf '无法删除凭据文件：%s' "$1" ;;
    incomplete_profile) printf '服务器配置不完整：%s' "$1" ;;
    invalid_name) printf '第 %s 行的服务器名称无效：%s' "$1" "$2" ;;
    invalid_port) printf '服务器 %s 的 %s 端口无效：%s' "$2" "$1" "$3" ;;
    identity_unreadable) printf '服务器 %s 的密钥文件不可读：%s' "$1" "$2" ;;
    invalid_reconnect) printf '服务器 %s 的 reconnect 必须为 yes 或 no' "$1" ;;
    invalid_max_retries) printf '服务器 %s 的 max_retries 必须为非负整数' "$1" ;;
    invalid_retry_delay) printf '服务器 %s 的 %s 必须为正整数' "$2" "$1" ;;
    retry_order) printf '服务器 %s 的 max_retry_delay 必须大于等于 retry_delay' "$1" ;;
    duplicate_profile) printf '服务器名称重复：%s' "$1" ;;
    shared_port_warning) printf '警告：本地端口 %s 被多个服务器共用；同一时间只能运行一个。' "$1" ;;
    config_valid) printf '配置有效：%s（%s 个服务器）' "$1" "$2" ;;
    dependencies) printf '依赖可用：ssh、base64、tr、stty%s' "$1" ;;
    already_running) printf '%s 已在运行（PID %s）' "$1" "$2" ;;
    port_busy) printf '本地端口 %s 已被占用；请选择其他端口或停止占用该端口的进程' "$1" ;;
    starting) printf '[%s] 正在启动 %s -> socks5h://127.0.0.1:%s' "$1" "$2" "$3" ;;
    connecting) printf '[%s] 正在连接 %s@%s:%s' "$1" "$2" "$3" "$4" ;;
    prompt_password) printf '如出现提示，请在此终端输入密码或 MFA 验证码。' ;;
    connected) printf '[%s] 已连接；SOCKS 代理已就绪：socks5h://127.0.0.1:%s' "$1" "$2" ;;
    connection_established) printf '连接成功，隧道正在运行。' ;;
    return_keep_running) printf '按 Enter 或 r 返回主界面并保持隧道运行。' ;;
    return_stop) printf '按 Ctrl-C 停止隧道并返回。' ;;
    returning) printf '正在返回主界面；隧道保持运行。' ;;
    auto_disabled) printf '[%s] 已断开，退出码 %s；自动重连已禁用' "$1" "$2" ;;
    retry_limit) printf '[%s] 已断开，退出码 %s；已达到重连上限（%s 次）' "$1" "$2" "$3" ;;
    disconnected) printf '[%s] 已断开，退出码 %s；将在 %s 秒后重连' "$1" "$2" "$3" ;;
    notify_retry_limit) printf 'SSH SOCKS 重连次数已达上限' ;;
    notify_disconnected) printf 'SSH SOCKS 已断开' ;;
    stopped) printf '[%s] 已停止 %s' "$1" "$2" ;;
    background_start) printf '已请求后台启动 %s；日志：%s' "$1" "$2" ;;
    stop_signal) printf '已发送停止信号：%s（PID %s）' "$1" "$2" ;;
    not_running) printf '%s 未运行' "$1" ;;
    no_log) printf '找不到日志文件：%s' "$1" ;;
    no_profiles) printf '配置文件中没有有效服务器' ;;
    terminal_settings) printf '无法读取终端设置' ;;
    state_directory_error) printf '无法创建运行目录：%s' "$1" ;;
    terminal_console_only) printf '此应用使用终端控制台；使用 --help 查看选项' ;;
    usage_help) printf '用法：ssh-proxy.sh --help' ;;
    usage_version) printf '用法：ssh-proxy.sh --version' ;;
    locale_error) printf '无法加载 %s 语言文件' "$1" ;;
    active_profile) printf '%s 当前已经是 %s。' "$1" "$2" ;;
    stop_before_interactive) printf '请先按 Enter/t 停止当前隧道，再打开交互式连接。' ;;
    interactive_start) printf '交互式连接：%s' "$1" ;;
    interactive_prompt) printf '如出现提示，请输入密码或 MFA 响应。' ;;
    pause) printf '按任意键返回……' ;;
    ui_description_1) printf '轻量级 Bash SSH 动态 SOCKS5 隧道控制台。' ;;
    ui_description_2) printf '支持自动重连、外部配置和可选密码保存。' ;;
    profile_file_label) printf '配置文件' ;;
    table_name) printf '名称' ;;
    table_server) printf '服务器' ;;
    table_status) printf '状态' ;;
    table_socks_port) printf 'SOCKS端口' ;;
    status_stopped) printf '已停止' ;;
    status_running) printf '运行中' ;;
    status_starting) printf '启动中' ;;
    status_connected) printf '已连接' ;;
    status_reconnecting) printf '重连中' ;;
    status_stopping) printf '停止中' ;;
    ui_controls_1) printf '上/下或 j/k：选择   Enter/t：启动/停止   r：重启   l：日志   c：交互式连接' ;;
    ui_controls_2) printf 'p：保存服务器密码   g：保存默认密码   d：删除服务器密码   x：删除默认密码   q：退出' ;;
    *) locale_msg_en "$key" "$@" ;;
  esac
}

locale_usage() {
  cat <<'EOF'
用法：
  bash ssh-proxy.sh            打开统一终端控制台

全局选项：
  --config <path>              使用自定义配置文件
  --state-dir <path>           使用自定义运行目录
  --no-notify                  禁用 macOS 通知（保留终端提示音）

语言设置：
  在 [settings] 中设置 language = en 或 language = zh-CN，或使用 SSH_PROXY_LANG。

配置格式（INI；每台服务器使用独立区块）：
  [settings]
  language = zh-CN
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

重连设置：
  reconnect                     yes 或 no；默认：yes
  max_retries                   最大重连次数；0 表示无限重连
  retry_delay                   初始重连等待秒数
  max_retry_delay               指数退避的最大等待秒数

控制键：
  上/下或 j/k                   选择服务器
  Enter/t                       启动或停止隧道
  r                             重启选中的隧道
  l                             查看日志
  c                             打开交互式连接；连接成功后按 Enter 返回
  p                             保存服务器密码
  g                             保存默认密码
  d                             删除服务器密码
  x                             删除默认密码
  q                             退出
EOF
}
