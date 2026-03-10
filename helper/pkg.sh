#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="$PROJECT_ROOT/manifests/packages"

readonly SUPPORTED_OS_LIST="all/linux/arch/ubuntu/debian/fedora/manjaro/endeavouros/pop/opensuse/nixos/macos"
readonly SUPPORTED_PKG_MANAGER_LIST="auto/pacman/apt/dnf/brew/aur/yay/paru"

show_help() {
  cat <<'EOF'
用法:
  ./helper/pkg.sh --manifest <name-or-file> [--title <text>] [--os <os>] [--pkg-manager <manager>] [--stdin] [<pkg[|desc]> ...]

说明:
  1) 使用 --manifest 指定清单。
     - 如果文件已存在: 追加
     - 如果文件不存在: 自动创建新的编号清单（NNN-name.txt）
  2) 每个条目使用 pkg[|desc]，一次可追加多条。
  3) 追加前会检查清单内是否已存在同名包，存在则报错并终止。

参数:
  --manifest   清单标识（文件名/绝对路径/逻辑名）
  --title      写入清单头部 @desc: 文本（仅在自动新建时生效）
  --os         清单中的 os 字段，默认 all
  --pkg-manager 清单中的 pkg_manager 字段，默认 auto
  --manager    等价于 --pkg-manager
  --stdin      从标准输入读取批量条目（每行一个 pkg[|desc]）
  -h, --help   显示帮助

字段说明:
  清单行格式固定为: package|os|pkg_manager|desc
  os 支持: all/linux/arch/ubuntu/debian/fedora/manjaro/endeavouros/pop/opensuse/nixos/macos
  pkg_manager 支持: auto/pacman/apt/dnf/brew/aur/yay/paru
  其中 aur 会在安装时自动优先使用 paru，其次 yay。
  package 仅允许: 字母/数字/._:+-@
  若 package 或 desc 中包含竖线，请使用 \| 转义。
  若包含反斜杠，请使用 \\ 表示字面量反斜杠。

示例:
  ./helper/pkg.sh --manifest cli-base --title "基础命令行工具" --os all --pkg-manager auto \
    "git|Git 版本管理" "curl|命令行下载"

  ./helper/pkg.sh --manifest base.txt --os arch --pkg-manager pacman \
    "wl-clipboard|Wayland 剪贴板" "fd|更快的 find"

  printf '%s\n' "eza|现代 ls" "bat|语法高亮 cat" | \
    ./helper/pkg.sh --manifest base.txt --os all --pkg-manager auto --stdin
EOF
}

die() {
  printf "[X] %s\n" "$*" >&2
  exit 1
}

sanitize_name() {
  local raw="$1"
  local sanitized
  sanitized="$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf "%s\n" "$sanitized"
}

is_supported_os() {
  local os_name="$1"
  case "$os_name" in
    all|linux|arch|ubuntu|debian|fedora|manjaro|endeavouros|pop|opensuse|nixos|macos)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_supported_pkg_manager() {
  local manager="$1"
  case "$manager" in
    auto|pacman|apt|dnf|brew|aur|yay|paru)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_package_name() {
  local pkg="$1"
  [[ "$pkg" =~ ^[A-Za-z0-9._:+@-]+$ ]]
}

