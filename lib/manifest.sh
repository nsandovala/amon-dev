#!/usr/bin/env bash

manifest_require_yq() {
  if ! command -v yq >/dev/null 2>&1; then
    out_error "yq no está disponible. Instálalo con: mise use -g yq"
    return 1
  fi
}

manifest_exists() {
  [ -f "$AMON_MANIFEST" ]
}

manifest_validate() {
  manifest_require_yq || return 1
  manifest_exists || return 1
  yq eval -e '.projects | type == "!!map"' "$AMON_MANIFEST" >/dev/null 2>&1
}

manifest_project_count() {
  yq eval -r '.projects | length' "$AMON_MANIFEST"
}

manifest_list_projects() {
  yq eval -r '.projects | to_entries | .[].key' "$AMON_MANIFEST"
}

manifest_project_exists() {
  local slug=$1
  PROJECT_SLUG="$slug" yq eval -e \
    '.projects[strenv(PROJECT_SLUG)] != null' "$AMON_MANIFEST" >/dev/null 2>&1
}

manifest_project_field() {
  local slug=$1
  local field=$2
  PROJECT_SLUG="$slug" PROJECT_FIELD="$field" yq eval -r \
    '.projects[strenv(PROJECT_SLUG)][strenv(PROJECT_FIELD)] // ""' "$AMON_MANIFEST"
}

manifest_project_array() {
  local slug=$1
  local field=$2
  PROJECT_SLUG="$slug" PROJECT_FIELD="$field" yq eval -r \
    '.projects[strenv(PROJECT_SLUG)][strenv(PROJECT_FIELD)][]?' "$AMON_MANIFEST"
}

manifest_project_ports_csv() {
  local slug=$1
  manifest_project_array "$slug" ports | paste -sd, -
}

manifest_root() {
  yq eval -r '.root // ""' "$AMON_MANIFEST"
}

manifest_runtimes() {
  yq eval -r '.projects[].runtime // ""' "$AMON_MANIFEST" |
    awk 'NF' |
    sort -u
}
