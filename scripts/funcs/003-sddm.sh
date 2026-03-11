#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

THEME_REPO="https://github.com/keyitdev/sddm-astronaut-theme.git"
THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
FONTS_SRC="$THEME_DIR/Fonts"
FONTS_DST="/usr/share/fonts"
SDDM_CONF="/etc/sddm.conf"
SDDM_CONF_D="/etc/sddm.conf.d"
VIRTUALKBD_CONF="$SDDM_CONF_D/virtualkbd.conf"

SDDM_PKGS=(
  sddm
  qt6-svg
  qt6-virtualkeyboard
  qt6-multimedia-ffmpeg
)

show_help() {
  cat <<'HELP_EOF'
用法: 003-sddm.sh [--dry-run]

说明:
  安装 sddm-astronaut-theme SDDM 主题。
  步骤：安装依赖 → 克隆主题仓库 → 复制字体 → 写入 sddm.conf → 配置虚拟键盘。

环境变量:
  SDDM_THEME_VARIANT   要启用的主题配置文件名（不含路径和 .conf 后缀），默认 astronaut

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
HELP_EOF
}

env_spec() {
  cat <<'ENV_EOF'
SDDM_THEME_VARIANT|hyprland_kath|启用的主题配置文件名（不含路径和 .conf 后缀，如 astronaut / black_hole / japanese_aesthetic / hyprland_kath）
ENV_EOF
}

_install_deps() {
  log::info "[1/5] 安装依赖包: ${SDDM_PKGS[*]}"
  pkg::install_with_backend pacman "${SDDM_PKGS[@]}"
}

_clone_theme() {
  log::info "[2/5] 克隆主题仓库到 $THEME_DIR"
  if [[ -d "$THEME_DIR" ]]; then
    log::warn "主题目录已存在，跳过克隆: $THEME_DIR"
  else
    privilege::as_root git clone -b master --depth 1 "$THEME_REPO" "$THEME_DIR"
  fi
}

_copy_fonts() {
  log::info "[3/5] 复制字体到 $FONTS_DST"
  privilege::as_root cp -r "$FONTS_SRC/." "$FONTS_DST/"
}

_write_sddm_conf() {
  log::info "[4/5] 写入 $SDDM_CONF"
  local content="[Theme]
Current=sddm-astronaut-theme"
  if cli::is_dry_run; then
    log::info "DRY RUN: printf '%s\\n' '[Theme]\\nCurrent=sddm-astronaut-theme' | sudo tee $SDDM_CONF"
  else
    printf '%s\n' "$content" | privilege::as_root tee "$SDDM_CONF" >/dev/null
  fi
}

_write_virtualkbd_conf() {
  log::info "[5/5] 写入虚拟键盘配置 $VIRTUALKBD_CONF"
  local content="[General]
InputMethod=qtvirtualkeyboard"
  if cli::is_dry_run; then
    log::info "DRY RUN: mkdir -p $SDDM_CONF_D && printf '%s\\n' '[General]\\nInputMethod=qtvirtualkeyboard' | sudo tee $VIRTUALKBD_CONF"
    return 0
  fi
  privilege::as_root mkdir -p "$SDDM_CONF_D"
  printf '%s\n' "$content" | privilege::as_root tee "$VIRTUALKBD_CONF" >/dev/null
}

_set_theme_variant() {
  local variant="${SDDM_THEME_VARIANT:-hyprland_kath}"
  local metadata="$THEME_DIR/metadata.desktop"
  log::info "设置主题变体: $variant"
  if cli::is_dry_run; then
    log::info "DRY RUN: sed -i 's|^ConfigFile=.*|ConfigFile=Themes/$variant.conf|' $metadata"
    return 0
  fi
  privilege::as_root sed -i "s|^ConfigFile=.*|ConfigFile=Themes/$variant.conf|" "$metadata"
  log::ok "主题变体已设置为: $variant"
}

run_impl() {
  _install_deps
  _clone_theme
  _copy_fonts
  _write_sddm_conf
  _write_virtualkbd_conf
  _set_theme_variant
  log::ok "sddm-astronaut-theme 安装完成！可运行以下命令预览效果："
  log::ok "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR"
}

dry_run_impl() {
  log::info "[DRY-RUN] 将执行以下步骤："
  log::info "[1/5] pacman -S --noconfirm --needed ${SDDM_PKGS[*]}"
  log::info "[2/5] git clone -b master --depth 1 $THEME_REPO $THEME_DIR"
  log::info "[3/5] cp -r $FONTS_SRC/. $FONTS_DST/"
  log::info "[4/5] 写入 $SDDM_CONF: [Theme] Current=sddm-astronaut-theme"
  log::info "[5/5] 写入 $VIRTUALKBD_CONF: [General] InputMethod=qtvirtualkeyboard"
  log::info "[+]   设置主题变体: ${SDDM_THEME_VARIANT:-hyprland_kath}"
}

cli::run_noargs_hooks "003-sddm.sh" show_help env_spec run_impl dry_run_impl "$@"
