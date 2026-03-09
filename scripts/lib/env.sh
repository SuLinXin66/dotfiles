#!/usr/bin/env bash

# 约定：env_spec 函数按行输出 "KEY|DEFAULT|DESC"。

# 输出指定 env_spec 的原始规格行。
# 参数:
#   $1: env_spec 函数名
env::print_specs_raw() {
  local spec_func="$1"
  declare -F "$spec_func" >/dev/null 2>&1 || return 0
  "$spec_func"
}

# 以 help 友好格式输出环境变量说明。
# 参数:
#   $1: env_spec 函数名
env::print_specs_help() {
  local spec_func="$1"
  local line key def desc
  local has_any="0"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%|*}"
    line="${line#*|}"
    def="${line%%|*}"
    desc="${line#*|}"
    has_any="1"

    if [[ -n "$def" ]]; then
      printf "  - %s (默认: %s): %s\n" "$key" "$def" "$desc"
    else
      printf "  - %s (必填): %s\n" "$key" "$desc"
    fi
  done < <(env::print_specs_raw "$spec_func")

  [[ "$has_any" == "1" ]] || printf "  - 无\n"
}

# 检查某个 key 是否在 env_spec 中定义。
# 参数:
#   $1: env_spec 函数名
#   $2: 环境变量名
# 返回:
#   0=存在, 1=不存在
env::has_key() {
  local spec_func="$1"
  local key="$2"
  local line spec_key

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    spec_key="${line%%|*}"
    if [[ "$spec_key" == "$key" ]]; then
      return 0
    fi
  done < <(env::print_specs_raw "$spec_func")

  return 1
}

# 获取 env_spec 中某个 key 的默认值。
# 参数:
#   $1: env_spec 函数名
#   $2: 环境变量名
env::default_of() {
  local spec_func="$1"
  local key="$2"
  local line spec_key rest def

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    spec_key="${line%%|*}"
    rest="${line#*|}"
    def="${rest%%|*}"

    if [[ "$spec_key" == "$key" ]]; then
      printf "%s\n" "$def"
      return 0
    fi
  done < <(env::print_specs_raw "$spec_func")

  return 1
}

# 按规格读取环境变量。
# 参数:
#   $1: env_spec 函数名
#   $2: 环境变量名
# 规则:
#   - 未在规格中定义: 报错
#   - 已定义且环境中有值: 返回环境值
#   - 环境中无值但有默认值: 返回默认值
#   - 环境中无值且无默认值: 报错
env::get() {
  local spec_func="$1"
  local key="$2"
  local default
  local has_default="0"

  env::has_key "$spec_func" "$key" || {
    log::die "Unknown env key for ${spec_func}: ${key}"
  }

  if [[ -n "${!key:-}" ]]; then
    printf "%s\n" "${!key}"
    return 0
  fi

  if default="$(env::default_of "$spec_func" "$key" 2>/dev/null)"; then
    has_default="1"
  else
    default=""
  fi

  if [[ -n "$default" ]]; then
    printf "%s\n" "$default"
    return 0
  fi

  if [[ "$has_default" == "1" ]]; then
    printf "\n"
    return 0
  fi

  log::die "Missing required env: ${key}"
}
