#!/usr/bin/env bash

# 通用 CLI 解析层
# 统一能力：
#   - --dry-run
#   - -h / --help
#   - 剩余参数收集

# 重置本次解析状态。
# 参数:
#   无
cli::reset() {
  CLI_DRY_RUN="${DRY_RUN:-0}"
  CLI_SHOW_HELP="0"
  CLI_PRINT_ENV_SPEC="0"
  CLI_ARGS=()
}

# 解析通用参数。
# 参数:
#   $@: 命令行参数
# 行为:
#   识别 --dry-run/-h/--help，其余参数收集到 CLI_ARGS。
cli::parse_common() {
  cli::reset

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        CLI_DRY_RUN="1"
        shift
        ;;
      -h|--help)
        CLI_SHOW_HELP="1"
        shift
        ;;
      --print-env-spec)
        CLI_PRINT_ENV_SPEC="1"
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          CLI_ARGS+=("$1")
          shift
        done
        ;;
      *)
        CLI_ARGS+=("$1")
        shift
        ;;
    esac
  done

  export DRY_RUN="$CLI_DRY_RUN"
}

# 判断是否请求打印环境变量规格。
# 参数:
#   无
# 返回:
#   0=是, 1=否
cli::is_print_env_spec() {
  [[ "$CLI_PRINT_ENV_SPEC" == "1" ]]
}

# 如果命中 help 参数则调用 usage 函数并退出。
# 参数:
#   $1: usage 函数名
cli::maybe_show_help() {
  local usage_func="$1"

  if [[ "$CLI_SHOW_HELP" == "1" ]]; then
    "$usage_func"
    exit 0
  fi
}

# 要求不存在位置参数，否则中止。
# 参数:
#   $1: 脚本名（用于错误提示）
cli::require_no_args() {
  local script_name="$1"

  if [[ ${#CLI_ARGS[@]} -gt 0 ]]; then
    log::die "$script_name 不接受位置参数: ${CLI_ARGS[*]}"
  fi
}

# 判断当前是否 dry-run。
# 参数:
#   无
# 返回:
#   0=是 dry-run, 1=否
cli::is_dry_run() {
  [[ "${DRY_RUN:-0}" == "1" ]]
}

# 按 dry-run 状态分发到不同钩子。
# 参数:
#   $1: 真实执行钩子函数名
#   $2: dry-run 执行钩子函数名
cli::dispatch_hooks() {
  local run_hook="$1"
  local dry_run_hook="$2"

  declare -F "$run_hook" >/dev/null 2>&1 || log::die "Run hook not found: $run_hook"
  declare -F "$dry_run_hook" >/dev/null 2>&1 || log::die "Dry-run hook not found: $dry_run_hook"

  if cli::is_dry_run; then
    "$dry_run_hook"
  else
    "$run_hook"
  fi
}

# 无位置参数脚本的一站式入口。
# 参数:
#   $1: 脚本名
#   $2: usage 函数名
#   $3: 真实执行钩子函数名
#   $4: dry-run 执行钩子函数名
#   $@: 原始命令行参数
cli::run_noargs_hooks() {
  local script_name="$1"
  local usage_func="$2"
  local env_spec_func="$3"
  local run_hook="$4"
  local dry_run_hook="$5"
  shift 5

  cli::parse_common "$@"

  if cli::is_print_env_spec; then
    env::print_specs_raw "$env_spec_func"
    exit 0
  fi

  if [[ "$CLI_SHOW_HELP" == "1" ]]; then
    "$usage_func"
    printf "\n环境变量:\n"
    env::print_specs_help "$env_spec_func"
    exit 0
  fi

  cli::require_no_args "$script_name"
  cli::dispatch_hooks "$run_hook" "$dry_run_hook"
}
