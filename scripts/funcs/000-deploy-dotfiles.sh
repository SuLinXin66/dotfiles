#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

show_help() {
  cat <<'EOF'
用法: 000-deploy-dotfiles.sh [--dry-run]

说明:
  使用 stow 将 PROJECT_ROOT/dotfiles 直接映射到目标用户 HOME。

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
EOF
}

env_spec() {
  cat <<EOF
DOTFILES_BACKUP_ENABLE|1|是否启用部署前备份（1=启用，0=关闭）
DOTFILES_BACKUP_DIR|${HOME}/.dotfiles-backups|备份根目录
DOTFILES_BACKUP_SUFFIX|.bak|备份文件后缀
DOTFILES_STOW_IGNORE|\\.gitkeep$|stow 忽略正则（默认忽略 .gitkeep）
EOF
}

ensure_stow() {
  if cmd::exists stow; then
    return 0
  fi

  log::warn "stow 未安装，准备自动安装"
  pkg::install stow

  if ! cli::is_dry_run && ! cmd::exists stow; then
    log::die "stow 安装失败，请手动检查包管理器输出"
  fi
}

collect_target_sources() {
  local dotfiles_root="$1"
  local -n out_sources_ref="$2"

  out_sources_ref=()

  local rel src
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$dotfiles_root/$rel"
    out_sources_ref[$rel]="$src"
  done < <(find "$dotfiles_root" \( -type f -o -type l \) ! -name '.gitkeep' -printf '%P\n' | sort)
}

backup_targets_run() {
  local deploy_home="$1"
  local backup_root="$2"
  local backup_suffix="$3"
  local -n sources_ref="$4"

  local ts
  ts="$(date +%Y%m%d_%H%M%S)"

  local rel target src resolved_target resolved_src backup_path
  for rel in "${!sources_ref[@]}"; do
    target="$deploy_home/$rel"
    src="${sources_ref[$rel]}"

    [[ -e "$target" || -L "$target" ]] || continue

    if [[ -L "$target" ]]; then
      resolved_target="$(readlink -f "$target" 2>/dev/null || true)"
      resolved_src="$(readlink -f "$src" 2>/dev/null || true)"
      if [[ -n "$resolved_target" && -n "$resolved_src" && "$resolved_target" == "$resolved_src" ]]; then
        continue
      fi
    fi

    backup_path="$backup_root/$ts/$rel"
    backup_path="${backup_path}${backup_suffix}"

    cmd::run mkdir -p "$(dirname "$backup_path")"
    cmd::run mv "$target" "$backup_path"
    log::info "Backup created: $target -> $backup_path"
  done
}

backup_targets_dry() {
  local deploy_home="$1"
  local backup_root="$2"
  local backup_suffix="$3"
  local -n sources_ref="$4"

  local ts
  ts="$(date +%Y%m%d_%H%M%S)"

  local rel target src resolved_target resolved_src backup_path
  for rel in "${!sources_ref[@]}"; do
    target="$deploy_home/$rel"
    src="${sources_ref[$rel]}"

    [[ -e "$target" || -L "$target" ]] || continue

    if [[ -L "$target" ]]; then
      resolved_target="$(readlink -f "$target" 2>/dev/null || true)"
      resolved_src="$(readlink -f "$src" 2>/dev/null || true)"
      if [[ -n "$resolved_target" && -n "$resolved_src" && "$resolved_target" == "$resolved_src" ]]; then
        continue
      fi
    fi

    backup_path="$backup_root/$ts/$rel"
    backup_path="${backup_path}${backup_suffix}"

    cmd::run mkdir -p "$(dirname "$backup_path")"
    cmd::run mv "$target" "$backup_path"
    log::info "[DRY-RUN] Backup preview: $target -> $backup_path"
  done
}

prepare_deploy_context() {
  local out_dotfiles_root_name="$1"
  local out_user_name="$2"
  local out_home_name="$3"

  local -n out_dotfiles_root_ref="$out_dotfiles_root_name"
  local -n out_user_ref="$out_user_name"
  local -n out_home_ref="$out_home_name"

  out_dotfiles_root_ref="$PROJECT_ROOT/dotfiles"
  [[ -d "$out_dotfiles_root_ref" ]] || log::die "dotfiles directory not found: $out_dotfiles_root_ref"

  out_user_ref="$(privilege::target_user)"
  out_home_ref="$(privilege::target_home)"
}

run_impl() {
  ensure_stow

  local dotfiles_root deploy_user deploy_home
  prepare_deploy_context dotfiles_root deploy_user deploy_home
  local -A sources_by_rel=()
  collect_target_sources "$dotfiles_root" sources_by_rel

  local backup_enable backup_dir backup_suffix stow_ignore
  backup_enable="$(env::get env_spec DOTFILES_BACKUP_ENABLE)"
  backup_dir="$(env::get env_spec DOTFILES_BACKUP_DIR)"
  backup_suffix="$(env::get env_spec DOTFILES_BACKUP_SUFFIX)"
  stow_ignore="$(env::get env_spec DOTFILES_STOW_IGNORE)"

  [[ ${#sources_by_rel[@]} -gt 0 ]] || {
    log::warn "No managed files found in $dotfiles_root"
    return 0
  }

  log::info "Deploy target user: $deploy_user"
  log::info "Deploy target home: $deploy_home"

  if [[ "$backup_enable" == "1" ]]; then
    backup_targets_run "$deploy_home" "$backup_dir" "$backup_suffix" sources_by_rel
  else
    log::warn "Backup disabled by DOTFILES_BACKUP_ENABLE=$backup_enable"
  fi

  log::info "Stowing package: dotfiles"
  privilege::as_user stow -d "$PROJECT_ROOT" -t "$deploy_home" --ignore="$stow_ignore" dotfiles

  log::ok "Dotfiles deploy completed"
}

dry_run_impl() {
  ensure_stow

  local dotfiles_root deploy_user deploy_home
  prepare_deploy_context dotfiles_root deploy_user deploy_home
  local -A sources_by_rel=()
  collect_target_sources "$dotfiles_root" sources_by_rel

  local backup_enable backup_dir backup_suffix stow_ignore
  backup_enable="$(env::get env_spec DOTFILES_BACKUP_ENABLE)"
  backup_dir="$(env::get env_spec DOTFILES_BACKUP_DIR)"
  backup_suffix="$(env::get env_spec DOTFILES_BACKUP_SUFFIX)"
  stow_ignore="$(env::get env_spec DOTFILES_STOW_IGNORE)"

  [[ ${#sources_by_rel[@]} -gt 0 ]] || {
    log::warn "No managed files found in $dotfiles_root"
    return 0
  }

  log::info "[DRY-RUN] Deploy target user: $deploy_user"
  log::info "[DRY-RUN] Deploy target home: $deploy_home"

  if [[ "$backup_enable" == "1" ]]; then
    backup_targets_dry "$deploy_home" "$backup_dir" "$backup_suffix" sources_by_rel
  else
    log::warn "[DRY-RUN] Backup disabled by DOTFILES_BACKUP_ENABLE=$backup_enable"
  fi

  log::info "[DRY-RUN] Stowing package: dotfiles"
  privilege::as_user stow -d "$PROJECT_ROOT" -t "$deploy_home" --ignore="$stow_ignore" dotfiles

  log::ok "[DRY-RUN] Dotfiles deploy preview completed"
}

cli::run_noargs_hooks "000-deploy-dotfiles.sh" show_help env_spec run_impl dry_run_impl "$@"
