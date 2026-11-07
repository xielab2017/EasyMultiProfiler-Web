#!/usr/bin/env bash
# Pure command-line ownership check. Fail closed for old relative-path launches.
emp_command_belongs_to_repo() {
  local command_line="$1" root="$2" script expected
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
