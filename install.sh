#!/usr/bin/env bash
# 7z-context installer: 7-Zip context menu for Linux file managers.
#
#   ./install.sh install   [--fm auto|all|dolphin,nautilus,nemo,thunar,caja,pcmanfm]
#                          [--prefix DIR] [--lang en|pt_BR] [--restart] [--dry-run]
#                          [--nautilus-mode auto|scripts|python]
#   ./install.sh uninstall [--purge] [--prefix DIR] [--dry-run]
#   ./install.sh status
#   ./install.sh doctor
#
# Everything is installed under $HOME (default prefix: ~/.local); nothing needs root.
# shellcheck disable=SC2317,SC2329  # install_<fm> functions are called by name from do_install
set -u
shopt -u patsub_replacement 2>/dev/null || true

if (( BASH_VERSINFO[0] < 4 )); then
  echo "install.sh needs Bash 4 or newer." >&2
  exit 2
fi

VERSION=1.0.0
SELF=$(readlink -f -- "${BASH_SOURCE[0]}")
SRC=${SELF%/*}
HELPER_NAME=7z-context-helper
ALL_FMS=(dolphin nautilus nemo thunar caja pcmanfm)

# id|English label|Portuguese label|icon|kind (any = files and folders, archive = archives only)|helper arguments
ACTIONS=(
  'compress-dialog|Add to archive…|Adicionar ao arquivo…|archive-insert|any|compress-dialog'
  'compress-7z|Compress to .7z|Compactar em .7z|archive-insert|any|compress 7z'
  'compress-zip|Compress to .zip|Compactar em .zip|archive-insert|any|compress zip'
  'compress-targz|Compress to .tar.gz|Compactar em .tar.gz|archive-insert|any|compress tar.gz'
  'extract-here|Extract here|Extrair aqui|archive-extract|archive|extract-here'
  'extract-to|Extract to folder|Extrair para pasta própria|archive-extract|archive|extract-to'
  'test|Test archive|Testar arquivo|dialog-ok|archive|test'
  'list|List contents|Listar conteúdo|view-list-text|archive|list'
)

DRY=0 PURGE=0 RESTART=0
PREFIX="" PREFIX_SET=0 LANG_SEL="" FM_SEL=auto NAUTILUS_MODE=auto
EXITCODE=0
MF="" # manifest being written
declare -A S=()

# ------------------------------------------------------------------ output

say() { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 2; }
partial() { warn "$*"; EXITCODE=1; }

# ------------------------------------------------------------------ escaping per file format

# Desktop Entry "Exec": always double-quoted; inside quotes " ` $ \ are escaped with a
# backslash and, because the value is also a string, every backslash is doubled; % -> %%.
desktop_quote() {
  local p=$1 bs=$'\\'
  p=${p//"$bs"/"$bs$bs$bs$bs"}
  p=${p//'"'/"$bs$bs\""}
  p=${p//'`'/"$bs$bs\`"}
  p=${p//'$'/"$bs$bs\$"}
  p=${p//'%'/'%%'}
  REPLY="\"$p\""
}

# POSIX shell single quotes.
sh_quote() {
  local p=${1//\'/\'\\\'\'}
  REPLY="'$p'"
}

xml_escape() {
  local p=$1
  p=${p//&/&amp;}
  p=${p//</&lt;}
  p=${p//>/&gt;}
  p=${p//'"'/&quot;}
  p=${p//\'/&apos;}
  REPLY=$p
}

py_quote() {
  local p=$1 bs=$'\\'
  p=${p//"$bs"/"$bs$bs"}
  p=${p//'"'/"$bs\""}
  REPLY="\"$p\""
}

# ------------------------------------------------------------------ small helpers

join_by() { # separator items...
  local sep=$1 out="" i
  shift
  for i in "$@"; do out+=${out:+$sep}$i; done
  REPLY=$out
}

read_list() { # file -> LIST (array), ignoring blanks and comments
  LIST=()
  local line
  [[ -r $1 ]] || die "missing file: $1"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    LIST+=("$line")
  done <"$1"
}

# render TEMPLATE: replaces @KEY@ tokens from S in a single left-to-right pass.
render() {
  local c rest out="" tok key
  IFS= read -r -d '' c <"$SRC/templates/$1" || true
  rest=$c
  while [[ $rest =~ @([A-Z_]+)@ ]]; do
    tok=${BASH_REMATCH[0]}
    key=${BASH_REMATCH[1]}
    out+=${rest%%"$tok"*}
    if [[ -v S[$key] ]]; then out+=${S[$key]}; else out+=$tok; fi
    rest=${rest#*"$tok"}
  done
  REPLY=$out$rest
}

rec() { # type path [extra]
  (( DRY )) && return 0
  [[ -n $MF ]] || return 0
  printf '%s %s%s\n' "$1" "$2" "${3:+ $3}" >>"$MF"
}

# mkdir_rec DIR: mkdir -p that records in the manifest each folder it had to create
mkdir_rec() {
  local d=$1 missing=() i
  while [[ ! -d $d && $d != / && -n $d ]]; do
    missing=("$d" "${missing[@]+"${missing[@]}"}")
    d=${d%/*}
  done
  mkdir -p -- "$1" || return 1
  for i in "${missing[@]+"${missing[@]}"}"; do rec D "$i"; done
  return 0
}

# put_file DEST MODE CONTENT
put_file() {
  local dest=$1 mode=$2 content=$3 tmp
  if (( DRY )); then info "would create $dest"; return 0; fi
  mkdir_rec "${dest%/*}" || { partial "cannot create ${dest%/*}"; return 1; }
  tmp=$(mktemp "${dest%/*}/.7zctx.XXXXXX") || { partial "cannot write in ${dest%/*}"; return 1; }
  if printf '%s' "$content" >"$tmp" && chmod "$mode" "$tmp" && mv -f -- "$tmp" "$dest"; then
    rec F "$dest"
    info "created $dest"
  else
    rm -f -- "$tmp"
    partial "cannot write $dest"
    return 1
  fi
}

# copy_file SRC DEST MODE
copy_file() {
  local src=$1 dest=$2 mode=$3 tmp
  if (( DRY )); then info "would create $dest"; return 0; fi
  mkdir_rec "${dest%/*}" || { partial "cannot create ${dest%/*}"; return 1; }
  tmp=$(mktemp "${dest%/*}/.7zctx.XXXXXX") || { partial "cannot write in ${dest%/*}"; return 1; }
  if cp -- "$src" "$tmp" && chmod "$mode" "$tmp" && mv -f -- "$tmp" "$dest"; then
    rec F "$dest"
    info "created $dest"
  else
    rm -f -- "$tmp"
    partial "cannot write $dest"
    return 1
  fi
}

data_home() { REPLY=${XDG_DATA_HOME:-$HOME/.local/share}; }
config_home() { REPLY=${XDG_CONFIG_HOME:-$HOME/.config}; }

have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------ Thunar uca.xml merge (python3)

thunar_py() {
  python3 - "$@" <<'PY'
import os, shutil, sys, tempfile
import xml.etree.ElementTree as ET

mode, path = sys.argv[1], sys.argv[2]
frag = sys.argv[3] if len(sys.argv) > 3 else None
created = len(sys.argv) > 4 and sys.argv[4] == "created"
keepbak = len(sys.argv) > 5 and sys.argv[5] == "keepbak"
PFX = "7zctx-"


def load(p):
    return ET.parse(p, ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))


existed = os.path.exists(path)
if existed:
    try:
        tree = load(path)
    except ET.ParseError as e:
        print("invalid XML in %s: %s" % (path, e), file=sys.stderr)
        sys.exit(3)
    root = tree.getroot()
    if root.tag != "actions":
        print("unexpected root element <%s> in %s" % (root.tag, path), file=sys.stderr)
        sys.exit(3)
else:
    if mode == "remove":
        sys.exit(0)
    root = ET.Element("actions")
    tree = ET.ElementTree(root)


def ours(a):
    u = a.find("unique-id")
    return a.tag == "action" and u is not None and (u.text or "").strip().startswith(PFX)


for a in [a for a in root if ours(a)]:
    root.remove(a)

bak = path + ".7zctx.bak"
if mode == "merge":
    if existed and not os.path.exists(bak):
        shutil.copy2(path, bak)
    for a in load(frag).getroot():
        root.append(a)
elif mode == "remove":
    if created and len(root.findall("action")) == 0:
        os.unlink(path)
        if os.path.exists(bak) and not keepbak:
            os.unlink(bak)
        sys.exit(0)

if hasattr(ET, "indent"):
    ET.indent(tree, space="  ")
d = os.path.dirname(path) or "."
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".7zctx.")
os.close(fd)
try:
    tree.write(tmp, encoding="UTF-8", xml_declaration=True)
    with open(tmp, "ab") as f:
        f.write(b"\n")
    if existed:
        shutil.copymode(path, tmp)
    else:
        os.chmod(tmp, 0o644)
    os.replace(tmp, path)
except BaseException:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
if mode == "remove" and os.path.exists(bak) and not keepbak:
    os.unlink(bak)
PY
}

# ------------------------------------------------------------------ per-file-manager install

action_fields() { # entry -> A_ID A_EN A_PT A_ICON A_KIND A_CMD
  IFS='|' read -r A_ID A_EN A_PT A_ICON A_KIND A_CMD <<<"$1"
}

set_action_subst() {
  S[ID]=$A_ID S[NAME_EN]=$A_EN S[NAME_PT]=$A_PT S[ICON]=$A_ICON S[CMD]=$A_CMD
  S[LABEL]=$A_EN
  [[ $LANG_SEL == pt_BR ]] && S[LABEL]=$A_PT
}

install_dolphin() {
  local d
  data_home
  d=$REPLY/kio/servicemenus
  render dolphin/7z-context.desktop.in
  put_file "$d/7z-context.desktop" 755 "$REPLY"
  render dolphin/7z-context-archives.desktop.in
  put_file "$d/7z-context-archives.desktop" 755 "$REPLY"
  if have kf5-config; then
    data_home
    d=$REPLY/kservices5/ServiceMenus
    render dolphin/7z-context.desktop.in
    put_file "$d/7z-context.desktop" 755 "$REPLY"
    render dolphin/7z-context-archives.desktop.in
    put_file "$d/7z-context-archives.desktop" 755 "$REPLY"
  fi
  if (( ! DRY )) && [[ -z ${CTX7Z_NO_POST:-} ]]; then
    if have kbuildsycoca6; then kbuildsycoca6 >/dev/null 2>&1 || true
    elif have kbuildsycoca5; then kbuildsycoca5 >/dev/null 2>&1 || true
    fi
  fi
  info "Dolphin: the menu appears under \"7-Zip\" (Ark keeps its own \"Extract\" menu)."
}

install_scripts() { # DIR  (Nautilus/Caja scripts, one shim per action)
  local dir=$1 e
  for e in "${ACTIONS[@]}"; do
    action_fields "$e"
    set_action_subst
    render scripts/shim.sh.in
    put_file "$dir/${S[LABEL]}" 755 "$REPLY"
  done
}

nautilus_python_available() {
  local d
  [[ -n ${CTX7Z_ASSUME_NAUTILUS_PYTHON:-} ]] && return 0 # test hook
  have python3 || return 1
  for d in /usr/lib/nautilus/extensions-* /usr/lib64/nautilus/extensions-* /usr/lib/*/nautilus/extensions-*; do
    [[ -e $d/libnautilus-python.so ]] && return 0
  done
  return 1
}

