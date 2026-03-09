#!/usr/bin/env bash

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

# 安装软件包。
# 参数:
#   $@: 软件包名称列表
# 行为:
#   根据当前包管理器自动选择安装命令。
pkg::install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -gt 0 ]] || return 0

  pkg::detect_manager

  case "$PKG_MANAGER" in
    pacman)
      privilege::as_root pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    apt)
      privilege::as_root apt-get update -y
      privilege::as_root apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      privilege::as_root dnf install -y "${pkgs[@]}"
      ;;
    brew)
      privilege::as_user brew install "${pkgs[@]}"
      ;;
    *)
      log::die "Unsupported package manager: $PKG_MANAGER"
      ;;
  esac
}

