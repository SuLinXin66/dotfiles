#!/usr/bin/env bash

if [[ -t 1 ]]; then
  LOG_RESET=$'\033[0m'
  LOG_DIM=$'\033[2m'
  LOG_RED=$'\033[31m'
  LOG_GREEN=$'\033[32m'
  LOG_YELLOW=$'\033[33m'
  LOG_BLUE=$'\033[34m'
else
  LOG_RESET=""
  LOG_DIM=""
  LOG_RED=""
  LOG_GREEN=""
  LOG_YELLOW=""
  LOG_BLUE=""
fi

# 内部日志打印函数（统一格式）。
# 参数:
#   $1: 级别标记
#   $2: ANSI 颜色
#   $@: 日志正文
log::_print() {
  local level="$1"
  local color="$2"
  shift 2
  printf "%s%s[%s]%s %s\n" "$LOG_DIM" "$color" "$level" "$LOG_RESET" "$*"
}

# 打印普通信息日志。
# 参数:
#   $@: 日志正文
log::info() { log::_print "+" "$LOG_BLUE" "$@"; }
# 打印成功日志。
# 参数:
#   $@: 日志正文
log::ok() { log::_print "OK" "$LOG_GREEN" "$@"; }
# 打印警告日志。
# 参数:
#   $@: 日志正文
log::warn() { log::_print "!" "$LOG_YELLOW" "$@"; }
# 打印错误日志。
# 参数:
#   $@: 日志正文
log::error() { log::_print "X" "$LOG_RED" "$@"; }

# 打印错误并退出。
# 参数:
#   $@: 错误信息
log::die() {
  log::error "$@"
  exit 1
}

# 启用 ERR trap，出现错误时统一输出错误并退出。
# 参数:
#   无
log::enable_err_trap() {
  trap 'log::die "Failed at line $LINENO: $BASH_COMMAND"' ERR
}