install_nautilus() {
  local mode=$NAUTILUS_MODE d
  if [[ $mode == auto ]]; then mode=scripts; fi
  if [[ $mode == python ]]; then
    if ! nautilus_python_available; then
      partial "nautilus-python is not installed; use --nautilus-mode scripts"
      return 1
    fi
    data_home
    d=$REPLY/nautilus-python/extensions
    py_quote "${S[HELPER]}"
    S[HELPER_PY]=$REPLY
    render nautilus-python/7z_context.py.in
    put_file "$d/7z_context.py" 644 "$REPLY"
    info "Nautilus (nautilus-python): restart with 'nautilus -q'."
  else
    data_home
    install_scripts "$REPLY/nautilus/scripts/7-Zip"
    info "Nautilus: menu under Scripts → 7-Zip; restart with 'nautilus -q' if it does not show up."
  fi
  (( RESTART && ! DRY )) && have nautilus && nautilus -q >/dev/null 2>&1
  return 0
}

install_nemo() {
  local e d
  data_home
  d=$REPLY/nemo/actions
  for e in "${ACTIONS[@]}"; do
    action_fields "$e"
    set_action_subst
    render "nemo/action-$([[ $A_KIND == any ]] && echo any || echo archive).nemo_action.in"
    put_file "$d/7zctx-$A_ID.nemo_action" 644 "$REPLY"
  done
  info "Nemo: actions are picked up automatically (labels are prefixed with \"7-Zip: \")."
}

