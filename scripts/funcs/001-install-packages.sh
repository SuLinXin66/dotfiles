#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

readonly SUPPORTED_OS_LIST="all/linux/arch/ubuntu/debian/fedora/manjaro/endeavouros/pop/opensuse/nixos/macos"
readonly SUPPORTED_PKG_MANAGER_LIST="auto/pacman/apt/dnf/brew/aur/yay/paru"

show_help() {
  cat <<'EOF'
用法: 001-install-packages.sh [--dry-run]

说明:
  读取 manifests/packages/*.txt 并安装其中的软件包。
  支持清单格式: package|os|pkg_manager|desc
  其中 os/pkg_manager/desc 均可省略。
  如果字段内需要使用竖线，请写成 \|。
  os 支持: all/linux/arch/ubuntu/debian/fedora/manjaro/endeavouros/pop/opensuse/nixos/macos
  pkg_manager 支持: auto/pacman/apt/dnf/brew/aur/yay/paru
  顶级说明使用: @desc: 说明文本
  可通过 PKG_OS_OVERRIDE 强制系统过滤。

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
EOF
}

env_spec() {
  cat <<EOF
PKG_MANIFEST_DIR|${PROJECT_ROOT}/manifests/packages|软件包清单目录
PKG_INSTALL_LOG_ENABLE|0|是否打印安装前清单日志（1=开启，0=关闭）
PKG_OS_OVERRIDE||强制系统过滤（如 arch/ubuntu/all），为空则按当前系统自动匹配
PKG_TARGET_OVERRIDE||兼容旧变量名（等价于 PKG_OS_OVERRIDE）
EOF
}

run_impl() {
  local package_dir
  package_dir="$(env::get env_spec PKG_MANIFEST_DIR)"
  local install_log_enable
  install_log_enable="$(env::get env_spec PKG_INSTALL_LOG_ENABLE)"
  local os_override
  os_override="$(env::get env_spec PKG_OS_OVERRIDE)"
  local target_override_compat
  target_override_compat="$(env::get env_spec PKG_TARGET_OVERRIDE)"
  [[ -n "$os_override" ]] || os_override="$target_override_compat"
  [[ -z "$os_override" ]] || validate_os_value "$os_override" "env:PKG_OS_OVERRIDE"
  [[ -d "$package_dir" ]] || {
    log::warn "Package manifest directory not found: $package_dir"
    return 0
  }

  local manifest_files=()
  while IFS= read -r file; do
    manifest_files+=("$file")
  done < <(find "$package_dir" -mindepth 1 -maxdepth 1 -type f -name '*.txt' | sort)

  [[ ${#manifest_files[@]} -gt 0 ]] || {
    log::warn "No package manifest files found in $package_dir"
    return 0
  }

  local -a entries=()
  parse_manifest_entries manifest_files entries

  [[ ${#entries[@]} -gt 0 ]] || {
    log::warn "No valid package entries found in manifests"
    return 0
  }

  local -A manager_pkgs=()
  local -a manager_order=()
  group_entries_by_manager entries manager_pkgs manager_order "$os_override"

  if [[ "$install_log_enable" == "1" ]]; then
    print_install_plan entries "" "$os_override"
  fi

  local pkg_manager
  local pkg_line
  local -a pkgs=()
  for pkg_manager in "${manager_order[@]}"; do
    pkg_line="${manager_pkgs[$pkg_manager]}"
    read -r -a pkgs <<< "$pkg_line"
    [[ ${#pkgs[@]} -gt 0 ]] || continue

    log::info "Installing by pkg_manager [$pkg_manager]: ${pkgs[*]}"
    pkg::install_with_backend "$pkg_manager" "${pkgs[@]}"
  done

  log::ok "Package installation completed"
}

dry_run_impl() {
  local package_dir
  package_dir="$(env::get env_spec PKG_MANIFEST_DIR)"
  local install_log_enable
  install_log_enable="$(env::get env_spec PKG_INSTALL_LOG_ENABLE)"
  local os_override
  os_override="$(env::get env_spec PKG_OS_OVERRIDE)"
  local target_override_compat
  target_override_compat="$(env::get env_spec PKG_TARGET_OVERRIDE)"
  [[ -n "$os_override" ]] || os_override="$target_override_compat"
  [[ -z "$os_override" ]] || validate_os_value "$os_override" "env:PKG_OS_OVERRIDE"
  [[ -d "$package_dir" ]] || {
    log::warn "Package manifest directory not found: $package_dir"
    return 0
  }

  local manifest_files=()
  while IFS= read -r file; do
    manifest_files+=("$file")
  done < <(find "$package_dir" -mindepth 1 -maxdepth 1 -type f -name '*.txt' | sort)

  [[ ${#manifest_files[@]} -gt 0 ]] || {
    log::warn "No package manifest files found in $package_dir"
    return 0
  }

  local -a entries=()
  parse_manifest_entries manifest_files entries

  [[ ${#entries[@]} -gt 0 ]] || {
    log::warn "No valid package entries found in manifests"
    return 0
  }

  local -A manager_pkgs=()
  local -a manager_order=()
  group_entries_by_manager entries manager_pkgs manager_order "$os_override"

  if [[ "$install_log_enable" == "1" ]]; then
    print_install_plan entries "[DRY-RUN] " "$os_override"
  fi

  local pkg_manager
  local pkg_line
  local -a pkgs=()
  for pkg_manager in "${manager_order[@]}"; do
    pkg_line="${manager_pkgs[$pkg_manager]}"
    read -r -a pkgs <<< "$pkg_line"
    [[ ${#pkgs[@]} -gt 0 ]] || continue

    log::info "[DRY-RUN] Installing by pkg_manager [$pkg_manager]: ${pkgs[*]}"
    pkg::install_with_backend "$pkg_manager" "${pkgs[@]}"
  done

  log::ok "[DRY-RUN] Package installation preview completed"
}

parse_manifest_entries() {
  local -n manifest_files_ref="$1"
  local -n out_entries_ref="$2"

  out_entries_ref=()

  local file line line_no
  local file_base manifest_desc
  local pkg os_target pkg_manager desc
  local -a fields=()

  for file in "${manifest_files_ref[@]}"; do
    file_base="$(basename "$file")"
    manifest_desc="$file_base"
    line_no=0

    while IFS= read -r line || [[ -n "$line" ]]; do
      line_no=$((line_no + 1))
      line="$(trim_space "$line")"
      [[ -n "$line" ]] || continue

      if [[ "$line" == \#* ]]; then
        continue
      fi

      if [[ "$line" =~ ^@desc:[[:space:]]*(.*)$ ]]; then
        manifest_desc="$(trim_space "${BASH_REMATCH[1]}")"
        continue
      fi

      pkg=""
      os_target="all"
      pkg_manager="auto"
      desc=""

      split_escaped_pipe "$line" fields

      if (( ${#fields[@]} > 4 )); then
        log::die "Invalid manifest entry (too many fields, use \\| for literal pipe): ${file}:${line_no}"
      fi

      pkg="$(trim_space "${fields[0]:-}")"
      os_target="$(trim_space "${fields[1]:-all}")"
      pkg_manager="$(trim_space "${fields[2]:-auto}")"
      desc="$(trim_space "${fields[3]:-}")"

      [[ -n "$pkg" ]] || {
        log::die "Invalid manifest entry (empty package): ${file}:${line_no}"
      }

      validate_os_value "$os_target" "${file}:${line_no}"
      validate_pkg_manager_value "$pkg_manager" "${file}:${line_no}"

      os_target="${os_target,,}"
      pkg_manager="${pkg_manager,,}"

      out_entries_ref+=("$(join_row "$file_base" "$manifest_desc" "$pkg" "$os_target" "$pkg_manager" "$desc")")
    done < "$file"
  done
}

entry_match_target() {
  local target="$1"
  local override="${2:-}"
  local os_id
  os_id="$(os::id)"

  if [[ -n "$override" ]]; then
    [[ "$target" == "all" || "$target" == "$override" ]]
    return $?
  fi

  case "$target" in
    all)
      return 0
      ;;
    linux)
      os::is_linux
      return $?
      ;;
    "$os_id")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_os_value() {
  local os_value="$1"
  local where="$2"

  case "${os_value,,}" in
    all|linux|arch|ubuntu|debian|fedora|manjaro|endeavouros|pop|opensuse|nixos|macos)
      return 0
      ;;
    *)
      log::die "Unsupported os in manifest (${where}): ${os_value}; allowed=${SUPPORTED_OS_LIST}"
      ;;
  esac
}

validate_pkg_manager_value() {
  local manager_value="$1"
  local where="$2"

  case "${manager_value,,}" in
    auto|pacman|apt|dnf|brew|aur|yay|paru)
      return 0
      ;;
    *)
      log::die "Unsupported pkg_manager in manifest (${where}): ${manager_value}; allowed=${SUPPORTED_PKG_MANAGER_LIST}"
      ;;
  esac
}

group_entries_by_manager() {
  local -n entries_ref="$1"
  local -n out_manager_pkgs_ref="$2"
  local -n out_manager_order_ref="$3"
  local target_override="${4:-}"

  out_manager_pkgs_ref=()
  out_manager_order_ref=()

  local row file_base manifest_desc pkg target pkg_manager desc resolved_manager
  for row in "${entries_ref[@]}"; do
    split_row "$row" file_base manifest_desc pkg target pkg_manager desc

    entry_match_target "$target" "$target_override" || continue

    resolved_manager="$(pkg::resolve_backend "$pkg_manager")"

    if [[ -z "${out_manager_pkgs_ref[$resolved_manager]:-}" ]]; then
      out_manager_order_ref+=("$resolved_manager")
      out_manager_pkgs_ref[$resolved_manager]="$pkg"
    else
      out_manager_pkgs_ref[$resolved_manager]="${out_manager_pkgs_ref[$resolved_manager]} $pkg"
    fi
  done
}

print_install_plan() {
  local -n entries_ref="$1"
  local prefix="$2"
  local target_override="${3:-}"

  local row file_base manifest_desc pkg target pkg_manager desc resolved_manager
  for row in "${entries_ref[@]}"; do
    split_row "$row" file_base manifest_desc pkg target pkg_manager desc

    entry_match_target "$target" "$target_override" || continue
    resolved_manager="$(pkg::resolve_backend "$pkg_manager")"

    if [[ -n "$desc" ]]; then
      log::info "${prefix}[PLAN] ${file_base} (${manifest_desc}) -> ${pkg} | pkg_manager=${resolved_manager} | ${desc}"
    else
      log::info "${prefix}[PLAN] ${file_base} (${manifest_desc}) -> ${pkg} | pkg_manager=${resolved_manager}"
    fi
  done
}

trim_space() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

split_escaped_pipe() {
  local input="$1"
  local -n out_ref="$2"

  out_ref=()
  local current=""
  local escaped=0
  local i ch

  for ((i = 0; i < ${#input}; i++)); do
    ch="${input:i:1}"

    if (( escaped )); then
      if [[ "$ch" == '|' || "$ch" == "\\" ]]; then
        current+="$ch"
      else
        current+="\\$ch"
      fi
      escaped=0
      continue
    fi

    if [[ "$ch" == "\\" ]]; then
      escaped=1
      continue
    fi

    if [[ "$ch" == '|' ]]; then
      out_ref+=("$current")
      current=""
      continue
    fi

    current+="$ch"
  done

  if (( escaped )); then
    current+="\\"
  fi

  out_ref+=("$current")
}

join_row() {
  local sep=$'\x1f'
  printf '%s' "$1"
  shift
  local v
  for v in "$@"; do
    printf '%s%s' "$sep" "$v"
  done
  printf '\n'
}

split_row() {
  local row="$1"
  local -n out1="$2"
  local -n out2="$3"
  local -n out3="$4"
  local -n out4="$5"
  local -n out5="$6"
  local -n out6="$7"

  local sep=$'\x1f'
  local -a parts=()
  IFS="$sep" read -r -a parts <<< "$row"

  out1="${parts[0]:-}"
  out2="${parts[1]:-}"
  out3="${parts[2]:-}"
  out4="${parts[3]:-}"
  out5="${parts[4]:-}"
  out6="${parts[5]:-}"
}

cli::run_noargs_hooks "001-install-packages.sh" show_help env_spec run_impl dry_run_impl "$@"
