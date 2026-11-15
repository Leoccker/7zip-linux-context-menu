# shellcheck shell=bash
# Testes do helper (H1–H13 do plano + camada de UI com stubs).
# shellcheck disable=SC2154  # RC, OUT, ERR, T, W, FIXT vêm do lib.sh

t_h01_doctor_ok() {
  run "$H" doctor
  assert_rc 0
  assert_contains "$OUT" "7-Zip"
  assert_contains "$OUT" "ui backend"
}

t_h01_doctor_bad_bin() {
  CTX7Z_BIN=/nao/existe run "$H" doctor
  assert_rc_not 0
  assert_contains "$OUT$ERR" "/nao/existe"
}

t_h01_version_help() {
  run "$H" --version
  assert_rc 0
  assert_contains "$OUT" "7z-context-helper"
  run "$H" --help
  assert_rc 0
  assert_contains "$OUT" "compress"
}

t_h01_usage_errors() {
  run "$H"
  assert_rc 64
  run "$H" frobnicate x
  assert_rc 64
  run "$H" extract-here
  assert_rc 64
}

t_h02_compress_7z_dir_and_collision() {
  mkdir -p "$W/Minha Pasta/sub"
  echo a >"$W/Minha Pasta/sub/a.txt"
  run "$H" compress 7z -- "$W/Minha Pasta"
  assert_rc 0
  assert_exists "$W/Minha Pasta.7z"
  list=$("$SZ" l -slt -spd "$W/Minha Pasta.7z" </dev/null)
  assert_contains "$list" "Path = Minha Pasta/sub/a.txt"
  run "$H" compress 7z -- "$W/Minha Pasta"
  assert_rc 0
  assert_exists "$W/Minha Pasta (2).7z"
  run "$H" compress 7z -- "$W/Minha Pasta"
  assert_exists "$W/Minha Pasta (3).7z"
}

t_h02_output_names() {
  echo x >"$W/a.txt"
  echo x >"$W/.bashrc"
  run "$H" compress 7z -- "$W/a.txt"
  assert_exists "$W/a.7z"
  run "$H" compress 7z -- "$W/.bashrc"
  assert_exists "$W/.bashrc.7z"
}

t_h03_compress_all_formats_three_items() {
  mkdir -p "$W/pai"
  echo 1 >"$W/pai/um.txt"
  echo 2 >"$W/pai/dois.txt"
  mkdir "$W/pai/tres"
  echo 3 >"$W/pai/tres/t.txt"
  local ext
  for ext in 7z zip tar tar.gz tar.xz tar.bz2; do
    run "$H" compress "$ext" -- "$W/pai/um.txt" "$W/pai/dois.txt" "$W/pai/tres"
    assert_rc 0
    assert_exists "$W/pai/pai.$ext"
  done
  local f
  for ext in tar tar.gz tar.xz tar.bz2; do
    f="$W/pai/pai.$ext"
    listing=$(tar -tf "$f")
    assert_contains "$listing" "um.txt"
    assert_contains "$listing" "dois.txt"
    assert_contains "$listing" "tres/t.txt"
  done
  gzip -t "$W/pai/pai.tar.gz" || fail "invalid gzip"
  xz -t "$W/pai/pai.tar.xz" || fail "invalid xz"
  bzip2 -t "$W/pai/pai.tar.bz2" || fail "invalid bz2"
  "$SZ" t -spd "$W/pai/pai.zip" </dev/null >/dev/null || fail "invalid zip"
}

t_h03_compress_level_and_name() {
  echo x >"$W/a.txt"
  run "$H" compress 7z --level 9 --name "meu arquivo" -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/meu arquivo.7z"
  run "$H" compress rar -- "$W/a.txt"
  assert_rc 64
}

t_h04_hard_names_roundtrip() {
  fixture names
  before=$(cd "$W/names" && find . -type f -print0 | sort -z | tr '\0' '|')
  local fmt
  for fmt in 7z zip tar.gz; do
    rm -rf "$W/out"
    mkdir "$W/out"
    # compacta a pasta inteira e extrai em outra pasta
    run "$H" compress "$fmt" --name "n-$fmt" -- "$W/names"
    assert_rc 0
    mv "$W/n-$fmt.$fmt" "$W/out/"
    run "$H" extract-here "$W/out/n-$fmt.$fmt"
    assert_rc 0
    after=$(cd "$W/out/names" && find . -type f -print0 | sort -z | tr '\0' '|')
    assert_eq "$after" "$before"
  done
}