install_thunar() {
  local uca created=existing tmp rc=0
  have python3 || { partial "python3 not found: Thunar integration skipped"; return 1; }
  config_home
  uca=$REPLY/Thunar/uca.xml
  [[ -e $uca ]] || created=created
  local k e
  for e in "${ACTIONS[@]}"; do
    action_fields "$e"
    k=${A_ID//-/_}
    S[L_${k^^}]=$A_EN
    [[ $LANG_SEL == pt_BR ]] && S[L_${k^^}]=$A_PT
  done
  # values go into XML: escape them
  local sh_xml pat_xml
  xml_escape "${S[HELPER_SH_QUOTED]}"
  sh_xml=$REPLY
  xml_escape "${S[PATTERNS]}"
  pat_xml=$REPLY
  local saved_sh=${S[HELPER_SH_QUOTED]} saved_pat=${S[PATTERNS]}
  S[HELPER_SH_QUOTED]=$sh_xml S[PATTERNS]=$pat_xml
  for e in "${!S[@]}"; do
    [[ $e == L_* ]] || continue
    xml_escape "${S[$e]}"
    S[$e]=$REPLY
  done
  render thunar/uca-actions.xml.in
  S[HELPER_SH_QUOTED]=$saved_sh S[PATTERNS]=$saved_pat
  if (( DRY )); then
    info "would merge ${#ACTIONS[@]} actions (7zctx-*) into $uca"
    return 0
  fi
  if (( RESTART )) && have thunar && pgrep -x thunar >/dev/null 2>&1; then thunar -q >/dev/null 2>&1; fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/7zctx-uca.XXXXXX") || { partial "cannot create a temporary file"; return 1; }
  printf '%s' "$REPLY" >"$tmp"
  mkdir_rec "${uca%/*}" || { rm -f -- "$tmp"; partial "cannot create ${uca%/*}"; return 1; }
  thunar_py merge "$uca" "$tmp" "$created" || rc=$?
  rm -f -- "$tmp"
  if (( rc != 0 )); then
    partial "Thunar integration skipped (uca.xml was not touched): see message above"
    return 1
  fi
  rec T "$uca" "$created"
  info "merged ${#ACTIONS[@]} actions into $uca"
  info "Thunar rewrites uca.xml when it quits: run 'thunar -q' before installing, or use --restart."
}

install_caja() {
  local d
  if have caja-actions-config-tool; then
    warn "caja-actions detected: Caja will use the actions installed for PCManFM (file-manager/actions); Caja scripts were not installed to avoid duplicate items."
    return 0
  fi
  config_home
  d=$REPLY/caja/scripts/7-Zip
  install_scripts "$d"
  info "Caja: menu under Scripts → 7-Zip."
}

install_pcmanfm() {
  local d e items=()
  data_home
  d=$REPLY/file-manager/actions
  for e in "${ACTIONS[@]}"; do
    action_fields "$e"
    items+=("7zctx-$A_ID")
  done
  join_by ';' "${items[@]}"
  S[ITEMS]=$REPLY\;
  render desema/menu.desktop.in
  put_file "$d/7zctx-menu.desktop" 644 "$REPLY"
  for e in "${ACTIONS[@]}"; do
    action_fields "$e"
    set_action_subst
    render "desema/action-$([[ $A_KIND == any ]] && echo any || echo archive).desktop.in"
    put_file "$d/7zctx-$A_ID.desktop" 644 "$REPLY"
  done
  info "PCManFM / PCManFM-Qt / FileManager-Actions: restart the file manager if the menu does not show up."
}

# ------------------------------------------------------------------ detection

detect_fm() { # name -> 0 if present
  if [[ -n ${CTX7Z_DETECTED_FMS+x} ]]; then
    local l=" ${CTX7Z_DETECTED_FMS//,/ } "
    [[ $l == *" $1 "* ]]
    return
  fi
  case $1 in
    pcmanfm) have pcmanfm || have pcmanfm-qt ;;
    *) have "$1" ;;
  esac
}

