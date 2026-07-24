#!/usr/bin/env bash

agents_prepare_engine() {
  local package_json
  local bin_entry
  local runtime_dir

  require_manifest || return 1
  if ! manifest_project_exists "amon-agents"; then
    out_error "El manifiesto no declara el proyecto plumbing amon-agents"
    return 1
  fi

  AGENTS_ENGINE_PATH=$(manifest_project_field "amon-agents" path)
  AGENTS_ENGINE_RUNTIME=$(manifest_project_field "amon-agents" runtime)
  package_json="$AGENTS_ENGINE_PATH/package.json"

  if [ ! -d "$AGENTS_ENGINE_PATH" ]; then
    out_error "La ruta declarada para amon-agents no existe: $AGENTS_ENGINE_PATH"
    return 1
  fi
  if [ ! -f "$package_json" ]; then
    out_error "amon-agents no tiene package.json en su ruta declarada"
    return 1
  fi

  bin_entry=$(yq eval -p=json -r '.bin."amon-agents" // ""' "$package_json" 2>/dev/null)
  if [ -z "$bin_entry" ] || [ ! -f "$AGENTS_ENGINE_PATH/$bin_entry" ]; then
    out_error "El paquete declarado no expone un bin amon-agents utilizable"
    return 1
  fi

  if ! command -v mise >/dev/null 2>&1; then
    out_error "mise no está disponible para ejecutar amon-agents"
    return 1
  fi
  runtime_dir=$(mise where "$AGENTS_ENGINE_RUNTIME" 2>/dev/null) || {
    out_error "Runtime de amon-agents no disponible: $AGENTS_ENGINE_RUNTIME"
    return 1
  }
  AGENTS_SAFE_PATH="$runtime_dir/bin:/usr/local/bin:/usr/bin:/bin"

  if ! (
    cd "$AGENTS_ENGINE_PATH" || exit 1
    mise exec "$AGENTS_ENGINE_RUNTIME" -- \
      env PATH="$AGENTS_SAFE_PATH" \
      npm exec --offline -- amon-agents --help >/dev/null 2>&1
  ); then
    out_error "El bin Linux amon-agents no responde mediante mise"
    return 1
  fi
}

agents_exec() {
  (
    cd "$AGENTS_ENGINE_PATH" || exit 1
    exec mise exec "$AGENTS_ENGINE_RUNTIME" -- \
      env PATH="$AGENTS_SAFE_PATH" \
      npm exec --offline -- amon-agents "$@"
  )
}

delegate_to_agents() {
  local subcommand=$1
  local slug="*"
  local project_path
  local exit_code
  local result
  shift

  case "$subcommand" in
    audit|scan)
      if [ "$#" -lt 1 ]; then
        out_error "$subcommand requiere un proyecto"
        return 2
      fi
      slug=$1
      shift
      if ! require_project "$slug"; then
        record_event "agents:$subcommand" "$slug" "invalid-project"
        return 1
      fi
      project_path=$(manifest_project_field "$slug" path)
      set -- "$subcommand" --repo "$project_path" "$@"
      ;;
    status|doctor)
      set -- "$subcommand" "$@"
      ;;
    *)
      out_error "Subcomando de agentes no soportado: $subcommand"
      return 2
      ;;
  esac

  if ! agents_prepare_engine; then
    record_event "agents:$subcommand" "$slug" "engine-unavailable"
    return 1
  fi

  agents_exec "$@"
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    result="ok"
  else
    result="exit:$exit_code"
  fi
  record_event "agents:$subcommand" "$slug" "$result"
  return "$exit_code"
}
