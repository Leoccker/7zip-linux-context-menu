# shellcheck shell=bash
# shellcheck disable=SC2034  # variáveis usadas pelos arquivos de teste que fazem source deste
# Funções de apoio da suíte de testes. Cada teste roda em subshell e usa um
# sandbox próprio (HOME temporário, modo headless).

H=$ROOT/bin/7z-context-helper
INSTALL=$ROOT/install.sh

# binário 7-Zip para verificações independentes do helper
SZ=""
for _c in 7zz 7z 7za; do
  if command -v "$_c" >/dev/null 2>&1; then SZ=$(command -v "$_c"); break; fi
done

make_global_fixtures() {
  FIXT=$TEST_TMP/fixtures
  bash "$ROOT/tests/fixtures/make_fixtures.sh" "$FIXT" >/dev/null 2>&1 || {
    echo "could not build fixtures" >&2
    exit 1
  }
  export FIXT
}

setup_sandbox() {
  T=$(mktemp -d "$TEST_TMP/t.XXXXXX")
  export T
  export HOME=$T/home
  W=$T/work
  mkdir -p "$HOME" "$W"
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CURRENT_DESKTOP DISPLAY WAYLAND_DISPLAY
  unset CTX7Z_ASSUME_NAUTILUS_PYTHON CTX7Z_BIN CTX7Z_PASSWORD CTX7Z_OVERWRITE CTX7Z_LEVEL CTX7Z_SHARE_DIR CTX7Z_DETECTED_FMS
  unset CTX7Z_FORM_NAME CTX7Z_FORM_FORMAT CTX7Z_FORM_LEVEL CTX7Z_FORM_PASSWORD CTX7Z_FORM_ENCNAMES CTX7Z_FORM_SPLIT CTX7Z_FORM_CANCEL
  export CTX7Z_NO_POST=1 CTX7Z_DIALOG=none CTX7Z_LANG=en LANG=C.UTF-8 LC_ALL=C.UTF-8
  cd "$W" || exit 1
}

# copia fixtures para dentro do sandbox
fixture() { cp -a -- "$FIXT/$1" "${2:-$W}/"; }

# run CMD... -> RC, OUT, ERR
run() {
  "$@" >"$T/out" 2>"$T/err" </dev/null
  RC=$?
  OUT=$(<"$T/out")
  ERR=$(<"$T/err")
}

# run_t SEGUNDOS CMD... (com limite de tempo; RC=124 se estourar)
run_t() {
  local s=$1
  shift
  timeout "$s" "$@" >"$T/out" 2>"$T/err" </dev/null
  RC=$?
  OUT=$(<"$T/out")
  ERR=$(<"$T/err")
}

fail() { echo "ASSERT: $*" >&2; exit 1; }
skip() { echo "$*"; exit 77; }

assert_rc() { [[ $RC -eq $1 ]] || fail "expected exit code $1, got $RC
--- stdout:
$OUT
--- stderr:
$ERR"; }
assert_rc_not() { [[ $RC -ne $1 ]] || fail "exit code must not be $1
--- stderr:
$ERR"; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "expected to contain: [$2]
in: [$1]"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail "must not contain: [$2]
in: [$1]"; }
assert_exists() { [[ -e $1 || -L $1 ]] || fail "missing: $1"; }
assert_not_exists() { [[ ! -e $1 && ! -L $1 ]] || fail "should not exist: $1"; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_exec() { [[ -x $1 ]] || fail "not executable: $1"; }

sha() { sha256sum -- "$1" | cut -d' ' -f1; }

# lista de arquivos regulares (nomes-base) sob DIR, separada por NUL e ordenada
names_of() { find "$1" -type f -printf '%f\0' | sort -z; }

# Cria stubs de zenity/notify-send em $T/stubbin para testar a camada de UI.
# Variáveis de controle: STUB_PW_SEQ (arquivo com uma senha por linha),
# STUB_CANCEL=1 (o diálogo de progresso "cancela"), STUB_CHOICES (lista de respostas
# para diálogos de escolha), STUB_QUESTION=0|1 (resposta de sim/não).
make_ui_stubs() {
  STUB=$T/stubbin
  mkdir -p "$STUB"
  export STUB_LOG=$T/stub.log
  : >"$STUB_LOG"
  cat >"$STUB/zenity" <<'STUBEOF'
#!/usr/bin/env bash
echo "zenity $*" >>"$STUB_LOG"
mode=""
entry_text=""
filename=""
rows=()
for a in "$@"; do
  case $a in
    --password) mode=password ;;
    --progress) mode=progress ;;
    --entry) mode=entry ;;
    --list) mode=list ;;
    --text-info) mode=textinfo ;;
    --question) mode=question ;;
    --info|--error|--warning) mode=msg ;;
    --entry-text=*) entry_text=${a#--entry-text=} ;;
    --filename=*) filename=${a#--filename=} ;;
    --*) ;;
    *) rows+=("$a") ;;
  esac
done
dir=$(dirname "$STUB_LOG")
case $mode in
  password)
    idx=$(cat "$dir/pwidx" 2>/dev/null || echo 0)
    echo $((idx + 1)) >"$dir/pwidx"
    line=$(sed -n "$((idx + 1))p" "${STUB_PW_SEQ:-/dev/null}")
    [[ -n $line ]] || exit 1
    printf '%s\n' "$line"
    ;;
  progress)
    if [[ ${STUB_CANCEL:-0} == 1 ]]; then read -r _; exit 1; fi
    cat >/dev/null
    ;;
  entry) printf '%s\n' "${STUB_ENTRY:-$entry_text}" ;;
  list)
    if [[ -n ${STUB_CHOICES:-} ]]; then
      read -r first rest <<<"$STUB_CHOICES"
      echo "$rest" >"$dir/choices.next"
      STUB_CHOICES=$rest
      # persiste o restante para a próxima chamada
      printf '%s\n' "$first"
      echo "$rest" >"$dir/choices"
    else
      for ((i = 0; i + 2 < ${#rows[@]} + 1; i += 3)); do
        if [[ ${rows[i]} == TRUE ]]; then printf '%s\n' "${rows[i + 1]}"; break; fi
      done
    fi
    ;;
  textinfo) cp -- "$filename" "$dir/textinfo.out" ;;
  question) exit "${STUB_QUESTION:-1}" ;;
esac
exit 0
STUBEOF
  cat >"$STUB/notify-send" <<'STUBEOF'
#!/usr/bin/env bash
echo "notify-send $*" >>"$STUB_LOG"
exit 0
STUBEOF
  chmod +x "$STUB/zenity" "$STUB/notify-send"
}