valid_fm() {
  local f
  for f in "${ALL_FMS[@]}"; do [[ $f == "$1" ]] && return 0; done
  return 1
}

# ------------------------------------------------------------------ prefix handling

resolve_prefix() {
  [[ -n $PREFIX ]] || PREFIX=$HOME/.local
  [[ $PREFIX == /* ]] || PREFIX=$PWD/$PREFIX
  while [[ $PREFIX == *//* ]]; do PREFIX=${PREFIX//\/\//\/}; done
  while (( ${#PREFIX} > 1 )) && [[ $PREFIX == */ ]]; do PREFIX=${PREFIX%/}; done
  if [[ $PREFIX == *[[:cntrl:]]* || $PREFIX == *%* ]]; then
    die "the prefix may not contain '%' or control characters: $PREFIX"
  fi
}

pointer_file() { config_home; REPLY=$REPLY/7z-context/install-prefix; }

previous_prefix() { # -> REPLY (empty if none)
  local f
  pointer_file
  f=$REPLY
  REPLY=""
  [[ -r $f ]] && IFS= read -r REPLY <"$f"
  return 0
}

# ------------------------------------------------------------------ install

do_install() {
  local fms=() detected=() fm e
  resolve_prefix
  if (( EUID == 0 && ! PREFIX_SET )); then
    die "refusing to install into root's home; run as your normal user or pass --prefix explicitly."
  fi
  [[ -n $LANG_SEL ]] || case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in pt*) LANG_SEL=pt_BR ;; *) LANG_SEL=en ;; esac
  [[ $LANG_SEL == en || $LANG_SEL == pt_BR ]] || die "--lang must be en or pt_BR"
  [[ $NAUTILUS_MODE == auto || $NAUTILUS_MODE == scripts || $NAUTILUS_MODE == python ]] || die "--nautilus-mode must be auto, scripts or python"

  # which file managers
  for fm in "${ALL_FMS[@]}"; do detect_fm "$fm" && detected+=("$fm"); done
  case $FM_SEL in
    auto) fms=("${detected[@]+"${detected[@]}"}") ;;
    all) fms=("${ALL_FMS[@]}") ;;
    *)
      local list
      IFS=, read -ra list <<<"$FM_SEL"
      for fm in "${list[@]}"; do
        valid_fm "$fm" || die "unknown file manager '$fm' (use: ${ALL_FMS[*]})"
        fms+=("$fm")
      done
      ;;
  esac
  if [[ " ${fms[*]} " == *" caja "* ]] && have caja-actions-config-tool && [[ " ${fms[*]} " != *" pcmanfm "* ]]; then
    fms+=(pcmanfm)
  fi

  # checks
  have 7zz || have 7z || have 7za || warn "7-Zip was not found (Arch: 7zip, Debian/Ubuntu: 7zip or p7zip-full, Fedora: 7zip). The menu will show an error until it is installed."
  have zenity || have kdialog || have yad || warn "none of zenity, kdialog or yad found: dialogs (password, 'Add to archive…') will not work."

  say "7z-context $VERSION → prefix $PREFIX (language: $LANG_SEL)"
  (( DRY )) && say "dry run: nothing will be changed"

  # remove a previous installation first (idempotent; handles a changed prefix)
  previous_prefix
  local prev=$REPLY
  [[ -n $prev && -r $prev/share/7z-context/manifest ]] || prev=""
  [[ -r $PREFIX/share/7z-context/manifest ]] && prev=$PREFIX
  if [[ -n $prev ]]; then
    say "removing the previous installation ($prev)"
    KEEP_BAK=1 remove_installation "$prev" 0 || true
  fi

  local share=$PREFIX/share/7z-context helper=$PREFIX/bin/$HELPER_NAME
  MF=$share/manifest
  if (( ! DRY )); then
    local missing=() d=$share
    while [[ ! -d $d && $d != / && -n $d ]]; do missing=("$d" "${missing[@]+"${missing[@]}"}"); d=${d%/*}; done
    mkdir -p -- "$share" || die "cannot create $share"
    {
      echo "# 7z-context manifest — used by install.sh uninstall"
      echo "V $VERSION"
      echo "P $PREFIX"
      echo "L $LANG_SEL"
      for d in "${missing[@]+"${missing[@]}"}"; do echo "D $d"; done
    } >"$MF"
  fi

  copy_file "$SRC/bin/$HELPER_NAME" "$helper" 755
  copy_file "$SRC/share/extensions.list" "$share/extensions.list" 644
  copy_file "$SRC/share/mimetypes.list" "$share/mimetypes.list" 644

  local mimes patterns
  read_list "$SRC/share/mimetypes.list"
  join_by ';' "${LIST[@]}"
  mimes=$REPLY\;
  read_list "$SRC/share/extensions.list"
  join_by ';' "${LIST[@]}"
  patterns=$REPLY
  desktop_quote "$helper"
  S[HELPER_DESKTOP_QUOTED]=$REPLY
  sh_quote "$helper"
  S[HELPER_SH_QUOTED]=$REPLY
  S[HELPER]=$helper S[MIMETYPES]=$mimes S[PATTERNS]=$patterns S[VERSION]=$VERSION S[LANG]=$LANG_SEL

  for fm in "${ALL_FMS[@]}"; do
    if [[ " ${fms[*]} " != *" $fm "* ]]; then
      detect_fm "$fm" || info "skipped $fm: not detected"
      continue
    fi
    say "installing for $fm"
    "install_$fm" || true
  done

  if (( ! DRY )); then
    pointer_file
    mkdir -p -- "${REPLY%/*}" && printf '%s\n' "$PREFIX" >"$REPLY"
  fi

  case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) info "note: $PREFIX/bin is not in your PATH (not needed: the menus use the full path)." ;;
  esac
  if (( ${#fms[@]} == 0 )); then
    info "no supported file manager detected: only the helper was installed. Use --fm to choose, or --fm all."
  fi
  if (( DRY )); then say "dry run finished"; else say "done"; fi
  return "$EXITCODE"
}

# ------------------------------------------------------------------ uninstall

safe_path() { # absolute, no '..' component
  [[ $1 == /* && $1 != */../* && $1 != */.. ]]
}

