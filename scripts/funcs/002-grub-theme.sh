#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

show_help() {
  cat <<'EOF'
用法: 002-grub-theme.sh [--dry-run]

说明:
  进行 GRUB 高级配置与主题设置（含本地主题、Minegrub 在线安装、菜单项写入、grub-mkconfig）。

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
EOF
}

env_spec() {
  cat <<EOF
GRUB_THEME_ALLOW_SELECT|false|是否允许用户交互选择主题（true/false）
GRUB_THEME_DEFAULT_CHOICE|2|禁用交互时使用的默认选项序号
GRUB_THEME_TIMEOUT|60|主题选择菜单超时时间（秒）
EOF
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if cli::is_dry_run; then
      log::warn "Dry-run mode: running without root privileges"
      return 0
    fi
    log::die "This script must be run as root"
  fi
}

section() {
  local step="$1"
  local title="$2"
  log::info "[$step] $title"
}

info_kv() {
  local key="$1"
  local value="$2"
  log::info "$key: $value"
}

set_grub_value() {
  local key="$1"
  local value="$2"
  local conf_file="/etc/default/grub"
  local escaped_value

  escaped_value="$(printf '%s\n' "$value" | sed 's,[/&],\\&,g')"

  if grep -q -E "^#\s*$key=" "$conf_file"; then
    cmd::run sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
  elif grep -q -E "^$key=" "$conf_file"; then
    cmd::run sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
  else
    log::info "Appending new key: $key"
    if cli::is_dry_run; then
      log::info "DRY RUN: append $key to $conf_file"
    else
      echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
  fi
}

manage_kernel_param() {
  local action="$1"
  local param="$2"
  local conf_file="/etc/default/grub"
  local line
  local params
  local param_key

  line="$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$conf_file" || true)"
  params="$(echo "$line" | sed -e 's/GRUB_CMDLINE_LINUX_DEFAULT=//' -e 's/"//g')"

  if [[ "$param" == *"="* ]]; then
    param_key="${param%%=*}"
  else
    param_key="$param"
  fi

  params="$(echo "$params" | sed -E "s/\\b${param_key}(=[^ ]*)?\\b//g")"

  if [[ "$action" == "add" ]]; then
    params="$params $param"
  fi

  params="$(echo "$params" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  cmd::run sed -i "s,^GRUB_CMDLINE_LINUX_DEFAULT=.*,GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"," "$conf_file"
}

cleanup_minegrub() {
  local minegrub_found=false

  if [[ -f "/etc/grub.d/05_twomenus" ]] || [[ -f "/boot/grub/mainmenu.cfg" ]]; then
    minegrub_found=true
    log::info "Found Minegrub artifacts. Cleaning up..."
    [[ -f "/etc/grub.d/05_twomenus" ]] && cmd::run rm -f /etc/grub.d/05_twomenus
    [[ -f "/boot/grub/mainmenu.cfg" ]] && cmd::run rm -f /boot/grub/mainmenu.cfg
  fi

  if command -v grub-editenv >/dev/null 2>&1; then
    if grub-editenv - list 2>/dev/null | grep -q "^config_file="; then
      minegrub_found=true
      log::info "Unsetting Minegrub GRUB environment variable..."
      cmd::run grub-editenv - unset config_file
    fi
  fi

  if [[ "$minegrub_found" == "true" ]]; then
    log::ok "Minegrub double-menu configuration completely removed"
  fi
}