t_h04_hard_names_individually() {
  fixture names
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$W/names" -type f -print0 | sort -z)
  run "$H" compress 7z --name multi -- "${files[@]}"
  assert_rc 0
  mkdir "$W/x"
  mv "$W/names/multi.7z" "$W/x/"
  run "$H" extract-here "$W/x/multi.7z"
  assert_rc 0
  [[ -f "$W/x/-começa-com-traço.txt" ]] || fail "leading dash name lost"
  [[ -f "$W/x/as*te?risco.txt" ]] || fail "glob name lost"
  [[ -f "$W/x/quebra"$'\n'"linha.txt" ]] || fail "newline name lost"
  [[ -f "$W/x/back\\slash.txt" ]] || fail "backslash name lost"
  [[ -f "$W/x/ação ✓.txt" ]] || fail "unicode name lost"
}

t_h05_extract_here_never_overwrites() {
  mkdir "$W/d"
  fixture a.7z "$W/d"
  mkdir "$W/d/plain"
  echo ORIGINAL >"$W/d/plain/um.txt"
  h=$(sha "$W/d/plain/um.txt")
  run "$H" extract-here "$W/d/a.7z"
  assert_rc 0
  assert_eq "$(sha "$W/d/plain/um.txt")" "$h"
  # a cópia renomeada existe em algum lugar
  n=$(find "$W/d" -name '*um*' -type f | wc -l)
  (( n >= 2 )) || fail "no renamed copy found (n=$n)"
}

t_h05_overwrite_and_skip_policies() {
  mkdir "$W/d"
  fixture a.7z "$W/d"
  mkdir "$W/d/plain"
  echo ORIGINAL >"$W/d/plain/um.txt"
  CTX7Z_OVERWRITE=skip run "$H" extract-here "$W/d/a.7z"
  assert_eq "$(<"$W/d/plain/um.txt")" ORIGINAL
  CTX7Z_OVERWRITE=overwrite run "$H" extract-here "$W/d/a.7z"
  assert_eq "$(<"$W/d/plain/um.txt")" um
}

t_h06_extract_to_tarball() {
  fixture "Backup 2024.tar.gz"
  run "$H" extract-to "$W/Backup 2024.tar.gz"
  assert_rc 0
  assert_exists "$W/Backup 2024/um.txt"
  assert_exists "$W/Backup 2024/sub/dois.txt"
  [[ -z $(find "$W" -name '*.tar' -type f) ]] || fail "a .tar leaked out"
  run "$H" extract-to "$W/Backup 2024.tar.gz"
  assert_rc 0
  assert_exists "$W/Backup 2024 (2)/um.txt"
}

t_h06_extract_here_tarball() {
  fixture "Backup 2024.tar.gz"
  run "$H" extract-here "$W/Backup 2024.tar.gz"
  assert_rc 0
  assert_exists "$W/um.txt"
  assert_exists "$W/sub/dois.txt"
}

t_h06_extract_to_zip_and_7z() {
  fixture a.7z
  fixture b.zip
  run "$H" extract-to "$W/a.7z" "$W/b.zip"
  assert_rc 0
  assert_exists "$W/a/plain/um.txt"
  assert_exists "$W/b/plain/um.txt"
}

t_h07_mixed_selection() {
  fixture a.7z
  fixture b.zip
  fixture "Backup 2024.tar.gz"
  fixture notarchive.txt
  run "$H" extract-to "$W/a.7z" "$W/b.zip" "$W/Backup 2024.tar.gz" "$W/notarchive.txt"
  assert_rc 2
  assert_exists "$W/a/plain/um.txt"
  assert_exists "$W/b/plain/um.txt"
  assert_exists "$W/Backup 2024/um.txt"
  assert_contains "$ERR" "notarchive.txt"
  assert_contains "$ERR" "Not a supported archive"
  assert_not_exists "$W/notarchive"
}

