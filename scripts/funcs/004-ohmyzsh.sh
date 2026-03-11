#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# 外部插件列表：name|git_url
EXTERNAL_PLUGINS=(
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
  "fast-syntax-highlighting|https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
)

show_help() {
  cat <<'HELP_EOF'
用法: 004-ohmyzsh.sh [--dry-run]

说明:
  安装 oh-my-zsh 及 dotfiles 中使用的外部插件，并将 zsh 设为默认 Shell。
  步骤：
    1. 安装 zsh（若未安装）
    2. 克隆 oh-my-zsh（已存在则跳过）
    3. 安装各外部插件（单独检测，已存在则跳过）
    4. 将 zsh 设为目标用户默认 Shell（已是则跳过）

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
HELP_EOF
}

env_spec() {
  cat <<'ENV_EOF'
ENV_EOF
}

_target_home() {
  privilege::target_home
}

_omz_dir() {
  printf "%s/.oh-my-zsh\n" "$(_target_home)"
}

_custom_plugins_dir() {
  printf "%s/custom/plugins\n" "$(_omz_dir)"
}

_install_zsh() {
  if cmd::exists zsh; then
    log::info "[1/4] zsh 已安装，跳过"
    return 0
  fi
  log::info "[1/4] 安装 zsh"
  pkg::install_with_backend pacman zsh
}

_install_omz() {
  local omz_dir
  omz_dir="$(_omz_dir)"

  if [[ -d "$omz_dir" ]]; then
    log::info "[2/4] oh-my-zsh 已存在，跳过: $omz_dir"
    return 0
  fi

  log::info "[2/4] 克隆 oh-my-zsh 到 $omz_dir"
  privilege::as_user git clone --depth 1 "$OMZ_REPO" "$omz_dir"
}

_install_plugin() {
  local name="$1"
  local url="$2"
  local plugin_dir
  plugin_dir="$(_custom_plugins_dir)/$name"

  if [[ -d "$plugin_dir" ]]; then
    log::info "  插件 $name 已存在，跳过"
    return 0
  fi

  log::info "  安装插件 $name -> $plugin_dir"
  privilege::as_user git clone --depth 1 "$url" "$plugin_dir"
}

_install_plugins() {
  log::info "[3/4] 检测并安装外部插件"
  local entry name url
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    _install_plugin "$name" "$url"
  done
}

_set_default_shell() {
  local user shell_path
  user="$(privilege::target_user)"
  shell_path="$(command -v zsh 2>/dev/null || true)"

  if [[ -z "$shell_path" ]]; then
    log::warn "[4/4] zsh 未找到，跳过设置默认 Shell"
    return 0
  fi

  local current_shell
  current_shell="$(getent passwd "$user" | awk -F: '{print $7}')"

  # 用 realpath 消除 /bin → /usr/bin 等符号链接差异
  local real_current real_target
  real_current="$(realpath "$current_shell" 2>/dev/null || printf "%s\n" "$current_shell")"
  real_target="$(realpath "$shell_path" 2>/dev/null || printf "%s\n" "$shell_path")"

  if [[ "$real_current" == "$real_target" ]]; then
    log::info "[4/4] 默认 Shell 已是 zsh，跳过"
    return 0
  fi

  log::info "[4/4] 将 $user 的默认 Shell 设为 $shell_path（当前: $current_shell）"
  privilege::as_root chsh -s "$shell_path" "$user"
  log::ok "默认 Shell 已设置为 $shell_path"
}

run_impl() {
  _install_zsh
  _install_omz
  _install_plugins
  _set_default_shell
  log::ok "oh-my-zsh 安装完成！"
}

dry_run_impl() {
  local omz_dir plugin_dir entry name url user shell_path
  omz_dir="$(_omz_dir)"
  user="$(privilege::target_user)"
  shell_path="$(command -v zsh 2>/dev/null || echo '/usr/bin/zsh')"

  log::info "[DRY-RUN] 将执行以下步骤："

  if cmd::exists zsh; then
    log::info "[1/4] zsh 已安装，跳过"
  else
    log::info "[1/4] pacman -S --noconfirm --needed zsh"
  fi

  if [[ -d "$omz_dir" ]]; then
    log::info "[2/4] oh-my-zsh 已存在，跳过: $omz_dir"
  else
    log::info "[2/4] git clone --depth 1 $OMZ_REPO $omz_dir"
  fi

  log::info "[3/4] 检测外部插件："
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    plugin_dir="$(_custom_plugins_dir)/$name"
    if [[ -d "$plugin_dir" ]]; then
      log::info "  插件 $name 已存在，跳过"
    else
      log::info "  git clone --depth 1 $url $plugin_dir"
    fi
  done

  local current_shell real_current real_target
  current_shell="$(getent passwd "$user" | awk -F: '{print $7}')"
  real_current="$(realpath "$current_shell" 2>/dev/null || printf "%s\n" "$current_shell")"
  real_target="$(realpath "$shell_path" 2>/dev/null || printf "%s\n" "$shell_path")"
  if [[ "$real_current" == "$real_target" ]]; then
    log::info "[4/4] 默认 Shell 已是 zsh，跳过"
  else
    log::info "[4/4] chsh -s $shell_path $user（当前: $current_shell）"
  fi
}

cli::run_noargs_hooks "004-ohmyzsh.sh" show_help env_spec run_impl dry_run_impl "$@"
