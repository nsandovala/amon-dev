#!/usr/bin/env bash

doctor_reset() {
  DOCTOR_FAILS=0
  DOCTOR_WARNS=0
}

doctor_ok() {
  out_ok "$*"
}

doctor_warn() {
  DOCTOR_WARNS=$((DOCTOR_WARNS + 1))
  out_warn "$*"
}

doctor_fail() {
  DOCTOR_FAILS=$((DOCTOR_FAILS + 1))
  out_fail "$*"
}

port_is_listening() {
  local port=$1

  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null |
      awk -v wanted="$port" '
        {
          count = split($4, parts, ":")
          if (parts[count] == wanted) {
            found = 1
          }
        }
        END { exit found ? 0 : 1 }
      '
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  return 2
}

doctor_check_environment() {
  local kernel
  kernel=$(uname -s 2>/dev/null || printf 'unknown')

  case "$kernel" in
    Linux)
      if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        doctor_ok "Entorno: WSL2/Linux"
      else
        doctor_ok "Entorno: Linux"
      fi
      ;;
    Darwin)
      doctor_ok "Entorno: macOS (compatible)"
      ;;
    *)
      doctor_warn "Entorno no identificado: $kernel [PENDIENTE VERIFICAR]"
      ;;
  esac
}

doctor_check_root() {
  local root
  root=$(manifest_root)

  if [ -z "$root" ]; then
    doctor_fail "El manifiesto no declara la raíz de proyectos"
    return
  fi

  case "$root" in
    /mnt/c|/mnt/c/*)
      doctor_fail "La raíz de proyectos está bajo /mnt/c: $root"
      ;;
    *)
      doctor_ok "Raíz de proyectos fuera de /mnt/c: $root"
      ;;
  esac

  if [ -d "$root" ]; then
    local free_kb
    local free_mib
    free_kb=$(df -Pk "$root" 2>/dev/null | awk 'NR == 2 { print $4 }')
    if [ -n "$free_kb" ]; then
      free_mib=$((free_kb / 1024))
      doctor_ok "Espacio libre en la raíz: ${free_mib} MiB"
    else
      doctor_warn "No se pudo calcular el espacio libre en $root"
    fi
  else
    doctor_fail "La raíz de proyectos no existe: $root"
  fi
}

doctor_check_mise() {
  local runtime

  if ! command -v mise >/dev/null 2>&1; then
    doctor_fail "mise no está disponible"
    return
  fi
  doctor_ok "mise disponible"

  while IFS= read -r runtime; do
    [ -n "$runtime" ] || continue
    if mise where "$runtime" >/dev/null 2>&1; then
      doctor_ok "Runtime instalado: $runtime"
    else
      doctor_fail "Runtime declarado no instalado: $runtime"
    fi
  done < <(manifest_runtimes)
}

doctor_check_ollama() {
  if ! command -v curl >/dev/null 2>&1; then
    doctor_warn "curl no está disponible; Ollama no se pudo comprobar"
    return
  fi

  if curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    doctor_ok "Ollama alcanzable en localhost:11434"
  else
    doctor_warn "Ollama no alcanzable en localhost:11434 (informativo) [PENDIENTE VERIFICAR]"
  fi
}

doctor_global_checks() {
  out_heading "Chequeos globales"

  if command -v yq >/dev/null 2>&1; then
    doctor_ok "yq disponible: $(yq --version 2>/dev/null)"
  else
    doctor_fail "yq no está disponible. Instálalo con: mise use -g yq"
  fi

  if [ ! -f "$AMON_MANIFEST" ]; then
    doctor_fail "Manifiesto no encontrado: $AMON_MANIFEST"
    doctor_check_environment
    return
  fi

  if ! command -v yq >/dev/null 2>&1; then
    doctor_fail "No se puede parsear el manifiesto sin yq"
    doctor_check_environment
    return
  fi

  if manifest_validate; then
    doctor_ok "Manifiesto válido: $(manifest_project_count) proyectos"
  else
    doctor_fail "El manifiesto no parsea como un mapa de proyectos: $AMON_MANIFEST"
    doctor_check_environment
    return
  fi

  doctor_check_environment
  doctor_check_root
  doctor_check_mise
  doctor_check_ollama
}

doctor_check_dependencies() {
  local path=$1
  local manager=$2
  local dependency_dir
  local candidate

  case "$manager" in
    npm|pnpm|yarn)
      dependency_dir=
      for candidate in \
        "$path/node_modules" \
        "$path"/*/node_modules \
        "$path"/*/*/node_modules; do
        if [ -d "$candidate" ]; then
          dependency_dir=$candidate
          break
        fi
      done
      if [ -n "$dependency_dir" ]; then
        doctor_ok "Dependencias instaladas: ${dependency_dir#"$path"/}"
      else
        doctor_fail "Dependencias ausentes: no se encontró node_modules/ hasta profundidad 3"
      fi
      ;;
    pip|python|venv)
      dependency_dir=
      for candidate in \
        "$path/.venv" \
        "$path"/*/.venv \
        "$path"/*/*/.venv; do
        if [ -d "$candidate" ]; then
          dependency_dir=$candidate
          break
        fi
      done
      if [ -n "$dependency_dir" ]; then
        doctor_ok "Dependencias instaladas: ${dependency_dir#"$path"/}"
      else
        doctor_fail "Dependencias ausentes: no se encontró .venv/ hasta profundidad 3"
      fi
      ;;
    *)
      doctor_warn "Gestor sin regla de dependencias: $manager [PENDIENTE VERIFICAR]"
      ;;
  esac
}