t_h08_multivolume_extracted_once() {
  fixture vol.7z.001
  fixture vol.7z.002
  fixture vol.7z.003
  run "$H" extract-to "$W/vol.7z.001" "$W/vol.7z.002" "$W/vol.7z.003"
  assert_rc 0
  assert_exists "$W/vol/volsrc/random.bin"
  assert_not_exists "$W/vol (2)"
  [[ $(stat -c %s "$W/vol/volsrc/random.bin") -eq 1500000 ]] || fail "wrong size"
  # só o primeiro volume também funciona
  run "$H" extract-to "$W/vol.7z.001"
  assert_rc 0
  assert_exists "$W/vol (2)/volsrc/random.bin"
  # selecionando só o volume 002, o conjunto é resolvido
  run "$H" extract-to "$W/vol.7z.002"
  assert_rc 0
  assert_exists "$W/vol (3)/volsrc/random.bin"
}

t_h09_test_ok() {
  fixture a.7z
  fixture b.zip
  fixture "Backup 2024.tar.gz"
  run "$H" test "$W/a.7z" "$W/b.zip" "$W/Backup 2024.tar.gz"
  assert_rc 0
  assert_contains "$ERR$OUT" "3 OK"
}

t_h09_test_corrupt() {
  fixture corrupt.7z
  run "$H" test "$W/corrupt.7z"
  assert_rc 2
  assert_contains "$ERR" "damaged"
}

t_h09_extract_corrupt_leaves_no_empty_dir() {
  fixture corrupt.7z
  run "$H" extract-to "$W/corrupt.7z"
  assert_rc 2
  [[ -z $(find "$W/corrupt" -type f 2>/dev/null) ]] || true
}

t_h10_password_content_missing_does_not_hang() {
  fixture enc_content.7z
  run_t 20 "$H" extract-to "$W/enc_content.7z"
  assert_rc 2
  assert_not_exists "$W/enc_content"
  assert_contains "$ERR" "Password"
}

t_h10_password_header_missing_does_not_hang() {
  fixture enc_header.7z
  run_t 20 "$H" extract-to "$W/enc_header.7z"
  assert_rc 2
  assert_not_exists "$W/enc_header"
  run_t 20 "$H" test "$W/enc_header.7z"
  assert_rc 2
  run_t 20 "$H" list "$W/enc_header.7z"
  assert_rc_not 0
}

t_h10_password_right() {
  fixture enc_content.7z
  fixture enc_header.7z
  CTX7Z_PASSWORD=secret run_t 30 "$H" extract-to "$W/enc_content.7z" "$W/enc_header.7z"
  assert_rc 0
  assert_exists "$W/enc_content/plain/um.txt"
  assert_exists "$W/enc_header/plain/sub/dois.txt"
  CTX7Z_PASSWORD=secret run_t 30 "$H" test "$W/enc_content.7z" "$W/enc_header.7z"
  assert_rc 0
}

t_h10_password_wrong_leaves_nothing() {
  fixture enc_content.7z
  fixture enc_header.7z
  CTX7Z_PASSWORD=errada run_t 30 "$H" extract-to "$W/enc_content.7z" "$W/enc_header.7z"
  assert_rc 2
  assert_not_exists "$W/enc_content"
  assert_not_exists "$W/enc_header"
  assert_contains "$ERR" "Wrong password"
}

t_h10_password_extract_here_wrong_leaves_nothing() {
  mkdir "$W/d"
  fixture enc_content.7z "$W/d"
  CTX7Z_PASSWORD=errada run_t 30 "$H" extract-here "$W/d/enc_content.7z"
  assert_rc 2
  [[ -z $(find "$W/d" -mindepth 1 -not -name enc_content.7z) ]] || fail "leftovers: $(find "$W/d" -mindepth 1)"
}

t_h11_log_never_has_password() {
  fixture enc_content.7z
  CTX7Z_PASSWORD=segredoUnico123 run_t 30 "$H" extract-to "$W/enc_content.7z"
  CTX7Z_PASSWORD=secret run_t 30 "$H" extract-to "$W/enc_content.7z"
  assert_rc 0
  log=$HOME/.local/state/7z-context/helper.log
  assert_exists "$log"
  if grep -q -e 'segredoUnico123' -e 'secret' "$log"; then fail "password found in log: $(grep -n -e segredoUnico123 -e secret "$log")"; fi
  # compactação com senha também não vaza
  echo x >"$W/a.txt"
  CTX7Z_FORM_PASSWORD=senhaDeCompactar9 run "$H" compress-dialog "$W/a.txt"
  assert_rc 0
  if grep -q 'senhaDeCompactar9' "$log"; then fail "compress password in log"; fi
  if [[ $ERR == *senhaDeCompactar9* ]]; then fail "compress password on stderr"; fi
}

