#!/usr/bin/env bash

declare -Ag PKG_REFRESH_DONE=()

# 是否启用索引刷新（默认启用）。
# 环境变量:
#   PKG_REFRESH_ENABLE=1|0
pkg::refresh_enabled() {
  [[ "${PKG_REFRESH_ENABLE:-1}" == "1" ]]
}

# pacman 系列刷新模式。
# 环境变量:
#   PKG_PACMAN_REFRESH_MODE=sync|force|skip
pkg::pacman_refresh_mode() {
  local mode="${PKG_PACMAN_REFRESH_MODE:-sync}"
  mode="${mode,,}"

  case "$mode" in
    sync|force|skip)
      printf "%s\n" "$mode"
      ;;
    *)
      log::die "Unsupported PKG_PACMAN_REFRESH_MODE: $mode (allowed: sync|force|skip)"
      ;;
  esac
}

pkg::is_refresh_done() {
  local backend="$1"

  if [[ "${PKG_REFRESH_DONE[$backend]:-0}" == "1" ]]; then
    return 0
  fi

  local state_file="${PKG_REFRESH_STATE_FILE:-}"
  if [[ -n "$state_file" && -f "$state_file" ]]; then
    grep -Fxq "$backend" "$state_file"
    return $?
  fi

  return 1
}

pkg::mark_refresh_done() {
  local backend="$1"

  PKG_REFRESH_DONE[$backend]="1"

  local state_file="${PKG_REFRESH_STATE_FILE:-}"
  if [[ -n "$state_file" ]]; then
    touch "$state_file"
    if ! grep -Fxq "$backend" "$state_file"; then
      printf "%s\n" "$backend" >> "$state_file"
    fi
  fi
}

# 检测可用包管理器并导出 PKG_MANAGER。
# 参数:
#   无
# 返回:
#   通过环境变量导出 PKG_MANAGER
pkg::detect_manager() {
  if cmd::exists pacman; then
    PKG_MANAGER="pacman"
  elif cmd::exists apt-get; then
    PKG_MANAGER="apt"
  elif cmd::exists dnf; then
    PKG_MANAGER="dnf"
  elif cmd::exists brew; then
    PKG_MANAGER="brew"
  else
    log::die "No supported package manager found"
  fi

  export PKG_MANAGER
}

# 检测可用 AUR 助手（优先 paru，其次 yay）。
# 参数:
#   无
# 返回:
#   输出助手名，若不存在则输出空字符串
pkg::detect_aur_helper() {
  if cmd::exists paru; then
    printf "paru\n"
    return 0
  fi

  if cmd::exists yay; then
    printf "yay\n"
    return 0
  fi

  printf "\n"
}

# 将声明的 backend 解析为最终 backend。
# 参数:
#   $1: 声明 backend（auto/pacman/aur/yay/paru/apt/dnf/brew）
# 返回:
#   输出最终 backend
pkg::resolve_backend() {
  local declared_backend="$1"
  local native_manager aur_helper

  declared_backend="${declared_backend:-auto}"

  case "$declared_backend" in
    auto)
      pkg::detect_manager
      native_manager="$PKG_MANAGER"
      printf "%s\n" "$native_manager"
      ;;
    aur)
      aur_helper="$(pkg::detect_aur_helper)"
      [[ -n "$aur_helper" ]] || log::die "AUR backend requested but no helper found (paru/yay)"
      printf "%s\n" "$aur_helper"
      ;;
    pacman|apt|dnf|brew|yay|paru)
      printf "%s\n" "$declared_backend"
      ;;
    *)
      log::die "Unsupported backend: $declared_backend"
      ;;
  esac
}

# 对需要索引更新的 backend 做“本轮仅一次”更新。
# 参数:
#   $1: backend
pkg::refresh_once() {
  local backend="$1"
  local pacman_mode=""

  [[ -n "$backend" ]] || return 0
  pkg::is_refresh_done "$backend" && return 0

  if ! pkg::refresh_enabled; then
    pkg::mark_refresh_done "$backend"
    return 0
  fi

  case "$backend" in
    apt)
      privilege::as_root apt-get update -y
      ;;
    pacman)
      pacman_mode="$(pkg::pacman_refresh_mode)"
      case "$pacman_mode" in
        sync)
          privilege::as_root pacman -Sy --noconfirm
          ;;
        force)
          privilege::as_root pacman -Syy --noconfirm
          ;;
        skip)
          ;;
      esac
      ;;
    dnf)
      privilege::as_root dnf makecache -y
      ;;
    brew)
      privilege::as_user brew update
      ;;
    yay)
      cmd::require yay
      pacman_mode="$(pkg::pacman_refresh_mode)"
      case "$pacman_mode" in
        sync)
          privilege::as_user yay -Sy --noconfirm
          ;;
        force)
          privilege::as_user yay -Syy --noconfirm
          ;;
        skip)
          ;;
      esac
      ;;
    paru)
      cmd::require paru
      pacman_mode="$(pkg::pacman_refresh_mode)"
      case "$pacman_mode" in
        sync)
          privilege::as_user paru -Sy --noconfirm
          ;;
        force)
          privilege::as_user paru -Syy --noconfirm
          ;;
        skip)
          ;;
      esac
      ;;
    *)
      # 其他 backend 目前不做统一 refresh。
      ;;
  esac

  pkg::mark_refresh_done "$backend"
}

# 使用指定 backend 安装软件包。
# 参数:
#   $1: backend
#   $@: 软件包名称列表
pkg::install_with_backend() {
  local backend="$1"
  shift || true
  local pkgs=("$@")

  [[ ${#pkgs[@]} -gt 0 ]] || return 0
  pkg::refresh_once "$backend"

  case "$backend" in
    pacman)
      privilege::as_root pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    apt)
      privilege::as_root apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      privilege::as_root dnf install -y "${pkgs[@]}"
      ;;
    brew)
      privilege::as_user brew install "${pkgs[@]}"
      ;;
    yay)
      cmd::require yay
      privilege::as_user yay -S --noconfirm --needed "${pkgs[@]}"
      ;;
    paru)
      cmd::require paru
      privilege::as_user paru -S --noconfirm --needed "${pkgs[@]}"
      ;;
    *)
      log::die "Unsupported backend for install: $backend"
      ;;
  esac
}

# 安装软件包。
# 参数:
#   $@: 软件包名称列表
# 行为:
#   根据当前包管理器自动选择安装命令。
pkg::install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -gt 0 ]] || return 0

  local backend
  backend="$(pkg::resolve_backend auto)"
  pkg::install_with_backend "$backend" "${pkgs[@]}"
}