doctor_check_ports() {
  local slug=$1
  local port
  local result
  local found=0

  while IFS= read -r port; do
    [ -n "$port" ] || continue
    found=1
    port_is_listening "$port"
    result=$?
    case "$result" in
      0) doctor_warn "Puerto $port ocupado" ;;
      1) doctor_ok "Puerto $port libre" ;;
      2) doctor_warn "Puerto $port: falta ss/lsof [PENDIENTE VERIFICAR]" ;;
    esac
  done < <(manifest_project_array "$slug" ports)

  if [ "$found" -eq 0 ]; then
    doctor_ok "El proyecto no declara puertos"
  fi
}

doctor_check_env_files() {
  local slug=$1
  local path=$2
  local required

  required=$(manifest_project_array "$slug" env_required | paste -sd, -)
  if [ -z "$required" ]; then
    doctor_ok "El proyecto no declara variables de entorno requeridas"
    return
  fi

  if [ -f "$path/.env.local" ]; then
    doctor_ok "Archivo de entorno presente: .env.local"
    doctor_warn "No se leyó .env.local; nombres por verificar: $required [PENDIENTE VERIFICAR]"
    return
  fi

  if [ -f "$path/.env" ]; then
    doctor_ok "Archivo de entorno presente: .env"
    doctor_warn "No se leyó .env; nombres por verificar: $required [PENDIENTE VERIFICAR]"
    return
  fi

  doctor_fail "Sin .env/.env.local; variables faltantes: $required"
}

doctor_project_checks() {
  local slug=$1
  local path
  local runtime
  local manager
  local project_status

  out_heading "Chequeos de proyecto: $slug"

  if ! manifest_project_exists "$slug"; then
    doctor_fail "Proyecto no encontrado en el manifiesto: $slug"
    return
  fi

  path=$(manifest_project_field "$slug" path)
  runtime=$(manifest_project_field "$slug" runtime)
  manager=$(manifest_project_field "$slug" manager)
  project_status=$(manifest_project_field "$slug" status)

  case "$project_status" in
    blocked:*) doctor_warn "Estado del manifiesto: $project_status" ;;
    *) doctor_ok "Estado del manifiesto: $project_status" ;;
  esac

  if [ -d "$path" ]; then
    doctor_ok "Ruta existente: $path"
  else
    doctor_fail "Ruta inexistente: $path"
    return
  fi

  if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    doctor_ok "Repositorio Git válido"
  else
    doctor_fail "La ruta no es un repositorio Git"
  fi

  if command -v mise >/dev/null 2>&1 && mise where "$runtime" >/dev/null 2>&1; then
    doctor_ok "Runtime disponible vía mise: $runtime"
  else
    doctor_fail "Runtime no disponible vía mise: $runtime"
  fi

  doctor_check_dependencies "$path" "$manager"
  doctor_check_ports "$slug"
  doctor_check_env_files "$slug" "$path"
}

doctor_run() {
  local slug=${1:-}

  doctor_reset
  doctor_global_checks
  if [ -n "$slug" ] && [ "$DOCTOR_FAILS" -eq 0 ]; then
    doctor_project_checks "$slug"
  elif [ -n "$slug" ]; then
    doctor_warn "Chequeos de proyecto omitidos por fallos globales"
  fi

  printf '\nResumen: %s FAIL, %s WARN\n' "$DOCTOR_FAILS" "$DOCTOR_WARNS"
  [ "$DOCTOR_FAILS" -eq 0 ]
}