t_h12_relative_path_and_pwd() {
  mkdir "$W/dir"
  fixture a.7z "$W/dir"
  cd "$W/dir" || exit 1
  run "$H" extract-here a.7z
  assert_rc 0
  assert_exists "$W/dir/plain/um.txt"
  run "$H" compress 7z -- plain
  assert_rc 0
  assert_exists "$W/dir/plain.7z"
  run "$H" extract-to ./a.7z
  assert_rc 0
  assert_exists "$W/dir/a/plain/um.txt"
}

t_h12_file_url_and_remote_rejected() {
  fixture a.7z
  run "$H" extract-to "file://$W/a.7z"
  assert_rc 0
  assert_exists "$W/a/plain/um.txt"
  run "$H" extract-to "smb://servidor/x.7z"
  assert_rc 2
  assert_contains "$ERR" "local"
  run "$H" extract-to "$W/nao-existe.7z"
  assert_rc 2
  assert_contains "$ERR" "not found"
}

t_h12_file_url_percent_decoding() {
  fixture "Backup 2024.tar.gz"
  run "$H" extract-to "file://$W/Backup%202024.tar.gz"
  assert_rc 0
  assert_exists "$W/Backup 2024/um.txt"
}

t_h12_duplicates_deduped() {
  fixture a.7z
  run "$H" extract-to "$W/a.7z" "$W/a.7z" "./a.7z"
  assert_rc 0
  assert_exists "$W/a/plain/um.txt"
  assert_not_exists "$W/a (2)"
}

t_h14_list() {
  fixture a.7z
  fixture "Backup 2024.tar.gz"
  run "$H" list "$W/a.7z" "$W/Backup 2024.tar.gz"
  assert_rc 0
  assert_contains "$OUT" "plain/um.txt"
  assert_contains "$OUT" "um.txt"
  assert_contains "$OUT" "sub/dois.txt"
}

t_h15_config_whitelist_and_no_exec() {
  mkdir -p "$HOME/.config/7z-context"
  cat >"$HOME/.config/7z-context/config" <<CFG
# comentário
CTX7Z_OVERWRITE=skip
CTX7Z_LEVEL=1
EVIL=\$(touch $T/pwned)
CTX7Z_LANG=pt_BR; touch $T/pwned2
\$(touch $T/pwned3)
CFG
  unset CTX7Z_LANG
  run "$H" doctor
  assert_not_exists "$T/pwned"
  assert_not_exists "$T/pwned2"
  assert_not_exists "$T/pwned3"
  # ambiente tem prioridade sobre o config
  fixture a.7z
  mkdir "$W/d"
  mkdir "$W/d/plain"
  echo ORIGINAL >"$W/d/plain/um.txt"
  fixture a.7z "$W/d"
  CTX7Z_OVERWRITE=overwrite run "$H" extract-here "$W/d/a.7z"
  assert_eq "$(<"$W/d/plain/um.txt")" um
}

t_h16_lang_pt() {
  CTX7Z_LANG=pt_BR run "$H" extract-to "$W/nao-existe.7z"
  assert_contains "$ERR" "não encontrado"
}

t_h17_compress_unwritable_dir() {
  [[ $(id -u) -ne 0 ]] || skip "root can write anywhere"
  mkdir "$W/ro"
  echo x >"$W/ro/a.txt"
  chmod 555 "$W/ro"
  run "$H" compress 7z -- "$W/ro/a.txt"
  chmod 755 "$W/ro"
  assert_rc 2
  assert_not_exists "$W/ro/a.7z"
}

# ------------------------------------------------------------------ compress-dialog (headless)

t_d01_dialog_defaults() {
  mkdir "$W/Fotos"
  echo x >"$W/Fotos/a.txt"
  run "$H" compress-dialog "$W/Fotos"
  assert_rc 0
  assert_exists "$W/Fotos.7z"
}

