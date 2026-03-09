#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RUN_FUNCS=(
  "000"
  "001"
)

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/export.sh"

log::enable_err_trap

show_help() {
  cat <<'EOF'
用法: ./setup.sh [--dry-run]

参数:
  --dry-run             仅打印命令，不执行实质变更
  -h, --help            显示帮助

行为:
  按 RUN_FUNCS 严格顺序执行 funcs。
  RUN_FUNCS 支持两种写法:
    - 仅编号: 000 / 001
    - 完整文件名: 000-deploy-dotfiles.sh
  执行前会校验 funcs 目录编号是否重复，重复则直接失败。

示例:
  ./setup.sh
  ./setup.sh --dry-run
EOF

  setup::print_env_help
}

setup::print_env_help() {
  local funcs_dir="$PROJECT_ROOT/scripts/funcs"
  [[ -d "$funcs_dir" ]] || return 0

  printf "\n执行链环境变量配置:\n"

  declare -gA FUNC_INDEX=()
  build_func_index

  local token func func_path raw line key def desc
  for token in "${RUN_FUNCS[@]}"; do
    func="$(resolve_func_token "$token")"
    func_path="$funcs_dir/$func"

    printf "\n[%s]\n" "$func"

    raw="$("$func_path" --print-env-spec 2>/dev/null || true)"
    if [[ -z "$raw" ]]; then
      printf "  - 无\n"
      continue
    fi

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ "$line" == \#* ]] && continue

      key="${line%%|*}"
      line="${line#*|}"
      def="${line%%|*}"
      desc="${line#*|}"

      if [[ -n "$def" ]]; then
        printf "  - %s (默认: %s): %s\n" "$key" "$def" "$desc"
      else
        printf "  - %s (必填): %s\n" "$key" "$desc"
      fi
    done <<< "$raw"
  done
}

build_func_index() {
  local funcs_dir="$PROJECT_ROOT/scripts/funcs"
  [[ -d "$funcs_dir" ]] || log::die "Missing funcs directory: $funcs_dir"

  FUNC_INDEX=()
  local file prefix

  while IFS= read -r file; do
    prefix="${file%%-*}"

    [[ "$prefix" =~ ^[0-9]{3}$ ]] || {
      log::die "Invalid func filename (need NNN-name.sh): $file"
    }

    if [[ -n "${FUNC_INDEX[$prefix]:-}" ]]; then
      log::die "Duplicate func prefix detected: $prefix (${FUNC_INDEX[$prefix]} and $file)"
    fi

    FUNC_INDEX[$prefix]="$file"
  done < <(find "$funcs_dir" -mindepth 1 -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)
}

resolve_func_token() {
  local token="$1"
  local funcs_dir="$PROJECT_ROOT/scripts/funcs"

  if [[ "$token" =~ ^[0-9]{3}$ ]]; then
    [[ -n "${FUNC_INDEX[$token]:-}" ]] || log::die "No func matches prefix: $token"
    printf "%s\n" "${FUNC_INDEX[$token]}"
    return 0
  fi

  if [[ "$token" =~ ^[0-9]{3}-[a-zA-Z0-9._-]+$ ]] && [[ "$token" != *.sh ]]; then
    token="${token}.sh"
  fi

  [[ -f "$funcs_dir/$token" ]] || log::die "Func not found: $token"
  printf "%s\n" "$token"
}

main() {
  cli::parse_common "$@"
  cli::maybe_show_help show_help
  cli::require_no_args "setup.sh"

  export PROJECT_ROOT
  if [[ -z "${PKG_REFRESH_STATE_FILE:-}" ]]; then
    PKG_REFRESH_STATE_FILE="$(mktemp "/tmp/dotfiles-pkg-refresh.XXXXXX")"
    export PKG_REFRESH_STATE_FILE
    trap 'rm -f "${PKG_REFRESH_STATE_FILE:-}"' EXIT
  fi

  declare -A FUNC_INDEX=()

  build_func_index

  local token func func_path
  for token in "${RUN_FUNCS[@]}"; do
    func="$(resolve_func_token "$token")"
    func_path="$PROJECT_ROOT/scripts/funcs/$func"

    log::info "Running func: $func"
    if "$func_path"; then
      log::ok "Func succeeded: $func"
    else
      log::die "Func failed: $func"
    fi
  done
}

main "$@"