remove_file() {
  local p=$1
  safe_path "$p" || { warn "ignoring unsafe path in manifest: $p"; return; }
  if [[ -e $p || -L $p ]]; then
    if (( DRY )); then info "would remove $p"; else rm -f -- "$p" && info "removed $p"; fi
  fi
}

remove_dir_if_empty() {
  local p=$1
  safe_path "$p" || return 0
  [[ -d $p ]] || return 0
  if (( DRY )); then
    [[ -z $(ls -A -- "$p" 2>/dev/null) ]] && info "would remove empty folder $p"
  else
    rmdir -- "$p" 2>/dev/null && info "removed empty folder $p"
  fi
  return 0
}

remove_thunar() { # path created|existing
  local path=$1 created=${2:-existing}
  if (( DRY )); then info "would remove the 7zctx-* actions from $path"; return 0; fi
  [[ -e $path ]] || return 0
  if ! have python3; then warn "python3 not found: could not clean $path"; return 1; fi
  local rc=0
  thunar_py remove "$path" "" "$created" "$([[ ${KEEP_BAK:-0} == 1 ]] && echo keepbak)" || rc=$?
  if (( rc == 0 )); then info "removed the 7zctx-* actions from $path"
  else warn "could not clean $path (invalid XML?); remove the 7zctx-* actions by hand."; EXITCODE=1
  fi
}