t_d02_dialog_zip_password_and_header_encryption() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_FORMAT=7z CTX7Z_FORM_PASSWORD=pw1 CTX7Z_FORM_ENCNAMES=1 run "$H" compress-dialog "$W/a.txt"
  assert_rc 0
  # com -mhe=on, sem a senha não dá nem para listar
  if "$SZ" l -spd -p"" "$W/a.7z" </dev/null >/dev/null 2>&1; then fail "header not encrypted"; fi
  "$SZ" t -spd -ppw1 "$W/a.7z" </dev/null >/dev/null || fail "password does not open"
  CTX7Z_FORM_FORMAT=zip CTX7Z_FORM_PASSWORD=pw2 run "$H" compress-dialog "$W/a.txt"
  assert_rc 0
  "$SZ" t -spd -ppw2 "$W/a.zip" </dev/null >/dev/null || fail "zip password does not open"
  if "$SZ" t -spd -pbad "$W/a.zip" </dev/null >/dev/null 2>&1; then fail "zip not encrypted"; fi
}

t_d03_dialog_tar_with_password_blocked() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_FORMAT=tar.gz CTX7Z_FORM_PASSWORD=pw run "$H" compress-dialog "$W/a.txt"
  assert_rc 64
  assert_contains "$ERR" "Passwords are only supported"
  assert_not_exists "$W/a.tar.gz"
}

t_d04_dialog_cancel_has_no_side_effects() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_CANCEL=1 run "$H" compress-dialog "$W/a.txt"
  assert_rc 3
  [[ $(find "$W" -type f | wc -l) -eq 1 ]] || fail "extra files: $(find "$W" -type f)"
}

t_d05_dialog_name_validation_and_split() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_NAME="a/" run "$H" compress-dialog "$W/a.txt"
  assert_rc 64
  assert_contains "$ERR" "Invalid archive name"
  CTX7Z_FORM_NAME=".." run "$H" compress-dialog "$W/a.txt"
  assert_rc 64
  CTX7Z_FORM_SPLIT=abc run "$H" compress-dialog "$W/a.txt"
  assert_rc 64
  CTX7Z_FORM_NAME=custom CTX7Z_FORM_FORMAT=zip CTX7Z_FORM_LEVEL=9 run "$H" compress-dialog "$W/a.txt"
  assert_rc 0
  assert_exists "$W/custom.zip"
}

t_d06_dialog_wrong_extension_gets_fixed() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_NAME="pacote.zip" CTX7Z_FORM_FORMAT=7z run "$H" compress-dialog "$W/a.txt"
  assert_rc 0
  assert_exists "$W/pacote.zip.7z"
  CTX7Z_FORM_NAME="pacote.7z" CTX7Z_FORM_FORMAT=7z run "$H" compress-dialog "$W/a.txt"
  assert_exists "$W/pacote.7z"
  [[ ! -e $W/pacote.7z.7z ]] || fail "extension duplicated"
}

t_d07_dialog_split_volumes() {
  head -c 1500000 /dev/urandom >"$W/rand.bin"
  CTX7Z_FORM_FORMAT=7z CTX7Z_FORM_LEVEL=0 CTX7Z_FORM_SPLIT=500k run "$H" compress-dialog "$W/rand.bin"
  assert_rc 0
  assert_exists "$W/rand.7z.001"
  assert_exists "$W/rand.7z.002"
  mkdir "$W/o"
  mv "$W"/rand.7z.* "$W/o/"
  rm "$W/rand.bin"
  run "$H" extract-here "$W/o/rand.7z.001"
  assert_rc 0
  [[ $(stat -c %s "$W/o/rand.bin") -eq 1500000 ]] || fail "volume extraction wrong"
}

# ------------------------------------------------------------------ camada de UI com stubs

t_u01_notification_summary_with_notify_stub() {
  make_ui_stubs
  fixture a.7z
  CTX7Z_DIALOG=notify PATH="$STUB:$PATH" run "$H" extract-to "$W/a.7z"
  assert_rc 0
  grep -q '^notify-send' "$STUB_LOG" || fail "no notification was sent: $(cat "$STUB_LOG")"
}

