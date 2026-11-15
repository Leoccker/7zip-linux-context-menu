#!/usr/bin/env bash
# Suíte de testes automatizados do 7z-context (Bash puro; não requer bats).
#
# Uso:
#   tests/run.sh                 roda tudo
#   tests/run.sh PADRÃO          roda só os testes cujo nome casa com o glob *PADRÃO*
#   tests/run.sh --list          lista os testes
#
# Variáveis: SHELLCHECK=/caminho/shellcheck, KEEP=1 (não apaga o diretório temporário)
set -u

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export ROOT
# shellcheck source=/dev/null
source "$ROOT/tests/lib.sh"
# shellcheck source=/dev/null
source "$ROOT/tests/helper_tests.sh"
# shellcheck source=/dev/null
source "$ROOT/tests/install_tests.sh"

mapfile -t TESTS < <(declare -F | awk '{print $3}' | grep '^t_' | sort)

if [[ ${1:-} == --list ]]; then printf '%s\n' "${TESTS[@]}"; exit 0; fi
filter=${1:-}

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/7zctx-tests.XXXXXX")
export TEST_TMP
cleanup() { [[ ${KEEP:-0} == 1 ]] || rm -rf -- "$TEST_TMP"; }
trap cleanup EXIT

make_global_fixtures

pass=0 fail=0 skip=0
failed=()
for t in "${TESTS[@]}"; do
  if [[ -n $filter && $t != *$filter* ]]; then continue; fi
  start=$SECONDS
  setup_sandbox
  ( "$t" ) >"$TEST_TMP/last.out" 2>&1
  rc=$?
  if (( rc == 0 )); then
    printf 'ok      %s (%ds)\n' "$t" $((SECONDS - start))
    pass=$((pass + 1))
  elif (( rc == 77 )); then
    printf 'skip    %s: %s\n' "$t" "$(tail -n 1 "$TEST_TMP/last.out")"
    skip=$((skip + 1))
  else
    printf 'FAIL    %s\n' "$t"
    sed 's/^/        | /' "$TEST_TMP/last.out" | tail -n 25
    fail=$((fail + 1))
    failed+=("$t")
  fi
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