# fallback when there is no manifest: known folders only, marked files only
scan_known() { # prefix
  local prefix=$1 d f
  data_home
  local dh=$REPLY
  config_home
  local ch=$REPLY
  for d in "$dh/kio/servicemenus" "$dh/kservices5/ServiceMenus"; do
    for f in "$d"/7z-context.desktop "$d"/7z-context-archives.desktop; do
      [[ -e $f ]] && grep -q '7zctx-generated' "$f" && remove_file "$f"
    done
  done
  for f in "$dh"/nemo/actions/7zctx-*.nemo_action "$dh"/file-manager/actions/7zctx-*.desktop \
    "$dh/nautilus-python/extensions/7z_context.py"; do
    [[ -e $f ]] && grep -q '7zctx-generated' "$f" && remove_file "$f"
  done
  for d in "$dh/nautilus/scripts/7-Zip" "$ch/caja/scripts/7-Zip"; do
    [[ -d $d ]] || continue
    for f in "$d"/*; do
      [[ -f $f ]] && grep -q '7zctx-generated' "$f" && remove_file "$f"
    done
    remove_dir_if_empty "$d"
  done
  [[ -e $ch/Thunar/uca.xml ]] && remove_thunar "$ch/Thunar/uca.xml" existing
  f=$prefix/bin/$HELPER_NAME
  [[ -e $f ]] && grep -q '7z-context' "$f" && remove_file "$f"
  remove_file "$prefix/share/7z-context/extensions.list"
  remove_file "$prefix/share/7z-context/mimetypes.list"
  remove_dir_if_empty "$prefix/share/7z-context"
}

# remove_installation PREFIX PURGE
remove_installation() {
  local prefix=$1 purge=$2 mf type path extra line
  mf=$prefix/share/7z-context/manifest
  if [[ -r $mf ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      type=${line%% *}
      path=${line#"$type "}
      extra=""
      case $type in
        F) remove_file "$path" ;;
        T)
          extra=${path##* }
          path=${path% *}
          remove_thunar "$path" "$extra"
          ;;
      esac
    done <"$mf"
    # folders last, innermost first (the manifest lists them in creation order)
    local dirs=()
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line == "D "* ]] && dirs+=("${line#D }")
    done <"$mf"
    local i
    remove_file "$mf"
    for ((i = ${#dirs[@]} - 1; i >= 0; i--)); do remove_dir_if_empty "${dirs[i]}"; done
  else
    warn "no manifest at $mf: removing only marked files in the known folders"
    scan_known "$prefix"
  fi
  pointer_file
  local ptr=$REPLY
  if (( ! DRY )); then
    if [[ -r $ptr ]] && [[ $(<"$ptr") == "$prefix" ]]; then rm -f -- "$ptr"; fi
  fi
  if (( purge )); then
    config_home
    local cfg=$REPLY/7z-context
    local st=${XDG_STATE_HOME:-$HOME/.local/state}/7z-context
    local p
    for p in "$cfg" "$st"; do
      if [[ -d $p ]]; then
        if (( DRY )); then info "would remove $p"; else rm -rf -- "$p" && info "removed $p"; fi
      fi
    done
  else
    pointer_file
    rmdir -- "${REPLY%/*}" 2>/dev/null || true
  fi
  return 0
}

do_uninstall() {
  local prefix
  if (( PREFIX_SET )); then
    resolve_prefix
    prefix=$PREFIX
  else
    previous_prefix
    prefix=$REPLY
    [[ -n $prefix ]] || prefix=$HOME/.local
  fi
  say "uninstalling 7z-context from $prefix"
  (( DRY )) && say "dry run: nothing will be changed"
  remove_installation "$prefix" "$PURGE"
  say "done"
  return "$EXITCODE"
}

# ------------------------------------------------------------------ status / doctor

do_status() {
  local prefix mf line n=0 nmiss=0 type path
  if (( PREFIX_SET )); then resolve_prefix; prefix=$PREFIX
  else
    previous_prefix
    prefix=$REPLY
  fi
  say "7z-context installer $VERSION"
  if [[ -z $prefix ]]; then
    say "installed: no (no install pointer found)"
  else
    mf=$prefix/share/7z-context/manifest
    if [[ -r $mf ]]; then
      say "installed: yes (prefix $prefix)"
      while IFS= read -r line || [[ -n $line ]]; do
        type=${line%% *}
        path=${line#"$type "}
        case $type in
          V) say "version: $path" ;;
          L) say "language: $path" ;;
          F)
            n=$((n + 1))
            [[ -e $path ]] || { nmiss=$((nmiss + 1)); say "  MISSING $path"; }
            ;;
          T) say "thunar: ${path% *} (merged)" ;;
        esac
      done <"$mf"
      say "files: $n, missing: $nmiss"
    else
      say "installed: no (manifest not found at $mf)"
    fi
  fi
  say "file managers:"
  local fm
  for fm in "${ALL_FMS[@]}"; do
    if detect_fm "$fm"; then say "  $fm: detected"; else say "  $fm: not detected"; fi
  done
  return 0
}

do_doctor() {
  local prefix mf rc=0 line type path
  do_status
  previous_prefix
  prefix=${REPLY:-$HOME/.local}
  say "checks:"
  if [[ -x $prefix/bin/$HELPER_NAME ]]; then say "  ok: helper executable"
  else say "  FAIL: helper missing or not executable ($prefix/bin/$HELPER_NAME)"; rc=1
  fi
  case ":$PATH:" in *":$prefix/bin:"*) say "  ok: $prefix/bin is in PATH" ;; *) say "  note: $prefix/bin is not in PATH (menus use the full path)" ;; esac
  mf=$prefix/share/7z-context/manifest
  if [[ -r $mf ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      type=${line%% *}
      path=${line#"$type "}
      case $type in
        F)
          if [[ $path == */kio/servicemenus/*.desktop || $path == */kservices5/ServiceMenus/*.desktop ]]; then
            if [[ -x $path ]]; then say "  ok: executable $path"
            else say "  FAIL: not executable (Dolphin ignores it): $path"; rc=1
            fi
            if have desktop-file-validate; then
              desktop-file-validate "$path" >/dev/null 2>&1 || say "  note: desktop-file-validate reports issues in $path (X-KDE-* keys are expected)"
            fi
          fi
          ;;
        T)
          path=${path% *}
          if have python3 && python3 -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$path" 2>/dev/null; then
            say "  ok: valid XML $path"
          else
            say "  FAIL: invalid or missing XML $path"
            rc=1
          fi
          ;;
      esac
    done <"$mf"
  fi
  if [[ -x $prefix/bin/$HELPER_NAME ]]; then
    say "helper doctor:"
    "$prefix/bin/$HELPER_NAME" doctor 2>&1 | sed 's/^/  /' || rc=1
  fi
  return "$rc"
}

# ------------------------------------------------------------------ CLI

usage() {
  cat <<'EOF'
Usage:
  ./install.sh install   [--fm auto|all|dolphin,nautilus,nemo,thunar,caja,pcmanfm]
                         [--prefix DIR] [--lang en|pt_BR] [--restart] [--dry-run]
                         [--nautilus-mode auto|scripts|python]
  ./install.sh uninstall [--purge] [--prefix DIR] [--dry-run]
  ./install.sh status
  ./install.sh doctor

install    copies the helper to PREFIX/bin (default ~/.local/bin) and creates the menu
           files for the chosen file managers (auto = the ones found on this system).
uninstall  removes exactly what the manifest lists (--purge also deletes config and log).
EOF
}

main() {
  local cmd=${1:-}
  case $cmd in
    -h|--help|help|'') usage; [[ -n $cmd ]] && return 0 || return 64 ;;
    install|uninstall|status|doctor) shift ;;
    *) usage >&2; return 64 ;;
  esac
  while (( $# )); do
    local opt=$1 val=""
    if [[ $opt == --*=* ]]; then val=${opt#*=}; opt=${opt%%=*}; set -- "$opt" "$val" "${@:2}"; fi
    case $opt in
      --dry-run) DRY=1 ;;
      --purge) PURGE=1 ;;
      --restart) RESTART=1 ;;
      --fm|--prefix|--lang|--nautilus-mode)
        (( $# >= 2 )) || die "$opt needs a value"
        case $opt in
          --fm) FM_SEL=$2 ;;
          --prefix) PREFIX=$2; PREFIX_SET=1 ;;
          --lang) LANG_SEL=$2 ;;
          --nautilus-mode) NAUTILUS_MODE=$2 ;;
        esac
        shift
        ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option: $opt (see --help)" ;;
    esac
    shift
  done
  case $cmd in
    install) do_install ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    doctor) do_doctor ;;
  esac
}

main "$@"
exit $?