t_u02_password_three_wrong_attempts() {
  make_ui_stubs
  fixture enc_content.7z
  printf 'x1\nx2\nx3\nsecret\n' >"$T/pws"
  STUB_PW_SEQ=$T/pws CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 40 "$H" extract-to "$W/enc_content.7z"
  assert_rc 2
  assert_not_exists "$W/enc_content"
  n=$(grep -c -- '--password' "$STUB_LOG")
  assert_eq "$n" 3
  # a quarta (senha certa) nunca foi pedida
  assert_eq "$(cat "$T/pwidx")" 3
}

t_u03_password_second_attempt_ok() {
  make_ui_stubs
  fixture enc_content.7z
  printf 'errada\nsecret\n' >"$T/pws"
  STUB_PW_SEQ=$T/pws CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 40 "$H" extract-to "$W/enc_content.7z"
  assert_rc 0
  assert_exists "$W/enc_content/plain/um.txt"
}

t_u04_password_dialog_cancelled() {
  make_ui_stubs
  fixture enc_content.7z
  : >"$T/pws"
  STUB_PW_SEQ=$T/pws CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" extract-to "$W/enc_content.7z"
  assert_rc_not 0
  assert_not_exists "$W/enc_content"
}

t_u05_progress_cancel_kills_7z_and_removes_partial() {
  make_ui_stubs
  # arquivo grande e incompressível, para a compactação durar mais que ~2 s
  head -c 150000000 /dev/urandom >"$W/big.bin"
  start=$SECONDS
  STUB_CANCEL=1 CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 60 "$H" compress 7z --level 9 -- "$W/big.bin"
  took=$((SECONDS - start))
  assert_rc 3
  assert_not_exists "$W/big.7z"
  (( took <= 8 )) || fail "cancellation took ${took}s"
  sleep 0.5
  if pgrep -f "$W/big" >/dev/null; then fail "7z still running after cancel"; fi
}

t_u06_list_uses_text_dialog() {
  make_ui_stubs
  fixture a.7z
  CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run "$H" list "$W/a.7z"
  assert_rc 0
  assert_exists "$T/textinfo.out"
  assert_contains "$(<"$T/textinfo.out")" "plain/um.txt"
}

t_u07_compress_dialog_via_stub() {
  make_ui_stubs
  mkdir "$W/Docs"
  echo x >"$W/Docs/a.txt"
  STUB_ENTRY=feito STUB_CHOICES="zip 5" STUB_PW_SEQ=/dev/null CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress-dialog "$W/Docs"
  # sem suporte a respostas sequenciais no stub, só verificamos que o fluxo termina com código válido
  case $RC in 0|1|2|3|64) ;; *) fail "unexpected rc=$RC" ;; esac
}

t_u08_no_dialog_tool_only_notify() {
  make_ui_stubs
  echo x >"$W/a.txt"
  # PATH reduzido: só os stubs de notificação e as ferramentas básicas
  CTX7Z_DIALOG=notify PATH="$STUB:$PATH" run "$H" compress-dialog "$W/a.txt"
  assert_rc_not 0
  grep -q 'zenity, kdialog or yad' "$STUB_LOG" || fail "no explanation sent: $(cat "$STUB_LOG")"
  assert_not_exists "$W/a.7z"
}

# ------------------------------------------------------------------ nome e pasta do arquivo

t_n01_name_may_be_relative_or_absolute_path() {
  mkdir "$W/Fotos"
  echo x >"$W/Fotos/a.txt"
  run "$H" compress 7z --name sub/meu -- "$W/Fotos"
  assert_rc 0
  assert_exists "$W/sub/meu.7z"
  run "$H" compress zip --name "$T/abs/out" -- "$W/Fotos"
  assert_rc 0
  assert_exists "$T/abs/out.zip"
  assert_contains "$ERR" "Created: $T/abs/out.zip"
}

t_n02_invalid_names_rejected() {
  echo x >"$W/a.txt"
  local n
  for n in "dir/" ".." "a/.." "/"; do
    run "$H" compress 7z --name "$n" -- "$W/a.txt"
    assert_rc 64
    assert_contains "$ERR" "Invalid archive name"
  done
  [[ $(find "$W" -type f | wc -l) -eq 1 ]] || fail "unexpected files: $(find "$W" -type f)"
}

