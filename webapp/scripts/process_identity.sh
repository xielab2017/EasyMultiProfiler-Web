#!/usr/bin/env bash
# Pure command-line ownership check. Fail closed for old relative-path launches.
emp_command_belongs_to_repo() {
  local command_line="$1" root="$2" script expected
  # Rscript execs R with --file= and encodes spaces in that argument as ~+~.
  expected="${root}/webapp/backend/run_api.R"
  case " ${command_line} " in
    *" --file=${expected} "*|*" --file=${expected// /~+~} "*) return 0 ;;
  esac
  for script in backend/run_api.R scripts/static_server.py scripts/emp_gateway.py scripts/public_data_server.py; do
    expected="${root}/webapp/${script}"
    # ps strips Unix argument quoting, but the full absolute script path remains.
    # Require the exact script path with an argument/end boundary on each side.
    case " ${command_line} " in
      *" ${expected} "*|*" \"${expected}\" "*|*" '${expected}' "*) return 0 ;;
    esac
  done
  return 1
}

emp_stop_recorded_process() {
  local pid_file="$1" root="$2" pid attempt
  [[ -f "$pid_file" ]] || return 0
  pid="$(cat "$pid_file")"
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] &&
     emp_command_belongs_to_repo "$(ps -ww -p "$pid" -o args= 2>/dev/null)" "$root"; then
    kill "$pid" 2>/dev/null || true
    for attempt in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if emp_command_belongs_to_repo "$(ps -ww -p "$pid" -o args= 2>/dev/null)" "$root"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}
