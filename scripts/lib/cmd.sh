#!/usr/bin/env bash

# 判断命令是否存在。
# 参数:
#   $1: 命令名
cmd::exists() {
  command -v "$1" >/dev/null 2>&1
}

# 要求命令必须存在，不存在则中止。
# 参数:
#   $1: 命令名
cmd::require() {
  local cmd="$1"
  cmd::exists "$cmd" || log::die "Required command not found: $cmd"
}

# 执行命令。
# 参数:
#   $@: 需要执行的完整命令
# 行为:
#   dry-run 模式下仅打印命令，不实际执行。
cmd::run() {
  if cli::is_dry_run; then
    log::info "DRY RUN: $*"
    return 0
  fi
  "$@"
}