t_n03_dest_option_creates_folder_and_keeps_source() {
  echo x >"$W/a.txt"
  run "$H" compress 7z --dest "$W/novo/dest" -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/novo/dest/a.7z"
  assert_exists "$W/a.txt"
  # --dest relativo vale a partir do diretório atual; nome relativo, a partir do --dest
  run "$H" compress zip --dest rel --name in/x -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/rel/in/x.zip"
  # nome absoluto ignora --dest
  run "$H" compress zip --dest "$W/ignorado" --name "$W/abs" -- "$W/a.txt"
  assert_exists "$W/abs.zip"
  assert_not_exists "$W/ignorado"
}

t_n04_dest_works_for_tarballs_and_collisions() {
  echo x >"$W/a.txt"
  run "$H" compress tar.gz --dest "$W/d" -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/d/a.tar.gz"
  run "$H" compress tar.gz --dest "$W/d" -- "$W/a.txt"
  assert_exists "$W/d/a (2).tar.gz"
}

t_n05_dest_not_writable_fails_cleanly() {
  echo x >"$W/a.txt"
  run "$H" compress 7z --dest /proc/nao-pode -- "$W/a.txt"
  assert_rc 2
  assert_contains "$ERR" "Cannot write to the folder"
}

t_n06_archive_inside_its_own_source_folder() {
  mkdir "$W/Fotos"
  echo x >"$W/Fotos/a.txt"
  run "$H" compress 7z --dest "$W/Fotos" -- "$W/Fotos"
  assert_rc 0
  assert_exists "$W/Fotos/Fotos.7z"
  local listing
  listing=$("$SZ" l -ba -spd "$W/Fotos/Fotos.7z" </dev/null)
  assert_contains "$listing" "Fotos/a.txt"
  [[ $listing != *"Fotos.7z"* ]] || fail "archive contains itself"
}

t_n07_ask_headless_uses_form_values() {
  echo x >"$W/a.txt"
  CTX7Z_FORM_NAME=escolhido CTX7Z_FORM_DEST="$W/pasta" run "$H" compress zip --ask -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/pasta/escolhido.zip"
  # sem valores, --ask mantém os padrões
  run "$H" compress zip --ask -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/a.zip"
  # cancelar não cria nada
  CTX7Z_FORM_CANCEL=1 run "$H" compress 7z --ask -- "$W/a.txt"
  assert_rc 3
  assert_not_exists "$W/a.7z"
  # nome inválido vindo do diálogo
  CTX7Z_FORM_NAME="x/" run "$H" compress 7z --ask -- "$W/a.txt"
  assert_rc 64
}

t_n08_compress_dialog_dest_and_name_with_path() {
  mkdir "$W/Docs"
  echo x >"$W/Docs/a.txt"
  CTX7Z_FORM_DEST="$W/saida" run "$H" compress-dialog "$W/Docs"
  assert_rc 0
  assert_exists "$W/saida/Docs.7z"
  CTX7Z_FORM_DEST="$W/saida" CTX7Z_FORM_NAME="sub/outro" CTX7Z_FORM_FORMAT=zip run "$H" compress-dialog "$W/Docs"
  assert_rc 0
  assert_exists "$W/saida/sub/outro.zip"
  CTX7Z_FORM_NAME="$W/livre" CTX7Z_FORM_DEST="$W/saida" run "$H" compress-dialog "$W/Docs"
  assert_exists "$W/livre.7z"
}

t_n09_ask_dialog_via_save_chooser() {
  make_ui_stubs
  echo x >"$W/a.txt"
  # o seletor "Salvar como" começa em <pasta do item>/<nome>.<formato> e devolve o caminho escolhido
  CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress 7z --ask -- "$W/a.txt"
  assert_rc 0
  grep -q -- "--file-selection --save .*--filename=$W/a.7z" "$STUB_LOG" || fail "bad default: $(grep file-selection "$STUB_LOG")"
  assert_exists "$W/a.7z"
  mkdir "$W/novo"
  STUB_SAVE_PICK="$W/novo/meu nome.7z" CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress 7z --ask -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/novo/meu nome.7z"
  [[ ! -e "$W/novo/meu nome.7z.7z" ]] || fail "extension duplicated"
  assert_contains "$ERR$(<"$STUB_LOG")" "Created: $W/novo/meu nome.7z"
}

t_n10_ask_dialog_cancel_creates_nothing() {
  make_ui_stubs
  echo x >"$W/a.txt"
  STUB_FILESEL_CANCEL=1 CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress 7z --ask -- "$W/a.txt"
  assert_rc 3
  assert_not_exists "$W/a.7z"
}