run_workflow() {
  require_root

  if ! command -v grub-mkconfig >/dev/null 2>&1; then
    log::warn "GRUB (grub-mkconfig) not found on this system"
    log::info "Skipping GRUB theme installation"
    return 0
  fi

  section "Phase 7" "GRUB Customization & Theming"

  section "Step 1/7" "General GRUB Settings"

  if [[ -L "/boot/grub" ]]; then
    local link_target
    link_target="$(readlink -f "/boot/grub" || true)"

    if [[ "$link_target" == "/efi/grub" ]] || [[ "$link_target" == "/boot/efi/grub" ]]; then
      log::info "Detected /boot/grub linked to ESP ($link_target). Enabling GRUB savedefault..."
      set_grub_value "GRUB_DEFAULT" "saved"
      set_grub_value "GRUB_SAVEDEFAULT" "true"
    else
      log::info "Skipping savedefault: /boot/grub links to $link_target (not /efi/grub or /boot/efi/grub)"
    fi
  else
    log::info "Skipping savedefault: /boot/grub is not a symbolic link"
  fi

  log::info "Configuring kernel boot parameters for detailed logs and performance..."
  manage_kernel_param "remove" "quiet"
  manage_kernel_param "remove" "splash"
  manage_kernel_param "add" "loglevel=5"
  manage_kernel_param "add" "nowatchdog"

  local cpu_vendor
  cpu_vendor="$(LC_ALL=C lscpu 2>/dev/null | awk '/Vendor ID:/ {print $3}' || true)"
  if [[ "${cpu_vendor:-}" == "GenuineIntel" ]]; then
    log::info "Intel CPU detected. Disabling iTCO_wdt watchdog"
    manage_kernel_param "add" "modprobe.blacklist=iTCO_wdt"
  elif [[ "${cpu_vendor:-}" == "AuthenticAMD" ]]; then
    log::info "AMD CPU detected. Disabling sp5100_tco watchdog"
    manage_kernel_param "add" "modprobe.blacklist=sp5100_tco"
  fi

  log::ok "Kernel parameters updated"

  section "Step 2/7" "Sync Themes to System Directory"

  local source_base dest_dir
  source_base="$PROJECT_ROOT/grub-themes"
  dest_dir="/boot/grub/themes"

  [[ -d "$dest_dir" ]] || cmd::run mkdir -p "$dest_dir"

  if [[ -d "$source_base" ]]; then
    log::info "Syncing repository themes to $dest_dir..."

    local dir theme_basename
    for dir in "$source_base"/*; do
      if [[ -d "$dir" ]] && [[ -f "$dir/theme.txt" ]]; then
        theme_basename="$(basename "$dir")"
        if [[ ! -d "$dest_dir/$theme_basename" ]]; then
          log::info "Copying $theme_basename..."
          cmd::run cp -r "$dir" "$dest_dir/"
        fi
      fi
    done

    log::ok "Local themes synced"
  else
    log::warn "Directory 'grub-themes' not found in repo. Only online/existing themes available"
  fi

  log::info "Scanning $dest_dir for available themes..."
  local -a theme_paths=() theme_names=() found_dirs=()

  mapfile -t found_dirs < <(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d | sort 2>/dev/null || true)

  local dir_name
  for dir in "${found_dirs[@]:-}"; do
    if [[ -n "$dir" ]] && [[ -f "$dir/theme.txt" ]]; then
      dir_name="$(basename "$dir")"
      if [[ "$dir_name" != "minegrub" && "$dir_name" != "minegrub-world-selection" ]]; then
        theme_paths+=("$dir")
        theme_names+=("$dir_name")
      fi
    fi
  done

  if [[ ${#theme_names[@]} -eq 0 ]]; then
    log::info "No valid local theme folders found. Proceeding to online menu"
  fi

  section "Step 3/7" "Theme Selection"

  local install_minegrub=false
  local skip_theme=false

  local minegrub_option_name="Minegrub"
  local skip_option_name="No theme (Skip/Clear)"
  local minegrub_idx=$(( ${#theme_names[@]} + 1 ))
  local skip_idx=$(( ${#theme_names[@]} + 2 ))

  local allow_select_raw allow_select timeout_seconds default_choice_raw default_choice
  allow_select_raw="$(env::get env_spec GRUB_THEME_ALLOW_SELECT)"
  default_choice_raw="$(env::get env_spec GRUB_THEME_DEFAULT_CHOICE)"
  timeout_seconds="$(env::get env_spec GRUB_THEME_TIMEOUT)"

  allow_select="0"
  case "${allow_select_raw,,}" in
    1|true|yes|y|on)
      allow_select="1"
      ;;
    0|false|no|n|off|"")
      allow_select="0"
      ;;
    *)
      log::warn "Invalid GRUB_THEME_ALLOW_SELECT='$allow_select_raw', fallback to false"
      allow_select="0"
      ;;
  esac

  default_choice="2"
  if [[ "$default_choice_raw" =~ ^[0-9]+$ ]]; then
    default_choice="$default_choice_raw"
  else
    log::warn "Invalid GRUB_THEME_DEFAULT_CHOICE='$default_choice_raw', fallback to 2"
  fi

  if [[ "$default_choice" -lt 1 ]] || [[ "$default_choice" -gt "$skip_idx" ]]; then
    local fallback_choice="2"
    if [[ "$fallback_choice" -gt "$skip_idx" ]]; then
      fallback_choice="1"
    fi
    log::warn "GRUB_THEME_DEFAULT_CHOICE out of range (1-$skip_idx), fallback to $fallback_choice"
    default_choice="$fallback_choice"
  fi

  local title_text="Select GRUB Theme (${timeout_seconds}s Timeout)"
  local line_str="───────────────────────────────────────────────────────"

  printf "\n╭%s\n" "$line_str"
  printf "│   %s\n" "$title_text"
  printf "├%s\n" "$line_str"

  local i name display_name display_idx
  for i in "${!theme_names[@]}"; do
    name="${theme_names[$i]}"
    display_name="$(echo "$name" | sed -E 's/^[0-9]+//')"
    display_idx=$((i + 1))

    if [[ "$i" -eq 0 ]]; then
      printf "│ [%s] %s - Default\n" "$display_idx" "$display_name"
    else
      printf "│ [%s] %s\n" "$display_idx" "$display_name"
    fi
  done

  printf "│ [%s] %s\n" "$minegrub_idx" "$minegrub_option_name"
  printf "│ [%s] %s\n" "$skip_idx" "$skip_option_name"
  printf "╰%s\n\n" "$line_str"

  local user_choice
  if [[ "$allow_select" == "1" ]]; then
    echo -ne "   Enter choice [1-$skip_idx]: "
    read -t "$timeout_seconds" user_choice || true
    [[ -n "${user_choice:-}" ]] || echo ""
    user_choice="${user_choice:-$default_choice}"
  else
    user_choice="$default_choice"
    log::info "Selection disabled by GRUB_THEME_ALLOW_SELECT=false, using default choice: $user_choice"
  fi

  if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || [[ "$user_choice" -lt 1 ]] || [[ "$user_choice" -gt "$skip_idx" ]]; then
    log::info "Invalid choice or timeout. Defaulting to configured choice: $default_choice"
    user_choice="$default_choice"
  fi

  local selected_index theme_path theme_name
  if [[ "$user_choice" -eq "$skip_idx" ]]; then
    skip_theme=true
    info_kv "Selected" "None (Clear Theme)"
  elif [[ "$user_choice" -eq "$minegrub_idx" ]]; then
    install_minegrub=true
    info_kv "Selected" "Minegrub (Online Repository)"
  else
    selected_index=$((user_choice - 1))
    if [[ -n "${theme_names[$selected_index]:-}" ]]; then
      theme_path="${theme_paths[$selected_index]}/theme.txt"
      theme_name="${theme_names[$selected_index]}"
      info_kv "Selected" "Local: $theme_name"
    else
      log::warn "Local theme array empty but selected. Defaulting to Minegrub"
      install_minegrub=true
    fi
  fi

  section "Step 4/7" "Theme Configuration"

  local grub_conf="/etc/default/grub"
  if [[ "$skip_theme" == "true" ]]; then
    log::info "Clearing GRUB theme configuration..."
    cleanup_minegrub

    if [[ -f "$grub_conf" ]]; then
      if grep -q "^GRUB_THEME=" "$grub_conf"; then
        cmd::run sed -i 's|^GRUB_THEME=|#GRUB_THEME=|' "$grub_conf"
        log::ok "Disabled existing GRUB_THEME in configuration"
      else
        log::info "No active GRUB_THEME found to disable"
      fi
    fi
  elif [[ "$install_minegrub" == "true" ]]; then
    log::info "Preparing to install Minegrub theme..."

    if ! command -v git >/dev/null 2>&1; then
      log::error "'git' is required to clone Minegrub but was not found. Skipping"
    else
      local temp_mg_dir
      temp_mg_dir="$(mktemp -d -t minegrub_install_XXXXXX)"

      log::info "Cloning Lxtharia/double-minegrub-menu..."
      if cmd::run git clone --depth 1 "https://github.com/Lxtharia/double-minegrub-menu.git" "$temp_mg_dir"; then
        if [[ -f "$temp_mg_dir/install.sh" ]]; then
          log::info "Executing Minegrub install.sh..."
          if cli::is_dry_run; then
            log::info "DRY RUN: chmod +x $temp_mg_dir/install.sh && $temp_mg_dir/install.sh"
          else
            (
              cd "$temp_mg_dir" || exit 1
              chmod +x install.sh
              ./install.sh
            )
            if [[ $? -eq 0 ]]; then
              log::ok "Minegrub theme successfully installed via its script"
            else
              log::error "Minegrub install.sh exited with an error"
            fi
          fi
        else
          log::error "install.sh not found in the cloned repository"
        fi
      else
        log::error "Failed to clone Minegrub repository"
      fi

      [[ -n "$temp_mg_dir" ]] && cmd::run rm -rf "$temp_mg_dir"
    fi
  else
    cleanup_minegrub

    if [[ -f "$grub_conf" ]]; then
      if grep -q "^GRUB_THEME=" "$grub_conf"; then
        cmd::run sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$theme_path\"|" "$grub_conf"
      elif grep -q "^#GRUB_THEME=" "$grub_conf"; then
        cmd::run sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$theme_path\"|" "$grub_conf"
      else
        if cli::is_dry_run; then
          log::info "DRY RUN: append GRUB_THEME to $grub_conf"
        else
          echo "GRUB_THEME=\"$theme_path\"" >> "$grub_conf"
        fi
      fi

      if grep -q '^GRUB_TERMINAL_OUTPUT="console"' "$grub_conf"; then
        cmd::run sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$grub_conf"
      fi

      if ! grep -q "^GRUB_GFXMODE=" "$grub_conf"; then
        if cli::is_dry_run; then
          log::info "DRY RUN: append GRUB_GFXMODE=auto to $grub_conf"
        else
          echo 'GRUB_GFXMODE=auto' >> "$grub_conf"
        fi
      fi

      log::ok "Configured GRUB to use theme: ${theme_name:-unknown}"
    else
      log::die "$grub_conf not found"
    fi
  fi

  section "Step 5/7" "Menu Entries"
  log::info "Adding Power Options to GRUB menu..."

  cmd::run cp /etc/grub.d/40_custom /etc/grub.d/99_custom
  if cli::is_dry_run; then
    log::info 'DRY RUN: append menuentry "Reboot" {reboot} to /etc/grub.d/99_custom'
    log::info 'DRY RUN: append menuentry "Shutdown" {halt} to /etc/grub.d/99_custom'
  else
    echo 'menuentry "Reboot" {reboot}' >> /etc/grub.d/99_custom
    echo 'menuentry "Shutdown" {halt}' >> /etc/grub.d/99_custom
  fi

  log::ok "Added grub menuentry 99-shutdown"

  section "Step 7/7" "Apply Changes"
  log::info "Generating new GRUB configuration..."

  if cmd::run grub-mkconfig -o /boot/grub/grub.cfg; then
    log::ok "GRUB updated successfully"
  else
    log::error "Failed to update GRUB"
    log::warn "You may need to run 'grub-mkconfig' manually"
  fi

  log::ok "Module 07 completed"
}

run_impl() {
  run_workflow
}

dry_run_impl() {
  run_workflow
}

cli::run_noargs_hooks "002-grub-theme.sh" show_help env_spec run_impl dry_run_impl "$@"
