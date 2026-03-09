#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

show_help() {
  cat <<'EOF'
用法: 001-install-packages.sh [--dry-run]

说明:
  读取 manifests/packages/*.txt 并安装其中的软件包。

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
EOF
}

env_spec() {
  cat <<EOF
PKG_MANIFEST_DIR|${PROJECT_ROOT}/manifests/packages|软件包清单目录
EOF
}

run_impl() {
  local package_dir
  package_dir="$(env::get env_spec PKG_MANIFEST_DIR)"
  [[ -d "$package_dir" ]] || {
    log::warn "Package manifest directory not found: $package_dir"
    return 0
  }

  pkg::detect_manager

  local manifest_files=()
  while IFS= read -r file; do
    manifest_files+=("$file")
  done < <(find "$package_dir" -mindepth 1 -maxdepth 1 -type f -name '*.txt' | sort)

  [[ ${#manifest_files[@]} -gt 0 ]] || {
    log::warn "No package manifest files found in $package_dir"
    return 0
  }

  local -a packages=()
  collect_packages_from_manifests manifest_files packages

  [[ ${#packages[@]} -gt 0 ]] || {
    log::warn "No valid package names found in manifests"
    return 0
  }

  log::info "Installing packages from manifests: ${packages[*]}"
  pkg::install "${packages[@]}"
  log::ok "Package installation completed"
}

dry_run_impl() {
  local package_dir
  package_dir="$(env::get env_spec PKG_MANIFEST_DIR)"
  [[ -d "$package_dir" ]] || {
    log::warn "Package manifest directory not found: $package_dir"
    return 0
  }

  pkg::detect_manager

  local manifest_files=()
  while IFS= read -r file; do
    manifest_files+=("$file")
  done < <(find "$package_dir" -mindepth 1 -maxdepth 1 -type f -name '*.txt' | sort)

  [[ ${#manifest_files[@]} -gt 0 ]] || {
    log::warn "No package manifest files found in $package_dir"
    return 0
  }

  local -a packages=()
  collect_packages_from_manifests manifest_files packages

  [[ ${#packages[@]} -gt 0 ]] || {
    log::warn "No valid package names found in manifests"
    return 0
  }

  log::info "[DRY-RUN] Installing packages from manifests: ${packages[*]}"
  pkg::install "${packages[@]}"
  log::ok "[DRY-RUN] Package installation preview completed"
}

collect_packages_from_manifests() {
  local -n manifest_files_ref="$1"
  local -n out_packages_ref="$2"

  out_packages_ref=()

  local line
  local file
  for file in "${manifest_files_ref[@]}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs)"
      [[ -n "$line" ]] || continue
      out_packages_ref+=("$line")
    done < "$file"
  done
}

cli::run_noargs_hooks "001-install-packages.sh" show_help env_spec run_impl dry_run_impl "$@"