next_index() {
  local max="-1"
  local name prefix

  while IFS= read -r name; do
    prefix="${name%%-*}"
    if [[ "$prefix" =~ ^[0-9]{3}$ ]] && ((10#$prefix > max)); then
      max=$((10#$prefix))
    fi
  done < <(find "$MANIFEST_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.txt' -printf '%f\n' | sort)

  printf "%03d\n" $((max + 1))
}

trim_space() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

split_first_escaped_pipe() {
  local input="$1"
  local -n out_left="$2"
  local -n out_right="$3"

  out_left=""
  out_right=""

  local escaped=0
  local saw_sep=0
  local current_left=""
  local current_right=""
  local i ch

  for ((i = 0; i < ${#input}; i++)); do
    ch="${input:i:1}"

    if (( escaped )); then
      if [[ "$ch" == '|' || "$ch" == "\\" ]]; then
        if (( saw_sep )); then
          current_right+="$ch"
        else
          current_left+="$ch"
        fi
      else
        if (( saw_sep )); then
          current_right+="\\$ch"
        else
          current_left+="\\$ch"
        fi
      fi
      escaped=0
      continue
    fi

    if [[ "$ch" == "\\" ]]; then
      escaped=1
      continue
    fi

    if [[ "$ch" == '|' && $saw_sep -eq 0 ]]; then
      saw_sep=1
      continue
    fi

    if (( saw_sep )); then
      current_right+="$ch"
    else
      current_left+="$ch"
    fi
  done

  if (( escaped )); then
    if (( saw_sep )); then
      current_right+="\\"
    else
      current_left+="\\"
    fi
  fi

  (( saw_sep == 1 )) || return 1

  out_left="$(trim_space "$current_left")"
  out_right="$(trim_space "$current_right")"
}

parse_entry_pkg_desc() {
  local item="$1"
  local -n out_pkg_ref="$2"
  local -n out_desc_ref="$3"

  if split_first_escaped_pipe "$item" out_pkg_ref out_desc_ref; then
    return 0
  fi

  out_pkg_ref="$(trim_space "$item")"
  out_desc_ref=""
}

escape_field() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//|/\\|}"
  printf '%s\n' "$s"
}

resolve_target_file() {
  local name="$1"
  local sanitized idx

  sanitized="$(sanitize_name "$name")"
  [[ -n "$sanitized" ]] || die "清单名称无效，请使用字母/数字/连接符组合"

  idx="$(next_index)"
  printf "%s/%s-%s.txt\n" "$MANIFEST_DIR" "$idx" "$sanitized"
}

split_escaped_pipe_all() {
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

load_existing_packages() {
  local file_path="$1"
  local -n out_pkgs_ref="$2"

  out_pkgs_ref=()

  local line pkg
  local -a fields=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_space "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" == @desc:* ]] && continue

    split_escaped_pipe_all "$line" fields
    pkg="$(trim_space "${fields[0]:-}")"
    [[ -n "$pkg" ]] || continue
    out_pkgs_ref["$pkg"]="1"
  done < "$file_path"
}

resolve_manifest() {
  local manifest_ref="$1"
  local -n out_target_file_ref="$2"
  local -n out_created_ref="$3"

  out_created_ref=0

  local candidate=""
  if [[ "$manifest_ref" = /* ]]; then
    candidate="$manifest_ref"
  else
    candidate="$MANIFEST_DIR/$manifest_ref"
  fi

  if [[ -f "$candidate" ]]; then
    out_target_file_ref="$candidate"
    return 0
  fi

  local base_name
  base_name="$(basename -- "$manifest_ref")"
  base_name="${base_name%.txt}"
  base_name="${base_name#[0-9][0-9][0-9]-}"

  out_target_file_ref="$(resolve_target_file "$base_name")"
  out_created_ref=1
}

collect_input_entries() {
  local use_stdin="$1"
  shift
  local -n out_entries_ref="$1"
  shift

  out_entries_ref=()
  local item

  for item in "$@"; do
    out_entries_ref+=("$item")
  done

  if [[ "$use_stdin" == "1" || ( ${#out_entries_ref[@]} -eq 0 && ! -t 0 ) ]]; then
    while IFS= read -r item || [[ -n "$item" ]]; do
      item="$(trim_space "$item")"
      [[ -n "$item" ]] || continue
      [[ "$item" == \#* ]] && continue
      out_entries_ref+=("$item")
    done
  fi
}

ensure_no_pkg_conflict() {
  local file_path="$1"
  shift

  local -A existing_pkgs=()
  load_existing_packages "$file_path" existing_pkgs

  local -A incoming_pkgs=()
  local item pkg desc
  for item in "$@"; do
    parse_entry_pkg_desc "$item" pkg desc
    [[ -n "$pkg" ]] || die "条目中的 package 不能为空: $item"
    validate_package_name "$pkg" || die "package 含非法字符，仅允许字母/数字/._:+-@: $pkg"

    if [[ -n "${incoming_pkgs[$pkg]:-}" ]]; then
      die "批量输入中出现重复 package: $pkg"
    fi

    if [[ -n "${existing_pkgs[$pkg]:-}" ]]; then
      die "清单已存在同名 package，禁止追加: $pkg"
    fi

    incoming_pkgs["$pkg"]="1"
  done
}

append_entries() {
  local file_path="$1"
  local os_target="$2"
  local pkg_manager="$3"
  shift 3

  local item pkg desc pkg_out desc_out
  for item in "$@"; do
    parse_entry_pkg_desc "$item" pkg desc
    [[ -n "$pkg" ]] || die "条目中的 package 不能为空: $item"

    pkg_out="$(escape_field "$pkg")"
    desc_out="$(escape_field "$desc")"

    printf "%s|%s|%s|%s\n" "$pkg_out" "$os_target" "$pkg_manager" "$desc_out" >> "$file_path"
  done
}

main() {
  [[ -d "$MANIFEST_DIR" ]] || die "目录不存在: $MANIFEST_DIR"

  local manifest_arg=""
  local title_arg=""
  local os_target="all"
  local pkg_manager="auto"
  local use_stdin="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest|-m)
        [[ $# -ge 2 ]] || die "--manifest 需要一个参数"
        manifest_arg="$2"
        shift 2
        ;;
      --title)
        [[ $# -ge 2 ]] || die "--title 需要一个参数"
        title_arg="$2"
        shift 2
        ;;
      --os)
        [[ $# -ge 2 ]] || die "--os 需要一个参数"
        os_target="${2,,}"
        shift 2
        ;;
      --pkg-manager|--manager)
        [[ $# -ge 2 ]] || die "$1 需要一个参数"
        pkg_manager="${2,,}"
        shift 2
        ;;
      --stdin)
        use_stdin="1"
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "未知参数: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  [[ -n "$manifest_arg" ]] || die "必须指定 --manifest"

  is_supported_os "$os_target" || {
    die "不支持的 os: $os_target；支持列表: $SUPPORTED_OS_LIST"
  }

  is_supported_pkg_manager "$pkg_manager" || {
    die "不支持的 pkg_manager: $pkg_manager；支持列表: $SUPPORTED_PKG_MANAGER_LIST"
  }

  local -a input_entries=()
  collect_input_entries "$use_stdin" input_entries "$@"
  [[ ${#input_entries[@]} -gt 0 ]] || die "至少提供一条 pkg[|desc]（参数或 --stdin）"

  local target_file=""
  local created=0
  resolve_manifest "$manifest_arg" target_file created

  if (( created == 1 )); then
    {
      [[ -n "$title_arg" ]] && printf "@desc: %s\n\n" "$title_arg"
    } > "$target_file"
  fi

  ensure_no_pkg_conflict "$target_file" "${input_entries[@]}"
  append_entries "$target_file" "$os_target" "$pkg_manager" "${input_entries[@]}"

  if (( created == 1 )); then
    printf "[OK] 已创建并追加: %s\n" "$target_file"
  else
    printf "[OK] 已追加到: %s\n" "$target_file"
  fi
}

main "$@"
