#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FUNCS_DIR="$PROJECT_ROOT/scripts/funcs"

show_help() {
  cat <<'EOF'
用法: ./new-func.sh <name>

说明:
  在 scripts/funcs 下创建新的编号模块脚本。
  传入名称不带序号，脚本会自动使用当前最大序号 + 1。

示例:
  ./new-func.sh sync-git-config
  -> scripts/funcs/002-sync-git-config.sh
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

next_index() {
  local max="-1"
  local name prefix

  while IFS= read -r name; do
    prefix="${name%%-*}"
    if [[ "$prefix" =~ ^[0-9]{3}$ ]] && ((10#$prefix > max)); then
      max=$((10#$prefix))
    fi
  done < <(find "$FUNCS_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)

  printf "%03d\n" $((max + 1))
}

main() {
  [[ $# -eq 1 ]] || {
    show_help
    exit 1
  }

  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
  esac

  [[ -d "$FUNCS_DIR" ]] || die "目录不存在: $FUNCS_DIR"

  local raw_name="$1"
  if [[ "$raw_name" =~ ^[0-9]{3}- ]]; then
    die "名称不能包含序号前缀，请仅传功能名，例如: install-packages"
  fi

  local func_name
  func_name="$(sanitize_name "$raw_name")"
  [[ -n "$func_name" ]] || die "名称无效，请使用字母/数字/连接符组合"

  local idx
  idx="$(next_index)"

  local file_name="${idx}-${func_name}.sh"
  local file_path="$FUNCS_DIR/$file_name"

  [[ ! -e "$file_path" ]] || die "目标文件已存在: $file_path"

  cat >"$file_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd -- "\$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "\$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

show_help() {
  cat <<'HELP_EOF'
用法: ${file_name} [--dry-run]

说明:
  TODO: 请在此处补充该模块的功能说明。

通用参数:
  --dry-run   仅打印将执行的命令
  -h, --help  显示本帮助
HELP_EOF
}

env_spec() {
  cat <<'ENV_EOF'
# 格式: KEY|DEFAULT|DESC
ENV_EOF
}

run_impl() {
  # TODO: 在这里实现 ${file_name} 的核心逻辑。
  # 建议：只写业务代码，不处理参数解析。
  log::info "TODO: 实现 ${file_name}"
}

dry_run_impl() {
  # TODO: 在这里实现 ${file_name} 的 dry-run 专属逻辑。
  # 建议：仅输出预演信息，不执行真实变更。
  log::info "[DRY-RUN] TODO: 实现 ${file_name}"
}

cli::run_noargs_hooks "${file_name}" show_help env_spec run_impl dry_run_impl "\$@"
EOF

  chmod +x "$file_path"
  printf "[OK] 已创建: %s\n" "$file_path"
}

main "$@"
