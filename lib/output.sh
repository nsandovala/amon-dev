#!/usr/bin/env bash

output_init() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    AMON_RED=$(printf '\033[31m')
    AMON_GREEN=$(printf '\033[32m')
    AMON_YELLOW=$(printf '\033[33m')
    AMON_BOLD=$(printf '\033[1m')
    AMON_RESET=$(printf '\033[0m')
  else
    AMON_RED=
    AMON_GREEN=
    AMON_YELLOW=
    AMON_BOLD=
    AMON_RESET=
  fi
}

out_ok() {
  printf '%sOK%s   %s\n' "$AMON_GREEN" "$AMON_RESET" "$*"
}

out_warn() {
  printf '%sWARN%s %s\n' "$AMON_YELLOW" "$AMON_RESET" "$*"
}

out_fail() {
  printf '%sFAIL%s %s\n' "$AMON_RED" "$AMON_RESET" "$*" >&2
}

out_info() {
  printf '     %s\n' "$*"
}

out_error() {
  printf '%sError:%s %s\n' "$AMON_RED" "$AMON_RESET" "$*" >&2
}

out_heading() {
  printf '%s%s%s\n' "$AMON_BOLD" "$*" "$AMON_RESET"
}

out_blocked_status() {
  printf '%s[BLOCKED] %s%s' "$AMON_RED" "$1" "$AMON_RESET"
}

out_conflict_row() {
  printf '%s%-8s %-42s %-8s %s%s\n' \
    "$AMON_RED" "$1" "$2" "$3" "CONFLICT" "$AMON_RESET"
}
