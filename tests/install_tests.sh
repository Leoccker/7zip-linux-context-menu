# shellcheck shell=bash
# Testes do instalador (I1–I7 do plano e extras).
# shellcheck disable=SC2154  # RC, OUT, ERR, T, W, HOME vêm do lib.sh

inst() { run "$INSTALL" "$@"; }

# lista de arquivos regulares sob HOME (ordenada)
home_files() { (cd "$HOME" && find . -type f | sort); }

# arquivos listados no manifesto (tipo F)
manifest_files() { sed -n 's/^F //p' "$1" | sort; }

# parser independente de Exec de Desktop Entry: imprime os argumentos separados por NUL
desktop_exec_args() { # valor_bruto_da_chave_Exec  [substituto_de_%F]
  python3 -I - "$@" <<'PY'
import sys
raw = sys.argv[1]
fcode = sys.argv[2] if len(sys.argv) > 2 else ""
# 1) escapes de string do Desktop Entry
s = ""
i = 0
while i < len(raw):
    c = raw[i]
    if c == "\\" and i + 1 < len(raw):
        n = raw[i + 1]
        s += {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(n, "\\" + n)
        i += 2
    else:
        s += c
        i += 1
# 2) divisão em argumentos (aspas duplas; dentro delas \" \` \$ \\ são escapes)
args, cur, inq, started = [], "", False, False
i = 0
while i < len(s):
    c = s[i]
    if inq:
        if c == "\\" and i + 1 < len(s) and s[i + 1] in '"`$\\':
            cur += s[i + 1]
            i += 2
            continue
        if c == '"':
            inq = False
        else:
            cur += c
    else:
        if c == '"':
            inq = True
            started = True
        elif c in " \t":
            if cur or started:
                args.append(cur)
            cur, started = "", False
        else:
            cur += c
            started = True
    i += 1
if cur or started:
    args.append(cur)
out = []
for a in args:
    if a == "%F":
        out.append(fcode)
    else:
        out.append(a.replace("%%", "%"))
sys.stdout.buffer.write(b"\0".join(x.encode() for x in out))
PY
}

key_value() { # arquivo chave -> primeiro valor
  sed -n "s/^$2=//p" "$1" | head -n 1
}

t_i01_install_all_matches_manifest() {
  inst install --fm all --lang en
  assert_rc 0
  mf=$HOME/.local/share/7z-context/manifest
  assert_exists "$mf"
  expected=$( (manifest_files "$mf"; echo "$mf"; echo "$HOME/.config/Thunar/uca.xml"; echo "$HOME/.config/7z-context/install-prefix") | sort)
  actual=$(find "$HOME" -type f | sort)
  assert_eq "$actual" "$expected"
  for f in "$HOME"/.local/share/kio/servicemenus/*.desktop; do assert_exec "$f"; done
  assert_exec "$HOME/.local/bin/7z-context-helper"
  assert_exec "$HOME/.local/share/nautilus/scripts/7-Zip/Extract here"
  assert_exec "$HOME/.config/caja/scripts/7-Zip/Extract here"
  assert_eq "$(find "$HOME/.local/share/kio/servicemenus" -type f | wc -l)" 2
  assert_eq "$(find "$HOME/.local/share/nemo/actions" -type f | wc -l)" 8
  assert_eq "$(find "$HOME/.local/share/file-manager/actions" -type f | wc -l)" 9
  assert_eq "$(find "$HOME/.local/share/nautilus/scripts/7-Zip" -type f | wc -l)" 8
}

t_i01_validators() {
  inst install --fm all --lang pt_BR
  assert_rc 0
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$HOME/.config/Thunar/uca.xml" || fail "uca.xml is not well-formed"
  fi
  if command -v desktop-file-validate >/dev/null 2>&1; then
    local f
    for f in "$HOME"/.local/share/kio/servicemenus/*.desktop; do
      out=$(desktop-file-validate "$f" 2>&1) || true
      # só erros reais contam; avisos/hints sobre chaves X-KDE são aceitáveis
      # (Type=Service é a convenção do KDE para service menus; o validador genérico não a conhece)
      if grep -E ': error:' <<<"$out" | grep -v -e 'X-KDE' -e 'KonqPopupMenu' -e 'type is "Service"' -e 'all/allfiles' >/dev/null; then
        fail "desktop-file-validate: $out"
      fi
    done
  fi
  # nenhum placeholder sobrando
  if grep -rEl '@[A-Z_]+@' "$HOME" 2>/dev/null | grep -v '/7z-context-helper$'; then fail "unreplaced placeholder"; fi
}

t_i01_labels_follow_language() {
  inst install --fm nautilus,thunar,dolphin --lang pt_BR
  assert_rc 0
  assert_exists "$HOME/.local/share/nautilus/scripts/7-Zip/Extrair aqui"
  assert_contains "$(<"$HOME/.config/Thunar/uca.xml")" "<name>Extrair aqui</name>"
  assert_contains "$(<"$HOME/.local/share/kio/servicemenus/7z-context-archives.desktop")" "Name[pt_BR]=Extrair aqui"
  inst install --fm nautilus --lang en
  assert_exists "$HOME/.local/share/nautilus/scripts/7-Zip/Extract here"
  assert_not_exists "$HOME/.local/share/nautilus/scripts/7-Zip/Extrair aqui"
}

t_i02_thunar_merge_preserves_user_actions() {
  mkdir -p "$HOME/.config/Thunar"
  cat >"$HOME/.config/Thunar/uca.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions>
  <!-- minhas ações -->
  <action>
    <icon>utilities-terminal</icon>
    <name>Open Terminal Here</name>
    <unique-id>1234-1</unique-id>
    <command>exo-open --working-directory %f --launch TerminalEmulator</command>
    <description>Example for a custom action</description>
    <patterns>*</patterns>
    <startup-notify/>
    <directories/>
  </action>
  <action>
    <icon></icon>
    <name>Meu &amp; script</name>
    <unique-id>1234-2</unique-id>
    <command>/home/x/meu\ script.sh %F</command>
    <description></description>
    <patterns>*.txt</patterns>
    <text-files/>
  </action>
</actions>
XML
  cp "$HOME/.config/Thunar/uca.xml" "$T/original.xml"
  inst install --fm thunar --lang en
  assert_rc 0
  cnt=$(python3 -I - "$HOME/.config/Thunar/uca.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
ids = [a.findtext("unique-id") for a in r.findall("action")]
print(len(ids), ids.count("1234-1"), ids.count("1234-2"), sum(i.startswith("7zctx-") for i in ids))
PY
)
  assert_eq "$cnt" "10 1 1 8"
  grep -q 'minhas ações' "$HOME/.config/Thunar/uca.xml" || fail "user comment lost"
  assert_exists "$HOME/.config/Thunar/uca.xml.7zctx.bak"
  inst uninstall
  assert_rc 0
  same=$(python3 -I - "$T/original.xml" "$HOME/.config/Thunar/uca.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
def norm(e):
    return (e.tag, (e.text or "").strip(), tuple(sorted(e.attrib.items())), tuple(norm(c) for c in e))
a = ET.parse(sys.argv[1]).getroot()
b = ET.parse(sys.argv[2]).getroot()
print("same" if norm(a) == norm(b) else "different")
PY
)
  assert_eq "$same" same
  assert_not_exists "$HOME/.config/Thunar/uca.xml.7zctx.bak"
}

t_i03_install_twice_is_idempotent() {
  inst install --fm all --lang en
  assert_rc 0
  first=$(home_files)
  cp "$HOME/.config/Thunar/uca.xml" "$T/uca.after1"
  inst install --fm all --lang en
  assert_rc 0
  assert_eq "$(home_files)" "$first"
  n=$(grep -c '<unique-id>7zctx-' "$HOME/.config/Thunar/uca.xml")
  assert_eq "$n" 8
  assert_eq "$(grep -c '^F ' "$HOME/.local/share/7z-context/manifest")" "$(sort -u "$HOME/.local/share/7z-context/manifest" | grep -c '^F ')"
}

t_i03_backup_kept_from_first_install() {
  mkdir -p "$HOME/.config/Thunar"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<actions/>\n' >"$HOME/.config/Thunar/uca.xml"
  cp "$HOME/.config/Thunar/uca.xml" "$T/orig"
  inst install --fm thunar
  inst install --fm thunar
  assert_eq "$(<"$HOME/.config/Thunar/uca.xml.7zctx.bak")" "$(<"$T/orig")"
}

t_i04_uninstall_leaves_nothing_of_ours() {
  mkdir -p "$HOME/.local/share/nemo/actions" "$HOME/.local/share/nautilus/scripts/7-Zip" "$HOME/.local/share/kio/servicemenus"
  echo mine >"$HOME/.local/share/nemo/actions/mine.nemo_action"
  echo mine >"$HOME/.local/share/nautilus/scripts/7-Zip/Meu script"
  echo mine >"$HOME/.local/share/kio/servicemenus/mine.desktop"
  before=$(home_files)
  inst install --fm all
  assert_rc 0
  inst uninstall
  assert_rc 0
  assert_eq "$(home_files)" "$before"
  if find "$HOME" \( -name '*7zctx*' -o -name '7z-context*' \) | grep -q .; then fail "leftovers: $(find "$HOME" -name '*7zctx*' -o -name '7z-context*')"; fi
  # a pasta 7-Zip do usuário não vazia continua lá
  assert_exists "$HOME/.local/share/nautilus/scripts/7-Zip/Meu script"
  # nada de pastas vazias criadas por nós (Thunar, caja, file-manager)
  assert_not_exists "$HOME/.config/Thunar/uca.xml"
}

t_i04_uninstall_without_install_is_harmless() {
  inst uninstall
  assert_rc 0
  assert_eq "$(find "$HOME" -mindepth 1 | wc -l)" 0
}

t_i04_uninstall_without_manifest_falls_back_to_markers() {
  inst install --fm dolphin,nemo,pcmanfm,nautilus
  assert_rc 0
  echo mine >"$HOME/.local/share/nemo/actions/mine.nemo_action"
  rm "$HOME/.local/share/7z-context/manifest"
  inst uninstall
  assert_rc 0
  assert_exists "$HOME/.local/share/nemo/actions/mine.nemo_action"
  assert_eq "$(home_files)" "./.local/share/nemo/actions/mine.nemo_action"
}

t_i04_purge_removes_config_and_log() {
  inst install --fm dolphin
  mkdir -p "$HOME/.config/7z-context" "$HOME/.local/state/7z-context"
  echo CTX7Z_LEVEL=9 >"$HOME/.config/7z-context/config"
  echo log >"$HOME/.local/state/7z-context/helper.log"
  inst uninstall
  assert_exists "$HOME/.config/7z-context/config"
  assert_exists "$HOME/.local/state/7z-context/helper.log"
  inst install --fm dolphin
  inst uninstall --purge
  assert_rc 0
  assert_eq "$(find "$HOME" -mindepth 1 -type f | wc -l)" 0
  assert_not_exists "$HOME/.config/7z-context"
}

t_i05_dry_run_changes_nothing() {
  mkdir -p "$HOME/.config/Thunar"
  echo '<actions/>' >"$HOME/.config/Thunar/uca.xml"
  touch "$T/marker"
  sleep 1.1
  inst install --fm all --dry-run
  assert_rc 0
  assert_contains "$OUT" "would create"
  [[ -z $(find "$HOME" -newer "$T/marker") ]] || fail "dry-run changed: $(find "$HOME" -newer "$T/marker")"
  assert_eq "$(<"$HOME/.config/Thunar/uca.xml")" "<actions/>"
  inst install --fm all
  sleep 1.1
  touch "$T/marker2"
  sleep 1.1
  inst uninstall --dry-run
  assert_rc 0
  assert_contains "$OUT" "would remove"
  [[ -z $(find "$HOME" -newer "$T/marker2") ]] || fail "uninstall dry-run changed: $(find "$HOME" -newer "$T/marker2")"
  inst install --fm all --dry-run
  assert_rc 0
  [[ -z $(find "$HOME" -newer "$T/marker2") ]] || fail "reinstall dry-run changed something"
}

t_i05_dry_run_on_empty_home_creates_no_dirs() {
  inst install --fm all --dry-run
  assert_rc 0
  assert_eq "$(find "$HOME" -mindepth 1 | wc -l)" 0
}

t_i06_auto_installs_only_detected() {
  CTX7Z_DETECTED_FMS=dolphin inst install --fm auto
  assert_rc 0
  assert_exists "$HOME/.local/share/kio/servicemenus/7z-context.desktop"
  assert_not_exists "$HOME/.local/share/nemo"
  assert_not_exists "$HOME/.local/share/nautilus"
  assert_not_exists "$HOME/.config/Thunar"
  assert_not_exists "$HOME/.config/caja"
  assert_not_exists "$HOME/.local/share/file-manager"
  assert_contains "$OUT" "nautilus: not detected"
  assert_contains "$OUT" "thunar: not detected"
  # padrão é auto
  inst uninstall
  CTX7Z_DETECTED_FMS="nemo,thunar" inst install
  assert_exists "$HOME/.local/share/nemo/actions/7zctx-extract-here.nemo_action"
  assert_exists "$HOME/.config/Thunar/uca.xml"
  assert_not_exists "$HOME/.local/share/kio"
}

t_i06_nothing_detected() {
  CTX7Z_DETECTED_FMS="" inst install --fm auto
  assert_rc 0
  assert_exists "$HOME/.local/bin/7z-context-helper"
  assert_contains "$OUT" "no supported file manager"
  assert_eq "$(find "$HOME" -type f | wc -l)" 5 # helper, 2 listas, manifesto, ponteiro
}

t_i07_prefix_with_space_and_exec_escaping() {
  local pfx="$HOME/meu prefixo"
  inst install --fm dolphin,nemo,thunar,pcmanfm,nautilus --prefix "$pfx" --lang en
  assert_rc 0
  assert_exec "$pfx/bin/7z-context-helper"
  local f raw first
  fixture a.7z
  # Dolphin / DES-EMA: Exec com aspas e escapes de Desktop Entry; executa de verdade
  for f in "$HOME/.local/share/kio/servicemenus/7z-context-archives.desktop" "$HOME/.local/share/file-manager/actions/7zctx-extract-here.desktop"; do
    raw=$(grep -m1 '^Exec=' "$f"); raw=${raw#Exec=}
    mapfile -d '' -t argv < <(desktop_exec_args "$raw" "$W/a.7z")
    assert_eq "${argv[0]}" "$pfx/bin/7z-context-helper"
    rm -rf "$W/plain"
    "${argv[@]}" >/dev/null 2>&1 </dev/null || fail "Exec failed: ${argv[*]}"
    assert_exists "$W/plain/um.txt"
  done
  # Nemo e Thunar: aspas de shell
  raw=$(grep -m1 '^Exec=' "$HOME/.local/share/nemo/actions/7zctx-extract-here.nemo_action"); raw=${raw#Exec=}
  first=$(python3 -I -c 'import shlex,sys; print(shlex.split(sys.argv[1])[0])' "$raw")
  assert_eq "$first" "$pfx/bin/7z-context-helper"
  first=$(python3 -I - "$HOME/.config/Thunar/uca.xml" <<'PY'
import shlex, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for a in r.findall("action"):
    if a.findtext("unique-id") == "7zctx-extract-here":
        print(shlex.split(a.findtext("command"))[0])
PY
)
  assert_eq "$first" "$pfx/bin/7z-context-helper"
  # Nautilus: o shim realmente roda o helper e extrai
  mkdir "$W/d"
  cp "$W/a.7z" "$W/d/"
  (cd "$W/d" && "$HOME/.local/share/nautilus/scripts/7-Zip/Extract here" a.7z) >/dev/null 2>&1
  assert_exists "$W/d/plain/um.txt"
}

t_i07_prefix_with_nasty_characters() {
  local pfx="$HOME/we ird'q\"u\\b\$d\`t;&x"
  inst install --fm dolphin,nemo,thunar,pcmanfm --prefix "$pfx" --lang en
  assert_rc 0
  local f raw first
  fixture a.7z
  for f in "$HOME/.local/share/kio/servicemenus/7z-context-archives.desktop" "$HOME/.local/share/file-manager/actions/7zctx-extract-here.desktop"; do
    raw=$(grep -m1 '^Exec=' "$f"); raw=${raw#Exec=}
    mapfile -d '' -t argv < <(desktop_exec_args "$raw" "$W/a.7z")
    assert_eq "${argv[0]}" "$pfx/bin/7z-context-helper"
    rm -rf "$W/plain"
    "${argv[@]}" >/dev/null 2>&1 </dev/null || fail "Exec failed: ${argv[*]}"
    assert_exists "$W/plain/um.txt"
  done
  raw=$(grep -m1 '^Exec=' "$HOME/.local/share/nemo/actions/7zctx-test.nemo_action"); raw=${raw#Exec=}
  first=$(python3 -I -c 'import shlex,sys; print(shlex.split(sys.argv[1])[0])' "$raw")
  assert_eq "$first" "$pfx/bin/7z-context-helper"
  first=$(python3 -I - "$HOME/.config/Thunar/uca.xml" <<'PY'
import shlex, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for a in r.findall("action"):
    if a.findtext("unique-id") == "7zctx-test":
        print(shlex.split(a.findtext("command"))[0])
PY
)
  assert_eq "$first" "$pfx/bin/7z-context-helper"
  inst uninstall
  assert_rc 0
  rm -rf "$HOME/.local/state" # log do helper, não faz parte da instalação
  assert_eq "$(find "$HOME" -type f | wc -l)" 0
}

t_i07_prefix_rejects_percent() {
  inst install --fm dolphin --prefix "$HOME/50%off"
  assert_rc 2
  assert_not_exists "$HOME/50%off"
}

t_i08_invalid_uca_xml_only_skips_thunar() {
  mkdir -p "$HOME/.config/Thunar"
  echo '<actions><action></actions>' >"$HOME/.config/Thunar/uca.xml"
  cp "$HOME/.config/Thunar/uca.xml" "$T/bad"
  inst install --fm thunar,dolphin
  assert_rc 1
  assert_eq "$(<"$HOME/.config/Thunar/uca.xml")" "$(<"$T/bad")"
  assert_not_exists "$HOME/.config/Thunar/uca.xml.7zctx.bak"
  assert_exists "$HOME/.local/share/kio/servicemenus/7z-context.desktop"
  assert_contains "$ERR" "Thunar"
}

t_i09_changing_prefix_removes_previous() {
  inst install --fm dolphin,nemo --prefix "$HOME/A"
  assert_rc 0
  assert_exists "$HOME/A/bin/7z-context-helper"
  inst install --fm dolphin,nemo --prefix "$HOME/B"
  assert_rc 0
  assert_not_exists "$HOME/A/bin/7z-context-helper"
  assert_not_exists "$HOME/A/share/7z-context"
  assert_exists "$HOME/B/bin/7z-context-helper"
  assert_contains "$(<"$HOME/.local/share/kio/servicemenus/7z-context.desktop")" "$HOME/B/bin"
  assert_eq "$(find "$HOME/.local/share/nemo/actions" -type f | wc -l)" 8
  inst uninstall
  assert_eq "$(find "$HOME" -type f | wc -l)" 0
}

t_i10_status_and_doctor() {
  inst status
  assert_rc 0
  assert_contains "$OUT" "installed: no"
  inst install --fm dolphin,thunar
  inst status
  assert_rc 0
  assert_contains "$OUT" "installed: yes"
  assert_contains "$OUT" "missing: 0"
  inst doctor
  assert_rc 0
  assert_contains "$OUT" "ok: helper executable"
  assert_contains "$OUT" "ok: valid XML"
  assert_contains "$OUT" "7z binary"
  chmod -x "$HOME/.local/share/kio/servicemenus/7z-context.desktop"
  inst doctor
  assert_rc 1
  assert_contains "$OUT" "not executable"
  rm "$HOME/.local/share/kio/servicemenus/7z-context-archives.desktop"
  inst status
  assert_contains "$OUT" "MISSING"
}

t_i11_nautilus_python_mode() {
  CTX7Z_ASSUME_NAUTILUS_PYTHON=1 inst install --fm nautilus --nautilus-mode python --lang pt_BR
  assert_rc 0
  ext=$HOME/.local/share/nautilus-python/extensions/7z_context.py
  assert_exists "$ext"
  assert_not_exists "$HOME/.local/share/nautilus/scripts"
  python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$ext" || fail "extension does not compile"
  # carregar com um Nautilus/gi falsos e conferir o menu produzido
  mkdir -p "$T/fake/gi/repository"
  cat >"$T/fake/gi/__init__.py" <<'PY'
def require_version(*a):
    pass
PY
  touch "$T/fake/gi/repository/__init__.py"
  cat >"$T/fake/gi/repository/GObject.py" <<'PY'
class GObject: pass
PY
  cat >"$T/fake/gi/repository/Nautilus.py" <<'PY'
class MenuProvider: pass
class Menu:
    def __init__(self): self.items = []
    def append_item(self, i): self.items.append(i)
class MenuItem:
    def __init__(self, name, label): self.name, self.label, self.sub, self.cb = name, label, None, None
    def set_submenu(self, m): self.sub = m
    def connect(self, sig, cb, *a): self.cb = (cb, a)
PY
  cat >"$T/fake/run.py" <<PY
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ext", "$ext")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
class F:
    def __init__(self, path, mime, d=False): self.p, self.m, self.d = path, mime, d
    def get_uri_scheme(self): return "file"
    def get_location(self):
        class L:
            def get_path(s, p=self.p): return p
        return L()
    def get_mime_type(self): return self.m
    def is_directory(self): return self.d
p = m.SevenZipContext()
arch = [F("/x/a b.7z", "application/x-7z-compressed")]
plain = [F("/x/a.txt", "text/plain")]
for args in ((arch,), (None, arch)):  # API 4.0 e 3.0
    top = p.get_file_items(*args)[0]
    print(",".join(i.label for i in top.sub.items))
print(",".join(i.label for i in p.get_file_items(plain)[0].sub.items))
PY
  out=$(PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$T/fake" python3 "$T/fake/run.py" 2>&1) || fail "extension run failed: $out"
  line1=$(sed -n 1p <<<"$out")
  assert_contains "$line1" "Extrair aqui"
  assert_contains "$line1" "Compactar em .7z"
  assert_eq "$(sed -n 1p <<<"$out")" "$(sed -n 2p <<<"$out")"
  line3=$(sed -n 3p <<<"$out")
  assert_contains "$line3" "Compactar em .zip"
  assert_not_contains "$line3" "Extrair"
  inst uninstall
  assert_eq "$(find "$HOME" -type f | wc -l)" 0
}

t_i11_nautilus_python_missing_is_reported() {
  inst install --fm nautilus --nautilus-mode python
  assert_rc 1
  assert_contains "$ERR" "nautilus-python"
}

t_i12_caja_actions_avoid_duplicates() {
  mkdir -p "$T/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$T/fakebin/caja-actions-config-tool"
  chmod +x "$T/fakebin/caja-actions-config-tool"
  PATH="$T/fakebin:$PATH" inst install --fm caja
  assert_rc 0
  assert_not_exists "$HOME/.config/caja"
  assert_exists "$HOME/.local/share/file-manager/actions/7zctx-extract-here.desktop"
  assert_contains "$ERR" "caja-actions"
}

t_i13_cli_errors() {
  inst install --fm bogus
  assert_rc 2
  inst install --lang xx
  assert_rc 2
  inst frobnicate
  assert_rc 64
  inst install --bogus
  assert_rc 2
  inst --help
  assert_rc 0
}

t_i14_installed_helper_works_with_installed_lists() {
  inst install --fm dolphin
  assert_rc 0
  run "$HOME/.local/bin/7z-context-helper" doctor
  assert_rc 0
  assert_contains "$OUT" "/bin/../share/7z-context"
  fixture a.7z
  run "$HOME/.local/bin/7z-context-helper" extract-to "$W/a.7z"
  assert_rc 0
  assert_exists "$W/a/plain/um.txt"
}

t_i15_quick_compress_actions_ask_for_name_and_folder() {
  inst install --fm all --lang en
  assert_rc 0
  local f n
  # os três "Compactar em ..." chamam o helper com --ask em todos os exploradores
  assert_eq "$(grep -c -e 'compress [a-z.0-9]* --ask' "$HOME/.local/share/kio/servicemenus/7z-context.desktop")" 3
  assert_eq "$(grep -c -e 'compress [a-z.0-9]* --ask' "$HOME/.config/Thunar/uca.xml")" 3
  for f in "$HOME/.local/share/nemo/actions"/7zctx-compress-{7z,zip,targz}.nemo_action \
    "$HOME/.local/share/file-manager/actions"/7zctx-compress-{7z,zip,targz}.desktop \
    "$HOME/.local/share/nautilus/scripts/7-Zip/Compress to .7z" \
    "$HOME/.config/caja/scripts/7-Zip/Compress to .zip"; do
    [[ -e $f ]] || continue
    grep -q -e '--ask' "$f" || fail "no --ask in $f"
  done
  # executa de verdade a ação do Dolphin, com as respostas do diálogo no modo de teste
  local raw
  raw=$(awk '/^\[Desktop Action compress7z\]/{a=1;next} /^\[/{a=0} a&&/^Exec=/{print;exit}' "$HOME/.local/share/kio/servicemenus/7z-context.desktop")
  raw=${raw#Exec=}
  echo x >"$W/a.txt"
  mapfile -d '' -t argv < <(desktop_exec_args "$raw" "$W/a.txt")
  CTX7Z_FORM_NAME="escolhido" CTX7Z_FORM_DEST="$W/onde" "${argv[@]}" >/dev/null 2>&1 </dev/null || fail "Exec failed: ${argv[*]}"
  assert_exists "$W/onde/escolhido.7z"
  n=$(find "$W" -name '*.7z' | wc -l)
  assert_eq "$n" 1
}
