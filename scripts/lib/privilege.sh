#!/usr/bin/env bash

# 获取目标用户名。
# 参数:
#   无（可读取环境变量 TARGET_USER/SUDO_USER）
# 返回:
#   输出用户名
privilege::target_user() {
  if [[ -n "${TARGET_USER:-}" ]]; then
    printf "%s\n" "$TARGET_USER"
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    printf "%s\n" "$SUDO_USER"
    return 0
  fi

  id -un
}

# 获取目标用户 HOME 路径。
# 参数:
#   无
# 返回:
#   输出 HOME 绝对路径
privilege::target_home() {
  local user
  user="$(privilege::target_user)"

  if [[ "$user" == "root" ]]; then
    printf "/root\n"
    return 0
  fi

  getent passwd "$user" | awk -F: '{print $6}'
}

# 以 root 权限执行命令。
# 参数:
#   $@: 需要执行的命令
# 行为:
#   非 root 时自动使用 sudo。
privilege::as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    cmd::run "$@"
    return 0
  fi

  cmd::require sudo
  cmd::run sudo -- "$@"
}

# 以目标普通用户权限执行命令。
# 参数:
#   $@: 需要执行的命令
# 行为:
#   root 场景下优先降权到目标用户；非 root 场景直接执行。
privilege::as_user() {
  local user
  user="$(privilege::target_user)"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    cmd::run "$@"
    return 0
  fi

  if [[ "$user" == "root" ]]; then
    cmd::run "$@"
    return 0
  fi

  cmd::require sudo
  cmd::run sudo -H -u "$user" -- "$@"
}
