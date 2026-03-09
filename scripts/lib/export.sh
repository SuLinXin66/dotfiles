#!/usr/bin/env bash

# 统一导出入口：
# - 只做函数库加载，不做命令执行
# - 固定加载顺序，避免依赖错位

if [[ -n "${LIB_EXPORT_LOADED:-}" ]]; then
  return 0
fi
LIB_EXPORT_LOADED=1

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$LIB_DIR/log.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/cli.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/cmd.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/privilege.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/os.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/pkg.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/env.sh"