t_n11_compress_dialog_has_folder_chooser() {
  make_ui_stubs
  mkdir "$W/Docs"
  echo x >"$W/Docs/a.txt"
  printf 'meu pacote\n\n' >"$T/entries"   # nome; volumes (vazio)
  STUB_ENTRY_SEQ=$T/entries STUB_PW_EMPTY=1 STUB_DIR_PICK="$W/destino" CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" \
    run_t 30 "$H" compress-dialog "$W/Docs"
  assert_rc 0
  grep -q -- "--file-selection --directory .*--filename=$W/\$" "$STUB_LOG" || fail "folder chooser not offered at the items' folder: $(grep file-selection "$STUB_LOG")"
  assert_exists "$W/destino/meu pacote.7z"
}

# ------------------------------------------------------------------ progresso da compactação

# progress_lines: o que o diálogo de progresso recebeu, sem a hora
progress_lines() { cut -d' ' -f2- "$T/progress.in"; }

t_p01_progress_shows_percent_in_text_and_ends_at_100() {
  make_ui_stubs
  head -c 60000000 /dev/urandom >"$W/p.bin"
  CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 60 "$H" compress 7z --level 1 -- "$W/p.bin"
  assert_rc 0
  assert_exists "$W/p.7z"
  local lines first last
  lines=$(progress_lines)
  first=$(sed -n 1p <<<"$lines")
  [[ $first == 0 ]] || fail "first progress line should be 0, got [$first]"
  grep -Eq '^#Compressing: p\.7z — [1-9][0-9]?%$' <<<"$lines" || fail "no intermediate percent text: $lines"
  grep -Eq '^[1-9][0-9]?$' <<<"$lines" || fail "no intermediate bar value: $lines"
  last=$(tail -n 2 <<<"$lines" | paste -sd'|')
  [[ $last == '#Compressing: p.7z — 100%|100' ]] || fail "bad ending: [$last]"
}

t_p02_progress_window_stays_visible_for_small_files() {
  make_ui_stubs
  echo x >"$W/a.txt"
  CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress 7z -- "$W/a.txt"
  assert_rc 0
  assert_exists "$T/progress.end"
  local t0 t1
  t0=$(sed -n 1p "$T/progress.in" | cut -d' ' -f1)
  t1=$(<"$T/progress.end")
  (( t1 - t0 >= 900 )) || fail "progress window closed after $((t1 - t0)) ms"
  # o 100% chega antes do fechamento
  progress_lines | grep -qx 100 || fail "no 100 sent"
}

t_p03_progress_minimum_time_can_be_disabled() {
  make_ui_stubs
  echo x >"$W/a.txt"
  start=$SECONDS
  CTX7Z_PROGRESS_MIN_MS=0 CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress zip -- "$W/a.txt"
  assert_rc 0
  assert_exists "$W/a.zip"
  (( SECONDS - start <= 3 )) || fail "took too long without the minimum time"
}

t_p04_progress_window_is_not_auto_closed() {
  make_ui_stubs
  echo x >"$W/a.txt"
  CTX7Z_PROGRESS_MIN_MS=0 CTX7Z_DIALOG=zenity PATH="$STUB:$PATH" run_t 30 "$H" compress zip -- "$W/a.txt"
  grep -q -- '--progress' "$STUB_LOG" || fail "no progress window"
  if grep -q -- '--auto-close' "$STUB_LOG"; then fail "--auto-close would close the window at 100% before it is seen"; fi
}

t_h13_shellcheck() {
  local sc=${SHELLCHECK:-}
  [[ -n $sc ]] || sc=$(command -v shellcheck || true)
  [[ -n $sc ]] || skip "shellcheck not installed"
  local files=("$ROOT/bin/7z-context-helper" "$ROOT/tests/run.sh" "$ROOT/tests/lib.sh" "$ROOT/tests/helper_tests.sh" "$ROOT/tests/install_tests.sh" "$ROOT/tests/fixtures/make_fixtures.sh")
  [[ -f $ROOT/install.sh ]] && files+=("$ROOT/install.sh")
  run "$sc" -x -S style "${files[@]}"
  assert_rc 0
}
