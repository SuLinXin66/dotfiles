#!/usr/bin/env bash

# 获取内核名称。
# 参数:
#   无
os::kernel_name() {
  uname -s
}

# 获取内核版本。
# 参数:
#   无
os::kernel_release() {
  uname -r
}

# 获取系统架构。
# 参数:
#   无
os::arch() {
  uname -m
}

# 判断当前是否 Linux。
# 参数:
#   无
# 返回:
#   0=是, 1=否
os::is_linux() {
  [[ "$(os::kernel_name)" == "Linux" ]]
}

# 获取发行版 ID（读取 /etc/os-release）。
# 参数:
#   无
# 返回:
#   如 arch/ubuntu，读取失败返回 unknown
os::id() {
  if [[ -f /etc/os-release ]]; then
    awk -F= '/^ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release
    return 0
  fi

  printf "unknown\n"
}

# 获取发行版版本号（读取 /etc/os-release）。
# 参数:
#   无
# 返回:
#   如 24.04，读取失败返回 unknown
os::version_id() {
  if [[ -f /etc/os-release ]]; then
    awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release
    return 0
  fi

  printf "unknown\n"
}

# 判断是否 Arch Linux。
# 参数:
#   无
# 返回:
#   0=是, 1=否
os::is_archlinux() {
  [[ -f /etc/arch-release ]] || [[ "$(os::id)" == "arch" ]]
}

# 获取 CPU 核心数。
# 参数:
#   无
os::cpu_cores() {
  if cmd::exists nproc; then
    nproc
    return 0
  fi

  getconf _NPROCESSORS_ONLN
}

# 获取总内存（MB）。
# 参数:
#   无
os::memory_mb() {
  awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo
}

# 要求系统必须是 Linux，否则中止。
# 参数:
#   无
os::require_linux() {
  os::is_linux || log::die "Current system is not Linux"
}

# 要求 CPU 核心数达到最小值，否则中止。
# 参数:
#   $1: 最小核心数
os::require_min_cpu_cores() {
  local min_cores="$1"
  local current_cores
  current_cores="$(os::cpu_cores)"

  (( current_cores >= min_cores )) || {
    log::die "CPU cores not enough: need >= ${min_cores}, current=${current_cores}"
  }
}

# 要求内存达到最小值，否则中止。
# 参数:
#   $1: 最小内存（MB）
os::require_min_memory_mb() {
  local min_mb="$1"
  local current_mb
  current_mb="$(os::memory_mb)"

  (( current_mb >= min_mb )) || {
    log::die "Memory not enough: need >= ${min_mb}MB, current=${current_mb}MB"
  }
}
